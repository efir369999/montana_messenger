package quest.montana.app

import android.app.AlertDialog
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.text.format.DateUtils
import android.view.Gravity
import android.view.TextureView
import android.view.View
import android.view.WindowInsets
import android.view.MotionEvent
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import java.util.Date

// ─────────────────────────── what a row says of a letter (iOS MTRowLetter) ───────────────────────────

/** The words a letter shows in the list and the banner: its text, or the name of what it carries. */
fun letterWords(c: Context, t: String, meta: String? = null): String = when {
    t.startsWith(Marks.CALL) -> Calls.info(t)?.let { Calls.words(c, it) } ?: ""
    t.startsWith(Marks.RELEASE) -> Release.of(t)?.let { Release.words(c, it) } ?: ""   // iOS rowPreview: «New version» and the build
    // a group's event row speaks the group's names (iOS MTRowLetter.eventWords, stage R)
    Groups.isEvent(t) -> Groups.eventWords(c, t) ?: ""
    // a post's card: «Wall post» and the post's words (iOS MTRowLetter.preview, MTRowLetter.swift:143 at 2155)
    t.startsWith(WallCard.MARK) -> WallCard.of(t)?.let { k -> c.getString(R.string.wall_post) + WallCard.words(c, k).let { w -> if (w.isEmpty()) "" else " · " + w } } ?: ""
    t.startsWith(Marks.VOICE) -> c.getString(R.string.voice_message)
    t.startsWith(Marks.MEDIA) -> mediaWords(c, meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(t))
    t.startsWith(Marks.STICKER) -> t.removePrefix(Marks.STICKER)
    t.startsWith(Marks.LONG) -> c.getString(R.string.long_letter)
    // a game's letter: the knight and the word (iOS MTRowLetter.preview)
    ChessLetter.parse(t) != null -> ChessLetter.MARK + c.getString(R.string.chess_title)
    // a coin letter: the coin and the number (iOS MTRowLetter.coinCount)
    CoinLetter.parse(t) != null -> CoinLetter.preview(c, t) ?: t
    // a shared secret's every preview names no title and no content (iOS MTRowLetter.preview)
    SecretLetter.isOne(t) -> "\uD83D\uDD11 " + c.getString(R.string.pw_shared)
    else -> t
}
/** A query and a letter's words folded alike (iOS .caseInsensitive, .diacriticInsensitive): the accents off, one case. */
internal fun searchFold(s: String): String =
    java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase(java.util.Locale.ROOT)
/** What a letter is searched by (iOS message.text, message.docName): its own words; a media letter's caption and its file's name. */
internal fun searchWords(c: Context, m: Msg): String =
    if (m.text.startsWith(Marks.MEDIA)) Media.manifestOf(m)?.let { it.optString("cap") + "\n" + it.optString("n") } ?: ""
    else letterWords(c, m).takeIf { it == m.text } ?: ""
/** The same words for a letter of the book: its manifest, once read, names what it carries. */
fun letterWords(c: Context, m: Msg): String = letterWords(c, m.text, m.meta)

/**
 * THE WORDS OF A MEDIA LETTER (iOS MTRowLetter.mediaWords, mediaPreview): one answer for the row, the banner and the reply
 * strip, read from the manifest — a round note is a video message, as a voice is a voice message; a sticker is a sticker, a
 * moving picture a GIF. A manifest not read yet (sealed in its blob) is «Media».
 */
fun mediaWords(c: Context, man: JSONObject?): String {
    if (man == null) return c.getString(R.string.lw_media)
    val cap = man.optString("cap").trim()
    val name = man.optString("n").ifEmpty { man.optString("name") }
    return when (man.optString("k")) {
        "img" -> if (name == Stickers.CARD) c.getString(R.string.lw_sticker) else "📷 " + cap.ifEmpty { c.getString(R.string.lw_photo) }
        "vid", "video" -> "📹 " + if (man.optBoolean("r")) c.getString(R.string.lw_video_message) else cap.ifEmpty { c.getString(R.string.lw_video) }
        "aud" -> c.getString(R.string.voice_message)
        "doc" -> if (name.lowercase().endsWith(".gif")) c.getString(R.string.lw_gif) else "📄 " + name.ifEmpty { c.getString(R.string.file) }
        else -> c.getString(R.string.lw_media)
    }
}

/** The row's words without the glyph the vocabulary puts first, when a thumbnail stands there (iOS MontanaRowWords.bare). */
fun bareWords(p: String): String = listOf("🎤 ", "📹 ", "📷 ", "📄 ", "📞 ").firstOrNull { p.startsWith(it) }?.let { p.removePrefix(it) } ?: p

private val AUDIO_NAMES = setOf("mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aif", "aiff")

/**
 * THE ROW'S ONE WORD FOR WHAT A LETTER CARRIES (iOS ChatStore.rowMediaKind): the voice, the round note, the video, the photo,
 * music, a file — by the manifest, once the file is here — and the link of a letter of words. The thumbnail draws by it.
 */
fun rowKind(m: Msg): String? {
    Calls.info(m.text)?.let { return if (it.video) "vcall" else "acall" }
    if (!m.text.startsWith(Marks.MEDIA)) return if (LinkPreview.webURLs(m.text).isNotEmpty()) "link" else null
    val f = m.file?.let { java.io.File(it) }?.takeIf { it.exists() } ?: return null
    val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
    return when (man?.optString("k")) {
        "aud" -> "aud"
        "vid", "video" -> if (man.optBoolean("r")) "vnote" else "vid"
        "img" -> "img"
        "doc" -> if (man.optString("n").substringAfterLast('.', "").lowercase() in AUDIO_NAMES || f.extension.lowercase() in AUDIO_NAMES) "music" else "doc"
        else -> null
    }
}

private val rowPosters = Caches.kept("row_posters", android.util.LruCache<String, android.graphics.Bitmap>(48))

/** The small picture of a letter: the face its manifest carries, else the file's own first frame, kept while the list lives. */
private fun rowPoster(c: Context, m: Msg, kind: String): android.graphics.Bitmap? {
    rowPosters.get(m.mid)?.let { return it }
    val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
    val pic = Media.thumbOf(man)
        ?: m.file?.let { java.io.File(it) }?.takeIf { it.exists() }?.let { Media.preview(c, it, if (kind == "img") "img" else "vid", 96) }
    pic?.let { rowPosters.put(m.mid, it) }
    return pic
}

/**
 * ONE THUMBNAIL OF WHAT A LETTER CARRIES (iOS MTLetterThumb; side 20 in the list row): the voice's round of glass with the
 * quiet prism sheen (MTVoiceRound), the round note's window with its poster (MontanaNoteFrame), the photo and the video's
 * poster, and the quiet plate with the system's glyph for music, a file, a link.
 */
/** THE VOICE'S ROUND OF GLASS, ONE OWNER (iOS MTVoiceRound, MontanaBubble 3379-3397): the glass circle, the quiet prism sheen (cyan,
 *  purple, pink at 0.22) and the thin rim — the capsule's round in the feed and the list's thumbnail of a voice. */
fun Context.voiceRoundPlate(): android.graphics.drawable.Drawable = android.graphics.drawable.LayerDrawable(arrayOf(glassPlate(oval = true), GradientDrawable().apply {
    shape = GradientDrawable.OVAL
    gradientType = GradientDrawable.SWEEP_GRADIENT
    colors = intArrayOf(Color.argb(56, 50, 173, 230), Color.argb(56, 175, 82, 222), Color.argb(56, 255, 45, 85), Color.argb(56, 50, 173, 230))
    setStroke(1, Color.argb(89, 255, 255, 255))
}))

fun Context.letterThumb(m: Msg, kind: String, sideDp: Int = 20): View {
    val side = dp(sideDp)
    fun plate(glyph: Int) = FrameLayout(this).apply {
        background = rounded(Color.rgb(41, 41, 41), sideDp * 0.22f)
        addView(icon(glyph, MT.gray), FrameLayout.LayoutParams(side / 2, side / 2, Gravity.CENTER))
    }
    return when (kind) {
        "aud" -> FrameLayout(this).apply {
            background = voiceRoundPlate()
            addView(icon(R.drawable.ic_play_fill, Color.WHITE), FrameLayout.LayoutParams(side * 2 / 5, side * 2 / 5, Gravity.CENTER))
        }
        "vnote", "img", "vid" -> {
            val pic = rowPoster(this, m, kind)
            if (pic == null && kind != "vnote") plate(if (kind == "img") R.drawable.ic_photo else R.drawable.ic_peer_video)
            else ImageView(this).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                if (pic != null) setImageBitmap(pic) else setBackgroundColor(Color.BLACK)
                outlineProvider = object : android.view.ViewOutlineProvider() {
                    override fun getOutline(v: View, o: android.graphics.Outline) =
                        if (kind == "vnote") o.setOval(0, 0, v.width, v.height) else o.setRoundRect(0, 0, v.width, v.height, v.width * 0.22f)
                }
                clipToOutline = true
            }
        }
        "music" -> plate(R.drawable.ic_play_fill)
        "link" -> plate(R.drawable.ic_link)
        "acall" -> plate(R.drawable.ic_peer_phone)
        "vcall" -> plate(R.drawable.ic_peer_video)
        else -> plate(R.drawable.ic_set_doc)
    }
}

private var roomFace: android.graphics.Bitmap? = null
/** The face of a correspondent: the face laid beside the pipe, else the drawn initial (iOS MontanaAvatar). */
fun Context.peerFace(ref: String, name: String, sizeDp: Int): View {
    // THE MONTANA ROOM'S FACE IS THE APP'S ICON (iOS montanaRoomFace «IconGlassPreview»): the glass icon in the list and the chat's head alike
    if (Book.isMontana(ref)) return avatar(roomFace ?: BitmapFactory.decodeResource(resources, R.drawable.app_icon_glass_art)?.also { roomFace = it }, "M", sizeDp)
    val f = Book.shownFace(ref)
    val bmp = if (sizeDp <= 64) SmallPicture.of(f) else if (f.exists()) BitmapFactory.decodeFile(f.path) else null
    // THE GLYPH IS THEIRS EVEN UNDER MY NAME FOR THEM (iOS MTNameBook.faceGlyph/.face, MontanaNameBook.swift:104-122,
    // fork atom 8db297589396, 20.09): the emoji a person wears without a photo is the one THEY declared, not my own
    // rename of them — my word for them stands in only when they never said one. A group has no declared word of
    // its own; its title is the only glyph source.
    val glyph = (if (!Groups.isKey(ref)) Book.chat(ref)?.name?.ifBlank { null } else null) ?: name
    return avatar(bmp, glyph.ifBlank { "?" }, sizeDp)
}

/**
 * THE ONE FACE OF A CHAT (iOS MTChatFace → AvatarCircle timeMarkWhenMissing, 7e084edda45d; MTTimeMarkAvatar, MontanaShapes.swift:532-540):
 * the list's row, the contacts, the calls, the search, the chat's head and the hold menu's plate draw a person or a group by it. A
 * chosen face (the Montana room's icon, one's own in Saved Messages) stands as it is; with none, «absence is a complete, stable visual answer of its own» —
 * the black round with the sign (the iPhone's Logo) at 28 of the side and a rim of white 0.35, never a letter. The hexagon of iOS is
 * drawn as a circle under the platform's own look, the only look (MontanaSkin native), so the round is the same figure.
 */
fun Context.chatFace(ref: String, name: String, sizeDp: Int): View {
    if (ref == Book.SAVED) return avatar(SelfFace.load(this), Prefs.userName, sizeDp)   // the room without an address wears one's own (MTSelfFace)
    if (Book.isMontana(ref) || Book.shownFace(ref).exists()) return peerFace(ref, name, sizeDp)
    return FrameLayout(this).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.BLACK); setStroke(dp(1), Color.argb(89, 255, 255, 255)) }
        val pad = Math.round(dp(sizeDp) * 0.36f)
        addView(ImageView(context).apply {
            setImageResource(R.drawable.logo); scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(pad, pad, pad, pad)
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

/**
 * EVERY SMALL PICTURE IN A ROW IS BORN SMALL (iOS MontanaSmallPicture, MontanaMedia 1754-1760, the author's word 16.09): a face of 64
 * or less is drawn from a copy 192 px on its long side, decoded once and kept while its file stands unchanged — never the whole
 * photograph decoded again for every row.
 */
object SmallPicture {
    private const val SIDE = 192
    private val kept = Caches.kept("small_pictures", object : android.util.LruCache<String, android.graphics.Bitmap>(4 * 1024 * 1024) {
        override fun sizeOf(key: String, value: android.graphics.Bitmap) = value.byteCount
    })
    fun of(f: java.io.File): android.graphics.Bitmap? {
        if (!f.exists()) return null
        val key = f.path + "@" + f.lastModified()
        kept.get(key)?.let { return it }
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.path, o)
        var step = 1
        while (SIDE <= maxOf(o.outWidth, o.outHeight) / (step * 2)) step *= 2
        val b = BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = step }) ?: return null
        kept.put(key, b)
        return b
    }
}

/**
 * A BUBBLE'S PICTURE FOLLOWS ITS ROW (the author's word 09.10.2026 11:5x MSK: «I tap a chat and it thinks long while opening»; measured on
 * A1, build 249: a chat of 32 rows took 1063 ms to lay, and its four films had their first frames read by ThumbnailUtils on the main
 * thread -- a second tap, queued behind it, opened the chat twice): the row stands at once with the manifest's own small picture, the
 * full one and its mirrored blur are read on one worker, kept while their file stands unchanged, and laid in place when they come
 * (iOS: the feed's cells are drawn at once and their pictures follow).
 */
object BubblePicture {
    class Shot(val pic: android.graphics.Bitmap, val blur: android.graphics.Bitmap)
    private val kept = Caches.kept("bubble_pictures", object : android.util.LruCache<String, Shot>(32 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Shot) = value.pic.byteCount + value.blur.byteCount
    })
    private val worker = java.util.concurrent.Executors.newSingleThreadExecutor()
    private class Ask(val done: (Shot) -> Unit, val refused: (() -> Unit)?)
    private val waiting = HashMap<String, MutableList<Ask>>()
    private fun key(f: java.io.File, kind: String, px: Int) = f.path + "@" + f.lastModified() + "@" + kind + "@" + px
    fun kept(f: java.io.File, kind: String, px: Int): Shot? = kept.get(key(f, kind, px))
    fun load(c: Context, f: java.io.File, kind: String, px: Int, refused: (() -> Unit)? = null, done: (Shot) -> Unit) {
        val k = key(f, kind, px)
        kept.get(k)?.let { done(it); return }
        synchronized(waiting) {
            waiting[k]?.let { it.add(Ask(done, refused)); return }
            waiting[k] = mutableListOf(Ask(done, refused))
        }
        worker.execute {
            val shot = Media.preview(c, f, kind, px)?.let { Shot(it, WallPlacer.mirrorBlur(it)) }
            if (shot != null) kept.put(k, shot)
            val all = synchronized(waiting) { waiting.remove(k) } ?: emptyList()
            MainThread.post { all.forEach { a -> if (shot != null) a.done(shot) else a.refused?.invoke() } }
        }
    }
    /**
     * THE CIRCLE ASKS UNTIL IT WEARS ITS FRAME (iOS MTNoteFrame.wear, atom 3ce81b0e64f9): the decoder refuses while a call or an
     * encoder holds it, and one refusal left the manifest's small frame on the circle for the bubble's whole life. A refusal is
     * asked again at a growing pause, one second to thirty; the asking ends at the frame, after five empty answers, or when the
     * view that asked has left the screen. The small frame stands meanwhile.
     */
    fun wear(c: Context, f: java.io.File, kind: String, px: Int, view: View, done: (Shot) -> Unit) {
        var empty = 0
        var pause = 1000L
        fun ask() {
            load(c, f, kind, px, refused = {
                empty++
                android.util.Log.d("Montana", "note_frame refused try=" + empty + " -- the preview stands, the circle asks again")
                if (empty < 5) {
                    view.postDelayed({ if (view.isAttachedToWindow) ask() }, pause)
                    pause = minOf(pause * 2, 30_000L)
                }
            }, done = done)
        }
        ask()
    }
}

// ─────────────────────────── the banner (iOS MontanaNotify) ───────────────────────────

/**
 * THE SYSTEM HEARS A CONVERSATION'S ALIAS, NEVER ITS LINK (iOS MTNoticeAlias, 4a729f25): a banner's tag, its id, the pending intent
 * of its tap and the ring's page handed the system the conversation link -- and every app the person lets read notifications reads
 * a banner's tag. Each conversation wears one alias on this device -- «n:» and sixteen random bytes, made of nothing, different on
 * the other phone of the pair -- read back here alone. The store is this device's: mt.defaults is out of every system copy and no
 * copy of ours names the key; a conversation erased takes its alias, the person leaving takes them all (Prefs.forgetPerson).
 */
object NoticeAlias {
    private const val KEY = "noticeAliases"   // NOT-UI: alias to link, this device's names, never a copy
    const val HEAD = "n:"
    private val random = java.security.SecureRandom()
    // BOUND-OK: one row a conversation that rang; a conversation erased takes its row (forget).
    private fun rows(): JSONObject = runCatching { JSONObject(Prefs.str(KEY, "{}")) }.getOrElse { JSONObject() }
    /** The alias a conversation already wears here, or none: a look that gives birth to nothing. */
    @Synchronized fun held(conv: String): String? {
        val m = rows()
        return m.keys().asSequence().firstOrNull { a -> m.optString(a) == conv }
    }
    /** The alias a conversation wears on this device, born once, of nothing. */
    @Synchronized fun of(conv: String): String {
        if (conv.isEmpty()) return conv
        held(conv)?.let { return it }
        val a = HEAD + ByteArray(16).also { random.nextBytes(it) }.joinToString("") { "%02x".format(it) }
        Prefs.setStr(KEY, rows().put(a, conv).toString())
        return a
    }
    /** A value the system handed back: an alias read to its conversation; any other value (a link of the builds before) as it is. */
    @Synchronized fun open(value: String): String =
        if (!value.startsWith(HEAD)) value else rows().optString(value).ifEmpty { value }
    /** A conversation erased: its alias leaves, and is said, so the banners it named go with it. */
    @Synchronized fun forget(conv: String): List<String> {
        val m = rows()
        val gone = m.keys().asSequence().filter { a -> m.optString(a) == conv }.toList()
        if (gone.isEmpty()) return gone
        gone.forEach { m.remove(it) }
        Prefs.setStr(KEY, m.toString())
        return gone
    }
}

object Notify {
    private const val CHANNEL = "letters"
    /** The chat a banner speaks of, carried by its tap (iOS userInfo «chat» → ui.openChat, MontanaApp.didReceive). */
    const val EXTRA_CHAT = "montana.chat"
    @Volatile var tappedAt = 0L   // the tap's moment, read by the conversation's appearance (iOS notif_tap → chat_open why=banner)
    /** THE BANNER OPENS ITS CHAT (iOS didReceive → ui.openChat, atoms 4b49d03f071b, 86cef409a440): not the app's first page. */
    private fun opening(c: Context, ref: String): PendingIntent {
        val sys = NoticeAlias.of(ref)   // the tap names its chat by this phone's alias, read back in MainActivity.takeChat
        return PendingIntent.getActivity(c, sys.hashCode(),
            (c.packageManager.getLaunchIntentForPackage(c.packageName) ?: Intent()).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra(EXTRA_CHAT, sys),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
    private const val LETTER = 1   // a letter's banner: one a chat, under the chat's alias as its tag
    private const val QUIET = "letters_quiet"
    fun letter(ref: String, text: String, who: String? = null, mid: String? = null, mentioned: Boolean = false) {
        val c = Book.ctx
        val nm = c.getSystemService(NotificationManager::class.java) ?: return
        if (!Prefs.bool("notifMessages", true)) return
        // NO BANNER WHILE A PERSON PLAYS (iOS MTPlayQuiet.held, ContentView.swift:3232-3240, the author's words 03.10, atom
        // 9aa1fe955129): a chess board on the screen of the app in front says no letter of anyone; a phone in the background or
        // locked rings every letter. The Money Flow half of the rule waits for the flow, which Android has not.
        if (ChessSend.shownGame != null && CallScreen.front != null) return
        // A MUTED OR ARCHIVED CHAT SAYS NOTHING (iOS MTQuietChats, MontanaNotify 190-193; build 2083): no banner, no sound, no count --
        // but A MENTION RINGS THROUGH THE MUTE (iOS presentGroup mentioned, stage R): the person was named in a group
        if (!mentioned && (ChatMarks.isMuted(ref) || ChatMarks.isArchived(ref))) return
        // THE SOUND IS THE PERSON'S SWITCH (iOS MontanaNotify 379, NotificationService 400): a channel's sound is the platform's
        // once made, so the quiet letters have a channel of their own
        val sound = Prefs.bool("notifSound", true)
        val channel = if (sound) CHANNEL else QUIET
        nm.createNotificationChannel(NotificationChannel(channel, c.getString(if (sound) R.string.channel_letters else R.string.channel_letters_quiet), NotificationManager.IMPORTANCE_HIGH).apply {
            if (!sound) { setSound(null, null); enableVibration(false) }
        })
        val chat = Book.chat(ref)
        // SHOW SENDER OFF NAMES NOBODY (iOS MontanaNotify.showsSender, 245f03f5): the title reads Montana and a group's letter says
        // no speaker -- the switch reached personal letters only, and «who: words» still named who wrote in a group
        val sender = Prefs.bool("notifSender", true)
        val title = if (sender) chat?.shown?.ifBlank { null } ?: c.getString(R.string.peer) else "Montana"
        val shown = if (!Prefs.bool("notifPreview", true)) c.getString(R.string.new_message)
            else if (ContentFilter.hides(false, text)) c.getString(R.string.filter_hidden)   // the banner folds as the feed does (iOS NotificationService 399)
            else letterWords(c, text).ifBlank { c.getString(R.string.new_message) }   // no notification without words (iOS build 2070)
        val body = if (who.isNullOrEmpty() || !sender) shown else "$who: $shown"   // a group's letter says who wrote it (iOS presentGroup)
        val open = opening(c, ref)
        val n = Notification.Builder(c, channel)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)   // USER-DATA: the correspondent's name
            .setContentText(body)     // USER-DATA: the letter
            .apply { if (sender) faceOf(ref)?.let { setLargeIcon(it) } }   // USER-DATA: the correspondent's or the group's face
            .setAutoCancel(true)
            .setContentIntent(open)
            // THE NAME STANDS ON THE LOCKED SCREEN (iOS 1715, hiddenPreviewsShowTitle, MontanaP2PNode 1268-1290): with the system
            // hiding a locked phone's contents, the person's name stays and the words read «New message»; the switch can take it
            .setPublicVersion(Notification.Builder(c, channel)
                .setSmallIcon(R.drawable.ic_launcher_monochrome)
                .setContentTitle(if (Prefs.bool("notifLockName", true)) title else "Montana")   // USER-DATA: the correspondent's name
                .setContentText(c.getString(R.string.new_message))
                .build())
            .build()
        runCatching { nm.notify(NoticeAlias.of(ref), LETTER, n) }
        // the letter the banner speaks of: its deletion takes the banner off (withdraw); a call's or a game's banner names none
        if (mid != null) Prefs.setStr(NOTICE + ref, mid) else Prefs.remove(NOTICE + ref)
    }
    private const val NOTICE = "noticeMid."
    /**
     * A BANNER WEARS ITS CHAT'S OWN FACE (iOS 8cd39e19 at 2229, the author's words 17.10: «the notifications' thumbnails for groups
     * and channels»): a group's letter shows the group's face, never the face of the one who carried its word; a person's letter the
     * person's. The face is the chat's own file (Book.shownFace -- a group's lives under its key), drawn round; none -- no picture,
     * and no letter in a circle (iOS left the gold letter for the bare banner).
     */
    fun faceOf(ref: String): android.graphics.Bitmap? = runCatching {
        val f = Book.shownFace(ref).takeIf { it.exists() } ?: return null
        val o = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
        android.graphics.BitmapFactory.decodeFile(f.path, o)
        var step = 1
        while (minOf(o.outWidth, o.outHeight) / (step * 2) >= 192) step *= 2
        val src = android.graphics.BitmapFactory.decodeFile(f.path, android.graphics.BitmapFactory.Options().apply { inSampleSize = step }) ?: return null
        val side = minOf(src.width, src.height)
        val out = android.graphics.Bitmap.createBitmap(side, side, android.graphics.Bitmap.Config.ARGB_8888)
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            shader = android.graphics.BitmapShader(src, android.graphics.Shader.TileMode.CLAMP, android.graphics.Shader.TileMode.CLAMP).apply {
                setLocalMatrix(android.graphics.Matrix().apply { setTranslate(-(src.width - side) / 2f, -(src.height - side) / 2f) })
            }
        }
        android.graphics.Canvas(out).drawCircle(side / 2f, side / 2f, side / 2f, paint)
        out
    }.getOrNull()
    /**
     * A DELETION TAKES ITS LETTER'S BANNER OFF (iOS b6ab7094 at 2240, the author's words 16.10.2026 18:19-18:59 MSK: «let deletion
     * reach me by a silent push»; the extension takes off every notice named by the deleted letter's mid): the row left the feed, and
     * the banner kept its words on the shade and the locked screen. A banner of a later letter of the chat stands.
     */
    fun withdraw(ref: String, mid: String) {
        if (Prefs.str(NOTICE + ref, "") != mid) return
        clear(ref)
        android.util.Log.d("Montana", "notice_off why=deleted to=" + ref.take(10))
    }
    /**
     * THE PEER PINNED A LETTER (iOS presentPinned, MontanaNotify.swift:334-350 at 2155, the author's word 22.09): the app's own
     * banner -- the person's name, the pin and the letter's words, or the plain fact when previews are off; nothing while this
     * chat stands open -- the pinned plate there is the word already.
     */
    fun pinned(ref: String, sid: String, m: Msg) {
        val c = Book.ctx
        val nm = c.getSystemService(NotificationManager::class.java) ?: return
        if (!Prefs.bool("notifMessages", true) || ChatMarks.isMuted(ref) || ChatMarks.isArchived(ref) || Book.openChat == ref) return
        val sound = Prefs.bool("notifSound", true)
        val channel = if (sound) CHANNEL else QUIET
        nm.createNotificationChannel(NotificationChannel(channel, c.getString(if (sound) R.string.channel_letters else R.string.channel_letters_quiet), NotificationManager.IMPORTANCE_HIGH).apply {
            if (!sound) { setSound(null, null); enableVibration(false) }
        })
        val sender = Prefs.bool("notifSender", true)
        val title = if (sender) Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer) else "Montana"
        val body = "📌 " + if (Prefs.bool("notifPreview", true)) letterWords(c, m).ifBlank { c.getString(R.string.ld_pinned_banner) } else c.getString(R.string.ld_pinned_banner)
        val open = opening(c, ref)
        val n = Notification.Builder(c, channel)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)   // USER-DATA: the correspondent's name
            .setContentText(body)     // USER-DATA: the letter
            .apply { if (sender) faceOf(ref)?.let { setLargeIcon(it) } }   // USER-DATA: the chat's face
            .setAutoCancel(true)
            .setContentIntent(open)
            .setPublicVersion(Notification.Builder(c, channel)
                .setSmallIcon(R.drawable.ic_launcher_monochrome)
                .setContentTitle(if (Prefs.bool("notifLockName", true)) title else "Montana")   // USER-DATA: the correspondent's name
                .setContentText(c.getString(R.string.new_message))
                .build())
            .build()
        runCatching { nm.notify("pin:" + NoticeAlias.of(ref), sid.hashCode(), n) }
    }
    fun clear(ref: String) {
        val nm = Book.ctx.getSystemService(NotificationManager::class.java)
        NoticeAlias.held(ref)?.let { nm?.cancel(it, LETTER) }
        nm?.cancel(ref.hashCode())   // a banner of the builds before, under the link's own number
        Prefs.remove(NOTICE + ref)
    }
    /** The conversation left this device: every banner it named goes, the pins' and the keeper's too, and its alias with them. */
    fun forget(ref: String) {
        clear(ref)
        ShareSuggest.forget(ref)   // the share sheet no longer offers it (iOS forgetSuggestions), named by the alias about to go
        val gone = (NoticeAlias.forget(ref) + ref).toSet()
        val nm = Book.ctx.getSystemService(NotificationManager::class.java) ?: return
        runCatching { nm.activeNotifications }.getOrNull()?.forEach { s ->
            val t = s.tag ?: return@forEach
            if (t in gone || t.substringAfter(':') in gone) nm.cancel(t, s.id)
        }
    }
    /**
     * MY DELETION WAS KEPT THERE (iOS presentKept, MontanaNotify.swift:348 at 2242; MTLevelAccess.keepDeleted 16.10.2026 No.72): the
     * keeper's own word -- the correspondent's name over the fact that the letter I deleted for everyone stays on their phone, and
     * the rule of the levels that made it. An album is several letters, each kept by its own word: one banner a chat in half a
     * minute; a newer one stands in its place. It shows in the open chat too -- it is no letter the chat draws.
     */
    private val keptToldAt = HashMap<String, Long>()
    fun kept(ref: String) {
        val c = Book.ctx
        val nm = c.getSystemService(NotificationManager::class.java) ?: return
        if (!Prefs.bool("notifMessages", true)) { android.util.Log.d("Montana", "notify_skip why=disabled kind=kept"); return }
        val now = System.currentTimeMillis()
        synchronized(keptToldAt) {
            if (keptToldAt[ref]?.let { now - it < 30_000 } == true) { android.util.Log.d("Montana", "notify_skip why=kept-already-told"); return }
            keptToldAt[ref] = now
        }
        val sound = Prefs.bool("notifSound", true)
        val channel = if (sound) CHANNEL else QUIET
        nm.createNotificationChannel(NotificationChannel(channel, c.getString(if (sound) R.string.channel_letters else R.string.channel_letters_quiet), NotificationManager.IMPORTANCE_HIGH).apply {
            if (!sound) { setSound(null, null); enableVibration(false) }
        })
        val title = if (Prefs.bool("notifSender", true)) Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer) else "Montana"
        val body = c.getString(R.string.kept_banner, KEEP_DELETED_LEVEL)
        val n = Notification.Builder(c, channel)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)   // USER-DATA: the correspondent's name
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(opening(c, ref))
            .setPublicVersion(Notification.Builder(c, channel)
                .setSmallIcon(R.drawable.ic_launcher_monochrome)
                .setContentTitle(if (Prefs.bool("notifLockName", true)) title else "Montana")   // USER-DATA: the correspondent's name
                .setContentText(body)
                .build())
            .build()
        android.util.Log.d("Montana", "notify kind=kept from=" + ref.take(10))
        runCatching { nm.notify("kept:" + NoticeAlias.of(ref), 0, n) }
    }
    /** The level that opens «Forbid deletion on my phone» (iOS MTLevelAccess.Feature.keepDeleted.level). */
    const val KEEP_DELETED_LEVEL = 7
}

// ─────────────────────────── the chats as rows (iOS MTChatListView rows) ───────────────────────────

/** One conversation in the list: the face, the name, the last letter, its time and the unread count. */
/**
 * THE CHATS PAGE'S LINE (iOS ChatRow with library, MontanaChatsList.swift:2121-2226) in the App Library's measure, as the contacts'
 * and the calls': 72 high, the face 48 with the platform's presence dot while the word is live, the gap 16, the side 18; the two
 * lines at fixed heights, 22 and 20, 4 apart -- the name 17 semibold, the struck bell 12, the dots and the hour 14; under them one
 * line of 16: the draft in red first, else the thumbnail and the last letter; at its end the count, the hand's dot or the pin.
 */
fun chatRow(act: MainActivity, chat: Chat): View {
    val c: Context = act
    val last = chat.last
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(18), 0, dp(18), 0)
        minimumHeight = dp(72)
        addView(FrameLayout(c).apply {
            clipChildren = false
            addView(c.chatFace(chat.ref, chat.shown, 48), FrameLayout.LayoutParams(dp(48), dp(48)))
            if (!Groups.isKey(chat.ref) && Presence.word(c, chat.ref)?.second == true)
                addView(presenceBadge(c), FrameLayout.LayoutParams(dp(13), dp(13), Gravity.BOTTOM or Gravity.END))
        }, lp(dp(48), dp(48)).apply { marginEnd = dp(16) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(callHandset(act, true, chat.ref), lp(dp(44), dp(44)))   // 15.8 (iOS ChatRow 2143)
                addView(c.text(chat.shown.ifBlank { c.getString(R.string.peer) }, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
                addView(callHandset(act, false, chat.ref), lp(dp(44), dp(44)))   // 15.8 (iOS ChatRow 2150)
                // a muted chat wears the struck bell after its name (iOS ChatRow muted)
                if (ChatMarks.isMuted(chat.ref)) addView(c.icon(R.drawable.ic_bell_off, MT.gray, 12), lp(dp(12), dp(12)).apply { marginEnd = dp(5) })
                // a group's living room: the small green mark after its name (iOS MTRoomRowMark)
                Rooms.brief(chat.ref)?.let { b -> addView(c.icon(Rooms.glyph(b), SysColor.green, 12), lp(dp(12), dp(12)).apply { marginEnd = dp(5) }) }
                if (last != null) {
                    // the ladder's dots left of the hour, only when the last word was mine; a letter that did not go, the red mark
                    // THE ROW READS A PLATE AS ITS LINE DOES (iOS ChatStore.ladderLetter, MTLadder): the last plate's slowest letter, so
                    // one pick never says two things at once — read on the feed's tail, where a plate stands whole
                    val stage = if (!last.mine) last else feedRows(chat.msgs.takeLast(30).filter { !ChessLetter.isStep(it.text) }).lastOrNull()
                        ?.takeIf { r -> r.any { it.mid == last.mid } }?.minWithOrNull(compareBy<Msg>({ it.state }, { -it.statusMoment })) ?: last
                    addView(FrameLayout(c).apply {
                        addView(c.hstack {
                            gravity = Gravity.CENTER_VERTICAL
                            if (last.mine && !Groups.isEvent(last.text)) addView(if (stage.state == -1) c.failedMark() else c.deliveryDots(Ladder.of(chat.ref, stage).first),
                                lp(WRAP, WRAP).apply { marginEnd = dp(6) })
                            addView(c.text(rowTime(c, last.at), 14f, MT.gray))
                        }, FrameLayout.LayoutParams(WRAP, WRAP))
                        // THE BLOCKED PERSON'S ROW WEARS THE MARK UNDER THE CLOCK (iOS ChatRow, MontanaChatsList.swift:2168, build 1565)
                        if (PeerSafety.isBlocked(chat.ref)) addView(c.icon(R.drawable.ic_nosign, SysColor.red, 11),
                            FrameLayout.LayoutParams(dp(11), dp(11), Gravity.BOTTOM or Gravity.END).apply { topMargin = dp(14) })
                    }, lp(WRAP, WRAP))
                }
            }, lp(MATCH, dp(22)))
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                // A DRAFT STANDS UNDER THE NAME (iOS ChatRow 2175-2181, the author's word 20.09): unsent words are what the person will
                // see first on opening -- «Draft:» in red and the text, in place of the last letter
                val draft = Prefs.str("draft." + chat.ref, "").trim().replace('\n', ' ')
                if (draft.isNotEmpty()) addView(c.text("", 16f, MT.gray).apply {
                    text = android.text.SpannableStringBuilder(c.getString(R.string.cl_draft)).apply {
                        setSpan(android.text.style.ForegroundColorSpan(SysColor.red), 0, length, 0)
                        append(" ").append(draft)   // USER-DATA: the draft text
                    }
                    singleLineEllipsis()
                }, lp(0, WRAP, 1f)) else {
                // THE THUMBNAIL BEFORE THE WORDS (iOS MTLetterThumb, side 20, spacing 6): the voice's round and the round note's
                // poster stand in the row as in the player bar; the words then carry no glyph of their own
                // THE ANSWER TO A LETTER, THE PLATE'S WAY (iOS ChatRow 2184-2192, rowReaction): the face of whoever answered (18), the
                // answer (15), then the answered letter's thumbnail and words in place of the last letter's
                val answered = chat.answered
                if (answered != null) {
                    addView(if (chat.ansMine) c.avatar(SelfFace.load(c), Prefs.userName, 18) else c.chatFace(chat.ref, chat.shown, 18),
                        lp(dp(18), dp(18)).apply { marginEnd = dp(6) })
                    addView(c.text(chat.ans!!, 15f, Color.WHITE), lp(WRAP, WRAP).apply { marginEnd = dp(6) })   // USER-DATA: the answer itself
                }
                val shown = answered ?: last
                val kind = shown?.let { rowKind(it) }
                if (shown != null && kind != null) addView(c.letterThumb(shown, kind), lp(dp(20), dp(20)).apply { marginEnd = dp(6); gravity = Gravity.CENTER_VERTICAL })
                // a letter the filter hides is told as hidden in the row, opened or not (iOS ChatStore 159)
                val words = shown?.let { if (ContentFilter.hides(it.mine, it.text)) c.getString(R.string.filter_hidden) else letterWords(c, it) } ?: ""
                addView(c.text(if (kind != null) bareWords(words) else words, 16f, MT.gray).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the last letter
                }
                // THE ROW'S END (iOS ChatRow 2200-2214): the hand's mark first -- the blue dot 11; else the count, caption2 bold on the
                // blue capsule, 7 by 3; else the pin 12, turned 45
                if (ChatMarks.handMark(chat.ref)) addView(View(c).apply { background = c.rounded(SysColor.blue, 6) }, lp(dp(11), dp(11)).apply { marginStart = dp(6) })
                else if (chat.unread > 0) addView(c.text(chat.unread.toString(), 11f, Color.WHITE, bold = true, center = true).apply {
                    background = c.rounded(SysColor.blue, 9); setPadding(dp(7), dp(3), dp(7), dp(3)); minWidth = dp(18)
                }, lp(WRAP, WRAP).apply { marginStart = dp(6) })
                else if (ChatMarks.isPinned(chat.ref)) addView(c.icon(R.drawable.ic_pin, MT.gray, 12).apply { rotation = 45f }, lp(dp(12), dp(12)).apply { marginStart = dp(6) })
            }, lp(MATCH, dp(20)).apply { topMargin = dp(4) })
        }, lp(0, WRAP, 1f))
        pressable { act.push { close -> conversationPage(act, chat.ref, close) } }
        // the list sets the long press itself (ChatList.listRow: the person's menu)
    }
}

// ─────────────────────────── the delivery ladder (iOS MTDeliveryLine, MTDeliveryDots, MTPlayed) ───────────────────────────

/**
 * THE LADDER OF ONE'S OWN LETTER: sending → sent → delivered → read, each rung with its one word. A voice of mine is played,
 * not read: its third rung is the correspondent's own playing («Listened»); a correspondent whose build has said «played»
 * once keeps a mere «read» of a voice at «delivered» — the chat opened is no playing.
 */
object Ladder {
    private fun isVoice(m: Msg) = m.text.startsWith(Marks.MEDIA) &&
        ((m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text))?.optString("k") == "aud")

    /** The rung the dots stand on (0…3) and the word's resource: a voice is Listened, a round note Viewed, not merely Read —
     * each by the correspondent's own playing (iOS MTPlayed, MontanaBubble.swift:1634 at build 2155, atom cbd70b2f08ed). */
    fun of(ref: String, m: Msg): Pair<Int, Int> {
        if (m.state == -1) return 0 to R.string.ladder_failed
        val played = if (isVoice(m)) R.string.ladder_listened else if (roundNote(m)) R.string.ladder_viewed else null
        if (played != null) {
            if (m.heard) return 3 to played
            if (m.state == 3 && Prefs.bool("plcap_$ref", false)) return 2 to R.string.ladder_delivered
        }
        return m.state to when (m.state) {
            0 -> R.string.ladder_sending; 1 -> R.string.ladder_sent; 2 -> R.string.ladder_delivered; else -> R.string.ladder_read
        }
    }

    /** The rung's moment: the hour today, the day and the hour before (iOS MTDeliveryLine.moment). */
    fun moment(c: Context, at: Long): String {
        val t = android.text.format.DateFormat.getTimeFormat(c).format(Date(at))
        return if (DateUtils.isToday(at)) t else DateUtils.formatDateTime(c, at, DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH) + " " + t
    }
}

/** THE THREE DOTS (iOS MTDeliveryDots): five points each, five apart; green once their rung is reached, dark grey before. */
fun Context.deliveryDots(rung: Int): View = hstack {
    gravity = Gravity.CENTER_VERTICAL
    for (k in 1..3) addView(View(context).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (rung >= k) MT.green else Color.rgb(77, 77, 77)) }
    }, lp(dp(5), dp(5)).apply { if (k > 1) marginStart = dp(5) })
}

/** THE LADDER LINE (iOS MTDeliveryLine): the dots, the one word of the rung and — over the menu — the moment it was reached. */
fun Context.deliveryLine(ref: String, m: Msg, withMoment: Boolean = false): View = hstack {
    gravity = Gravity.CENTER_VERTICAL
    val (rung, word) = Ladder.of(ref, m)
    addView(deliveryDots(rung))
    addView(text(getString(word), 12f, Color.WHITE, bold = true), lp(WRAP, WRAP).apply { marginStart = dp(5) })
    if (withMoment) addView(text(Ladder.moment(context, m.statusMoment), 12f, Color.WHITE), lp(WRAP, WRAP).apply { marginStart = dp(5) })
}

/** THE RED MARK of a letter that did not go (iOS MTFailedMark): the bubble's corner and the chat row wear the same one. */
fun Context.failedMark(): View = text("!", 9f, Color.WHITE, bold = true, center = true).apply {
    background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(SysColor.red) }
    layoutParams = LinearLayout.LayoutParams(dp(12), dp(12))
    gravity = Gravity.CENTER
    setPadding(0, 0, 0, 0)
}

// ─────────────────────────── the conversation (iOS ChatConversationView) ───────────────────────────

/**
 * THE CONVERSATION (iOS ChatConversationView): the bar with the back mark, the person's name and face; the letters, newest at
 * the foot, a day's plate over each new day, each letter with its time, its ticks when it is one's own, «edited» when it was,
 * the quote it answers and the reactions it wears; the field on glass with the send artwork. A long press on a letter opens its
 * menu as iOS draws it: the quick reactions over the letter and the actions under it — Reply, Copy, Edit (one's own), Delete
 * (for me / for everyone). The feed follows the book live: a letter that lands, a receipt, a reaction redraw it.
 */
private var noteRing: NoteRing? = null

/**
 * THE ONE ROAD TO A LETTER (iOS ui.showLetter, ContentView.swift:351-354 at 2155): the chat standing on the screen jumps to it, or
 * opens the letter's chat in its place; with no chat standing, the letter's chat opens on it.
 */
object ShowLetter {
    var open: ((String, String) -> Unit)? = null
    /** The letter that carries a file, or the letter itself: the open chat first, then every chat and Saved Messages. */
    fun find(mid: String, file: String?): Pair<String, String>? {
        val chats = listOfNotNull(Book.openChat?.let { Book.chat(it) }) + Book.all() + listOfNotNull(Book.chat(Book.SAVED))
        for (ch in chats) ch.msgs.lastOrNull { (mid.isNotEmpty() && it.mid == mid) || (file != null && it.file == file) }?.let { return ch.ref to it.mid }
        return null
    }
    fun go(act: MainActivity, ref: String, mid: String) {
        open?.invoke(ref, mid) ?: act.push { close -> conversationPage(act, ref, close, jump = mid) }
    }
}

/** `jump` — a letter found by the search: the chat opens on it, and it glows once (iOS openChat(jump:)). */
fun conversationPage(act: MainActivity, ref: String, onClose: () -> Unit, jump: String? = null, search: Boolean = false): View {
    val c: Context = act
    val group = Groups.isKey(ref)   // a group's feed: no pipe, no presence, no doors (iOS MTGroup.isKey)
    // THE ROOM WITHOUT AN ADDRESS (iOS isLocalRoom): Saved Messages opens here like every chat -- no wire, no presence, no rung, no call
    val local = Book.isLocal(ref)
    val saved = ref == Book.SAVED   // one's own room wears one's own face and its own word; the Montana room its crowned name (iOS rowModel)
    val column = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(10), dp(8), dp(10), dp(8)) }
    val draftRow = FrameLayout(c).apply { setPadding(c.dp(10), 0, c.dp(10), c.dp(8)); visibility = View.GONE }
    val feedFrame = FrameLayout(c)
    // THE FEED BEHIND A TAPE IS BLURRED (iOS MontanaConversation.swift:1446-1452 at 2155: «.blur(radius: holding ? 10 : 0)» while a
    // voice or a note records; the open note's cloud blurs it on its own): radius 10, off again where every tape ends (onRecIdle).
    // WHAT STANDS BEHIND THE BLUR TAKES NO TOUCHES (iOS .allowsHitTesting(!recorder.isRecording), MontanaConversation.swift:1420 at
    // 2155, atom 859a533eef70): a finger on a bubble under the blur plays nothing and scrolls nothing while a tape rolls.
    var feedBlocked = false
    fun blurFeed(on: Boolean) {
        if (31 <= android.os.Build.VERSION.SDK_INT) feedFrame.setRenderEffect(if (!on) null
            else android.graphics.RenderEffect.createBlurEffect(c.dp(10).toFloat(), c.dp(10).toFloat(), android.graphics.Shader.TileMode.CLAMP))
        feedBlocked = on
    }
    var keysAway: () -> Unit = {}   // the field is born below
    var panelUp: () -> Boolean = { false }   // the field's own panel stands in the keyboard's place (Picker.kt), born below
    var panelAway: () -> Unit = {}
    var barTop: () -> Int = { Int.MAX_VALUE }   // the bar's top on the screen, once it stands
    var ride: KeyRide? = null   // the keys' cover and the finger that drags them (KeyRide.kt), born with the page below
    var lifted = 0   // how far the bar stands above the page's foot for the keys (their cover, less the panel's own room)
    // THE KEYBOARD GOES WHERE THE IPHONE'S GOES (the author's word 09.10.2026 11:5x MSK: «make the keyboard behave as on iOS -- here it
    // hangs when it is not needed»): a tap anywhere on the feed puts it away, unless a control under the finger took the tap (iOS
    // backgroundTap and MTTouchClaim, MontanaMessageFeed.swift:735-752, 980-986); a finger dragging the feed down onto the bar takes it
    // down (iOS keyboardDismissMode .interactive, 66-71: the keyboard rides under the dragging touch, a release below its top lets it go).
    val scroll = object : ScrollView(c) {
        private val slop = android.view.ViewConfiguration.get(c).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var downT = 0L
        private var moved = false
        private fun keysUp() = rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == true || panelUp()
        override fun dispatchTouchEvent(e: MotionEvent): Boolean {
            if (feedBlocked) return false   // a tape rolls: the feed behind the blur takes no touches (iOS allowsHitTesting)
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> { downX = e.x; downY = e.y; downT = e.eventTime; moved = false }
                MotionEvent.ACTION_MOVE -> {
                    if (slop < kotlin.math.abs(e.x - downX) || slop < kotlin.math.abs(e.y - downY)) moved = true
                    // the keyboard rides the finger (KeyRide); the panel in its place, and a system without the keys' controller, go at once
                    if (moved && downY < e.y && barTop() <= e.rawY.toInt() && (panelUp() || android.os.Build.VERSION.SDK_INT < 30) && keysUp()) keysAway()
                }
                MotionEvent.ACTION_UP -> if (!moved && e.eventTime - downT < android.view.ViewConfiguration.getLongPressTimeout() && keysUp()) {
                    val x = e.x
                    val y = e.y
                    post { if (!claimsTap(this, x, y)) keysAway() }   // one turn later: a control's own tap has run by then
                }
            }
            ride?.touch(e, moved && downY < e.y && !panelUp(), barTop())
            return super.dispatchTouchEvent(e)
        }
    }.apply {
        isVerticalScrollBarEnabled = false
        isFillViewport = true
        // the feed, and under it their live draft (iOS LiveDraftBubble at the feed's foot)
        addView(feedFrame.apply { addView(c.vstack(Gravity.NO_GRAVITY) { addView(column, lp()); addView(draftRow, lp()) }, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM)) })
    }
    fun toBottom() = scroll.post { scroll.scrollTo(0, scroll.getChildAt(0)?.height ?: 0) }

    var replyTo: Msg? = null
    var editing: Msg? = null
    // THE CHAT'S SELECTION (iOS selectingMsgs, selectedMsgs): «Select» in a letter's menu begins it
    var selecting = false
    val picked = linkedSetOf<String>()
    // THE CHAT'S OWN SEARCH (iOS searching / searchText, MontanaConversation.swift:1410-1412, 2495-2537 at 2312): open and asked
    // something, the feed shows only the letters whose words or file name hold the query, in any case and with any accent; a tap on
    // one carries the eye to its own place in the whole conversation (iOS searchJump, 2975-2990)
    var searching = false
    var searchQuery = ""
    var searchLeave: (String) -> Unit = {}
    lateinit var drawFoot: () -> Unit
    var toQuoted: (String) -> Unit = {}

    // A DRAFT OPENS AT ITS END (iOS MontanaBubble.swift:2429-2433 at 2155, atom 8cdb001dfc9d): the caret stands after the
    // last word, not at the beginning -- the writing goes on at once.
    val field = EditText(c).apply { setText(Prefs.str("draft.$ref", "")); setSelection(text.length) }
    // THE KEYBOARD AWAY IS THE FIELD LET GO (iOS inputFocused = false with hideKeyboard): a field kept focused under a hidden keyboard
    // is raised again by the system each time the window comes forward (SHOW_AUTO_EDITOR_FORWARD_NAV, the Pixel's own record 07.10 22:35)
    // and the panel in the keyboard's place goes with it: every other deed of the bar puts it away (iOS showEmoji = false)
    fun hideKeys() { c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(field.windowToken, 0); field.clearFocus(); panelAway() }
    keysAway = { hideKeys() }
    fun showKeys() { field.requestFocus(); c.getSystemService(InputMethodManager::class.java).showSoftInput(field, 0) }

    // AN EMPTY FEED SAYS WHICH EMPTINESS IT IS (iOS MTFeedEmpty, MontanaMessageFeed 227-265; feedEmptyKind, MontanaConversation
    // 2324-2334): a chat that never had a word invites the first one and a tap opens the keyboard; one whose words cannot leave
    // says so — a blank made the person wait for a letter that could not come.
    val emptyGlyph = c.icon(R.drawable.ic_antenna_slash, MT.gray, 30)
    val emptyTitle = c.text("", 17f, Color.WHITE, bold = true, center = true)
    val emptyNote = c.text("", 13f, MT.gray, center = true)
    val emptyView = c.vstack(Gravity.CENTER_HORIZONTAL) {
        visibility = View.GONE
        setPadding(dp(40), 0, dp(40), 0)
        addView(emptyGlyph, LinearLayout.LayoutParams(dp(30), dp(30)).apply { bottomMargin = dp(10) })
        addView(emptyTitle, lp())
        addView(emptyNote, lp().apply { topMargin = dp(10) })
        setOnClickListener { showKeys() }
    }
    feedFrame.addView(emptyView, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.CENTER))
    // THE OTHER SIDE CLOSED THIS CONVERSATION (iOS peerClosedPipe, the closed composer's note; fork atom 1927): its letters are read,
    // not answered — the words stand where the field stood
    var hideBar: () -> Unit = {}   // the field is born below; it hides once the conversation is closed
    val closedNote = c.text(c.getString(if (ref.startsWith("arc:")) R.string.recovered_history else R.string.pipe_closed_note), 13f, MT.gray, center = true).apply {
        setPadding(dp(24), dp(12), dp(24), dp(14)); visibility = if (Post.closed(ref)) View.VISIBLE else View.GONE
        background = c.glassPlate().apply { cornerRadius = dp(18).toFloat() }
    }
    fun drawEmpty(empty: Boolean, asked: Boolean = false) {
        if (!empty) { emptyView.visibility = View.GONE; return }
        emptyNote.visibility = View.VISIBLE
        // a search with a query is about the query (iOS feedEmptyKind .noResults, MTFeedEmpty: the magnifier and «Nothing found»)
        if (asked) {
            emptyGlyph.setImageResource(R.drawable.ic_search); emptyGlyph.visibility = View.VISIBLE
            emptyTitle.setText(R.string.nothing_found); emptyNote.visibility = View.GONE
            emptyView.isClickable = false; emptyView.visibility = View.VISIBLE
            return
        }
        emptyGlyph.setImageResource(R.drawable.ic_antenna_slash)
        val cm = c.getSystemService(android.net.ConnectivityManager::class.java)
        val net = cm?.getNetworkCapabilities(cm.activeNetwork)?.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val offline = !net || Signal.aliveHosts().isEmpty()
        emptyGlyph.visibility = if (offline) View.VISIBLE else View.GONE
        emptyTitle.setText(if (offline) R.string.feed_no_network else R.string.feed_fresh)
        emptyNote.setText(if (offline) R.string.feed_no_network_note else R.string.feed_fresh_note)
        emptyView.isClickable = !offline   // only the one state with something to do takes a tap (iOS allowsHitTesting)
        emptyView.visibility = View.VISIBLE
    }

    // THE LINE OVER THE FIELD (iOS the reply/edit strip): what the next letter answers, or which letter is being changed.
    val stripLead = c.hstack()   // the reply's glyph and thumbnail (iOS barPlate's HStack, MontanaConversation.swift:2578-2587); the edit's own bar; showStrip fills it
    val stripTitle = c.text("", 12f, MT.blue, bold = true)
    val stripWords = c.text("", 14f, Color.WHITE).apply { singleLineEllipsis() }
    val strip = c.hstack {
        visibility = View.GONE
        background = c.glassPlate().apply { cornerRadius = dp(18).toFloat() }   // the feed runs under it: the plate carries the glass
        setPadding(dp(16), dp(6), dp(8), dp(6))
        addView(stripLead, lp(WRAP, WRAP).apply { marginEnd = dp(8) })
        addView(c.vstack(Gravity.NO_GRAVITY) { addView(stripTitle); addView(stripWords) }, lp(0, WRAP, 1f))
        addView(c.icon(R.drawable.ic_close, MT.gray).apply {
            setPadding(dp(8), dp(8), dp(8), dp(8))
            pressable { if (editing != null) field.setText(""); replyTo = null; editing = null; this@hstack.visibility = View.GONE }
        }, lp(dp(36), dp(36)))
    }
    // THE REPLY'S AND THE EDIT'S PLATE CARRIES THE EYE TO ITS LETTER ON A TAP (iOS build 1868, barPlate onTap — the pinned plate's road),
    // the keys staying up; its cross keeps its own tap
    strip.setOnClickListener { (editing ?: replyTo)?.let { toQuoted(it.mid) } }
    fun showStrip() {
        val r = replyTo; val e = editing
        strip.visibility = if (r == null && e == null) View.GONE else View.VISIBLE
        stripLead.removeAllViews()
        if (e != null) {
            stripTitle.text = c.getString(R.string.editing); stripWords.text = letterWords(c, e)
            stripLead.addView(View(c).apply { setBackgroundColor(MT.blue) }, lp(c.dp(3), c.dp(34)))
        } else if (r != null) {
            // THE REPLY'S GLYPH AND THUMBNAIL (iOS replyPreview, MontanaConversation.swift:3269-3272; barPlate, 2576-2599): the
            // arrow at the bar's own 14pt (2580) and the quoted letter's small picture at composeHeight - 8 = 28dp (3272;
            // composeHeight 36, MontanaBubble.swift:2331) when ChatStore.rowMediaKind names a kind for it (MontanaChatStore.swift:
            // 368-377, which names the reply bar at 365-366) — a letter of plain words shows none, as MTLetterThumb's failable
            // init returns nil for it.
            stripTitle.text = c.getString(R.string.reply_to, if (r.mine) Prefs.userName.ifBlank { c.getString(R.string.coin_you) }
                else if (group) Groups.speakerName(c, r.from)   // a group's letter is its speaker's (iOS speakerName)
                else Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer))
            stripLead.addView(c.icon(R.drawable.ic_reply, MT.blue, 14), lp(c.dp(14), c.dp(14)))
            val kind = rowKind(r)
            if (kind != null) {
                stripLead.addView(c.letterThumb(r, kind, 28), lp(c.dp(28), c.dp(28)).apply { marginStart = c.dp(8) })
                stripWords.text = bareWords(letterWords(c, r))   // USER-DATA: the glyph the thumbnail already shows (iOS MontanaRowWords.bare)
            } else {
                stripWords.text = letterWords(c, r)   // USER-DATA
            }
        }
    }

    // THE CARD IS SEEN BEFORE IT RIDES (iOS linkPlate, MontanaConversation.swift:3246-3263 at 2155, the critic 22.09): a link
    // in the field grows a plate above it -- the page's title and words, or the link itself while it is read -- and the
    // cross beside it drops the card for this letter alone.
    val linkTitle = c.text("", 14f, Color.WHITE, bold = true).apply { singleLineEllipsis() }
    val linkWords = c.text("", 13f, MT.gray).apply { singleLineEllipsis() }
    val linkPlate = c.hstack {
        visibility = View.GONE
        background = c.glassPlate().apply { cornerRadius = dp(18).toFloat() }
        setPadding(dp(16), dp(6), dp(8), dp(6))
        addView(c.icon(R.drawable.ic_set_link, MT.blue, 16), lp(dp(16), dp(16)).apply { marginEnd = dp(10) })
        addView(c.vstack(Gravity.NO_GRAVITY) { addView(linkTitle); addView(linkWords) }, lp(0, WRAP, 1f))
        addView(c.icon(R.drawable.ic_close, MT.gray).apply {
            setPadding(dp(8), dp(8), dp(8), dp(8))
            pressable { LinkCompose.drop() }
        }, lp(dp(36), dp(36)))
    }
    fun drawLink() {
        val url = LinkCompose.url
        linkPlate.visibility = if (url.isEmpty()) View.GONE else View.VISIBLE
        if (url.isEmpty()) return
        val card = LinkCompose.card
        val host = runCatching { java.net.URL(url).host }.getOrNull()
        linkTitle.text = card?.t ?: card?.s ?: host ?: url   // USER-DATA: the page's own title
        linkWords.text = card?.d ?: card?.s ?: url           // USER-DATA
    }
    drawLink()
    linkPlate.setOnClickListener { runCatching { c.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(LinkCompose.url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }
    val linkListener: () -> Unit = { act.onMain { drawLink() } }

    // THE PEOPLE A «@» NAMES (iOS mentionPlate + MTMentionCompose, stage R, the reference folder's mention list): above a group's field
    // while a word follows «@», five at most -- the people whose name, by any of its words, begins with what is typed; the whole row
    // is the target, and the name goes into the words with a space after it
    val mentionPlate = c.vstack(Gravity.NO_GRAVITY) {
        visibility = View.GONE
        background = c.glassPlate().apply { cornerRadius = dp(18).toFloat() }
    }
    fun drawMentions(text: String) {
        val q = if (group && Groups.isGroup(ref)) Groups.mentionTail(text)?.lowercase() else null
        val all = if (q == null) emptyList() else Groups.mentionable(c, ref)
        val hit = (if (q.isNullOrEmpty()) all else all.filter { p -> p.name.lowercase().split(" ").any { it.startsWith(q) } }).take(5)
        mentionPlate.removeAllViews()
        mentionPlate.visibility = if (hit.isEmpty()) View.GONE else View.VISIBLE
        for (p in hit) mentionPlate.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), 0, dp(12), 0)
            minimumHeight = dp(44)
            addView(c.avatar(null, p.name, 30), lp(dp(30), dp(30)).apply { marginEnd = dp(10) })
            addView(c.text(p.name, 16f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a person's name in the group
            pressable {
                val now = field.text.toString()
                val tail = Groups.mentionTail(now) ?: return@pressable
                val next = now.dropLast(tail.length + 1) + "@" + p.name + " "
                field.setText(next)
                field.setSelection(next.length)   // the caret stands at the end
            }
        }, lp(MATCH, WRAP))
    }

    // ── the feed ──
    // THE FIRST UNREAD AT THIS OPENING (iOS firstUnreadId, MontanaConversation 1225, 2661): the quiet «Unread messages» line stands
    // before it while the page does; read before the page marks the chat read
    val firstUnread = Book.chat(ref)?.let { ch -> if (0 < ch.unread) ch.msgs.filter { !it.mine }.takeLast(ch.unread).firstOrNull()?.mid else null }
    // THE ROWS ARE KEPT BY THEIR LETTER (iOS MTFeedListView.apply, MontanaMessageFeed 821-913 at 2155: the snapshot names each cell
    // by its letter's MID and reconfigures only a cell whose fingerprint moved): every child of the column is named -- a letter's row
    // by its first letter, a day's line and the unread line by the letter they stand before -- and carries the signature of what it
    // shows. A pass keeps a row whose signature stands, builds anew in its own place a row whose signature moved, lays a new row at
    // its index and takes away a row whose letter left; the column is never cleared, so a voice playing keeps its row while another
    // letter lands, and a pass that moved nothing touches no view (iOS «feed saw nothing», 858). The column was built whole again at
    // every word of the book, any chat's.
    class FeedRow(val key: String, val sig: List<Any?>, val letter: Boolean) { var view: View? = null }
    val feed = ArrayList<FeedRow>()
    var laid = false
    // the chat a row reads at a tap (the next round note, the voice's sender): one object every pass refreshes, so a kept row never
    // reads the letters of the pass that built it
    val feedChat = Chat(ref, "")
    // THE BIRTH IN FLIGHT (iOS animateBirth, MontanaMessageFeed 928-966): where each row on the screen stood before the pass, the rows
    // the spring was carrying, the newborns waiting unseen for their rise, and the one spring
    var flight: android.animation.ValueAnimator? = null
    var landing = false
    val stood = HashMap<String, Float>()
    val flying = HashSet<String>()
    val newborn = HashSet<View>()
    // every row that rides stands where it stood: a pass with a newborn holds each row on the screen, a pass without one only the
    // rows the spring was carrying (iOS: no birth, no motion)
    fun pose() {
        if (!landing) return
        val y0 = mediaPlateOffset(column, scroll) - scroll.scrollY
        val all = newborn.isNotEmpty()
        for (r in feed) {
            val v = r.view ?: continue
            val from = stood[r.key] ?: continue
            if (v !in newborn && (all || r.key in flying)) v.translationY = from - (y0 + v.top)
        }
    }
    fun fadeIn(v: View) = v.animate().alpha(1f).setDuration(Math.round(LetterMotion.fade * 1000))
        .setInterpolator(android.view.animation.DecelerateInterpolator()).start()
    // THE RISE (iOS animateBirth 936-966), once the pass is laid and the feed has taken its place (toBottom), before the frame shows
    // it: every row already stands at its final size in its final place; the newborn starts 0.9 of its height below it and fades in
    // as it rises, and each row the settled layout moved rides from where it stood, on the same spring. Nothing is aimed at a guessed
    // place, nothing is measured in flight.
    fun land() {
        if (!landing) return
        pose()
        landing = false
        val y0 = mediaPlateOffset(column, scroll) - scroll.scrollY
        val births = ArrayList<View>()
        for (r in feed) {
            val v = r.view ?: continue
            if (v !in newborn) continue
            val y = y0 + v.top
            if (0 < y + v.height && y < scroll.height) births.add(v) else v.alpha = 1f
        }
        val ways = ArrayList<Pair<View, Float>>()
        for (r in feed) {
            val v = r.view ?: continue
            if (v in newborn) continue
            if (r.key in stood && (births.isNotEmpty() || r.key in flying) && 0.5f < Math.abs(v.translationY)) ways.add(v to v.translationY)
            else v.translationY = 0f
            if (v.alpha < 1f) fadeIn(v)
        }
        val moved = ways.size
        if (births.isNotEmpty()) {
            // THE NEWBORN RISES FROM UNDER THE FIELD'S GLASS (iOS: from below the feed's edge, the feed running under the bars): no
            // parent on its way up clips it -- each row keeps its own clip, so the reply's pull keeps its edge
            column.clipToPadding = false
            var up = column.parent as? android.view.ViewGroup
            while (up != null) { up.clipChildren = false; if (up === scroll) break; up = up.parent as? android.view.ViewGroup }
        }
        for (v in births) { v.translationY = v.height * LetterMotion.RISE; ways.add(v to v.translationY); fadeIn(v) }
        newborn.clear(); stood.clear(); flying.clear()
        if (ways.isEmpty()) return
        val d = LetterMotion.duration
        val b = LetterMotion.bounce
        val settle = LetterMotion.settle(d, b)
        flight = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = Math.round(settle * 1000)
            interpolator = android.view.animation.LinearInterpolator()
            addUpdateListener { a -> val k = LetterMotion.left(a.animatedFraction * settle, d, b).toFloat(); for ((v, w) in ways) v.translationY = w * k }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                var cut = false
                override fun onAnimationCancel(a: android.animation.Animator) { cut = true }
                override fun onAnimationEnd(a: android.animation.Animator) { if (!cut) for ((v, _) in ways) v.translationY = 0f }
            })
            start()
        }
        android.util.Log.d("Montana", "row_birth born=" + births.size + " moved=" + moved)
    }
    // A CHANNEL'S POSTS ON A SUBSCRIBER'S SCREEN (iOS the row's onAppear → MTChannelViews.shown): each post whose row stands in the
    // feed's window is told to the owner once, for the eye under it
    fun showPosts() {
        if (!group || !Groups.isChannel(ref) || Groups.owns(ref) || !scroll.isLaidOut) return
        val y0 = mediaPlateOffset(column, scroll) - scroll.scrollY
        var byMid: Map<String, Msg>? = null
        for (r in feed) {
            val v = r.view ?: continue
            if (!r.letter || !v.isLaidOut) continue
            val y = y0 + v.top
            if (y + v.height <= 0 || scroll.height <= y) continue
            val m = (byMid ?: feedChat.msgs.associateBy { it.mid }.also { byMid = it })[r.key.trimEnd('\'')] ?: continue
            ChannelViews.shown(m, ref)
        }
    }
    if (group) scroll.setOnScrollChangeListener { _, _, _, _, _ -> showPosts() }   // a channel's posts the finger brings into the window are told
    fun redraw() {
        val chat = Book.chat(ref) ?: return
        feedChat.name = chat.name; feedChat.pin = chat.pin
        feedChat.msgs.clear(); feedChat.msgs.addAll(chat.msgs)
        scroll.post { showPosts() }
        // the pass's own switches, read once: every row's signature takes the same answer
        val skin = BubbleStyle.style
        val canPull = !group || Groups.canWrite(ref)
        val talks = group && Groups.talks(ref)   // a channel's comments: every post wears its count
        val channel = group && Groups.isChannel(ref)   // a channel's eye: every post wears its number of people
        val played = Prefs.bool("plcap_$ref", false)
        val auto by lazy { Media.autoAllowed(c) }
        val byMid by lazy { chat.msgs.associateBy { it.mid } }
        val speakers = HashMap<String?, String>()
        val lines = HashMap<String?, String>()
        // WHAT A ROW SHOWS (iOS fingerprint, MontanaConversation 2855-2879): each letter's words, rung, edit, answers, file, manifest
        // and link card; the quote's name and the speaker's line; the filter's fold; the choice while the chat selects; the pass's
        // switches -- the skin, the reply's pull, the «played» word of the rung, the automatic download a waiting file obeys
        fun signOf(row: List<Msg>): List<Any?> {
            val m = row[0]
            val s = ArrayList<Any?>(10 * row.size + 12)
            for (x in row) { s.add(x.mid); s.add(x.text); s.add(x.state); s.add(x.edited); s.add(x.heard); s.add(x.reactions.toList()); s.add(x.myReact); s.add(x.file); s.add(x.meta); s.add(x.lp) }
            s.add(skin); s.add(canPull); s.add(m.mine && played); s.add(selecting); s.add(selecting && m.mid in picked)
            s.add(if (talks) ChannelComments.count(m.mid, ref) else -1)
            s.add(if (channel) ChannelViews.views(m, ref) else -1)
            if (m.qt != null && !isForwardQuote(m.qt)) {
                val whose = m.qm?.let { byMid[it] }
                s.add(if (whose?.mine == true) Prefs.userName else if (group) speakers.getOrPut(whose?.from) { Groups.speakerName(c, whose?.from) } else chat.shown)
            }
            if (group && !m.mine) s.add(lines.getOrPut(m.from) { Groups.speakerLine(c, m, ref) ?: "" })
            if (!m.mine) s.add(ContentFilter.folded(m))
            if (!m.mine && row.any { it.file == null && it.text.startsWith(Marks.MEDIA) }) s.add(auto)
            // A ROW THAT READS BEYOND ITS LETTERS is built at every pass, as the whole column was: a game's invitation reads the game
            // (Accept and Decline while it waits for me), a coin letter the road of its coins
            if (m.text.startsWith(ChessLetter.MARK) || m.text.startsWith(CoinLetter.MARK)) s.add(Any())
            return s
        }
        // ONE LETTER'S ROW, drawn as the column always drew it
        // A GROUP'S LETTER OF ANOTHER STANDS BESIDE ITS SPEAKER'S FACE COLUMN (iOS MTSpeakerFace.column): the face shows at the run's
        // last letter, a tap on it opens the person's page where this phone holds their pipe
        fun withFace(v: View, m: Msg, tail: Boolean): View {
            val from = m.from
            if (!group || m.mine || from == null || Groups.speakerLine(c, m, ref) == null) return v
            val top = (v.layoutParams as? LinearLayout.LayoutParams)?.topMargin ?: c.dp(3)
            val face = speakerFace(c, from, lines.getOrPut(from) { Groups.speakerLine(c, m, ref) ?: "" })
            face.visibility = if (tail) View.VISIBLE else View.INVISIBLE
            val pipe = Groups.speakerPipe(from)
            if (tail && pipe != null) face.pressable { hideKeys(); act.push { close -> peerInfoPage(act, SamePair.root(pipe), close) } }
            return c.hstack {
                gravity = Gravity.BOTTOM
                addView(face, lp(dp(SPEAKER_FACE), dp(SPEAKER_FACE)).apply { marginStart = dp(2); marginEnd = dp(6) })
                addView(v, lp(0, WRAP, 1f))
                layoutParams = lp().apply { topMargin = top }
            }
        }
        fun letterRow(m: Msg, row: List<Msg>, head: Boolean = true, tail: Boolean = true): View {
            val b = letterBubble(c, m, feedChat, row, head)
            if (selecting) {
                // WHILE THE CHAT SELECTS a letter is a choice: a circle on the left, a tap chooses (iOS the selection rows); a plate whole
                val chosen = m.mid in picked
                val circle = FrameLayout(c).apply {
                    background = if (chosen) c.rounded(Color.WHITE, 11) else c.rounded(Color.TRANSPARENT, 11, Color.WHITE)
                    if (chosen) addView(c.icon(R.drawable.ic_check, Color.BLACK, 14), FrameLayout.LayoutParams(dp(14), dp(14), Gravity.CENTER))
                }
                return c.hstack {
                    gravity = Gravity.TOP
                    addView(circle, lp(dp(22), dp(22)).apply { marginEnd = dp(8) })
                    addView(b.apply { isClickable = false }, lp(0, WRAP, 1f))
                    pressable { val mids = row.map { it.mid }; if (chosen) picked.removeAll(mids.toSet()) else picked.addAll(mids); redraw(); drawFoot() }
                    // THE CIRCLE STANDS LEVEL WITH THE MEDIA, NOT THE WHOLE BUBBLE (iOS MTSaveBeside item 21, MontanaBubble.swift
                    // 250-253 and 1709-1714, build 1771): a letter's picture or film names its own vertical middle, so a caption
                    // or reactions under it do not pull the circle down with them; a letter without media centres on itself.
                    b.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                        val plate = b.findViewWithTag<View>(MEDIA_PLATE_TAG)
                        val mid = if (plate != null) mediaPlateOffset(plate, b) + plate.height / 2f else b.height / 2f
                        circle.translationY = mid - circle.height / 2f
                    }
                    layoutParams = lp().apply { topMargin = c.dp(3) }
                }
            }
            // THE LADDER UNDER EVERY OWN BUBBLE (the author's word 29.09: «on every message, each on its own»): each letter its own rung
            // A PLATE STANDS WHERE ITS SLOWEST LETTER STANDS (iOS MTLadder, MontanaBubble 2047-2065, the author's word 29.09): «not sent»
            // below the clock, and of the letters on the lowest rung the one that reached it last names the moment — the line spoke
            // the plate's last letter, «Read» while a video of the same pick still rode
            // a post's card is this phone's own row, not a letter: no rung under it (iOS MTRowLetter.ownRow, MTRowLetter.swift:60-63 at 2155)
            // nor a channel's post: it goes out to every subscriber, no one rung speaks for it (iOS ladder !isChannel, MontanaConversation 2967)
            val laddered = m.mine && !local && !channel && WallCard.of(m.text) == null
            if (laddered) (b.getChildAt(0) as LinearLayout).addView(c.deliveryLine(ref, row.minWithOrNull(compareBy<Msg>({ it.state }, { -it.statusMoment })) ?: row.last()),
                LinearLayout.LayoutParams(WRAP, WRAP).apply { topMargin = c.dp(3); marginEnd = c.dp(4) })
            // ANY FAILED BUBBLE: A TAP SENDS IT AGAIN (iOS primaryTap → onResend → resendAny, the author's invariant 24.08): a plate's
            // red letters each ride again, its other letters keep their own tap -- the red stands over every control inside the bubble
            val red = row.filter { it.mine && it.state == -1 }
            if (red.isNotEmpty() && !local) b.getChildAt(0).tapEverywhere { red.forEach { resendAny(act, ref, it) } }
            val forward: () -> Unit = { hideKeys(); act.push { close -> forwardPage(act, ref, row, close) { to -> close(); if (to != ref) { onClose(); act.push { c2 -> conversationPage(act, to, c2) } } } } }
            // THE MENU OPENS ON EVERY LETTER (iOS: the long press is the bubble's, whatever it holds): a picture, a film, a circle, a
            // voice or a link's card keeps its own tap, and its long press opens the letter's menu as the words' does
            b.getChildAt(0).holdEverywhere { letterMenu(act, ref, m, onReply = { replyTo = m; editing = null; showStrip(); showKeys() },
                onEdit = { val e = Media.captionLetter(row) ?: m
                    editing = e; replyTo = null; field.setText(if (e.text.startsWith(Marks.MEDIA)) Media.captionOf(e) else e.text)
                    field.setSelection(field.text.length); showStrip(); showKeys() },
                onForward = forward,
                onSelect = { hideKeys(); selecting = true; picked.clear(); picked.addAll(row.map { it.mid }); redraw(); drawFoot() }, group = group, members = row); true }
            // the pull to the left answers, as the menu's «Reply»; in a group, while this phone writes into it
            if (!group || Groups.canWrite(ref)) b.onReply = { replyTo = m; editing = null; showStrip(); showKeys() }
            b.tag = m.mid
            // TEXT WITH A QUOTE — A TAP GOES TO THE ORIGINAL (iOS MontanaBubble 475, jumpTo 2999-3012)
            val q = m.qm
            if (q != null && !isForwardQuote(m.qt) && !Marks.isService(m.text)) b.getChildAt(0).setOnClickListener { toQuoted(q) }
            // SAVE TO PHOTOS, BESIDE THE BUBBLE (iOS MTSaveBeside/saveBesideBadge/MTSaveMediaBadge, MontanaBubble.swift 383-396,
            // 861-880, 1891-1923, the author's words 11.09 and 20.09): strictly to the right of a correspondent's photo or film,
            // level with the media's own middle, never on the picture itself and never on one's own letters; a plate wears one
            // circle that saves every picture and film on it, once all of them are on disk.
            // THE ROUND BESIDE A CHANNEL'S POST (iOS MTShareBeside, MTChannelShareRound; MontanaChannel 360-395, MontanaBubble 572): a round
            // of glass 30 across, 8 beside the post, its foot at the post's foot (over the rung under one's own); it hands the post on by
            // the menu's own «Forward». The finger keeps its 44 around the 30 drawn.
            val core: View = if (!channel || local) b else {
                val round = shareRound(c, forward)
                b.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                    val col = b.getChildAt(0) as? android.view.ViewGroup ?: return@addOnLayoutChangeListener
                    val last = col.getChildAt(col.childCount - if (laddered && 1 < col.childCount) 2 else 1) ?: return@addOnLayoutChangeListener
                    round.translationY = (col.top + last.bottom - c.dp(1) + c.dp(7) - c.dp(44)).toFloat()
                }
                c.hstack {
                    gravity = Gravity.TOP
                    addView(b, if (m.mine) lp(0, WRAP, 1f) else lp(WRAP, WRAP))
                    addView(round, lp(dp(44), dp(44)).apply { marginStart = dp(1) })
                }
            }
            saveMediaFiles(row)?.let { files ->
                val badge = saveMediaBadge(act, files)
                b.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                    val plate = b.findViewWithTag<View>(MEDIA_PLATE_TAG)
                    val mid = if (plate != null) mediaPlateOffset(plate, b) + plate.height / 2f else b.height / 2f
                    badge.translationY = mid - badge.height / 2f
                }
                val beside = c.hstack {
                    gravity = Gravity.TOP
                    addView(core, lp(0, WRAP, 1f))
                    addView(badge, lp(dp(40), dp(40)).apply { marginStart = dp(6) })
                }
                beside.layoutParams = lp().apply { topMargin = c.dp(3) }
                return withFace(beside, m, tail)
            }
            core.layoutParams = lp().apply { topMargin = c.dp(3) }
            return withFace(core, m, tail)
        }
        // the column as this pass wants it: each child named, its signature, and how it is built when it must be
        val want = ArrayList<FeedRow>()
        val makers = ArrayList<() -> View>()
        val used = HashSet<String>()
        fun lay(key: String, sig: List<Any?>, letter: Boolean, make: () -> View) {
            var k = key
            while (!used.add(k)) k += "'"   // a name stands once, whatever the book holds twice
            want.add(FeedRow(k, sig, letter)); makers.add(make)
        }
        var lastDay = -1L
        // A MEDIA GROUP IS ONE ROW (iOS buildRows): its letters stand as one plate, chosen, forwarded and deleted together
        val asked = if (searching) searchFold(searchQuery.trim()) else ""
        val rows = feedRows(chat.msgs.filter { !ChessLetter.isStep(it.text) }).toList()
            .let { all -> if (asked.isEmpty()) all else all.filter { r -> r.any { searchFold(searchWords(c, it)).contains(asked) } } }
        // A FOUND LETTER IS A WAY TO ITS PLACE (iOS searchJump: the row takes no tap of its own, the tap goes to the letter's place)
        fun searchHit(v: View, mid: String): View = FrameLayout(c).apply {
            layoutParams = v.layoutParams
            addView(v, FrameLayout.LayoutParams(MATCH, WRAP))
            addView(View(c).apply { contentDescription = c.getString(R.string.search); pressable { searchLeave(mid) } }, FrameLayout.LayoutParams(MATCH, MATCH))
        }
        // A GROUP'S RUN IS ONE PERSON'S (iOS buildRows): another speaker, a gap of ten minutes, a new day or an event begins another
        fun dayOf(at: Long) = java.util.Calendar.getInstance().apply { timeInMillis = at }.let { it.get(java.util.Calendar.YEAR) * 1000L + it.get(java.util.Calendar.DAY_OF_YEAR) }
        fun sameRun(a: List<Msg>, b: List<Msg>): Boolean {
            val x = a[0]; val y = b[0]
            return group && !x.mine && !y.mine && x.from != null && x.from == y.from && b[0].at - a.last().at < 600_000
                && dayOf(a.last().at) == dayOf(y.at) && Groups.eventWords(c, x.text) == null && Groups.eventWords(c, y.text) == null
        }
        for ((at, row) in rows.withIndex()) {
            val m = row[0]
            val head = !group || at == 0 || !sameRun(rows[at - 1], row)
            val tail = !group || at == rows.size - 1 || !sameRun(row, rows[at + 1])
            val cal = java.util.Calendar.getInstance().apply { timeInMillis = m.at }
            val day = cal.get(java.util.Calendar.YEAR) * 1000L + cal.get(java.util.Calendar.DAY_OF_YEAR)
            if (day != lastDay) {
                lastDay = day
                val words = dayWords(c, m.at)
                lay("day:" + m.mid, listOf(words), false) {
                    FrameLayout(c).apply {
                        addView(c.text(words, 13f, Color.WHITE).apply { background = c.glassPlate(); setPadding(dp(10), dp(3), dp(10), dp(3)) },
                            FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
                        layoutParams = lp().apply { topMargin = c.dp(8); bottomMargin = c.dp(8) }
                    }
                }
            }
            // «unread messages» (iOS unreadDivider 3014-3022): the caption in grey across the feed on its quiet band
            if (asked.isEmpty() && firstUnread != null && row.any { it.mid == firstUnread }) lay("unread:" + m.mid, emptyList(), false) {
                c.text(c.getString(R.string.unread_messages), 11f, MT.gray, center = true).apply {
                    setBackgroundColor(Color.rgb(31, 31, 31)); setPadding(0, dp(5), 0, dp(5))
                    layoutParams = lp().apply { topMargin = c.dp(2); bottomMargin = c.dp(2) }
                }
            }
            // A GROUP'S EVENT (iOS groupEventRow, stage R): the reference's service row, a capsule in the middle of the feed in the day's
            // own dress -- no bubble, no rung, no menu
            val event = if (group) Groups.eventWords(c, m.text) else null
            if (event != null) lay(m.mid, listOf(event), false) {
                FrameLayout(c).apply {
                    addView(c.text(event, 12f, Color.WHITE, center = true).apply { background = c.glassPlate(); setPadding(dp(12), dp(5), dp(12), dp(5)) },   // USER-DATA: names inside the sentence
                        FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER).apply { marginStart = dp(24); marginEnd = dp(24) })
                    layoutParams = lp().apply { topMargin = c.dp(4); bottomMargin = c.dp(4) }
                }
            }
            else lay(m.mid, signOf(row) + listOf(head, tail, asked.isNotEmpty()), true) {
                letterRow(m, row, head, tail).let { if (asked.isEmpty()) it else searchHit(it, m.mid) }
            }
        }
        if (want.size != feed.size || want.indices.any { want[it].key != feed[it].key || want[it].sig != feed[it].sig }) {
            val began = System.nanoTime()
            val old = HashMap<String, FeedRow>(feed.size * 2)
            for (r in feed) old[r.key] = r
            // THE BIRTH FOLLOWS THE NEWEST END (iOS grewNewest, MontanaMessageFeed 846-848 and 911): the newest letter before the pass
            // still stands and a letter now stands after it; the rows laid on opening, or older ones read in, are born still
            val prevLast = feed.lastOrNull { it.letter }?.key
            val lastKept = if (prevLast == null) -1 else want.indexOfFirst { it.key == prevLast }
            val motion = laid && LetterMotion.on
            val grew = motion && 0 <= lastKept && (lastKept + 1 until want.size).any { want[it].letter }
            if (motion && !landing && (grew || flight?.isRunning == true)) {
                // where every row on the screen stands before the pass, its flight included (iOS before, 868-875)
                flight?.cancel()
                val y0 = mediaPlateOffset(column, scroll) - scroll.scrollY
                for (r in feed) {
                    val v = r.view ?: continue
                    if (!v.isLaidOut) continue
                    val y = y0 + v.top + v.translationY
                    if (0f < y + v.height && y < scroll.height) stood[r.key] = y
                    if (v.translationY != 0f || v.alpha < 1f) flying.add(r.key)
                }
                landing = true
                // the pass's first frame already shows every row where it stood; the rise starts once the feed has taken its place
                scroll.viewTreeObserver.addOnPreDrawListener(object : android.view.ViewTreeObserver.OnPreDrawListener {
                    override fun onPreDraw(): Boolean { scroll.viewTreeObserver.removeOnPreDrawListener(this); pose(); return true }
                })
                scroll.post { scroll.post { land() } }
                // A NEWBORN IS NEVER LEFT UNSEEN: a view's post waits for its attachment, the main looper's does not -- land() is a no-op
                // once it ran, so this only lifts the alpha 0 of a pass whose posts never came
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ land() }, 600)
            }
            // the rows whose letter left go first, so every kept row already stands in its order
            val keys = HashSet<String>(want.size * 2)
            for (w in want) keys.add(w.key)
            var gone = 0
            for (r in feed) { val v = r.view ?: continue; if (r.key !in keys) { newborn.remove(v); column.removeView(v); gone++ } }
            var built = 0
            var born = 0
            for ((i, w) in want.withIndex()) {
                val was = old[w.key]
                val prior = was?.view
                val v = if (was != null && prior != null && was.sig == w.sig) prior else { built++; makers[i]() }
                w.view = v
                if (prior != null && prior !== v) {
                    // built anew in its own place: what its flight had reached stays with it
                    v.translationY = prior.translationY; v.alpha = prior.alpha
                    if (newborn.remove(prior)) newborn.add(v)
                    column.removeView(prior)
                } else if (prior == null && grew && lastKept < i) { v.alpha = 0f; newborn.add(v); born++ }   // unseen until it rises
                if (column.getChildAt(i) !== v) { if (v.parent === column) column.removeView(v); column.addView(v, i) }
            }
            feed.clear(); feed.addAll(want)
            android.util.Log.d("Montana", "feed_pass rows=" + want.size + " built=" + built + " born=" + born + " gone=" + gone + " ms=" + (System.nanoTime() - began) / 1_000_000)
        }
        laid = true
        drawEmpty(column.childCount == 0, asked.isNotEmpty())
        // the other side closed it: read, not answered (iOS closedChats) — the note where the field stood
        if (Post.closed(ref)) { hideBar(); closedNote.visibility = View.VISIBLE }
    }

    // ── sending (iOS sendMessage) ──
    var typedAt = 0L
    field.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun afterTextChanged(s: Editable?) {
            LinkCompose.look(s?.toString() ?: "")   // the plate above the field follows the words (iOS handleDraftChange:4308 at 2155)
            drawMentions(s?.toString() ?: "")   // «@» in a group raises its people (iOS MTMentionCompose.look, stage R)
            if (editing == null) Prefs.setStr("draft.$ref", s?.toString() ?: "")
            // A GROUP'S «TYPING» (the checklist's B.12, iOS MTGroup.typing): an instant word to the pipes this phone holds for the
            // group, at most every three seconds, as the pair's; a group streams no draft, nor does the room without an address
            if (group) {
                if (!s.isNullOrBlank() && System.currentTimeMillis() - typedAt > 3000) { typedAt = System.currentTimeMillis(); Thread { Groups.typing(ref) }.start() }
                return
            }
            if (local) return
            // «TYPING…» TO THEM (iOS: a word on the lane, at most every three seconds, only while there are words)
            if (!s.isNullOrBlank() && System.currentTimeMillis() - typedAt > 3000) { typedAt = System.currentTimeMillis(); Presence.sayTyping(ref) }
            // MY WORDS AS I TYPE THEM (iOS sendDraft): the field and its caret; emptied — sent or erased — the draft ends
            if (editing == null) LiveDraft.say(ref, s?.toString()?.takeIf { it.isNotBlank() } ?: "", field.selectionEnd, replyTo?.mid ?: "")
        }
    })
    // WHAT WAITS ABOVE THE FIELD (iOS pastedPreview, MontanaConversation 3087-3159): the chosen pictures themselves, 116 by 78,
    // the corner rounded, the cross in the top corner of each, not a word beside them; more than three travel sideways
    val staged = ArrayList<Pair<Media.Picked, android.graphics.Bitmap?>>()
    val stagedRow = c.hstack { setPadding(dp(16), dp(2), dp(16), dp(2)) }
    val stagedStrip = HorizontalScrollView(c).apply {
        isHorizontalScrollBarEnabled = false; visibility = View.GONE; setPadding(0, c.dp(6), 0, c.dp(6)); addView(stagedRow)
    }
    lateinit var drawStaged: () -> Unit
    lateinit var pickFiles: () -> Unit
    // THE PICTURES LEAVE WITH THE FIELD'S WORDS AS ONE GROUP (iOS sendPasted 3160-3206): the words ride with the first of them
    fun sendStaged() {
        val words = field.text.toString().trim()
        field.setText(""); Prefs.setStr("draft." + ref, "")
        val picks = staged.map { it.first }
        staged.clear(); drawStaged()
        Thread { Media.sendAll(c, ref, picks, words); MainThread.post { toBottom() } }.start()
    }
    val bar = ChatInputBar(act, field) {
        if (staged.isNotEmpty() && editing == null) { sendStaged(); return@ChatInputBar }
        val words = field.text.toString().trim()
        // THE CARD THE PERSON SAW IS TAKEN BEFORE THE FIELD EMPTIES (iOS sendMessage:4423-4432): the emptied field clears the plate
        // (LinkCompose.look("")), and a card read after it was always «dropped» -- every typed link left bare
        val seenCard = LinkCompose.attachable
        val refusedCard = LinkCompose.url.isEmpty() && LinkPreview.webURLs(words).isNotEmpty()
        field.setText("")
        val e = editing
        if (e != null) {
            // THE NEW WORDS OF A LETTER ALREADY SENT (iOS editMessage): the row changes here, the peer is told by ED:{sid,tx}.
            editing = null
            // and no edit becomes one (iOS editMessage 3353): the row keeps its words
            // a caption's new words go into the letter's manifest (Post.reword); a caption is never emptied by an edit (the peer
            // refuses empty words, iOS applyEditFromPeer)
            val caption = e.text.startsWith(Marks.MEDIA)
            val before = if (caption) Media.captionOf(e) else e.text
            if (words != before && CoinLetter.parse(words) == null && !(caption && words.isEmpty())) {
                Book.edit(ref) { ch -> ch.msgs.find { it.mid == e.mid }?.let { if (caption) Post.reword(it, words) else { it.text = words; it.edited = true } } }
                android.util.Log.d("Montana", "edit_tx caption=" + (if (caption) 1 else 0) + " len=" + words.length)
                val edit = Marks.EDIT + JSONObject().put("sid", e.mid).put("tx", words)
                // a group's edit rides the group's carrier to every phone of it (iOS editMessage → MTGroup.signal)
                if (group) Groups.signal(ref, edit) else Post.send(ref, Marks.mintMid(), edit)
            }
        } else if (group) {
            // A GROUP'S LETTER HAS ITS OWN CARRIER (iOS ChatStore.send → MTGroup.send): the row here, a copy to everyone it carries to
            val r = replyTo
            replyTo = null
            // refused (G.5: a right the group took, slow mode's wait) -- the words and the answer stay where they were
            // THE CARD BELONGS TO THE LETTER IN A GROUP TOO (iOS 89dfd51d): the plate above the field held it; the first piece takes it
            val qt = r?.let { letterWords(c, it).take(200) }
            if (Groups.send(ref, words, qt, r?.mid) { mid, piece -> LinkPreview.attend(ref, mid, piece, qt, r?.mid, seen = seenCard, refused = refusedCard) }) LinkCompose.sent()
            else { field.setText(words); field.setSelection(field.length()); replyTo = r; showStrip() }
        } else {
            val r = replyTo
            replyTo = null
            // THE LETTER TAKES THE CARD THE PERSON SAW (iOS sendMessage:4423-4432 at 2155, the critic 22.09): the plate above
            // the field held it, the cross could drop it -- the first piece carries exactly that and reads the page no more
            LinkCompose.sent()
            // A LONG LETTER LEAVES IN PIECES (iOS breakOutgoingText 5917-5945, send 5973-5989): up to 4500 characters a bubble, backing off
            // to the last line break or period, each piece a letter of its own; the quote rides with the first piece only
            Groups.pieces(words).forEachIndexed { i, piece ->
                val mid = Marks.mintMid()
                val qt = if (i == 0) r?.let { letterWords(c, it).take(200) } else null
                val qm = if (i == 0) r?.mid else null
                Book.edit(ref) { it.msgs.add(Msg(mid, piece, true, Marks.birthMs(mid) ?: System.currentTimeMillis(), qt = qt, qm = qm)) }
                Post.send(ref, mid, piece, qt, qm)
                // a link's card follows the letter (iOS MTLinkCards.attend); only the first piece carries what the plate saw
                LinkPreview.attend(ref, mid, piece, qt, qm, seen = if (i == 0) seenCard else null, refused = if (i == 0) refusedCard else false)
            }
        }
        showStrip()
        toBottom()
    }
    // THE GALLERY AND THE FILE KEYS SEND FOR REAL (iOS PhotosPicker / fileImporter → MontanaMedia): read, sealed, laid, lettered.
    fun sendPicked(asDoc: Boolean): (android.net.Uri?) -> Unit = { uri ->
        if (uri != null) Thread {
            val p = Media.read(c, uri, asDoc)
            if (p == null) MainThread.post { android.widget.Toast.makeText(c, R.string.media_failed, android.widget.Toast.LENGTH_LONG).show() }
            else if (asDoc) { Media.send(c, ref, p, ""); MainThread.post { toBottom() } }   // a file leaves as it is (iOS fileImporter)
            // A PICTURE OR A VIDEO GETS ITS CAPTION FIRST (iOS AttachSheet): the words already typed stand in it (the author's word 19.09)
            else MainThread.post {
                hideKeys()
                val draft = if (editing == null) field.text.toString().trim() else ""
                lateinit var close: () -> Unit
                close = act.overlay(captionPage(act, p, draft, onCancel = { close() }) { caption ->
                    close()
                    // THE DRAFT BECOMES THE CAPTION (iOS consumeDraftAsCaption): what was typed leaves the field with the picture
                    if (draft.isNotEmpty() && caption.startsWith(draft)) { field.setText(""); Prefs.setStr("draft.$ref", "") }
                    Thread { Media.send(c, ref, p, caption); MainThread.post { toBottom() } }.start()
                })
            }
        }.start()
    }
    // THE CAMERA BESIDE THE PHOTOS (iOS MTGalleryPick: the camera's tile, «All photos»): a shot goes the picked picture's road
    // THE ORDER IS SET HERE (iOS MTTrayDrop and MTStagedOrder.moved, 2315; the author's words 27.10.2026 09:16 UTC, council links
    // 9562-9563: «they are loaded into the field in the wrong order and it cannot be changed»): a plate held and carried over another
    // takes its place the moment it enters it, every other keeps its turn, the numbers follow, and the arrow sends the tray in the
    // order it stands. Only the other plates move in the row, never the one under the finger, so the touch is never cut.
    val traySlop = android.view.ViewConfiguration.get(c).scaledTouchSlop
    fun carryInTray(plate: View) {
        var downX = 0f; var leftAtDown = 0; var carrying = false
        val lift = Runnable {
            carrying = true
            plate.parent?.requestDisallowInterceptTouchEvent(true)
            plate.animate().scaleX(1.06f).scaleY(1.06f).setDuration(120).start()
            plate.elevation = c.dp(6).toFloat()
            plate.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        }
        plate.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; leftAtDown = v.left; carrying = false
                    v.postDelayed(lift, android.view.ViewConfiguration.getLongPressTimeout().toLong())
                }
                MotionEvent.ACTION_MOVE -> if (!carrying) { if (traySlop < kotlin.math.abs(e.rawX - downX)) v.removeCallbacks(lift) } else {
                    val from = stagedRow.indexOfChild(v)
                    val centre = leftAtDown + v.width / 2f + e.rawX - downX
                    var to = from
                    for (i in staged.indices) stagedRow.getChildAt(i)?.let { o -> if (o !== v && o.left <= centre && centre < o.right) to = i }
                    if (from in staged.indices && to != from) {
                        val moved = StagedOrder.moved(staged.toList(), from, to)
                        staged.clear(); staged.addAll(moved)
                        var at = from
                        while (at < to) { val n = stagedRow.getChildAt(at + 1); stagedRow.removeView(n); stagedRow.addView(n, at); at++ }
                        while (to < at) { val n = stagedRow.getChildAt(at - 1); stagedRow.removeView(n); stagedRow.addView(n, at); at-- }
                        for (i in staged.indices) stagedRow.getChildAt(i)?.findViewWithTag<TextView>(TRAY_NUMBER)?.text = StagedOrder.number(i).toString()
                    }
                    v.translationX = e.rawX - downX - (v.left - leftAtDown)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.removeCallbacks(lift)
                    if (carrying) {
                        carrying = false
                        v.animate().translationX(0f).scaleX(1f).scaleY(1f).setDuration(150).start()
                        v.elevation = 0f
                        android.util.Log.i("Montana", "tray_move place=" + StagedOrder.number(stagedRow.indexOfChild(v)) + " of=" + staged.size)
                    }
                }
            }
            true
        }
    }
    drawStaged = {
        stagedRow.removeAllViews()
        for ((place, s) in staged.toList().withIndex()) stagedRow.addView(FrameLayout(c).apply {
            carryInTray(this)
            addView(ImageView(c).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                if (s.second != null) setImageBitmap(s.second) else setBackgroundColor(Color.rgb(51, 51, 51))
                outlineProvider = object : android.view.ViewOutlineProvider() {
                    override fun getOutline(v: View, o: android.graphics.Outline) = o.setRoundRect(0, 0, v.width, v.height, v.dp(12).toFloat())
                }
                clipToOutline = true
            }, FrameLayout.LayoutParams(MATCH, MATCH))
            if (s.first.kind == "vid") addView(c.icon(R.drawable.ic_play_fill, Color.WHITE), FrameLayout.LayoutParams(c.dp(22), c.dp(22), Gravity.CENTER))
            // A FILE IN THE TRAY (iOS 2312) wears its kind, its own name and its size, at the plate's size
            if (s.first.kind == "doc") addView(c.vstack(Gravity.CENTER) {
                setPadding(c.dp(8), 0, c.dp(8), 0)
                addView(c.icon(R.drawable.ic_compose_doc, Color.argb(230, 255, 255, 255), 20), lp(c.dp(20), c.dp(20)))
                addView(c.text(s.first.name ?: "", 11f, Color.WHITE).apply {   // USER-DATA: the person's file name
                    maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END; gravity = Gravity.CENTER
                }, lp().apply { topMargin = c.dp(3) })
                addView(c.text(c.copySize(s.first.bytes.size.toLong()), 10f, Color.argb(153, 255, 255, 255)), lp().apply { topMargin = c.dp(3) })
            }, FrameLayout.LayoutParams(MATCH, MATCH))
            // THE PLACE IT HOLDS (iOS stagedNumber, 2312): 1, 2, 3 in the order chosen, the order the arrow sends them in; read off
            // the place in the tray, so a cross closes the numbers up
            addView(c.text(StagedOrder.number(place).toString(), 12f, Color.BLACK, bold = true).apply {   // USER-DATA: the place of the person's own pick, digits only
                tag = TRAY_NUMBER
                gravity = Gravity.CENTER
                minWidth = c.dp(20); minHeight = c.dp(20)
                setPadding(c.dp(5), 0, c.dp(5), 0)
                fontFeatureSettings = "tnum"
                background = GradientDrawable().apply { cornerRadius = c.dp(10).toFloat(); setColor(Color.WHITE) }
            }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.START).apply { setMargins(c.dp(5), c.dp(5), 0, 0) })
            // the cross drawn small and taken on the platform's least target: 22 drawn, 44 to the finger, grown inward from the corner
            addView(FrameLayout(c).apply {
                contentDescription = c.getString(R.string.cancel)
                addView(FrameLayout(c).apply {
                    background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(191, 0, 0, 0)) }
                    addView(c.icon(R.drawable.ic_close, Color.WHITE), FrameLayout.LayoutParams(c.dp(11), c.dp(11), Gravity.CENTER))
                }, FrameLayout.LayoutParams(c.dp(22), c.dp(22), Gravity.TOP or Gravity.END).apply { setMargins(0, c.dp(4), c.dp(4), 0) })
                pressable { staged.remove(s); drawStaged() }
            }, FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.TOP or Gravity.END))
        }, lp(c.dp(116), c.dp(78)).apply { marginEnd = c.dp(8) })
        // ONE MORE FILE (iOS 2312): a tray that holds files opens the files page again from here; what it hands back stands after
        // the last number
        if (staged.any { it.first.kind == "doc" }) stagedRow.addView(FrameLayout(c).apply {
            contentDescription = c.getString(R.string.file)
            background = GradientDrawable().apply { cornerRadius = c.dp(12).toFloat(); setColor(Color.rgb(51, 51, 51)) }
            addView(c.icon(R.drawable.ic_plus, Color.WHITE, 20), FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
            pressable { pickFiles() }
        }, lp(c.dp(78), c.dp(78)))
        stagedStrip.visibility = if (staged.isEmpty()) View.GONE else View.VISIBLE
        bar.attached = staged.isNotEmpty()
    }
    pickFiles = { act.openDocuments { uris -> if (uris.isNotEmpty()) {
        val t0 = System.currentTimeMillis()
        Thread {
            val made = uris.mapNotNull { u -> Media.read(c, u, true)?.let { p -> p to null } }
            MainThread.post {
                if (made.size < uris.size) android.widget.Toast.makeText(c, R.string.media_failed, android.widget.Toast.LENGTH_LONG).show()
                staged.addAll(made); drawStaged(); toBottom()
                android.util.Log.i("Montana", "files_pick picked=${uris.size} staged=${made.size} tray=${staged.size} ms=${System.currentTimeMillis() - t0}")
            }
        }.start()
    } } }
    /** The chosen pictures read whole off the frame and staged above the field, in the order the finger chose them (iOS stagePicks). */
    fun stage(uris: List<android.net.Uri>) {
        if (uris.isEmpty()) return
        Thread {
            val made = uris.mapNotNull { u -> Media.read(c, u, false)?.takeIf { it.kind == "img" || it.kind == "vid" }?.let { p -> p to stagedFace(c, p) } }
            MainThread.post {
                if (made.size < uris.size) android.widget.Toast.makeText(c, R.string.media_failed, android.widget.Toast.LENGTH_LONG).show()
                staged.addAll(made); drawStaged(); toBottom()
            }
        }.start()
    }
    // A PICTURE PASTED, OR HANDED OVER BY THE KEYBOARD, IS AN ATTACHMENT, NOT WORDS (iOS paste, MontanaBubble 2166-2188; attachPasted,
    // MontanaConversation 3052-3087; the author's word 10.09; fork atom 1443): an opaque one waits above the field as a photo in the
    // one shape of a photo on its way out; a see-through one is a sticker, kept as PNG, on the card-sticker road; a GIF keeps its
    // frames. Android took no picture into the field at all. The keyboard's grant lasts only while it hands the picture over, so
    // the bytes are read at once and shaped off the screen.
    fun seeThrough(b: android.graphics.Bitmap): Boolean {
        if (!b.hasAlpha()) return false
        val small = android.graphics.Bitmap.createScaledBitmap(b, 64, 64, true)
        for (y in 0 until 64) for (x in 0 until 64) if (android.graphics.Color.alpha(small.getPixel(x, y)) < 128) return true
        return false
    }
    fun pasted(bytes: ByteArray): Boolean {
        val gif = 4 <= bytes.size && String(bytes, 0, 4, Charsets.US_ASCII) == "GIF8"
        val bmp = if (gif) null else android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        if (bmp != null && seeThrough(bmp)) {
            val png = java.io.ByteArrayOutputStream().also { bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
            Media.send(c, ref, Media.Picked(png, "img", "png", Stickers.CARD), "")
            MainThread.post { toBottom() }
            return true
        }
        val p = if (gif) Media.Picked(bytes, "img", "gif", null) else Media.Picked(Media.photoForSend(bytes) ?: return false, "img", "jpg", null)
        val face = stagedFace(c, p)
        MainThread.post { staged.add(p to face); drawStaged(); toBottom() }
        return true
    }
    if (android.os.Build.VERSION.SDK_INT >= 31) field.setOnReceiveContentListener(arrayOf("image/*")) { _, payload ->
        val clip = payload.clip
        val held = ArrayList<ByteArray>()
        for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { u ->
            runCatching { c.contentResolver.openInputStream(u)?.use { it.readBytes() } }.getOrNull()?.let { held.add(it) }
        }
        // pictures in hand: the pictures alone ride, as the iPhone's paste takes images over words; none: the words paste as ever
        // the next «thinks long» is measurable (iOS paste_images, MontanaConversation 3083)
        if (held.isEmpty()) payload else {
            Thread { val t0 = System.currentTimeMillis(); val n = held.count { pasted(it) }; android.util.Log.d("Montana", "paste_images n=" + n + " ms=" + (System.currentTimeMillis() - t0)) }.start()
            null
        }
    }
    // THE LIBRARY IS WARM BEFORE THE FINGER ASKS (iOS RecentMedia.warm, MontanaMedia.swift:1301-1310 and
    // MontanaConversation.swift:3120-3126 at 2155, atom 1cf77b0a8360: «the first time it shows no photographs, only
    // the second time»): the chat warms it at its own opening, off the screen's thread, asking for no permission here.
    Library.warm(c)
    // THE GALLERY OF THE ROW (iOS openGallery → MTGalleryPick): the phone's latest pictures at once, the camera the first tile,
    // «All photos» the system's own picker, no ceiling of ours; what is chosen waits above the field
    barTop = { IntArray(2).also { bar.getLocationOnScreen(it) }[1] }
    bar.onGallery = { hideKeys(); galleryPick(act, onPick = { stage(it) },
        // THE CAMERA TILE (iOS onCamera → CameraPicker → sendCameraImage / sendCameraVideo): a photo or a film, sent once taken
        onCamera = { cameraPage(act) { f, film ->
            // the camera's photo leaves in the one shape of a photo on its way out, without the camera's record (iOS photoForSend)
            Thread { val b = f.readBytes(); Media.send(c, ref, Media.Picked(if (film) b else Media.photoForSend(b) ?: b, if (film) "vid" else "img", if (film) "mp4" else "jpg", null), ""); f.delete(); MainThread.post { toBottom() } }.start()
        } },
        onAll = { act.pickVisualMany { stage(it) } }) }
    // «SEND LATER» (iOS: the send key's hold): the words leave the field and wait for their moment (Schedule.kt)
    // THE COIN FROM THE FIELD (iOS sendCoin 1629-1645, coins: MTCoinSend.canPay at 3811): a pair's chat goes microphone, camera,
    // coin; the number written goes as the pair's own transfer, a short balance is told and the number stays. A GROUP'S COIN
    // (iOS groupCoin 3032, sheet .groupCoin 1632/2271; the author's word 17.10.2026 21:14 UTC) is a transfer to each person picked:
    // the coin's key opens the Send page over the group's people at any tap, the number written stands beside each pick.
    // THE AVAILABLE ABOVE THE FIELD (iOS MTCoinBalancePlate 1128-1160, composePreviews 3745; the author's word 06.10.2026 and 16.10.2026:
    // «a transfer from the chat shows only the available»): in the coin's mode a plate stands where a reply's stands -- our coin,
    // «Available» and the number a send is weighed by -- and its cross takes the button back to the microphone. It follows the book.
    val coinCount = c.text("", 14f, Color.WHITE).apply { fontFeatureSettings = "tnum"; singleLineEllipsis() }   // USER-DATA: the coins available
    val coinPlate = c.hstack {
        visibility = View.GONE
        background = c.glassPlate().apply { cornerRadius = dp(18).toFloat() }
        setPadding(dp(16), dp(6), dp(8), dp(6))
        addView(MintCoin(c, 22), lp(dp(22), dp(22)).apply { marginEnd = dp(10) })
        addView(c.vstack(Gravity.NO_GRAVITY) { addView(c.text(c.getString(R.string.coin_available), 12f, MT.gray)); addView(coinCount) }, lp(0, WRAP, 1f))
        addView(c.icon(R.drawable.ic_close, MT.gray).apply {
            setPadding(dp(8), dp(8), dp(8), dp(8)); contentDescription = c.getString(R.string.close)
            pressable { bar.toMic() }
        }, lp(dp(36), dp(36)))
    }
    val coinListener: () -> Unit = { coinCount.text = CoinText.count(CoinBook.balance) }
    bar.onCoinMode = { on -> coinPlate.visibility = if (on) View.VISIBLE else View.GONE; if (on) coinListener() }
    // A CHANNEL'S FIELD (iOS channel/silent/onSilent, 3806-3808): «Broadcast...» and the bell that turns the sound of the next posts
    if (group && Groups.isChannel(ref)) {
        bar.channel = true
        bar.silent = Groups.silent(ref)
        bar.onSilent = { Groups.setSilent(ref, !Groups.silent(ref)); bar.silent = Groups.silent(ref) }
    }
    val groupCoin = Groups.takesCoins(ref)
    bar.coinPicks = groupCoin
    bar.coins = CoinSend.canPay(ref) || groupCoin
    bar.onSendCoin = { n ->
        if (groupCoin) { hideKeys(); act.push { close -> sendCoinsPage(act, close, ref, n) { field.setText(""); Prefs.setStr("draft.$ref", "") } } }
        else when (CoinSend.transferResult(ref, n)) {
            // the three honest answers (iOS sendCoin 1636-1645): sent -- the field empties; short -- the balance; refused -- nothing left
            CoinSend.Sent.SENT -> { field.setText(""); Prefs.setStr("draft.$ref", "") }
            CoinSend.Sent.SHORT -> AlertDialog.Builder(c).setTitle(R.string.coin_not_enough).setMessage(R.string.coin_not_enough_sub).setPositiveButton(R.string.ok, null).show()
            CoinSend.Sent.REFUSED -> AlertDialog.Builder(c).setTitle(R.string.coin_not_sent).setMessage(R.string.coin_not_sent_sub).setPositiveButton(R.string.ok, null).show()
        }
    }
    bar.onSendLater = { v -> sendLaterMenu(act, v, ref, { field.text.toString() }) { field.setText(""); Prefs.setStr("draft.$ref", "") } }
    // A CONTACT OF THE PHONE (iOS ContactPicker): its name and number leave as one letter
    // A KEY OF THE BAR ASKS THE GROUP BEFORE ITS PAGE OPENS (iOS groupLets, 18b97c6c, G.5): a right the group took, or slow mode's
    // wait, is said at the tap, as the field says it at the arrow, so nothing chosen on a page is lost to a refusal
    val groupLets: (String, Boolean) -> Boolean = lets@{ words, photo ->
        if (!group) return@lets true
        val why = (if (photo) Groups.mediaRefusal(c, ref, "img", false, "card.jpg", "") else Groups.refusal(c, ref, words, true)) ?: return@lets true
        AlertDialog.Builder(c).setMessage(why).setPositiveButton(android.R.string.ok, null).show()
        false
    }
    bar.onContact = { hideKeys(); if (groupLets("\uD83D\uDC64", false)) act.pickContact { u -> u?.let { contactLetter(c, it) }?.let { words -> sendWords(ref, words); toBottom() } } }
    // FILES BY THE HANDFUL, IN THE ORDER CHOSEN (iOS 1e46c25e, the author's word 23.10 20:5x), AND THEY WAIT ABOVE THE FIELD WITH
    // THEIR NUMBERS (iOS stageChosen, 2312; the author's word 25.10.2026 17:40 UTC, council link 8089): read one after another in the
    // page's order, off the screen's thread, into the one tray the pictures stand in -- numbered, taken out and sent as a picture is;
    // the tray's «+» opens the page again, the arrow sends the tray in its order. The diary names the count.
    bar.onFile = { hideKeys(); pickFiles() }
    // THE CARD AS A PHOTO (iOS sendCardPhoto): the kept card drawn at the standard size, its words the caption under the card's mark
    bar.onCard = { hideKeys(); if (groupLets("", true)) act.push { close -> businessCardPage(act, close) { card ->
        close()
        Thread { Media.send(c, ref, Media.Picked(cardPhoto(c, card), "img", "jpg", null), card.wire); MainThread.post { toBottom() } }.start()
    } } }
    // THE PLACE (iOS onLocation → MTLocationPicker → mtSendPlace): this spot leaves as the place's words, by the one road of words
    bar.onLocation = { hideKeys(); if (groupLets(PlaceLetter.ROAD, false)) act.push { close -> placePage(act, close) { words -> sendWords(ref, words); toBottom() } } }
    // THE EMOJI KEY SWAPS THE KEYBOARD FOR THE FIELD'S OWN PANEL AND BACK (iOS emojiKey: showEmoji.toggle(), the glyph «keyboard»
    // while the panel stands; MontanaConversation.swift 803-813 at 2155). Android lets no app view be the field's input view, so the
    // panel stands in the keyboard's place under the bar, as tall as the keyboard last stood (Picker.kt); the keyboard rising puts it
    // away, and so does every other deed of the bar. A hold on the key opens it on the stickers.
    val panel = FieldPanel(act, ref, bar, field, hideKeys = { hideKeys() }, showKeys = { showKeys() }, toBottom = { toBottom() })
    panelUp = { panel.up }
    panelAway = { panel.away() }
    // THE VOICE (iOS the held mark): the tape starts under the finger and leaves as a media letter of kind «aud».
    // THE SWELL WHILE SPEAKING (iOS the recording row): the red mark, the running time and the wave that rises with the voice.
    // THE PLATFORM'S RECORDER LINES (iOS MTLiveWave, MontanaShapes.swift:262-279 at 2155, atom 92fba2cb8154: «the live wave is
    // the platform recorder's: system red»): the live wave during a tape is red, as the phone's own recorder draws it, not white.
    val liveWave = WaveView(c).apply { played = SysColor.red; barDp = 1f }   // iOS MTLiveWave.line = 1 at 2155 (MontanaShapes.swift:268)
    val liveTime = c.text("0:00", 15f, Color.WHITE)
    val dot = View(c).apply { background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(SysColor.red) } }
    // THE CONTROLS OF A LOCKED TAPE (iOS MTHoldOverlayView barRow): each the bar's round glass on a 44-point target
    fun ctl(icon: Int, label: Int, work: () -> Unit): FrameLayout = FrameLayout(c).apply {
        background = c.glassPlate(oval = true); contentDescription = c.getString(label)
        addView(c.icon(icon, Color.WHITE), FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
        visibility = View.GONE
        pressable(work)
    }
    fun paint(key: FrameLayout, pausedNow: Boolean) {
        (key.getChildAt(0) as? ImageView)?.let { it.setImageResource(if (pausedNow) R.drawable.ic_record_circle else R.drawable.ic_pause_fill)
            it.imageTintList = android.content.res.ColorStateList.valueOf(if (pausedNow) SysColor.red else Color.WHITE) }
    }
    val voiceBin = ctl(R.drawable.ic_close, R.string.cancel) { bar.cancelRecording() }
    lateinit var voicePause: FrameLayout
    // LISTEN TO WHAT WAS RECORDED (iOS MTHoldOverlayView seat «play», MontanaShapes.swift:928-946, and onPreview,
    // MontanaConversation.swift:3499-3514 at 2155; atom bef2cdaca45f, the author's word 23.09): on the line of the bin, a locked voice
    // only. The first press closes the tape and plays it through the ONE player of voices; the next ones pause and resume it. Heard,
    // the glyph wears the accent; a closed tape has nothing to pause, so the pause's seat empties -- the seat stays, nothing moves.
    lateinit var voiceEar: FrameLayout
    fun paintEar() {
        val f = VoiceTape.reviewed?.first?.path
        (voiceEar.getChildAt(0) as? ImageView)?.let {
            it.setImageResource(if (f != null && VoicePlayer.sounding(f)) R.drawable.ic_pause_fill else R.drawable.ic_play_fill)
            it.imageTintList = android.content.res.ColorStateList.valueOf(if (f != null) SysColor.blue else Color.WHITE)
        }
        (voicePause.getChildAt(0) as? ImageView)?.visibility = if (f != null) View.INVISIBLE else View.VISIBLE
        voicePause.isEnabled = f == null
    }
    voiceEar = ctl(R.drawable.ic_play_fill, R.string.rec_listen) {
        val heard = VoiceTape.reviewed?.first ?: VoiceTape.finishForReview()
        if (heard == null) { bar.cancelRecording(); bar.tooShortHint(); return@ctl }   // iOS tooShortTape + cancel(why: "ear-short")
        VoicePlayer.toggle(heard.path, onProgress = { _, _ -> paintEar() }, stopped = { paintEar() })
        android.util.Log.d("Montana", "voice_preview " + if (VoicePlayer.sounding(heard.path)) "playing" else "paused")
        paintEar()
    }
    voicePause = ctl(R.drawable.ic_pause_fill, R.string.rec_pause) { VoiceTape.togglePause(); paint(voicePause, VoiceTape.paused) }
    val recStrip = c.hstack {
        visibility = View.GONE
        gravity = Gravity.CENTER_VERTICAL
        background = c.glassPlate()   // iOS: the recording strip's capsule wears the field's glass (montanaFieldGlass)
        setPadding(dp(10), dp(4), dp(10), dp(4))
        addView(voiceBin, lp(dp(40), dp(40)).apply { marginEnd = dp(10) })
        addView(voiceEar, lp(dp(40), dp(40)).apply { marginEnd = dp(10) })
        addView(dot, lp(dp(10), dp(10)).apply { marginEnd = dp(8) })
        addView(liveTime, lp(WRAP, WRAP).apply { marginEnd = dp(12) })
        addView(liveWave, lp(0, WRAP, 1f))
        addView(voicePause, lp(dp(40), dp(40)).apply { marginStart = dp(10) })
    }
    // THE LOCK OVER THE KEY (iOS lockPlate): the padlock and the chevron above the held key; the chevron folds as the finger rises
    val padlock = c.icon(R.drawable.ic_lock_open, Color.WHITE)
    val chevron = c.icon(R.drawable.ic_chevron_up, Color.WHITE)
    val lockPlate = c.vstack(Gravity.CENTER_HORIZONTAL) {
        background = c.glassPlate().apply { cornerRadius = dp(18).toFloat(); setColor(Color.argb(170, 40, 40, 44)) }
        setPadding(0, dp(14), 0, dp(14))
        addView(padlock, lp(dp(24), dp(24)))
        addView(chevron, lp(dp(18), dp(18)).apply { topMargin = dp(8) })
        visibility = View.GONE
    }
    var noteControls: View? = null
    var plateHome: FrameLayout? = null
    fun plateLp() = FrameLayout.LayoutParams(c.dp(52), WRAP, Gravity.BOTTOM or Gravity.END).apply { bottomMargin = c.dp(150); marginEnd = c.dp(8) }
    /** The plate stands where the tape is watched: over the chat for a voice, over the note's window for a note. */
    fun movePlate(to: FrameLayout?) { val t = to ?: return; if (lockPlate.parent !== t) { (lockPlate.parent as? android.view.ViewGroup)?.removeView(lockPlate); t.addView(lockPlate, plateLp()) } }
    fun endStrip() { recStrip.visibility = View.GONE; VoiceTape.onLevel = null; dot.animate().cancel() }
    bar.onRecLift = { l ->
        lockPlate.visibility = View.VISIBLE; lockPlate.translationY = -c.dp(9) * l
        padlock.setImageResource(if (l >= 1f) R.drawable.ic_lock else R.drawable.ic_lock_open)
        chevron.alpha = 1f - l
    }
    bar.onRecLocked = {
        lockPlate.visibility = View.GONE
        voiceBin.visibility = View.VISIBLE; voicePause.visibility = View.VISIBLE; paint(voicePause, false)
        if (!bar.recordingNote) { voiceEar.visibility = View.VISIBLE; paintEar() }   // the ear is the voice's alone (iOS st.locked, !st.video)
        noteControls?.visibility = View.VISIBLE
    }
    bar.onRecIdle = {
        blurFeed(false)
        lockPlate.visibility = View.GONE
        voiceBin.visibility = View.GONE; voicePause.visibility = View.GONE; voiceEar.visibility = View.GONE
        noteControls = null
        movePlate(plateHome)
    }
    bar.onVoiceStart = {
        val on = VoiceTape.start(act)
        if (on) {
            blurFeed(true)
            liveWave.bars = FloatArray(0); liveWave.progress = 0f
            recStrip.visibility = View.VISIBLE
            dot.animate().alpha(0.2f).setDuration(600).withEndAction { dot.alpha = 1f }.start()
            VoiceTape.onLevel = { a ->
                liveWave.push(a)
                val s = VoiceTape.seconds.toInt(); liveTime.text = "%d:%02d".format(s / 60, s % 60)
                dot.alpha = if ((VoiceTape.levels.size / 20) % 2 == 0) 1f else 0.3f
            }
        }
        on
    }
    // THE REPLY AT THE EAR (iOS beginEarReply/endEarReply, MontanaConversation.swift:1263-1286 and 3516-3519 at 2155, the author's
    // word 14.09): the peer's last voice ended at the ear -- the ear tone, the sensor stays with the chat, and after 0.6 s, the phone
    // still at the ear, the reply records there with no finger; the phone leaves the ear -- a rolling tape pauses and stands locked
    // (the arrow sends it, the bin drops it, the pause resumes it), no tape -- nothing stays
    var earReply = false
    fun endEarReply() {
        if (!earReply) return
        earReply = false
        Proximity.onChange = null
        Proximity.hold("ear-reply", false)
        android.util.Log.d("Montana", "voice_ear_reply " + if (VoiceTape.rolling) "paused len=" + VoiceTape.seconds.toInt() else "nothing")
        if (!bar.earLock()) { bar.cancelRecording(); return }   // no tape rolled (permission, or the phone left before the start)
        if (!VoiceTape.paused) VoiceTape.togglePause()
        paint(voicePause, VoiceTape.paused)
    }
    fun beginEarReply() {
        if (earReply || VoiceTape.rolling) return
        earReply = true
        Proximity.hold("ear-reply", true)
        Proximity.onChange = { near -> if (!near) endEarReply() }
        EarTone.play()
        MainThread.later(600) {
            if (!earReply) return@later   // the phone already left the ear
            if (Proximity.isNear && bar.earStart()) android.util.Log.d("Montana", "voice_ear_reply record") else endEarReply()
        }
    }
    val earHook: () -> Unit = { beginEarReply() }
    // THE ROUND NOTE UNDER THE FINGER (iOS MontanaVideoNoteHold): the window over the feed, the ring for the time; a tap turns
    // the camera; let go to send, slide left to drop. What the window shows is the file itself.
    var note: NoteRecorder? = null
    var noteClose: (() -> Unit)? = null
    val noteTick = object : Runnable {
        override fun run() { val n = note ?: return; noteRing?.progress = (n.elapsed / NoteRecorder.MAX_SECONDS).toFloat(); MainThread.later(100, this) }
    }
    bar.onNoteStart = start@{
        if (c.checkSelfPermission(android.Manifest.permission.CAMERA) != android.content.pm.PackageManager.PERMISSION_GRANTED ||
            !VoiceTape.granted(c)) {
            act.requestPermissions(arrayOf(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO), 8); return@start false
        }
        val tv = TextureView(c)
        // NOTHING UNDER THE CIRCLE (iOS MontanaVideoNoteHold, MontanaFeeds.swift:1641-1643 at 2155, the author's word 22.09): the
        // grey glass ring is the clock, the buttons stand on their own row; no seconds are written anywhere on the recorder
        val ring = NoteRing(c, glass = true)   // the recorder's ring is grey glass (iOS MontanaNoteRing glass, MontanaFeeds.swift:1285-1297)
        noteRing = ring
        val side = noteSide(c)   // the player's open size: one rule for both (iOS 1605)
        lateinit var notePause: FrameLayout
        notePause = ctl(R.drawable.ic_pause_fill, R.string.rec_pause) { note?.togglePause(); paint(notePause, note?.paused == true) }
        // THE FILL LIGHT'S MARK (iOS the crown's «flash» seat, MontanaShapes.swift:957-967 at 2155): the bolt, crossed while the
        // light is off; it stands second, after the bin (the seats' order, 893)
        lateinit var noteFlash: FrameLayout
        var flashOn = false
        noteFlash = ctl(R.drawable.ic_flash_off, R.string.rec_flash) {
            note?.toggleFlash(); flashOn = !flashOn
            (noteFlash.getChildAt(0) as? ImageView)?.setImageResource(if (flashOn) R.drawable.ic_flash_on else R.drawable.ic_flash_off)
        }
        val controls = c.hstack {
            gravity = Gravity.CENTER
            visibility = View.GONE   // stands once the tape is locked (iOS: the bin, the flash, the flip, the pause, and the arrow that sends)
            listOf(ctl(R.drawable.ic_close, R.string.cancel) { bar.cancelRecording() },
                   noteFlash,
                   ctl(R.drawable.ic_camera_rotate, R.string.rec_flip) { note?.flip() },
                   // BOTH CAMERAS (iOS the dual seat): only where the hardware streams a back and a front camera together
                   *(if (NoteRecorder.dualPair(c) != null) arrayOf(ctl(R.drawable.ic_dual_camera, R.string.rec_dual) { note?.toggleDual() }) else emptyArray()),
                   notePause,
                   ctl(R.drawable.ic_arrow_circle_up, R.string.send) { bar.stopRecording() }).forEachIndexed { i, k ->
                k.visibility = View.VISIBLE
                addView(k, lp(dp(48), dp(48)).apply { if (i > 0) marginStart = dp(22) })
            }
        }
        noteControls = controls
        // THE VISIBLE STAGE, NOT THE WHOLE PAGE (iOS MontanaShapes.swift:674-679 at 2155, atom 404698df8f72, the author's
        // word 21.09: the circle centres on the room ABOVE the controls' row, not on the page's own middle -- the strip the
        // controls hold at the bottom is never part of the circle's middle, as the feed's own visible part excludes the bar).
        val noteStage = FrameLayout(c)
        val page = FrameLayout(c).apply {
            setBackgroundColor(Color.argb(170, 0, 0, 0))
            keepScreenOn = true   // the screen stays awake while a note records (iOS 1687)
            addView(controls, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM).apply { bottomMargin = c.dp(60) })
            addView(noteStage, FrameLayout.LayoutParams(MATCH, MATCH).apply { bottomMargin = c.dp(60 + 48) })
            noteStage.addView(ring, FrameLayout.LayoutParams(side + c.dp(16), side + c.dp(16), Gravity.CENTER))
            noteStage.addView(NoteWindow(c, live = { note?.badgeNow }).holding(tv.apply {
                setOnClickListener { note?.flip() }
                // THE BADGE UNDER THE FINGER (iOS MontanaVideoNoteHold 1658-1672): a finger on the badge drags it, and the badge
                // eases to the nearest corner when let go; a tap anywhere else turns the camera, as before
                // A PINCH ZOOMS THE BIG CIRCLE'S CAMERA (iOS MagnificationGesture simultaneous with the tap and the drag,
                // MontanaFeeds.swift:1675 at 2155): two fingers own the pinch, one finger the flip and the badge -- the
                // platform already hands single- and multi-touch apart by the pointer count.
                val scale = android.view.ScaleGestureDetector(c, object : android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
                    var acc = 1f
                    override fun onScaleBegin(d: android.view.ScaleGestureDetector): Boolean { acc = 1f; return true }
                    override fun onScale(d: android.view.ScaleGestureDetector): Boolean { acc *= d.scaleFactor; note?.pinch(acc); return true }
                    override fun onScaleEnd(d: android.view.ScaleGestureDetector) { note?.pinchEnded() }
                })
                setOnTouchListener(object : View.OnTouchListener {
                    var dragging = false
                    var sx = 0f
                    var sy = 0f
                    override fun onTouch(v: View, e: android.view.MotionEvent): Boolean {
                        val n = note ?: return false
                        scale.onTouchEvent(e)
                        if (1 < e.pointerCount || scale.isInProgress) return true
                        val k = v.width / NoteRecorder.SQUARE.toFloat()
                        if (k <= 0f) return false
                        when (e.actionMasked) {
                            android.view.MotionEvent.ACTION_DOWN -> {
                                dragging = n.onBadge(e.x / k - NoteRecorder.SQUARE / 2f, e.y / k - NoteRecorder.SQUARE / 2f)
                                if (dragging) { sx = e.x; sy = e.y; n.grabBadge() }
                            }
                            android.view.MotionEvent.ACTION_MOVE -> if (dragging) n.dragBadge((e.x - sx) / k, (e.y - sy) / k)
                            android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> if (dragging) { n.dropBadge(); dragging = false; return true }
                        }
                        return dragging
                    }
                })
            }), FrameLayout.LayoutParams(side, side, Gravity.CENTER))
        }
        // THE SCREEN AS THE FRONT CAMERA'S LIGHT (iOS MTNoteChrome, MontanaShapes.swift:1037-1039, and applyFlash 2232-2233): the
        // page behind the circle turns white and the screen goes to full brightness; both come back as the light goes or the page leaves
        var keptBright: Float? = null
        fun light(lit: Boolean) {
            page.setBackgroundColor(if (lit) Color.WHITE else Color.argb(170, 0, 0, 0))
            val w = act.window; val a = w.attributes
            if (lit && keptBright == null) { keptBright = a.screenBrightness; a.screenBrightness = 1f; w.attributes = a }
            if (!lit) keptBright?.let { a.screenBrightness = it; w.attributes = a; keptBright = null }
        }
        page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {}
            override fun onViewDetachedFromWindow(v: View) { light(false) }
        })
        noteClose = act.overlay(page)
        blurFeed(true)
        movePlate(page)
        tv.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(st: android.graphics.SurfaceTexture, w: Int, h: Int) {
                val r = NoteRecorder(c, tv)
                r.onLight = { lit -> light(lit) }
                r.onMax = { MainThread.post { bar.stopRecording() } }
                if (r.start()) { note = r; MainThread.later(100, noteTick) } else { noteClose?.invoke(); noteClose = null }
            }
            override fun onSurfaceTextureSizeChanged(st: android.graphics.SurfaceTexture, w: Int, h: Int) {}
            override fun onSurfaceTextureDestroyed(st: android.graphics.SurfaceTexture) = true
            override fun onSurfaceTextureUpdated(st: android.graphics.SurfaceTexture) {}
        }
        true
    }
    bar.onNoteEnd = { dropped ->
        val r = note; note = null
        val badge = r?.badgeTag   // the corner the badge rests in as the note ends (iOS usedDual, finalCorner)
        Thread {
            val got = r?.stop(keep = !dropped)
            MainThread.post { noteClose?.invoke(); noteClose = null }
            got?.let { (f, secs) -> Media.send(c, ref, Media.Picked(f.readBytes(), "vid", "mp4", null, secs, round = true, badge = badge), ""); f.delete(); MainThread.post { toBottom() } }
        }.start()
    }
    bar.onVoiceEnd = { dropped ->
        // send and bin stop the listening first (iOS st.onSend / st.onCancel: VoicePlayer.shared.stop())
        VoiceTape.reviewed?.first?.path?.let { if (VoicePlayer.playing == it) VoicePlayer.stop() }
        val wave = VoiceTape.waveform()
        endStrip()
        val got = VoiceTape.stop(keep = !dropped)
        if (got != null) {
            val (f, secs) = got
            Thread { Media.send(c, ref, Media.Picked(f.readBytes(), "aud", "m4a", null, secs, wave), ""); f.delete(); MainThread.post { toBottom() } }.start()
        } else if (!dropped) bar.tooShortHint()   // held less than the tape's own least length (iOS tooShortTape, MontanaConversation.swift:3909-3919 at 2155)
    }

    // ── the bar (iOS chatTop in MTChatTopBar, 8 from each edge): the back on the marks' round, the name's bubble on the rest of the
    // room, a pair's handset at its right ──
    val chat0 = Book.chat(ref)
    val title = c.text((if (saved) c.getString(R.string.saved_messages) else chat0?.shown?.ifBlank { null }) ?: c.getString(R.string.peer), 15f, Color.WHITE, bold = true).apply { singleLineEllipsis() }   // USER-DATA
    val faceSlot = FrameLayout(c)
    // THE PRESENCE UNDER THE NAME (iOS presenceWord in chatTitleBubble): the words in grey after a dot — green while the person is live
    // («typing…» / «in chat» / «online»), red on «last seen…»; a group's line is its people's count, with no dot
    val presenceLine = c.text("", 11f, MT.gray).apply { singleLineEllipsis() }
    val presenceDot = View(c)
    val presenceRow = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        visibility = View.GONE
        addView(presenceDot, lp(dp(9), dp(9)).apply { marginEnd = dp(4) })
        addView(presenceLine, lp(WRAP, WRAP))
    }
    fun drawPresence() {
        if (group) {   // a group has no presence of one person: who types, with the pair's green dot, or its people's count (iOS MTGroupHeadLine)
            val typing = Groups.typingLine(c, ref)
            presenceLine.text = Groups.outWords(c, ref) ?: typing ?: Groups.headLine(c, ref) ?: ""   // out of the group: removed or left (iOS outWords)
            presenceDot.visibility = if (typing != null) View.VISIBLE else View.GONE
            if (typing != null) presenceDot.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(SysColor.green) }
            presenceRow.visibility = if (presenceLine.text.isEmpty()) View.GONE else View.VISIBLE
            return
        }
        val w = if (local) null else Presence.word(c, ref)
        presenceRow.visibility = if (w == null) View.GONE else View.VISIBLE
        presenceLine.text = w?.first ?: ""
        presenceDot.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (w?.second == true) SysColor.green else SysColor.red) }
    }
    drawPresence()
    // THE PAIR'S MARKS BESIDE THE NAME (iOS chatRow 1866-1870 at 2155): the wallet with the balance short at its corner and the chess,
    // ringed while the pair's game is played, beside the handset -- in a pair's own chat (coinStands); a group wears none of them
    val coinStands = !group && CoinSend.canPay(ref)
    val walletStands = coinStands && GooglePlay.COINS   // the Google Play build wears no wallet, the chess stays
    val rounds = mutableListOf<View>()     // the marks' plates: 44, or 40 where the row is short (iOS ViewThatFits)
    val gapped = mutableListOf<View>()     // the marks that stand the row's gap after the mark before them
    val handsets = mutableListOf<View>()   // the folded call's two handsets, outside the fitted row (iOS chatTop 1847, 1852)
    var nameBubble: View? = null
    val walletBadge = c.text("", 13f, Color.WHITE, bold = true).apply {   // iOS MTCountBadge(word:): the platform's red capsule of 20
        background = c.rounded(SysColor.red, 10)
        gravity = Gravity.CENTER
        minWidth = c.dp(20)
        setPadding(c.dp(6), 0, c.dp(6), 0)
        translationX = c.dp(8).toFloat(); translationY = -c.dp(6).toFloat()
        visibility = View.GONE
    }
    val ringInk = GradientDrawable().apply { shape = GradientDrawable.OVAL; setStroke(Math.round(1.5f * c.resources.displayMetrics.density), MT.blue) }
    val chessRing = View(c).apply { background = ringInk; visibility = View.GONE }   // iOS MTMiniFace.playingRing, 1.5 inside the plate
    fun playedGame(): String? = ChessGame.current(ChessSend.entries(ref))?.takeIf { ChessSend.state(ref, it)?.status?.finished == false }
    fun drawMarks() {
        if (!coinStands) return
        val bal = CoinBook.balance
        walletBadge.text = if (0L < bal) PiLevels.short(c, bal) else ""   // USER-DATA: the balance, short
        walletBadge.visibility = if (0L < bal) View.VISIBLE else View.GONE
        chessRing.visibility = if (playedGame() != null) View.VISIBLE else View.GONE
    }
    fun drawHead() {
        val ch = Book.chat(ref) ?: return
        title.text = if (saved) c.getString(R.string.saved_messages) else ch.shown.ifBlank { c.getString(R.string.peer) }
        // Saved Messages wears one's own face (iOS MTChatAvatar: «one's own for the room without an address»)
        val face = if (saved) c.avatar(SelfFace.load(c), Prefs.userName, 36) else c.chatFace(ref, ch.shown, 36)
        faceSlot.removeAllViews(); faceSlot.addView(face, FrameLayout.LayoutParams(c.dp(36), c.dp(36)))
    }
    drawHead()
    // THE NAME'S BUBBLE IS THE ONE DOOR (iOS chatTitleDoor): the face, the name and the presence in one capsule of glass, the whole of it
    // the button into the correspondent's page (a group's into the group's page), the keyboard going down with it; a hold: «Copy name»
    // the page's «Show in chat» and its forward land here (iOS ui.showLetter): this chat jumps to the letter, another opens in its place
    var jumpHere: (String) -> Unit = {}
    val pageLanding: (String, String?) -> Unit = { to, mid ->
        if (to != ref) { onClose(); act.push { c2 -> conversationPage(act, to, c2) } } else if (mid != null) jumpHere(mid)
    }
    // THE SEARCH BAR UNDER THE HEADER (iOS searchBar, MontanaConversation.swift:2640-2660 at 2312): the platform's own search field,
    // «Search in chat…», the round cross beside it closes the search; the keys are asked for once it stands
    val searchField = EditText(c).apply {
        hint = c.getString(R.string.chat_search_hint)
        setHintTextColor(MT.gray); setTextColor(Color.WHITE)
        textSize = 17f
        background = null
        isSingleLine = true
        inputType = InputType.TYPE_CLASS_TEXT
        imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH
        setPadding(0, 0, 0, 0)
    }
    lateinit var closeSearch: () -> Unit
    val searchBar = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        visibility = View.GONE
        setPadding(dp(12), dp(4), dp(12), dp(4))
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            background = c.glassPlate()
            setPadding(dp(12), 0, dp(12), 0)
            addView(c.icon(R.drawable.ic_search, Color.rgb(230, 230, 230)), lp(dp(22), dp(22)).apply { marginEnd = dp(8) })
            addView(searchField, lp(0, WRAP, 1f))
        }, lp(0, dp(40), 1f))
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.cancel)
            addView(c.icon(R.drawable.ic_close, Color.rgb(204, 204, 204)), FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER))   // iOS MontanaOctagon.barGlyph
            pressable { closeSearch() }
        }, lp(dp(44), dp(44)).apply { marginStart = dp(8) })
    }
    // the feed answers the words a moment after the last key (iOS refreshMessageSearch: 120 ms), not at every letter
    val searchPass = Runnable { redraw() }
    searchField.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun afterTextChanged(s: android.text.Editable?) {
            if (!searching) return
            searchQuery = s?.toString() ?: ""
            searchField.removeCallbacks(searchPass); searchField.postDelayed(searchPass, 120)
        }
    })
    searchField.setOnEditorActionListener { v, _, _ -> c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(v.windowToken, 0); true }
    fun openSearch() {
        hideKeys()
        searching = true
        searchBar.visibility = View.VISIBLE
        searchField.requestFocus()
        searchField.post { c.getSystemService(InputMethodManager::class.java).showSoftInput(searchField, 0) }
        android.util.Log.i("Montana", "chat_search open")
    }
    closeSearch = {
        c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(searchField.windowToken, 0)
        searching = false; searchQuery = ""
        searchField.removeCallbacks(searchPass)
        searchField.setText(""); searchField.clearFocus()
        searchBar.visibility = View.GONE
        redraw()
    }
    // «SEARCH» OF THE GROUP'S PAGE (iOS perform(.search), MontanaPeerInfoScreen.swift:634-639): the page goes down to its chat and asks it
    val openPage = { hideKeys(); act.push { close -> if (group) groupPage(act, ref, close, pageLanding, onSearch = { close(); openSearch() }) else peerInfoPage(act, ref, close, pageLanding) } }
    // THE CHESS MARK'S TAP (iOS chessMark 1975-1986): an invitation waiting for my answer is answered in the feed, a played game opens
    // its board; with none the platform's question asks for a new game — no stake and no balance (iOS 480cd898)
    fun chessTap() {
        val id = playedGame()
        if (id != null && ChessSend.awaitsMe(ref, id)) {
            val invite = Book.chat(ref)?.msgs?.lastOrNull { m -> ChessSend.letterOf(m)?.let { l -> l.game == id && l.kind == ChessLetter.INVITE } == true }
            if (invite != null) { jumpHere(invite.mid); return }
        }
        if (id != null) { act.push { chessBoardPage(act, ref, id, true, it) }; return }
        AlertDialog.Builder(c)
            .setTitle(R.string.chess_ask_new)
            .setPositiveButton(R.string.chess_new_game) { _, _ ->
                val game = ChessSend.invite(c, ref, ChessSend.CHAT_CLOCK)
                if (game != null) act.push { chessBoardPage(act, ref, game, true, it) }
            }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }
    // one round of the bar (iOS MTBarRoundMark): the glass circle of 44 with the bar's grey glyph (MontanaOctagon.barGlyph)
    fun roundMark(res: Int, label: Int, onTap: (View) -> Unit): View = FrameLayout(c).apply {
        background = c.glassPlate(oval = true)
        contentDescription = c.getString(label)
        addView(c.icon(res, Color.rgb(204, 204, 204)), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
        pressable { onTap(this) }
    }
    // the menu's own ink for its glyphs, so they read on whichever plate the platform gives the menu
    fun menuInk() = c.obtainStyledAttributes(intArrayOf(android.R.attr.textColorPrimary)).let { t -> t.getColorStateList(0).also { t.recycle() } }
    val top = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(8), dp(4), dp(8), dp(4))
        addView(callHandset(act, true, null).also { handsets.add(it) }, lp(dp(44), dp(44)))   // 15.8: back to the folded call (iOS chatTop 1847)
        addView(roundMark(R.drawable.ic_arrow_back_ios_new, R.string.back) { hideKeys(); onClose() }.also { rounds.add(it) }, lp(dp(44), dp(44)))
        // THE SHIELD ON THE INTERLOCUTOR'S BUBBLE (iOS MontanaConversation.swift:1957-1962): a badge over its top right corner while this
        // phone keeps what others delete -- a sibling over the door, never inside it, its target centred on the corner; a group's too,
        // its keeper telling the one who deleted (Groups.tellKept).
        addView(FrameLayout(c).apply {
        nameBubble = this
        clipChildren = false
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            background = c.glassPlate()
            setPadding(dp(4), 0, dp(14), 0)
            addView(faceSlot, lp(dp(36), dp(36)).apply { marginEnd = dp(8) })
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(title, lp(WRAP, WRAP))
                addView(presenceRow, lp(WRAP, WRAP).apply { topMargin = dp(1) })
            }, lp(0, WRAP, 1f))
            if (!local) pressable { openPage() }   // the room without an address has no correspondent's page behind its name
            setOnLongClickListener { v ->
                PopupMenu(c, v).apply {
                    menu.add(R.string.copy_name)
                    setOnMenuItemClickListener {
                        c.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("name", title.text)); true
                    }
                }.show(); true
            }
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        if (!local) addView(keepShield(act).apply { translationX = c.dp(18).toFloat(); translationY = -c.dp(18).toFloat() },
            FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.TOP or Gravity.END))
        }, lp(0, dp(44), 1f).apply { marginStart = dp(6); if (!local) marginEnd = dp(6) })
        if (walletStands) {
            // THE WALLET BESIDE THE COIN (iOS walletMark): the wallet page over the chat, the one road a coin's link takes
            addView(FrameLayout(c).apply {
                clipChildren = false
                addView(roundMark(R.drawable.ic_app_wallet, R.string.app_wallet) { hideKeys(); act.push { walletPage(act, it) } }.also { rounds.add(it) },
                    FrameLayout.LayoutParams(MATCH, MATCH))
                addView(walletBadge, FrameLayout.LayoutParams(WRAP, c.dp(20), Gravity.TOP or Gravity.END))
            }, lp(dp(44), dp(44)))
        }
        if (coinStands) {
            // THE CHESS MARK (iOS chessMark): the game's knight on the marks' round, the platform's blue ring while the game is played
            addView(FrameLayout(c).apply {
                addView(roundMark(R.drawable.chess_knight, R.string.app_chess) { hideKeys(); chessTap() }.also { rounds.add(it) },
                    FrameLayout.LayoutParams(MATCH, MATCH))
                addView(chessRing, FrameLayout.LayoutParams(MATCH, MATCH))
            }.also { if (walletStands) gapped.add(it) }, lp(dp(44), dp(44)).apply { if (walletStands) marginStart = dp(6) })
        }
        // THE HANDSET AS IT WAS (iOS handsetMark, a pair's chat): the calls' menu behind the one bar glyph — a voice call or a video call
        if (!group && !local) addView(roundMark(R.drawable.ic_bar_calls, R.string.pi_voice_call) { v ->
            hideKeys()
            PopupMenu(c, v).apply {
                if (29 <= android.os.Build.VERSION.SDK_INT) setForceShowIcon(true)
                val ink = menuInk()
                menu.add(0, 0, 0, R.string.pi_voice_call).setIcon(R.drawable.ic_peer_phone).iconTintList = ink
                menu.add(0, 1, 1, R.string.pi_video_call).setIcon(R.drawable.ic_peer_video).iconTintList = ink
                setOnMenuItemClickListener { item -> act.callOut(ref, video = item.itemId == 1); true }
            }.show()
        }.also { rounds.add(it); if (coinStands) gapped.add(it) }, lp(dp(44), dp(44)).apply { if (coinStands) marginStart = dp(6) })
        addView(callHandset(act, false, null).also { handsets.add(it) }, lp(dp(44), dp(44)))   // 15.8: end it (iOS chatTop 1852)
        layoutParams = LinearLayout.LayoutParams(MATCH, dp(52))
    }
    // THE ROW FITS ANY SCREEN (iOS chatTop's ViewThatFits): rounds of 44 a gap of 6 apart while the name's bubble keeps 120, rounds of
    // 40 with no gap where it keeps less; every mark's target stays 44 -- the marks yield their glass, never the name its place
    fun fit(w: Int) {
        val n = rounds.size
        val calls = handsets.count { it.visibility == View.VISIBLE }
        val wide = c.dp(120) <= w - c.dp(16) - (n + calls) * c.dp(44) - n * c.dp(6)
        val inset = if (wide) 0 else c.dp(2)
        for (r in rounds) r.background = android.graphics.drawable.InsetDrawable(c.glassPlate(oval = true), inset)
        chessRing.background = android.graphics.drawable.InsetDrawable(ringInk, inset)
        for (v in gapped) (v.layoutParams as LinearLayout.LayoutParams).marginStart = if (wide) c.dp(6) else 0
        (nameBubble?.layoutParams as? LinearLayout.LayoutParams)?.apply {
            marginStart = if (wide) c.dp(6) else c.dp(2)
            if (!group && !local) marginEnd = if (wide) c.dp(6) else c.dp(2)
        }
        top.requestLayout()
    }
    top.clipChildren = false
    top.addOnLayoutChangeListener { _, l, _, r, _, ol, _, or2, _ -> if (r - l != or2 - ol) top.post { fit(r - l) } }
    drawMarks()

    val groupFoot = FrameLayout(c).apply { visibility = View.GONE }.also { if (group) fillGroupFoot(c, ref, it) { openSearch() } }
    var lane = false   // the live lane stands while the page does
    fun drawDraft() {
        val d = LiveDraft.of(ref)
        val was = draftRow.visibility == View.VISIBLE
        draftRow.removeAllViews()
        if (d == null) { draftRow.visibility = View.GONE; return }
        draftRow.addView(c.liveDraftBubble(d, Book.chat(ref)), FrameLayout.LayoutParams(MATCH, WRAP))
        draftRow.visibility = View.VISIBLE
        if (!was) toBottom()
    }
    val draftListener: () -> Unit = { drawDraft() }
    val presenceListener: () -> Unit = { drawPresence() }
    lateinit var chatBeat: Runnable
    // the 20-second beat (iOS P-109); THE BEAT SPEAKS ONLY WHILE THE APP IS ON THE SCREEN (iOS chatPresenceMoved 826-830): a chat
    // left open behind a locked phone said «in chat» after the app's own farewell
    chatBeat = Runnable { if (lane && !local) { if (Presence.shown) Presence.sayChat(ref, true); MainThread.later(Presence.BEAT, chatBeat) } }
    var folded = false
    val listener: () -> Unit = listener@{
        // THE GROUP LEFT THIS PHONE (iOS erase / dissolve → closeChat): «Delete and Exit», «Leave Group», «Delete for All»
        if (group && Book.chat(ref) == null) {
            if (!folded) { folded = true; hideKeys(); onClose() }
            return@listener
        }
        // THIS CHAT WAS FOLDED INTO THE OLDER ONE WITH THE SAME PERSON (iOS foldConversation → openChatRequest): the older opens instead.
        val into = SamePair.root(ref)
        if (into != ref && Book.chat(ref) == null) {
            if (!folded) { folded = true; hideKeys(); onClose(); act.push { close -> conversationPage(act, into, close) } }
            return@listener
        }
        val before = column.childCount
        redraw(); drawHead(); drawMarks()
        if (group) {
            drawPresence(); fillGroupFoot(c, ref, groupFoot) { openSearch() }
            // taken out of the group, or let back in: the field follows (iOS composeSlot)
            if (!selecting) bar.visibility = if (Groups.fieldOpen(ref)) View.VISIBLE else View.GONE
        }
        if (column.childCount != before) toBottom()
        if ((Book.chat(ref)?.unread ?: 0) > 0) Thread { Post.markRead(ref) }.start()
    }

    // THE EYE CARRIED TO A LETTER (the pinned plate's tap, the search's jump): scrolled a third down and lit for a moment
    fun jumpTo(mid: String) {
        val found = column.findViewWithTag<View>(mid) ?: return
        scroll.post {
            scroll.smoothScrollTo(0, (found.top + column.top + scroll.paddingTop - scroll.height / 3).coerceAtLeast(0))
            found.setBackgroundColor(Color.argb(60, 255, 255, 255))
            found.postDelayed({ found.background = null }, 1200)
        }
    }
    jumpHere = { jumpTo(it) }
    searchLeave = { mid -> closeSearch(); column.post { jumpTo(mid) } }
    if (search) searchBar.post { openSearch() }
    // THE BAR'S WAY BACK TO ITS BUBBLE (iOS goToLetter, MontanaConversation.swift:1315-1323 at 2155; atom 83753ae0754a): this
    // chat's letter is scrolled to and lit as a reply jump lights; another chat's opens in this one's place
    val showLetter: (String, String) -> Unit = { to, mid ->
        if (to == ref) toQuoted(mid) else { onClose(); act.push { c2 -> conversationPage(act, to, c2, jump = mid) } }
    }
    // a letter folded into a media group is reached by its plate's row (iOS rowLead)
    toQuoted = { q -> jumpTo(Book.chat(ref)?.let { ch -> feedRows(ch.msgs).firstOrNull { r -> r.any { it.mid == q } }?.get(0)?.mid } ?: q) }
    // THE FOOT WHILE THE CHAT SELECTS (iOS the selection bar): Forward and Delete for the chosen letters, in place of the field
    val foot = FrameLayout(c).apply { visibility = View.GONE }
    // THE HEAD WHILE THE CHAT SELECTS (iOS selectionTopBar, MontanaConversation.swift:4433-4453 at 2240): «Delete chat» on the
    // left, «Selected: N» in the middle, the cross on the right, in place of the chat's own head
    val selTop = FrameLayout(c).apply { visibility = View.GONE }
    drawFoot = {
        foot.removeAllViews()
        foot.visibility = if (selecting) View.VISIBLE else View.GONE
        selTop.removeAllViews()
        selTop.visibility = if (selecting) View.VISIBLE else View.GONE
        top.visibility = if (selecting) View.GONE else View.VISIBLE
        bar.visibility = if (selecting || (group && !Groups.fieldOpen(ref)) || Post.closed(ref) || Book.isMontana(ref)) View.GONE else View.VISIBLE
        if (selecting) {
            strip.visibility = View.GONE
            fun done() { selecting = false; picked.clear(); redraw(); drawFoot() }
            fun chosen() = Book.chat(ref)?.msgs?.filter { it.mid in picked } ?: emptyList()
            // THE SELECTION'S «DELETE CHAT» TAKES THE ONE ROAD (iOS 2144d461, deleteWholeChat): the one sheet of the chats tab asks
            // the one question -- for me and them, for me only, nothing while a coin letter of mine is on its way -- and the open chat
            // closes only when the conversation went. The room with no wire is not deleted: its bar offers no such deed; a group
            // leaves by its own road (the group's page).
            selTop.addView(letterSelectionHead(act, picked.size, canDeleteChat = !local && !group,
                onDeleteChat = { askDeleteChat(act, ref) { done(); hideKeys(); onClose() } }, onClose = { done() }), FrameLayout.LayoutParams(MATCH, WRAP))
            foot.addView(letterSelectionFoot(act, picked.size,
                onShare = {
                    // the chosen letters' words and finished files through the platform's share (iOS shareSelected 4475-4488)
                    val letters = chosen()
                    if (shareLetters(act, letters)) done()
                },
                onForward = {
                    val letters = chosen().filter { canForward(it) }
                    done()
                    if (letters.isNotEmpty()) act.push { close -> forwardPage(act, ref, letters, close) { to -> close(); if (to != ref) { onClose(); act.push { c2 -> conversationPage(act, to, c2) } } } }
                },
                onDelete = {
                    // a coin letter of mine on its way stays, and the person is told why once the rest are gone (iOS deleteSelected 4247-4250)
                    val all = chosen()
                    val letters = all.filter { !CoinSend.travels(it) }
                    val held = letters.size != all.size
                    fun told() { if (held) AlertDialog.Builder(c).setTitle(R.string.coins_travel).setMessage(R.string.coins_travel_note).setPositiveButton(R.string.ok, null).show() }
                    if (letters.isEmpty()) { done(); told(); return@letterSelectionFoot }
                    AlertDialog.Builder(c).setTitle(R.string.delete_message_q)
                        .setItems(arrayOf(c.getString(R.string.delete_for_everyone), c.getString(R.string.delete_for_me))) { _, which ->
                            val mids = letters.map { it.mid }.toSet()
                            Book.drop(ref, mids)
                            // in a group a speaker takes away their own letters for everyone (iOS MTGroup.answered checks the seat)
                            if (which == 0) letters.forEach { m ->
                                if (!group) Post.send(ref, Marks.mintMid(), Marks.DELETE + "mid:" + m.mid)
                                else if (m.mine || Groups.moderates(ref)) Groups.signal(ref, Marks.DELETE + "mid:" + m.mid)
                            }
                            done(); told()
                        }
                        .setNegativeButton(R.string.cancel, null).show()
                }), FrameLayout.LayoutParams(MATCH, WRAP))
        } else showStrip()
    }

    hideBar = { bar.visibility = View.GONE }
    if (Book.isMontana(ref)) hideBar()   // the room speaks; nobody writes into it (iOS composeSlot, MontanaConversation.swift:3636)
    return TabPan(act).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ref), FrameLayout.LayoutParams(MATCH, MATCH))   // the chat's own ground, or the pages' crest (iOS MTWallpaper)
        // THE FEED RUNS UNDER THE BARS (iOS MTFeedFrame.underlap, MontanaOctagon 107-114, the author's word 21.09; the word of
        // 08.10.2026 16:5x «the feed must run under the buttons»): the header and the compose panel have no ground of their own —
        // the letters scroll on under them and show between the plates; the plates alone carry the glass. The feed's own room above
        // and below is the bars' height as drawn, so the first and the last letter rest clear of them, and a feed at its end stays
        // at its end when the panel grows (a reply line, a recording, the keyboard).
        val head = c.vstack(Gravity.NO_GRAVITY) {
            addView(top)
            addView(searchBar, lp(MATCH, WRAP))
            addView(selTop, lp(MATCH, WRAP))
            // THE PINNED PLATE under the header (iOS the pinned bar): shown while a letter of this chat is pinned
            addView(pinnedPlate(act, ref) { mid -> jumpTo(mid) }, lp().apply { marginStart = dp(10); marginEnd = dp(10); bottomMargin = dp(4) })
            // THE ROOM'S BAR (iOS MTRoomBar): a group's living voice or video chat, or its stream
            if (group) addView(roomBar(act, ref), lp().apply { marginStart = dp(8); marginEnd = dp(8); bottomMargin = dp(4) })
        }
        val under = c.vstack(Gravity.NO_GRAVITY) {
            addView(strip, lp().apply { marginStart = dp(10); marginEnd = dp(10); bottomMargin = dp(4) })
            addView(coinPlate, lp().apply { marginStart = dp(10); marginEnd = dp(10); bottomMargin = dp(4) })
            addView(linkPlate, lp().apply { marginStart = dp(10); marginEnd = dp(10); bottomMargin = dp(4) })
            addView(mentionPlate, lp().apply { marginStart = dp(8); marginEnd = dp(8); bottomMargin = dp(4) })
            addView(stagedStrip, lp())
            addView(liveBar(act), lp().apply { bottomMargin = dp(2) })   // the one player bar above the field (iOS MontanaPlayerBar in the chat)
            addView(recStrip, lp().apply { marginStart = dp(10); marginEnd = dp(10); bottomMargin = dp(4) })
            addView(bar.apply { if ((group && !Groups.fieldOpen(ref)) || Post.closed(ref)) visibility = View.GONE }, lp())
            addView(panel.host, lp(MATCH, dp(300)))
            addView(closedNote, lp().apply { marginStart = dp(10); marginEnd = dp(10); bottomMargin = dp(6) })
            addView(foot, lp())
            addView(groupFoot, lp())
        }
        scroll.clipToPadding = false
        // THE FEED SINKS INTO THE GROUND PAST THE HEADER AND THE BAR (iOS MTEdgeWash, ContentView.swift:1182-1207 at 2155,
        // read 21.09 in WallpaperEdgeEffectNodeImpl; atoms d4817f6e3b72/39b5b03396cb/331a040adb4e/df3a6b50be61 -- the ground
        // drawn again under a fading mask, 80 past the header and 60+20 past the bar): the one EdgeSink mask (PeerInfo.kt's
        // own road, EdgeSink.kt) on the feed's own layer instead -- the ground never drawn twice.
        addView(EdgeSink(c, top = { head.height + dp(34) }, bottom = { height - under.height - lifted }).apply {
            addView(scroll, FrameLayout.LayoutParams(MATCH, MATCH))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(head, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.TOP))
        addView(under, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))
        // THE FEED KEEPS ITS HEIGHT UNDER THE KEYS (iOS MTFeedFrame, MontanaMessageFeed.swift:93-200 at 2155): the keys' cover is part
        // of the feed's one inset beside the bar's; a reader at the newest end is held there as the keys move by themselves, a finger
        // dragging them keeps its own scroll (iOS: «!isTracking, !keyboardGestureActive»), a reader higher up keeps the same letters.
        fun room(keys: Boolean = false) {
            val t = head.height
            val b = under.height + lifted
            if (scroll.paddingTop == t && scroll.paddingBottom == b) return
            val atEnd = !scroll.canScrollVertically(1)
            scroll.setPadding(0, t, 0, b)
            if (!atEnd || ride?.dragging == true) return
            if (keys) scroll.scrollTo(0, scroll.getChildAt(0)?.height ?: 0)   // this frame, not the next: the letters ride with the bar
            else toBottom()
        }
        // THE WAY TO THE NEWEST (iOS ScrollDownButton 384-399, MontanaConversation 2928-2940): the chevron in the compose tier's glass,
        // on the microphone's own vertical line, ten points above the panel; on past 260 points from the newest, off under 60
        val downKey = FrameLayout(c).apply {
            addView(FrameLayout(c).apply {
                background = c.glassPlate(oval = true)
                addView(c.icon(R.drawable.ic_chevron_down, Color.rgb(204, 204, 204)), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            }, FrameLayout.LayoutParams(dp(36), dp(36), Gravity.CENTER))
            contentDescription = c.getString(R.string.to_newest)
            visibility = View.GONE
            pressable { scroll.smoothScrollTo(0, (scroll.getChildAt(0)?.height ?: 0) + scroll.paddingTop + scroll.paddingBottom) }
        }
        addView(downKey, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.BOTTOM or Gravity.END).apply { marginEnd = dp(12) })
        // THE DAY THE FINGER IS READING (iOS MTDayHeader 359-372, stage 13.1): the pill of the topmost row's day under the header while
        // the feed travels, gone a second after the last movement; a sign, never a target
        val dayPill = c.text("", 13f, Color.WHITE).apply {
            background = c.glassPlate(); setPadding(dp(10), dp(3), dp(10), dp(3)); alpha = 0f
            isClickable = false; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        addView(dayPill, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.CENTER_HORIZONTAL))
        val dayAway = Runnable { dayPill.animate().alpha(0f).setDuration(180).start() }
        var downOn = false
        // THE FEED'S OWN DRAG AND ITS FLING, MEASURED (iOS MTFrameMeter, MontanaMessageFeed.swift:268-437, 1125-1149):
        // one diary line per gesture, never while the finger and the fling both stand still.
        Motion.watch(scroll) { _, _, y, _, _ ->
            val d = resources.displayMetrics.density
            val content = scroll.getChildAt(0) ?: return@watch
            val fromEnd = (content.height + scroll.paddingTop + scroll.paddingBottom - scroll.height - y) / d
            if (!downOn && 260 < fromEnd) { downOn = true; downKey.visibility = View.VISIBLE; downKey.alpha = 0f; downKey.animate().alpha(1f).setDuration(180).start() }
            else if (downOn && fromEnd < 60) { downOn = false; downKey.animate().alpha(0f).setDuration(180).withEndAction { if (!downOn) downKey.visibility = View.GONE }.start() }
            // the topmost row under the header: its letter's day
            val holder = column.parent as? View ?: return@watch
            val edge = y + scroll.paddingTop - content.top - holder.top - column.top
            var words: String? = null
            for (i in 0 until column.childCount) {
                val v = column.getChildAt(i)
                if (v.bottom <= edge) continue
                val mid = v.tag as? String ?: (v as? android.view.ViewGroup)?.let { g -> (0 until g.childCount).firstNotNullOfOrNull { j -> g.getChildAt(j).tag as? String } }
                val at = mid?.let { id -> Book.chat(ref)?.msgs?.firstOrNull { it.mid == id }?.at } ?: continue
                words = dayWords(c, at); break
            }
            if (words != null) {
                if (dayPill.text != words) dayPill.text = words
                if (dayPill.alpha < 1f) dayPill.animate().alpha(1f).setDuration(180).start()
                dayPill.removeCallbacks(dayAway); dayPill.postDelayed(dayAway, 1000)
            }
        }
        fun lift() {
            (downKey.layoutParams as FrameLayout.LayoutParams).let { lp -> val want = under.height + dp(10); if (lp.bottomMargin != want) { lp.bottomMargin = want; downKey.layoutParams = lp } }
            (dayPill.layoutParams as FrameLayout.LayoutParams).let { lp -> val want = head.height + dp(6); if (lp.topMargin != want) { lp.topMargin = want; dayPill.layoutParams = lp } }
        }
        head.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> room(); lift() }
        under.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> room(); lift() }
        plateHome = this; addView(lockPlate, plateLp())
        // THE BAR RIDES THE KEYS BY ITS LAYER (iOS MTKeyboardRider, ContentView.swift:1240 at 2155): the page stands inside the system
        // bars alone; the keyboard's cover lifts the bar, the «down» key over it and the feed's inset, frame by frame (KeyRide.kt)
        // THE PANEL IN THE KEYS' PLACE IS THEIR ROOM (FieldPanel): standing, it is part of the bar's tier and the keys falling under it
        // move nothing; going because the keys rise, its room is held until the keys reach it -- the bar never dips between the two.
        var hold = 0
        fun ridePlace() {
            val k = ride?.cover ?: 0
            val want = if (panel.up) (k - panel.host.layoutParams.height).coerceAtLeast(0) else { if (hold <= k) hold = 0; maxOf(k, hold) }
            if (want == lifted && under.translationY == -want.toFloat()) return
            lifted = want
            under.translationY = -want.toFloat()
            downKey.translationY = -want.toFloat()
            room(keys = true)
        }
        under.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> ridePlace() }
        // the keyboard key on the panel puts the panel away itself before the keys rise: its room is held for them from that tap
        val unhold = Runnable { hold = 0; ridePlace() }
        val emojiKey = bar.onEmojiKey
        bar.onEmojiKey = {
            if (panel.up) { hold = panel.host.layoutParams.height; removeCallbacks(unhold); postDelayed(unhold, 800) }
            emojiKey?.invoke()
        }
        val keys = KeyRide(this, place = { ridePlace() }, letGo = { hideKeys() }, drawn = {
            val at = IntArray(2).also { bar.getLocationOnScreen(it) }
            val d = resources.displayMetrics.density
            " bar_top=" + (at[1] / d).toInt() + " inset=" + (scroll.paddingBottom / d).toInt() + " off=" + (scroll.scrollY / d).toInt()
        })
        ride = keys
        setOnApplyWindowInsetsListener { v, insets ->
            val b = insets.getInsets(WindowInsets.Type.systemBars())
            v.setPadding(b.left, b.top, b.right, b.bottom)
            val imeCover = (insets.getInsets(WindowInsets.Type.ime()).bottom - b.bottom).coerceAtLeast(0)
            if (!insets.isVisible(WindowInsets.Type.ime())) hold = 0   // the keys going down: no room is held for them
            else hold = minOf(hold, imeCover)   // and never more than the keys will stand
            keys.insets(insets)
            val panelWas = panel.up
            panel.insets(insets)   // the keyboard's height is the panel's; the keyboard rising takes the panel's place
            if (panelWas && !panel.up) { hold = minOf(panel.host.layoutParams.height, imeCover); ridePlace() }
            insets
        }
        // a sticker sent from the panel answers the letter the plate holds, and the plate goes (Stickers.answering)
        val takeAnswer: (String) -> Msg? = { r -> if (r != ref || editing != null) null else replyTo.also { if (it != null) { replyTo = null; showStrip() } } }
        val sayRefusal: (String) -> Unit = { why -> AlertDialog.Builder(c).setMessage(why).setPositiveButton(android.R.string.ok, null).show() }
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {
                v.requestApplyInsets()
                Book.openChat = ref; Book.listen(listener); ChannelComments.listen(listener); ChannelViews.listen(listener); Notify.clear(ref)
                // WHAT THE GROUP REFUSED IS SAID HERE (iOS groupRefusal's alert): the reference's sentence, the field left as it was
                if (group) Groups.refused = sayRefusal
                ShowLetter.open = showLetter
                Stickers.answering = takeAnswer
                // the banner's road measured (iOS chat_open why=banner ms=…, 4b49d03f071b): from the tap to the chat standing
                if (Notify.tappedAt != 0L) {
                    val t0 = Notify.tappedAt
                    android.util.Log.d("Montana", "chat_open why=banner ms=" + (android.os.SystemClock.elapsedRealtime() - t0)); Notify.tappedAt = 0L
                    // THE FIRST FRAME OF THE FEED IS THE END OF THE ROAD (iOS MTFeedFrame feed_first, a5622f175804): the chat is
                    // open for the eye when its letters are laid out — the same clock stops at the feed's first laid-out frame
                    column.addOnLayoutChangeListener(object : View.OnLayoutChangeListener {
                        override fun onLayoutChange(v: View, l: Int, t: Int, r: Int, b: Int, ol: Int, ot: Int, or2: Int, ob: Int) {
                            if (b - t <= 1 || r - l <= 1) return
                            v.removeOnLayoutChangeListener(this)
                            android.util.Log.d("Montana", "feed_first why=banner ms=" + (android.os.SystemClock.elapsedRealtime() - t0) + " rows=" + feed.size)
                        }
                    })
                }
                Presence.listen(presenceListener); lane = true
                LiveDraft.listen(draftListener); drawDraft()
                LinkCompose.listen(linkListener); drawLink()
                CoinBook.listen(coinListener); Thread { CoinBook.warm(); MainThread.post { coinListener() } }.start()
                if (!local) { Presence.sayChat(ref, true); MainThread.later(Presence.BEAT, chatBeat); Signal.hold(ref, "chat") }
                VoicePlayer.endedAtEar = earHook   // the open chat answers its peer's voice at the ear
                if (!group && !local) LiveDraft.sayLink(ref)   // our daily link, to hand on (iOS sendLinkWord on a chat's opening)
                if ((Book.chat(ref)?.unread ?: 0) > 0) Thread { Post.markRead(ref) }.start()
            }
            override fun onViewDetachedFromWindow(v: View) {
                // A TAPE LEFT RECORDING BEHIND A CLOSED CHAT IS NOBODY'S (iOS ChatConversationView.onDisappear,
                // MontanaConversation.swift:1666 at 2155: «if rec.isRecording { rec.cancel(why: "chat-left") }»): a note left rolling
                // behind a closed chat rolled on and the next one was refused. The recorder's own page lies over the chat, so it
                // never detaches it; with nothing held the cancel does nothing.
                if (VoicePlayer.endedAtEar === earHook) VoicePlayer.endedAtEar = null
                if (Stickers.answering === takeAnswer) Stickers.answering = null
                endEarReply()
                bar.cancelRecording()
                VoiceTape.standDown()   // a tape readied by a hold that never began goes with the chat (iOS MontanaConversation.swift:1667)
                if (Book.openChat == ref) Book.openChat = null; Book.unlisten(listener); ChannelComments.unlisten(listener); ChannelViews.unlisten(listener)
                if (Groups.refused === sayRefusal) Groups.refused = null   // only this chat's own: another may stand over it
                if (ShowLetter.open === showLetter) ShowLetter.open = null
                Presence.unlisten(presenceListener); LiveDraft.unlisten(draftListener); LinkCompose.unlisten(linkListener); CoinBook.unlisten(coinListener)
                // words left in the field stand on their screen as a checkpoint, frozen, not typing (iOS «ck»)
                if (!local) field.text.toString().takeIf { it.isNotBlank() }?.let { LiveDraft.say(ref, it, field.selectionEnd, checkpoint = true) }
                if (!local) Signal.release(ref, "chat")
                if (lane) { lane = false; if (!local) Presence.sayChat(ref, false) }   // leaving says so at once (iOS: the departure word)
            }
        })
        scroll.addOnLayoutChangeListener { _, _, t, _, b, _, ot, _, ob -> if (b - t < ob - ot) toBottom() }
        redraw()
        val found = jump?.let { column.findViewWithTag<View>(it) }
        if (found == null) toBottom() else scroll.post {
            scroll.scrollTo(0, (found.top + column.top + scroll.paddingTop - scroll.height / 3).coerceAtLeast(0))
            found.setBackgroundColor(Color.argb(60, 255, 255, 255))
            found.postDelayed({ found.background = null }, 1200)
        }
    }
}

/** One letter: the quote it answers, its words, «edited» and the time; its reactions under it (iOS MessageBubble). */
/**
 * THE CHAT LEAVES FROM ITS CENTRE TOO (iOS MTTabPan on MontanaSlideController, e59b73a4; the author's word 18.10.2026: «the swipe out
 * of a chat not only from the screen's edge but, as when a page is turned, from its centre, so that it catches»): a stroke to the right
 * anywhere on the chat's page drags it off by the finger, the same road as the edge's back, and the release goes by the same rule as
 * iOS's pan -- faster than 300 a second, its way; slower, past a third of the width. The first points decide (iOS MTTabPan
 * touchesMoved): down at once is the feed's, flat at once is ours, else the dominant way after ten points; a stroke to the left is
 * the bubble's reply (ReplySwipe), and a view under the finger that scrolls sideways keeps its own stroke (iOS refuses).
 */
class TabPan(private val act: MainActivity) : FrameLayout(act) {
    private var x0 = 0f; private var y0 = 0f
    private var validated = false; private var failed = true; private var dragging = false
    private var tracker: android.view.VelocityTracker? = null
    private val dpx = resources.displayMetrics.density

    /** The deepest view under the point, the platform's own hit walk (iOS v.hitTest). */
    private fun hit(v: View, x: Float, y: Float): View {
        if (v is android.view.ViewGroup) for (i in v.childCount - 1 downTo 0) {
            val ch = v.getChildAt(i)
            if (ch.visibility != View.VISIBLE) continue
            val cx = x + v.scrollX - ch.left - ch.translationX; val cy = y + v.scrollY - ch.top - ch.translationY
            if (cx >= 0 && cy >= 0 && cx < ch.width && cy < ch.height) return hit(ch, cx, cy)
        }
        return v
    }
    private fun refuses(x: Float, y: Float): Boolean {
        var v: View? = hit(this, x, y)
        while (v != null && v !== this) { if (v.canScrollHorizontally(1) || v.canScrollHorizontally(-1)) return true; v = v.parent as? View }
        return false
    }
    private fun judge(e: android.view.MotionEvent) {
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> {
                x0 = e.rawX; y0 = e.rawY; validated = false; dragging = false
                failed = !act.panOwns(this) || refuses(e.x, e.y)
                tracker?.recycle(); tracker = if (failed) null else android.view.VelocityTracker.obtain()
            }
            android.view.MotionEvent.ACTION_MOVE -> if (!failed && !dragging) {
                val dx = e.rawX - x0; val adx = kotlin.math.abs(dx) / dpx; val ady = kotlin.math.abs(e.rawY - y0) / dpx
                if (!validated) {
                    if (kotlin.math.hypot(adx, ady) > 10) { if (adx >= ady) validated = true else failed = true }   // the dominant way after ten points
                    else if (ady > 2 && ady > adx * 2) failed = true   // down at once: the feed's
                    else if (adx > 2 && ady * 2 < adx) validated = true   // flat at once: ours
                }
                if (validated && dx < 0) failed = true   // a stroke to the left is the bubble's
                else if (validated) { dragging = true; parent?.requestDisallowInterceptTouchEvent(true); act.panBegin(this) }
            }
        }
        tracker?.addMovement(android.view.MotionEvent.obtain(e).apply { setLocation(e.rawX, e.rawY) })
    }
    override fun onInterceptTouchEvent(e: android.view.MotionEvent): Boolean { judge(e); return dragging }

    @android.annotation.SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: android.view.MotionEvent): Boolean {
        if (!dragging) { judge(e); return !failed }
        tracker?.addMovement(android.view.MotionEvent.obtain(e).apply { setLocation(e.rawX, e.rawY) })
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_MOVE -> act.panMove(this, e.rawX - x0)
            android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                val x = e.rawX - x0
                val v = tracker?.run { computeCurrentVelocity(1000); xVelocity / dpx } ?: 0f
                val out = e.actionMasked == android.view.MotionEvent.ACTION_UP && (if (kotlin.math.abs(v) > 300) v > 0 else x > width / 3f)
                android.util.Log.d("Montana", "page_pan page=chat end=" + (if (e.actionMasked == android.view.MotionEvent.ACTION_UP) "completed" else "cancelled") + " close=" + (if (out) 1 else 0))
                act.panEnd(this, out)
                dragging = false; failed = true; tracker?.recycle(); tracker = null
            }
        }
        return true
    }
}

/**
 * A LETTER PULLED TO THE LEFT IS ANSWERED (iOS MTReplySwipe + SwipeReplyRow): the two first points decide — a stroke to the
 * right or an upright one is the scroll's, a flat one to the left is ours; the letter rides by the finger, the round glass with
 * the reply arrow comes in from beyond the edge, growing and clearing; past the threshold (60 for one's own, 45 for theirs)
 * the pull stiffens and the phone knocks once; let go armed — the reply strip opens. The row slides back either way.
 */
class ReplySwipe(c: Context) : FrameLayout(c) {
    var onReply: (() -> Unit)? = null
    var mine = false
    private var badge: View? = null
    private var x0 = 0f; private var y0 = 0f
    private var validated = false; private var failed = false; private var armed = false
    private val slop = dp(2).toFloat()

    private fun threshold() = dp(if (mine) 60 else 45).toFloat()
    /** The pull past the threshold stiffens (iOS band: range 100, k 0.4). */
    private fun band(off: Float, start: Float): Float {
        if (off < start) return off
        val range = dp(100).toFloat()
        return start + (1 - 1 / ((off - start) * 0.4f / range + 1)) * range
    }
    private fun badge(): View = badge ?: FrameLayout(context).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(90, 120, 120, 128)); setStroke(dp(1), Color.argb(38, 255, 255, 255)) }
        addView(context.icon(R.drawable.ic_reply, Color.WHITE), LayoutParams(dp(17), dp(17), Gravity.CENTER))
        alpha = 0f
        this@ReplySwipe.addView(this, LayoutParams(dp(34), dp(34), Gravity.END or Gravity.CENTER_VERTICAL))
    }.also { badge = it }

    private fun ride(pull: Float) {
        val tx = band(pull, threshold()); val p = (pull / threshold()).coerceAtMost(1f)
        getChildAt(0)?.translationX = -tx
        badge().apply { translationX = dp(43) - tx; alpha = p; scaleX = 0.6f + 0.4f * p; scaleY = scaleX }
    }
    private fun settle() {
        val content = getChildAt(0) ?: return
        val from = -content.translationX
        if (from == 0f) return
        android.animation.ValueAnimator.ofFloat(from, 0f).apply {
            duration = 240; interpolator = android.view.animation.DecelerateInterpolator(1.6f)
            addUpdateListener { v -> val tx = v.animatedValue as Float; content.translationX = -tx
                badge?.let { b -> b.translationX = dp(43) - tx; val p = (tx / threshold()).coerceIn(0f, 1f); b.alpha = p; b.scaleX = 0.6f + 0.4f * p; b.scaleY = b.scaleX } }
            start()
        }
    }

    /** The first points of a touch: whether it is a pull to the left. */
    private fun judge(e: android.view.MotionEvent) {
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> { x0 = e.rawX; y0 = e.rawY; validated = false; failed = false; armed = false }
            android.view.MotionEvent.ACTION_MOVE -> if (!validated && !failed) {
                // two-point validation — quick enough to win the race against the scroll's own pan
                val dx = e.rawX - x0; val dy = e.rawY - y0
                if (dx > slop) failed = true
                else if (kotlin.math.abs(dy) > slop && kotlin.math.abs(dy) > kotlin.math.abs(dx) * 2) failed = true
                else if (kotlin.math.abs(dx) > slop && kotlin.math.abs(dy) * 2 < kotlin.math.abs(dx)) {
                    validated = true; parent?.requestDisallowInterceptTouchEvent(true)
                }
            }
        }
    }

    override fun onInterceptTouchEvent(e: android.view.MotionEvent): Boolean {
        if (onReply == null) return false
        judge(e)
        return validated
    }

    @android.annotation.SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: android.view.MotionEvent): Boolean {
        if (onReply == null) return false
        // A PULL BESIDE THE BUBBLE ANSWERS TOO (iOS: the letter's line, not the bubble's face): the row keeps the touch
        // that no bubble took, and judges it itself.
        if (!validated) { judge(e); return !failed }
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_MOVE -> {
                val pull = (x0 - e.rawX).coerceAtLeast(0f)
                ride(pull)
                if (pull >= threshold() && !armed) {
                    armed = true
                    performHapticFeedback(if (android.os.Build.VERSION.SDK_INT >= 34) android.view.HapticFeedbackConstants.GESTURE_THRESHOLD_ACTIVATE
                                          else android.view.HapticFeedbackConstants.LONG_PRESS)
                }
            }
            android.view.MotionEvent.ACTION_UP -> { if (armed) onReply?.invoke(); settle(); validated = false }
            android.view.MotionEvent.ACTION_CANCEL -> { settle(); validated = false }
        }
        return true
    }
}

/**
 * THE GROUP'S FOOT IN PLACE OF THE FIELD (iOS composeSlot): out of the group — the note that its letters stay to read
 * (groupOutNote); taken out of a channel -- «Join» in grey (channelJoinBar); a channel's subscriber -- the reference's channel panel:
 * one wide round of glass saying «Mute» or «Unmute», the same switch as the list's swipe, and the chat's own search on a round of
 * glass to its right (channelMuteBar, iOS MTChannelSubscriberBar, MontanaChannel 410-445).
 */
private fun fillGroupFoot(c: Context, ref: String, into: FrameLayout, onSearch: () -> Unit) {
    into.removeAllViews()
    // a room as wide as the right round stands on the left, so the word stays in the middle
    fun panel(word: View, right: View?) = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(6), dp(12), dp(6))
        addView(View(c), lp(dp(44), dp(44)).apply { marginEnd = dp(8) })
        addView(word, lp(0, dp(44), 1f))
        addView(right ?: View(c), lp(dp(44), dp(44)).apply { marginStart = dp(8) })
    }
    fun capsule(s: String, color: Int) = c.text(s, 17f, color, bold = true, center = true).apply {
        gravity = Gravity.CENTER
        background = c.rounded(GLASS_TONE, 22, Color.argb(46, 255, 255, 255))
    }
    // TAKEN OUT OF A CHANNEL (iOS channelJoinBar, 3.3): «Join» in grey on the same wide glass, answering nothing -- the owner alone lets
    // a removed person back
    if (Groups.isChannel(ref) && Groups.removed(ref)) into.addView(panel(capsule(c.getString(R.string.ch_join), MT.gray), null), FrameLayout.LayoutParams(MATCH, WRAP))
    // OUT OF A GROUP, THE FIELD'S PLACE IS THE WAY OUT (iOS groupDeleteBar, stage R): «Delete and Exit» after the platform's question
    else if (Groups.isOut(ref)) into.addView(c.text(c.getString(R.string.gr_erase), 17f, SysColor.red, center = true).apply {
        setPadding(c.dp(20), c.dp(14), c.dp(20), c.dp(14))
        pressable {
            AlertDialog.Builder(c).setTitle(c.getString(R.string.gr_erase_q, Book.chat(ref)?.shown ?: ""))   // USER-DATA: the group's title
                .setPositiveButton(R.string.gr_erase) { _, _ -> Groups.erase(ref) }
                .setNegativeButton(R.string.cancel, null).show()
        }
    }, FrameLayout.LayoutParams(MATCH, WRAP))
    else if (!Groups.canWrite(ref)) {
        val mute = capsule(c.getString(if (ChatMarks.isMuted(ref)) R.string.cl_unmute else R.string.cl_mute), Color.WHITE).apply {
            pressable { ChatMarks.toggleMute(ref); fillGroupFoot(c, ref, into, onSearch) }
        }
        val search = FrameLayout(c).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(GLASS_TONE); setStroke(c.dp(1), Color.argb(46, 255, 255, 255)) }
            addView(c.icon(R.drawable.ic_search, Color.WHITE, 20), FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
            contentDescription = c.getString(R.string.search)
            pressable { onSearch() }
        }
        into.addView(panel(mute, search), FrameLayout.LayoutParams(MATCH, WRAP))
    }
    // A MEMBER WHO MAY SEND NOTHING (iOS groupMutedNote, G.5): the reference's sentence stands where the field stood
    else if (Groups.mutes(ref)) into.addView(c.text(c.getString(R.string.gn_text), 13f, MT.gray, center = true).apply {
        setPadding(c.dp(20), c.dp(12), c.dp(20), c.dp(12))
    }, FrameLayout.LayoutParams(MATCH, WRAP))
    into.visibility = if (into.childCount > 0) View.VISIBLE else View.GONE
}

/** The footer of a channel's post (its comments): the failed bubble's resend tap passes it by. */
private const val COMMENTS_TAG = "channel-comments"

/** The context the recogniser is given for a voice of this chat: one's own name, the chat's, its speakers', and the chat's words
 *  (iOS voiceHints, MontanaConversation at b2fe4814). */
private fun voiceHints(c: Context, chat: Chat): List<String> {
    val speakers = chat.msgs.mapNotNull { it.from }.distinct().take(20).map { Groups.speakerName(c, it) }
    return VoiceText.hints(listOf(Prefs.userName, chat.shown) + speakers, chat.msgs.map { it.text })
}

private fun letterBubble(c: Context, m: Msg, chat: Chat, members: List<Msg> = listOf(m), head: Boolean = true): ReplySwipe = ReplySwipe(c).apply {
    mine = m.mine
    val mine = m.mine
    // THE SPEAKER AT THE HEAD OF THEIR RUN (iOS speakerPlace, MTSpeakerHead -- the reference's group feed): once a run, in the colour
    // every phone gives them; inside a bubble of words, over a file, a voice, a round note and our own plates, nowhere over a picture
    val place = if (head) speakerPlace(c, m, members) else SPEAKER_NONE
    val who = if (place != SPEAKER_NONE) Groups.speakerLine(c, m, chat.ref) else null
    addView(c.vstack(if (mine) Gravity.END else Gravity.START) {
        if (who != null && place == SPEAKER_ABOVE) addView(c.text(who, 12f, Groups.tint(m.from ?: ""), bold = true).apply {   // USER-DATA: the speaker's name
            singleLineEllipsis(); setPadding(c.dp(8), c.dp(6), 0, c.dp(2))
        }, lp(WRAP, WRAP))
        // THE PICTURE IS THE BUBBLE (iOS mediaBubble 1534-1600 and gifBubble 1113-1160, MontanaBubble.swift at 2155): a photo, a film or a
        // moving picture fills its bubble edge to edge, clipped to the bubble's own shape; the time stands ON the picture in a dark
        // capsule; the bubble's fill shows only under a caption. Android drew the picture inside the padded bubble: a blue frame round it.
        // a media group's plate is its bubble the same way (iOS groupBubble 1431-1468): the tiles fill it, the caption of the pick under them
        val edge = (1 == members.size && edgePlate(m)) || 1 < members.size
        val edgeCap = if (edge) members.firstNotNullOfOrNull { Media.manifestOf(it)?.optString("cap")?.takeIf { c -> c.isNotEmpty() } } else null
        val onPlate = edge && (edgeCap == null || BusinessCard.lines(edgeCap) != null)
        // A STICKER OR A LETTER OF EMOJI ALONE STANDS BARE (iOS bigEmojiText branch, MontanaBubble.swift 758-776): the quote keeps a
        // small bubble of its own above it, the time stands under it in the same dark capsule as on a picture
        val bare = Stickers.bare(m)
        val darkMeta = onPlate || (bare && !edge)
        addView(c.vstack(Gravity.END) {
            background = if (Stickers.bare(m)) null else BubbleStyle.drawable(context, mine)   // a sticker stands without a bubble
            if (Groups.isKey(chat.ref) && Groups.talks(chat.ref)) minimumWidth = dp(210)   // a post over its comments' footer (iOS MontanaBubble 506-541)
            if (edge) {
                setPadding(0, 0, 0, 0)
                outlineProvider = object : android.view.ViewOutlineProvider() {
                    override fun getOutline(v: View, o: android.graphics.Outline) = o.setRoundRect(0, 0, v.width, v.height, v.dp(18).toFloat())
                }
                clipToOutline = true
            } else setPadding(dp(12), dp(7), dp(12), dp(6))
            if (who != null && place == SPEAKER_INSIDE) addView(speakerHead(c, who, m.from), lp(WRAP, WRAP).apply { gravity = Gravity.START; bottomMargin = dp(2) })   // the name widens the bubble, never cut by its words
            // A FORWARDED LETTER (iOS isForwarded): one grey line over its words, no name and no bar; a channel's post names its
            // channel on that line (iOS MontanaBubble 552-560, «Forwarded from»)
            if (isForwardQuote(m.qt)) addView(c.text(forwardedFrom(m.qt)?.let { c.getString(R.string.ld_forwarded_from, it) } ?: c.getString(R.string.ld_forwarded), 13f, BubbleStyle.time(mine)).apply { singleLineEllipsis() }, lp(WRAP, WRAP).apply { bottomMargin = dp(3) })   // USER-DATA: the channel's name
            else if (m.qt != null) {
                val whose = m.qm?.let { q -> chat.msgs.find { it.mid == q } }
                // in a group the quoted letter's speaker wears their own colour (iOS quoteTint)
                val quoteInk = if (!mine && whose != null && !whose.mine && Groups.isKey(chat.ref) && whose.from != null) Groups.tint(whose.from) else BubbleStyle.text(mine)
                addView(c.hstack {
                    if (bare) { background = BubbleStyle.drawable(context, mine); setPadding(dp(10), dp(6), dp(10), dp(6)) }
                    addView(View(c).apply { setBackgroundColor(quoteInk) }, lp(dp(2), MATCH).apply { marginEnd = dp(6) })
                    addView(c.vstack(Gravity.NO_GRAVITY) {
                        addView(c.text(if (whose?.mine == true) Prefs.userName.ifBlank { "·" } else if (Groups.isKey(chat.ref)) Groups.speakerName(c, whose?.from) else chat.shown.ifBlank { c.getString(R.string.peer) }, 13f, quoteInk, bold = true))
                        addView(c.text(m.qt ?: "", 13f, BubbleStyle.time(mine)).apply { maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END; maxWidth = dp(240) })   // USER-DATA
                    })
                }, lp(WRAP, WRAP).apply { bottomMargin = dp(4) })
            }
            val call = Calls.info(m.text) != null
            val plateFolds = (1 < members.size || m.text.startsWith(Marks.MEDIA)) && ContentFilter.plateFolds(m, members)
            val bodyAt = childCount
            if (1 < members.size) albumBody(c, members, this)   // the plate of a media group (Album.kt)
            else if (Stickers.body(c, m, this)) Unit else if (m.text.startsWith(Marks.MEDIA)) mediaBody(c, m, this, chat)
            else if (call) Calls.body(c, m, this)   // a call's row carries its moment inside, as iOS callBubble
            // A NEW BUILD'S WORD (iOS releaseBubble, MontanaBubble.swift:1006-1010): the Montana room's letter, drawn as its scroll
            else if (Release.of(m.text) != null) Release.body(c, m, this)
            // A POST ON A WALL OF THE PAIR (iOS wallCardBubble, MontanaBubble.swift:694-695 and 903-920 at 2155): the wall's glyph, «Wall
            // post» and the post's first lines; the touch opens the wall the post stands on (wallCardPlate)
            else if (WallCard.of(m.text) != null) addView(wallCardPlate(c, c as? MainActivity, chat.ref, WallCard.of(m.text)!!, mine), lp(WRAP, WRAP))
            // A GAME'S INVITATION (iOS the chess letter's bubble): the knight, the seat and the clock; Accept and Decline while it waits for me
            else if (ChessSend.letterOf(m)?.kind == ChessLetter.INVITE) addView(c.chessPlate(c as? MainActivity, chat.ref, m, ChessSend.letterOf(m)!!, mine), lp(WRAP, WRAP))
            // A COIN LETTER (iOS MTCoinLetter's bubble): our coin, the signed number, which way the coins went
            else if (CoinSend.coinOf(m) != null) addView(c.coinPlate(m, CoinSend.coinOf(m)!!, mine, c as? MainActivity, chat.ref), lp(WRAP, WRAP))
            // A SECRET SHARED FROM PASSWORDS (iOS MTSecretLetter): the key and the title; the receiver's tap saves it
            else if (SecretLetter.parse(m.text) != null) addView(c.secretPlate(c as? MainActivity, SecretLetter.parse(m.text)!!, mine), lp(WRAP, WRAP))
            // A PLACE LETTER (iOS MTPlaceLetter.parse → the map plate): the pin, the name and the spot instead of the link's words
            else if (PlaceLetter.parse(c, m.text) != null) addView(c.placePlate(PlaceLetter.parse(c, m.text)!!, mine), lp(WRAP, WRAP))
            // THE FILTER (iOS MontanaBubble 672-691): a letter of theirs with a word of the list stands folded; the tap unfolds it
            else if (ContentFilter.folded(m)) {
                // EVERY MONTANA LINK OPENS AT A TOUCH (iOS MTMessageText.swift:227-252, MTLinkedText.updateUIView, atom
                // 20c5cef6f490): the web's own finder and a Montana link alike, underlined in the bubble's own ink (iOS
                // MontanaShapes.swift:524).
                val words = c.text(linkedWords(letterWords(c, m.text)) { u -> (c as? MainActivity)?.openLink(u.toString()) }, 16f * MontanaTextSize.system, BubbleStyle.text(mine)).apply {
                    maxWidth = dp(260); setTextIsSelectable(false); visibility = View.GONE
                    movementMethod = android.text.method.LinkMovementMethod.getInstance()
                    setLinkTextColor(BubbleStyle.text(mine))
                }   // USER-DATA: the letter
                val fold = c.vstack(Gravity.NO_GRAVITY) {
                    addView(c.hstack {
                        gravity = Gravity.CENTER_VERTICAL
                        addView(c.icon(R.drawable.ic_set_eye_slash, BubbleStyle.text(mine), 16), lp(dp(16), dp(16)).apply { marginEnd = dp(6) })
                        addView(c.text(c.getString(R.string.filter_hidden), 16f, BubbleStyle.text(mine)), lp(WRAP, WRAP))
                    }, lp(WRAP, WRAP))
                    addView(c.text(c.getString(R.string.filter_tap), 12f, BubbleStyle.text(mine)).apply { alpha = 0.7f }, lp(WRAP, WRAP).apply { topMargin = dp(4) })
                    pressable { ContentFilter.open(m.mid); visibility = View.GONE; words.visibility = View.VISIBLE }
                }
                addView(fold, lp(WRAP, WRAP))
                addView(words, lp(WRAP, WRAP))
            }
            // EVERY MONTANA LINK OPENS AT A TOUCH (iOS MTMessageText.swift:227-252, MTLinkedText.updateUIView, atom
            // 20c5cef6f490): the web's own finder and a Montana link alike, underlined in the bubble's own ink (iOS
            // MontanaShapes.swift:524).
            // THE SYSTEM'S TEXT SIZE REACHES ONLY THE LETTER'S OWN WORDS (iOS montanaTextScale/letterFont, the author's
            // word 11.09): every other size in the app stays pinned (pinnedText, Ui.kt), the bubble's own text does not.
            else addView(c.text(linkedWords(letterWords(c, m.text)) { u -> (c as? MainActivity)?.openLink(u.toString()) }, 16f * MontanaTextSize.system, BubbleStyle.text(mine)).apply {
                maxWidth = dp(260); setTextIsSelectable(false)
                movementMethod = android.text.method.LinkMovementMethod.getInstance()
                setLinkTextColor(BubbleStyle.text(mine))
            }, lp(WRAP, WRAP).apply { if (who != null && place == SPEAKER_INSIDE) gravity = Gravity.START })   // USER-DATA: the letter; under a speaker's name it keeps the bubble's leading edge (iOS VStack .leading)
            // THE FILTER FOLDS A PLATE OF PICTURES TOO (iOS filterFolds, read before the plate's branch): the plate stands hidden under the
            // same fold, and the person's own tap shows it whole
            if (plateFolds) {
                val body = (bodyAt until childCount).map { getChildAt(it) }
                body.forEach { it.visibility = View.GONE }
                addView(c.vstack(Gravity.NO_GRAVITY) {
                    setPadding(dp(12), dp(7), dp(12), dp(6))
                    addView(c.hstack {
                        gravity = Gravity.CENTER_VERTICAL
                        addView(c.icon(R.drawable.ic_set_eye_slash, BubbleStyle.text(mine), 16), lp(dp(16), dp(16)).apply { marginEnd = dp(6) })
                        addView(c.text(c.getString(R.string.filter_hidden), 16f, BubbleStyle.text(mine)), lp(WRAP, WRAP))
                    }, lp(WRAP, WRAP))
                    addView(c.text(c.getString(R.string.filter_tap), 12f, BubbleStyle.text(mine)).apply { alpha = 0.7f }, lp(WRAP, WRAP).apply { topMargin = dp(4) })
                    pressable { ContentFilter.open(m.mid); visibility = View.GONE; body.forEach { it.visibility = View.VISIBLE } }
                }, bodyAt, lp(WRAP, WRAP))
            }
            // THE LINK'S CARD UNDER THE WORDS (iOS the link card in the bubble), drawn from the letter's own bytes
            LinkCard.parse(m.lp)?.let { addView(linkCardView(c, it, mine), lp(WRAP, WRAP)) }
            // A VOICE'S STAMP STANDS UNDER ITS CAPSULE (iOS voiceCapsuleBubble 982-994): the microphone with the length and the stamp,
            // each on its quiet pill (MTVoicePill: black 0.38, a white 0.18 rim), white, on the feed under the capsule
            val voiceMan = if (m.text.startsWith(Marks.MEDIA)) (m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)) else null
            val voice = 1 == members.size && voiceMan?.optString("k") == "aud"
            val note = 1 == members.size && voiceMan?.optString("k") == "vid" && voiceMan.optBoolean("r")
            val metaInk = if (voice || darkMeta) Color.WHITE else BubbleStyle.time(mine)
            fun pill(v: View) = v.apply {
                background = GradientDrawable().apply { cornerRadius = dp(100).toFloat(); setColor(Color.argb(97, 0, 0, 0)); setStroke(1, Color.argb(46, 255, 255, 255)) }
                setPadding(dp(8), dp(3), dp(8), dp(3))
            }
            // THE VOICE'S WORDS UNDER ITS CAPSULE (iOS voiceTranscript, b2fe4814 at 2315): read on this phone, between the capsule
            // and its pills, where the person opened them; the glyph that opens them stands after the stamp's pill (below)
            val voiceFile = if (voice && VoiceText.canRead(c)) m.file?.takeIf { java.io.File(it).exists() } else null
            if (voiceFile != null) addView(voiceWordsView(c, voiceFile, mine), lp(WRAP, WRAP).apply { topMargin = dp(6); if (!mine) gravity = Gravity.START })
            if (!call) addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                if (darkMeta) {
                    background = c.rounded(Color.argb(115, 0, 0, 0), 10)   // iOS black 0.45 under the time on the picture
                    setPadding(dp(7), dp(3), dp(7), dp(3))
                }
                // THE TAPE ON ITS WAY (iOS 404698df progressPill): its ring and percent stand where its length will stand, and the
                // length comes back when the board lets the letter go; under the round note the pill stands at the left, the stamp right
                if (voice) {
                    val length = pill(c.hstack {
                        gravity = Gravity.CENTER_VERTICAL
                        addView(c.icon(R.drawable.ic_mic, Color.WHITE, 10), lp(dp(10), dp(10)).apply { marginEnd = dp(4) })
                        addView(c.text(fmtDuration(voiceMan?.optDouble("du", 0.0) ?: 0.0), 11f, Color.WHITE).apply { fontFeatureSettings = "tnum" })   // USER-DATA: a duration
                    })
                    addView(TransferMark(c, m.mid, null, length, line = true), lp(WRAP, WRAP).apply { marginEnd = dp(4) })
                    addView(length, lp(WRAP, WRAP).apply { marginEnd = dp(4) })
                }
                if (note) {
                    addView(TransferMark(c, m.mid, null, line = true), lp(WRAP, WRAP))
                    addView(android.widget.Space(c), lp(0, 0, 1f).apply { width = dp(4) })
                }
                val meta = c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    // THE EYE AND ITS NUMBER BEFORE THE TIME (iOS metaLine, the reference's channel stamp): the owner's count of people
                    if (Groups.isKey(chat.ref) && Groups.isChannel(chat.ref)) {
                        addView(c.icon(R.drawable.ic_set_eye, metaInk, 11), lp(dp(11), dp(11)).apply { marginEnd = dp(2) })
                        addView(c.text(ChannelViews.short(ChannelViews.views(m, chat.ref)) + " ", 11f, metaInk).apply { fontFeatureSettings = "tnum" })   // USER-DATA: a count of people
                    }
                    if (m.edited) addView(c.text(c.getString(R.string.edited) + " ", 11f, metaInk))
                    // a signed channel's post: its signer before the time, «Name, 12:30» (iOS signature, Sign Messages)
                    val time = android.text.format.DateFormat.getTimeFormat(c).format(Date(m.at))
                    val signer = if (Groups.isKey(chat.ref)) Groups.signature(c, m, chat.ref) else null
                    if (signer != null) addView(c.text(signer, 11f, metaInk).apply { singleLineEllipsis(); maxWidth = dp(160) })   // USER-DATA: the post's signer, cut, never its time
                    addView(c.text(if (signer == null) time else ", $time", 11f, metaInk))
                    // the letter's gematria right of the time, the same number on both phones (iOS metaLine's seal, MTLetterSeal.mark)
                    LetterSeal.gematria(m.mid)?.let { g ->
                        addView(c.text(" · $g", 11f, metaInk).apply { fontFeatureSettings = "tnum" })   // USER-DATA: the letter's gematria
                    }
                    // no ticks in the bubble (iOS 15.47): the words stand under the last own letter; only «not sent» marks the corner
                    if (mine && m.state == -1) addView(c.failedMark(), lp(dp(12), dp(12)).apply { marginStart = dp(4) })
                }
                addView(if (voice) pill(meta) else meta, lp(WRAP, WRAP))
                if (voiceFile != null) addView(voiceTextGlyph(c, voiceFile) { voiceHints(c, chat) }, lp(WRAP, WRAP))
            // iOS 966: the voice's stack leans to its own side -- their pills stand at the capsule's left edge, mine at its right
            }, lp(if (note) MATCH else WRAP, WRAP).apply { if (voice) { topMargin = dp(8); if (!mine) gravity = Gravity.START } })
            if (edge) edgeLay(this, onPlate)
        }, lp(WRAP, WRAP))
        // A POST'S COMMENTS (iOS MontanaBubble 506-541, the reference's «Leave a Comment»): under the post a plate of the bubble's own
        // fill across its width -- the bubble, «Leave a Comment» or «N Comments», the chevron; the touch opens the post's comments
        if (Groups.isKey(chat.ref) && Groups.talks(chat.ref)) {
            val n = ChannelComments.count(m.mid, chat.ref)
            val ink = BubbleStyle.text(mine)
            addView(c.hstack {
                tag = COMMENTS_TAG
                gravity = Gravity.CENTER_VERTICAL
                background = BubbleStyle.drawable(context, mine)
                setPadding(dp(12), dp(8), dp(10), dp(8))
                addView(c.icon(R.drawable.ic_set_textbubble, ink, 18), lp(dp(18), dp(18)).apply { marginEnd = dp(8) })
                addView(c.text(if (n == 0) c.getString(R.string.ch_leave_comment) else c.resources.getQuantityString(R.plurals.ch_comments_n, n, n), 15f, ink, bold = true).apply { singleLineEllipsis() }, lp(WRAP, WRAP))
                addView(android.widget.Space(c), lp(0, 0, 1f))
                addView(c.icon(R.drawable.ic_chevron_right, ink, 14).apply { alpha = 0.6f }, lp(dp(14), dp(14)))
                pressable { (c as? MainActivity)?.let { act -> act.push { back -> channelCommentsPage(act, chat.ref, m, back) } } }
            }, lp(MATCH, WRAP).apply { topMargin = dp(2) })
        }
        // ONE PLATE PER ANSWER, THE FACES ON IT (iOS MontanaBubble.swift 505-555 at 2155): the same emoji from both sides is one
        // plate with two faces; the correspondent's face stands only on the answer they are named on, mine on mine; my own answer
        // is taken back by a touch where it is shown (iOS onTapReaction), theirs is not mine to remove and answers no touch.
        if (m.reactions.isNotEmpty()) addView(c.hstack {
            val group = Groups.isKey(chat.ref)
            for (e in m.reactions.distinct()) {
                val mineHere = e == m.myReact
                val theirs = !group && e == m.peerReact
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    background = c.rounded(if (mineHere) Color.rgb(77, 77, 77) else Color.rgb(56, 56, 56), 10)   // iOS white 0.30 / 0.22
                    setPadding(dp(9), dp(4), dp(9), dp(4))
                    if (theirs) addView(c.peerFace(chat.ref, chat.shown, 18), lp(dp(18), dp(18)).apply { marginEnd = dp(4) })
                    if (mineHere) addView(c.avatar(smallSelfFace(c), Prefs.userName, 18), lp(dp(18), dp(18)).apply { marginEnd = dp(4) })
                    addView(c.text(e, 16f, Color.WHITE), lp(WRAP, WRAP))   // USER-DATA: an answer
                    if (mineHere) pressable { answerLetter(chat.ref, m, e, group) }
                }, lp(WRAP, WRAP).apply { marginEnd = dp(4) })
            }
        }, lp(WRAP, WRAP).apply { topMargin = dp(2) })
    }, FrameLayout.LayoutParams(WRAP, WRAP, if (mine) Gravity.END else Gravity.START))
}

/** My own face for a small mark (an answer's plate): decoded once, small, and again only when the face file changes. */
private var smallFace: Pair<Long, android.graphics.Bitmap?>? = null
private fun smallSelfFace(c: Context): android.graphics.Bitmap? {
    val f = SelfFace.file(c)
    val stamp = if (f.exists()) f.lastModified() else 0L
    smallFace?.takeIf { it.first == stamp }?.let { return it.second }
    val b = if (stamp == 0L) null else BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = 8 })
    smallFace = stamp to b
    return b
}

/**
 * MY ONE ANSWER ON A LETTER (iOS react, MTReactions): a new one replaces my old, the same one again takes it back; the other side
 * is told what left and what came (a group's answer rides the group's own carrier, iOS react → MTGroup.signal). The letter's menu
 * and the answer's own plate under the letter both come here ([C-1]).
 */
internal fun answerLetter(ref: String, m: Msg, e: String, group: Boolean) {
    // «Send Reactions» taken from the members (iOS react → MTGroup.refusal, G.5): said, and nothing changes
    if (group) Groups.refusal(Book.ctx, ref, Marks.REACTION, letter = false)?.let { Groups.tellRefusal(it); return }
    var added = false
    val prev = m.myReact
    Book.edit(ref) { ch ->
        ch.msgs.find { it.mid == m.mid }?.let { t ->
            t.myReact?.let { old -> t.reactions.remove(old) }
            if (prev == e) t.myReact = null else { t.reactions.add(e); t.myReact = e; added = true }
            if (added) ch.noteAnswer(e, true, t) else if (ch.ansMine) ch.noteAnswer(null, true, t)
        }
    }
    fun tell(emoji: String, add: Boolean) {
        val word = Marks.REACTION + JSONObject().put("sid", "mid:" + m.mid).put("txt", m.text.take(200)).put("e", emoji).put("op", if (add) "add" else "del")
        if (group) Groups.signal(ref, word) else Post.send(ref, Marks.mintMid(), word)
    }
    if (prev != null) tell(prev, false)
    if (added) { tell(e, true); QuickReactions.note(e) }
}

/** A letter whose picture fills its bubble (iOS mediaBubble, gifBubble): a photo, a film that is not a round note, or a moving
 * picture already on the phone (before that it is a file's plate, as mediaBody draws it). A sticker stands bare instead. */
private const val SPEAKER_NONE = 0
private const val SPEAKER_ABOVE = 1
private const val SPEAKER_INSIDE = 2
/**
 * WHERE A GROUP'S SPEAKER IS NAMED (iOS MessageBubble.speakerPlace): on the first line inside a bubble of words; over a file, a voice,
 * a round note, a sticker and every plate of our own; nowhere over a picture, a video, a plate of pictures or a place.
 */
private fun speakerPlace(c: Context, m: Msg, members: List<Msg>): Int = when {
    1 < members.size || edgePlate(m) -> SPEAKER_NONE
    m.text.startsWith(Marks.MEDIA) || Stickers.bare(m) || Calls.info(m.text) != null || WallCard.of(m.text) != null
        || ChessSend.letterOf(m) != null || CoinSend.coinOf(m) != null || SecretLetter.parse(m.text) != null -> SPEAKER_ABOVE
    m.qt == null && PlaceLetter.parse(c, m.text) != null -> SPEAKER_NONE
    else -> SPEAKER_INSIDE
}
/**
 * THE SPEAKER'S LINE INSIDE A GROUP'S BUBBLE (iOS speakerHeadLine): the name semibold at fourteen seventeenths of the letter in the
 * speaker's colour, the role's word a point smaller at its right on a capsule of its own colour -- owner in violet, admin in green.
 */
private fun speakerHead(c: Context, who: String, ref: String?): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    val size = Math.floor(16.0 * MontanaTextSize.system * 14 / 17).toFloat()
    addView(c.text(who, size, Groups.tint(ref ?: "")).apply {   // USER-DATA: the speaker's name
        singleLineEllipsis(); typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
    }, lp(WRAP, WRAP))
    val role = Groups.roleOf(ref)
    if (role != 0) {
        val tone = if (role == 1) Color.rgb(0x95, 0x6a, 0xc8) else Color.rgb(0x49, 0xa3, 0x55)
        addView(c.text(c.getString(if (role == 1) R.string.gp_owner else R.string.gp_admin), size - 1, tone).apply {
            gravity = Gravity.CENTER
            setPadding(c.dp(5), 0, c.dp(5), 0)
            background = c.rounded(Color.argb(51, Color.red(tone), Color.green(tone), Color.blue(tone)), 100)
        }, lp(WRAP, c.dp(17)).apply { marginStart = c.dp(8) })
    }
}
/**
 * THE SPEAKER'S FACE AT THE FOOT OF THEIR RUN (iOS MTSpeakerFace): the person's own picture where this phone holds their pipe, else
 * their initial on the colour every phone gives them.
 */
private fun speakerFace(c: Context, ref: String, name: String): View {
    val pipe = Groups.speakerPipe(ref)
    if (pipe != null) return c.peerFace(SamePair.root(pipe), name, SPEAKER_FACE)
    return c.avatar(null, name, SPEAKER_FACE).apply { background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Groups.tint(ref)) } }
}
private const val SPEAKER_FACE = 30

private fun edgePlate(m: Msg): Boolean {
    if (!m.text.startsWith(Marks.MEDIA) || Stickers.bare(m)) return false
    val man = Media.manifestOf(m)
    val f = m.file?.let { java.io.File(it) }?.takeIf { it.exists() }
    val ext = (f?.extension ?: man?.optString("e") ?: "").lowercase()
    val byExt = when (ext) { "jpg", "jpeg", "png", "gif", "webp", "heic", "heif" -> "img"; "mp4", "mov", "m4v", "webm", "3gp" -> "vid"; else -> "doc" }
    return when (man?.optString("k")?.ifEmpty { null } ?: byExt) {
        "img" -> true
        "vid" -> man?.optBoolean("r") != true
        "doc" -> ext == "gif" && f != null
        else -> false
    }
}

/**
 * The bubble that IS its picture, laid out (iOS mediaBubble): the plate loses its own corners and its gap -- the bubble's shape clips
 * it; every other line (a quote, a caption, a failure, the time under a caption) keeps the bubble's 12 at the sides; with no caption
 * the time leaves the foot and stands on the picture's corner, 6 in from its edges.
 */
private fun edgeLay(col: LinearLayout, onPlate: Boolean) {
    val c = col.context
    val kids = (0 until col.childCount).map { col.getChildAt(it) }
    val plate = kids.firstOrNull { it.tag == MEDIA_PLATE_TAG } as? FrameLayout ?: return
    plate.clipToOutline = false
    val plateW = plate.layoutParams.width
    val time = kids.last()
    if (onPlate && time !== plate) {
        col.removeView(time)
        plate.addView(time, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.BOTTOM or Gravity.END).apply { setMargins(c.dp(6), c.dp(6), c.dp(6), c.dp(6)) })
    }
    val lines = (0 until col.childCount).map { col.getChildAt(it) }
    lines.forEachIndexed { i, v ->
        val lp = v.layoutParams as LinearLayout.LayoutParams
        if (v === plate) { lp.bottomMargin = 0; lp.topMargin = 0 }
        else {
            lp.marginStart = c.dp(12); lp.marginEnd = c.dp(12)
            lp.topMargin = if (i == 0) c.dp(7) else c.dp(4)
            if (i == lines.size - 1) lp.bottomMargin = c.dp(6)
            if (v is TextView && 0 < plateW) v.maxWidth = plateW - c.dp(24)   // a caption wraps inside the picture's own width
        }
        v.layoutParams = lp
    }
}

/** THE FIELD'S OWN VOCABULARY (iOS emojiCategories, MontanaConversation.swift 34-104): every emoji of the panel, category by
 * category, read from the panel's own list (Picker.kt) — the opened reactions and the panel speak one vocabulary ([C-1]). */
private val fieldEmojiPanel: List<String> by lazy { EMOJI_CATEGORIES.flatMap { it.second } }

/**
 * WHAT A PERSON REACHES FOR FIRST (iOS MTReactions 93-142): every answer sent is counted, and the quick row offers what a
 * person reaches for most, filled out with the common ones while he has no history yet.
 */
object QuickReactions {
    private const val KEY = "reactionUse"
    private val common = listOf("👍", "❤️", "🔥", "😂", "😮", "😢", "🎉", "🙏", "👏")
    /** THE REACTIONS A CHANNEL'S OWNER CHOOSES AMONG (iOS MTChannelReactionsPage.choice): the common ones first, then the field's
     * emoji panel, each once, at most the list's limit. */
    val channelChoice: List<String> by lazy { (common + fieldEmojiPanel).distinct().take(Groups.REACT_LIST_LIMIT) }

    /** A new answer sent is counted once (iOS note(_:) 97-102); only when it is set, never when it is taken off. */
    fun note(e: String) {
        val use = runCatching { JSONObject(Prefs.str(KEY, "{}")) }.getOrNull() ?: JSONObject()
        use.put(e, use.optInt(e, 0) + 1)
        Prefs.setStr(KEY, use.toString())
        vocabulary = emptyList()   // the nine in front are about to stand in another order (iOS note(_:) 101)
    }

    /** Every answer counted, for a copy (iOS MTReactions 94-100: «reactionUse», one map of answer to count). */
    fun counts(): Map<String, Int> {
        val use = runCatching { JSONObject(Prefs.str(KEY, "{}")) }.getOrNull() ?: return emptyMap()
        return use.keys().asSequence().associateWith { use.optInt(it, 0) }.filterValues { it > 0 }
    }
    /** A copy laid (iOS SeedScope.unionKeys 6309; reread → forgetOrder 111-112): an answer counted here keeps its count, the copy adds the others. */
    fun lay(m: Map<String, Int>) {
        val use = runCatching { JSONObject(Prefs.str(KEY, "{}")) }.getOrNull() ?: JSONObject()
        for ((e, n) in m) if (!use.has(e) && n > 0) use.put(e, n)
        Prefs.setStr(KEY, use.toString())
        vocabulary = emptyList()
    }

    /** The most used first, then the common ones — never fewer than asked for, never a repeat (iOS top(_:) 133-142). */
    fun top(n: Int): List<String> {
        val use = runCatching { JSONObject(Prefs.str(KEY, "{}")) }.getOrNull() ?: JSONObject()
        val mine = use.keys().asSequence().sortedWith(compareByDescending<String> { use.optInt(it, 0) }.thenBy { it }).toList()
        val out = mutableListOf<String>()
        for (e in mine + common) if (e !in out) { out.add(e); if (out.size == n) break }
        return out
    }

    /** HOW MANY ANSWERS THE ROW HOLDS (iOS fitCount 126-130): the glyph measured by the platform, the capsule's own padding and
     * the page's side margins; never fewer than five, never more than seven. */
    fun fitCount(c: Context, widthPx: Int): Int {
        val glyph = Math.ceil(c.text("😀", 28f).paint.measureText("😀").toDouble()).toInt()
        val room = widthPx - c.dp(14) * 2 - c.dp(8) * 2
        return (room / (glyph + c.dp(12)).toFloat()).toInt().coerceIn(5, 7)
    }

    /** THE WHOLE CHOICE AS ONE LIST, EACH NAME ONCE (iOS MTReactions.all 104-119): the nine reached for most stand first, then
     * every emoji of the field's panel — one list, so a grid built from two lists cannot hold the same name in two places. */
    private var vocabulary: List<String> = emptyList()
    val all: List<String>
        get() {
            if (vocabulary.isEmpty()) {
                val seen = HashSet<String>()
                vocabulary = (top(9) + fieldEmojiPanel).filter { seen.add(it) }
            }
            return vocabulary
        }
}

/**
 * THE LETTER'S MENU (iOS MontanaMessageMenu): the room dims, the quick reactions stand over the letter, the actions under it —
 * Reply · Copy · Edit (one's own words) · Delete, which asks «for me» or «for everyone». The correspondent's page opens the same
 * cloud with its own rows (iOS onShowInChat).
 */
fun letterMenu(act: MainActivity, ref: String, m: Msg, onReply: () -> Unit, onEdit: () -> Unit, onForward: () -> Unit, onSelect: () -> Unit, group: Boolean = false, members: List<Msg> = listOf(m),
               onShowInChat: (() -> Unit)? = null) {
    val c: Context = act
    lateinit var close: () -> Unit
    // A GROUP'S LETTER (iOS MontanaMessageMenu in a group): the deeds that tell the group ride its carrier (Groups.signal); the
    // field's deeds stand while this phone writes into it
    val writes = !group || Groups.canWrite(ref)
    // a coin letter is never edited (iOS editMessage 3352-3353, 06.10): its coins were taken once, under its words
    // A PICTURE'S OR A FILM'S CAPTION IS A PERSON'S WORDS AND IS EDITED LIKE ANY LETTER (iOS MontanaConversation.swift:2210-2213 at
    // 2155, atom 3a5fc9f43b48): on the plate's one letter that carries it (Media.captionLetter); in the chat alone, as the words are
    val canEdit = m.mine && writes && ((!Marks.isService(m.text) && CoinLetter.parse(m.text) == null) ||
        (onShowInChat == null && Media.captionLetter(members) != null))
    val actions = c.vstack(Gravity.NO_GRAVITY) { background = c.rounded(Color.argb(235, 44, 44, 46), 16, Color.argb(26, 255, 255, 255)) }
    val line = Color.argb(77, 142, 142, 147)   // iOS MTMenuDivider: the gray at three tenths
    lateinit var fillActions: () -> Unit
    // iOS MTMenuRow: the title left, the glyph right — red for a deed that cannot be undone; «keep» stays in the menu
    fun row(words: String, glyph: Int, red: Boolean = false, mirrored: Boolean = false, keep: Boolean = false, work: () -> Unit) {
        if (actions.childCount > 0) actions.addView(View(c).apply { setBackgroundColor(line) }, lp(MATCH, 1))
        actions.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(11), dp(14), dp(11))
            addView(c.text(words, 16f, if (red) SysColor.red else Color.WHITE), lp(0, WRAP, 1f))
            addView(c.icon(glyph, if (red) SysColor.red else Color.argb(204, 255, 255, 255), 20).apply { if (mirrored) scaleX = -1f }, lp(dp(20), dp(20)))
            pressable { if (!keep) close(); work() }
        }, lp())
    }
    fillActions = {
        actions.removeAllViews()
        // THE PROFILE'S MENU (iOS MessageContextOverlay with onShowInChat): the same cloud, other rows — show in chat and forward, then
        // the chat's own delete (for me alone) and select
        val profile = onShowInChat
        if (profile != null) {
            row(c.getString(R.string.gl_show_in_chat), R.drawable.ic_bar_chats) { profile() }
            if (canForward(m)) row(c.getString(R.string.ld_forward), R.drawable.ic_reply, mirrored = true) { onForward() }
        } else {
            // THE RUNG AND ITS MOMENT over the actions (iOS MontanaMessageMenu ladder): the same line as under the bubble, with the time
            // none for a channel's post (iOS ladder !isChannel, MontanaConversation 2428)
            if (m.mine && !Book.isLocal(ref) && !(group && Groups.isChannel(ref))) actions.addView(c.deliveryLine(ref, m, withMoment = true).apply { setPadding(dp(16), dp(11), dp(16), dp(11)) }, lp())
            // «N SEEN» (iOS MTSeenByRow, B.13): who read a letter of mine in a group, «Nobody Viewed» while none has; a tap opens their names under it
            val seen = if (group && m.mine) Groups.seenBy(c, m, ref) else null
            if (seen != null) {
                if (actions.childCount > 0) actions.addView(View(c).apply { setBackgroundColor(line) }, lp(MATCH, 1))
                val names = c.vstack(Gravity.NO_GRAVITY) { visibility = View.GONE }
                for (n in seen) names.addView(c.text(n, 15f, Color.argb(217, 255, 255, 255)).apply {
                    maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END; setPadding(dp(14), dp(6), dp(14), dp(6))
                }, lp())
                actions.addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(14), dp(11), dp(14), dp(11))
                    addView(c.text(if (seen.isEmpty()) c.getString(R.string.gr_seen_none) else c.getString(R.string.gr_seen_n, seen.size.toString()), 16f, Color.WHITE), lp(0, WRAP, 1f))
                    addView(c.icon(R.drawable.ic_set_eye, Color.argb(204, 255, 255, 255), 20), lp(dp(20), dp(20)))
                    if (seen.isNotEmpty()) pressable { names.visibility = if (names.visibility == View.GONE) View.VISIBLE else View.GONE }
                }, lp())
                actions.addView(names, lp())
            }
            if (writes) row(c.getString(R.string.reply), R.drawable.ic_reply) { onReply() }
            // EDIT STICKER (iOS MontanaMessageMenu 474-476, MontanaConversation 2251-2254): a letter's own card sticker, re-cut into a new one
            if (Stickers.editable(m)) row(c.getString(R.string.sticker_edit), R.drawable.ic_pencil) { Stickers.editFromLetter(act, ref, m) }
            // VIEW STICKER SET · COPY LINK (iOS MontanaMessageMenu.swift:498-503, MontanaConversation.swift:2387-2402 at 2314): a
            // sticker of mine opens my own set, a sticker of another the set its passport names; the link is that set's
            if (Stickers.viewable(m)) row(c.getString(R.string.sticker_view_set), R.drawable.ic_grid_2x2) { Stickers.setPage(act, ref, Stickers.setOf(m)) }
            if (Stickers.viewable(m)) row(c.getString(R.string.copy_link), R.drawable.ic_link) { Stickers.copyLink(c, m) }
            // COPY (iOS MontanaMessageMenu 483-485): the letter's own text, whatever it carries — not narrowed to a kind
            if (m.text.isNotEmpty()) row(c.getString(R.string.copy), R.drawable.ic_content_copy) {
                // a post's card copies the post's words, never its record (iOS MTRowLetter.words, MTRowLetter.swift:55-59 at 2155)
                c.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("", WallCard.of(m.text)?.let { WallCard.words(c, it) } ?: m.text))
            }
            if (canEdit) row(c.getString(R.string.edit), R.drawable.ic_pencil) { onEdit() }
            // PIN · FORWARD (iOS MontanaMessageMenu 487-488): the pin asks «for both / for me», the unpin is told at once — every letter
            row(c.getString(if (MsgPins.isPinned(ref, m.mid)) R.string.ld_unpin else R.string.ld_pin), R.drawable.ic_pin) { pinOrUnpin(act, ref, m) }
            if (canForward(m)) row(c.getString(R.string.ld_forward), R.drawable.ic_reply, mirrored = true) { onForward() }
        }
        // «Delete» asks in place (iOS confirmingDelete 403-414): for everyone, for me — any bubble, mine or theirs, the mid is the same
        // on both sides — and «Cancel» goes back to the deeds. A coin letter of mine on its way is offered no deletion (iOS canDelete:
        // MTCoinSend.travels, MontanaConversation 2293): it keeps its coins and its row until its road ends
        if (members.none { CoinSend.travels(it) }) row(c.getString(R.string.delete), R.drawable.ic_delete, red = true, keep = true) {
            actions.removeAllViews()
            actions.addView(c.text(c.getString(R.string.delete_message_q), 13f, MT.gray, center = true).apply { setPadding(dp(16), dp(10), dp(16), dp(10)) }, lp())
            // in a group a speaker takes away their own letter for everyone (iOS canDeleteForEveryone: chat.isGroup ? m.isMine)
            // a plate of a media group goes whole (iOS rowLetters: a group is one bubble)
            val mids = members.map { it.mid }.toSet()
            // the group's owner and the administrators it named take another's letter away too (iOS moderates, stage R.6)
            if (profile == null && !Book.isLocal(ref) && (!group || m.mine || Groups.moderates(ref))) row(c.getString(R.string.delete_for_everyone), R.drawable.ic_delete, red = true) {
                Book.drop(ref, mids)
                for (x in mids) if (group) Groups.signal(ref, Marks.DELETE + "mid:" + x) else Post.send(ref, Marks.mintMid(), Marks.DELETE + "mid:" + x)
            }
            row(c.getString(R.string.delete_for_me), R.drawable.ic_delete, red = true) { Book.drop(ref, mids) }
            row(c.getString(R.string.cancel), R.drawable.ic_close, keep = true) { fillActions() }
        }
        // «Report» on their letter (iOS 499-502): the report of its sender, in a group's chat too — iOS carries no such guard
        if (profile == null && !m.mine) row(c.getString(R.string.pi_report), R.drawable.ic_report, red = true) {
            val name = Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
            act.push { cl -> reportPage(act, ref, name, onClose = cl) }
        }
        // «SELECT» stands apart at the foot (iOS 503-504: after a wider gap)
        actions.addView(View(c).apply { setBackgroundColor(line) }, lp(MATCH, c.dp(6)))
        val before = actions.childCount
        row(c.getString(R.string.ld_select), R.drawable.ic_set_check_circle) { onSelect() }
        if (actions.childCount - before == 2) actions.removeViewAt(before)   // the row's own hairline under the wide gap goes
    }
    fillActions()
    // THE QUICK REACTIONS FIT THE WIDTH AND LEARN FROM USE (iOS MTReactions 93-142, 239-262): five to seven answers — what this
    // person reaches for most stand first, filled out with the common ones — never a fixed nine on a narrow screen.
    fun react(e: String) { close(); answerLetter(ref, m, e, group) }
    // A CHANNEL THAT TAKES SOME REACTIONS (iOS reactionsOnly, «Some Reactions»): the row and the whole choice offer its list alone;
    // one whose owner turned them off (iOS reactionsAllowed, «Allow Reactions») stands no row at all
    val only = if (group) Groups.reactionList(ref) else null
    val reactsHere = !group || Groups.reactionsOn(ref)
    // THE WHOLE CHOICE AS A GRID (iOS cloud's reactionsOpen 355-374): the nine reached for most, then every emoji of the
    // field's panel, each name once (QuickReactions.all) — nine to a row, a choice here reacting exactly as a quick one does
    val grid = ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        visibility = View.GONE
        background = c.rounded(Color.argb(235, 44, 44, 46), 20, Color.argb(26, 255, 255, 255))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(10), dp(8), dp(10), dp(8))
            val rows = (only ?: QuickReactions.all).chunked(9)
            for ((i, row) in rows.withIndex()) {
                if (i > 0) gap(6)
                addView(c.hstack {
                    for (e in row) addView(c.text(e, 28f, center = true).apply { pressable { react(e) } }, lp(0, WRAP, 1f))
                    repeat(9 - row.size) { addView(View(c), lp(0, WRAP, 1f)) }
                }, lp(MATCH, WRAP))
            }
        })
    }
    lateinit var reactions: HorizontalScrollView
    reactions = HorizontalScrollView(c).apply {
        isHorizontalScrollBarEnabled = false
        background = c.rounded(Color.argb(235, 44, 44, 46), 24)
        addView(c.hstack {
            setPadding(dp(8), dp(4), dp(8), dp(4))
            val count = QuickReactions.fitCount(c, c.resources.displayMetrics.widthPixels)
            for (e in only?.take(count) ?: QuickReactions.top(count)) addView(c.text(e, 28f).apply {
                setPadding(dp(6), dp(4), dp(6), dp(4))
                pressable { react(e) }
            })
            // THE CHEVRON OPENS EVERY REACTION (iOS MontanaMessageMenu.reactionsRow 244-251): the row's last key, a 17-point
            // glyph wearing the 44-point target, turns the quick row into the grid above
            if ((only?.size ?: Int.MAX_VALUE) > count) addView(FrameLayout(c).apply {
                addView(c.icon(R.drawable.ic_chevron_down, Color.argb(191, 255, 255, 255), 17), FrameLayout.LayoutParams(dp(17), dp(17), Gravity.CENTER))
                contentDescription = c.getString(R.string.reactions_all)
                pressable { reactions.visibility = View.GONE; grid.visibility = View.VISIBLE }
            }, lp(dp(44), dp(44)))
        })
    }
    val chat = Book.chat(ref)
    val copy = if (chat != null) letterBubble(c, m, chat, members) else View(c)
    val menuColumn = c.vstack(if (m.mine) Gravity.END else Gravity.START) {
        setPadding(dp(14), 0, dp(14), 0)
        if ((!group || !Groups.isOut(ref)) && reactsHere) { addView(reactions, lp(WRAP, WRAP)); addView(grid, lp(MATCH, dp(220))); gap(8) }
        addView(copy, lp())
        gap(8)
        addView(actions, lp(dp(250), WRAP))
    }
    // A LETTER TALLER THAN THE SCREEN OPENS ON ITS BOTTOM (iOS the ScrollViewReader over the menu's cloud,
    // MontanaMessageMenu.swift:298-316 at 2155, the author's word 22.09): the actions are what the hold asked
    // for, so the cloud comes to rest with its end in view at once, no transition; a short letter keeps the
    // centred place fillViewport already gave it.
    val scroller = ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        isFillViewport = true
        addView(FrameLayout(c).apply { addView(menuColumn, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.CENTER)) }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
    val page = FrameLayout(c).apply {
        setBackgroundColor(Color.argb(150, 0, 0, 0))
        isClickable = true
        pressable { close() }
        addView(scroller, FrameLayout.LayoutParams(MATCH, MATCH))
    }
    close = act.overlay(page)
    scroller.post { if (menuColumn.height > scroller.height) scroller.scrollTo(0, menuColumn.height - scroller.height) }
}


/** THE MEDIA PLATE'S OWN TAG (iOS .mtMediaMiddle): the selection circle beside a letter finds this view to stand level
 *  with it, not with the whole bubble (item 21). */
internal const val MEDIA_PLATE_TAG = "media_plate"

/** How far a tagged view stands below `ancestor`, summing every parent's own top (iOS alignmentGuide, carried up the stacks). */
private fun mediaPlateOffset(v: View, ancestor: View): Int {
    var y = 0
    var cur: View = v
    while (cur !== ancestor) {
        y += cur.top
        cur = cur.parent as? View ?: return y
    }
    return y
}

/**
 * A MEDIA LETTER IN ITS BUBBLE (iOS MessageBubble media): the picture itself, a film's first frame under the play mark, or
 * a file's name and size; the small face that rode the manifest stands while the file is on its way; the caption under it.
 * A press opens it whole: a picture or a film in the app, a file in the system's viewer.
 */
private fun mediaBody(c: Context, m: Msg, into: LinearLayout, chat: Chat? = null) {
    val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
    val f = m.file?.let { java.io.File(it) }?.takeIf { it.exists() }
    val byExt = when (f?.extension?.lowercase()) { "jpg", "jpeg", "png", "gif", "webp", "heic", "heif" -> "img"; "mp4", "mov", "m4v", "webm", "3gp" -> "vid"; else -> "doc" }
    val kind = man?.optString("k")?.ifEmpty { null } ?: byExt
    val tint = BubbleStyle.text(m.mine)
    // A MOVING PICTURE IS A GIF, NOT A STILL PICTURE (iOS MontanaGif.isGif, 23.09): the file's own extension says so; one not
    // yet on the phone falls back to the waiting plate below, as any other picture does. A GIF LEAVES AN IPHONE AS A DOCUMENT
    // (iOS sendGifFile, kind "doc", MontanaConversation.swift 3807-3820 at 2155): the extension finds it under either kind.
    val isGif = f?.extension?.lowercase() == "gif" && (kind == "img" || kind == "doc")
    // A MUSIC FILE IS HEARD, NOT OPENED (iOS audioBubble voice=false): the voice's bubble with the track's name (trackBody)
    if (man != null && isTrackLetter(m, man)) { trackBody(c, m, man, into, chat); return }
    if (kind == "aud") {
        val wv = man?.optString("wv")?.takeIf { it.isNotEmpty() }?.let { runCatching { android.util.Base64.decode(it, android.util.Base64.DEFAULT) }.getOrNull() }
        voiceBody(c, m, man?.optDouble("du", 0.0) ?: 0.0, into, wv?.let { b -> FloatArray(b.size) { (b[it].toInt() and 0xFF) / 255f } }, chat)
        return
    }
    if (kind == "vid" && man?.optBoolean("r") == true) { noteBody(c, m, f, man, into, chat); return }
    var capRoom = c.dp(240)
    if (isGif && f != null) {
        capRoom = gifBody(c, m, f, into)
    } else if (kind == "img" || kind == "vid") {
        // the full picture when it is kept, else the manifest's small one of the same shape while the full one is read behind
        // (BubblePicture); with neither, nothing to size the plate by: it is read here, as before
        val full = f?.let { BubblePicture.kept(it, kind, 800) }
        val pic = full?.pic ?: Media.thumbOf(man) ?: f?.let { Media.preview(c, it, kind, 800) }
        var blurView: ImageView? = null
        var picView: ImageView? = null
        var spinner: View? = null
        // ONE PLATE FOR A PICTURE AND A VIDEO (iOS mediaBubble 1526-1574, the author's word 15.09): as wide as the widest of its contents —
        // the picture fitted, or the caption's own bubble — never the picture alone; a picture narrower than the plate keeps its fitted
        // size in the middle and the sides are a mirrored blur of the picture itself. A card's words are not drawn under it.
        val fit = mediaBox(c, pic?.width ?: 4, pic?.height ?: 3)
        val words = man?.optString("cap")?.takeIf { it.isNotEmpty() && BusinessCard.lines(it) == null }
        val boxW = minOf(c.dp(PLATE_CEILING), maxOf(fit.first, words?.let { captionWidth(c, it, c.text(it, 16f, tint).paint) } ?: 0))
        val narrow = pic != null && fit.first < boxW - 1
        capRoom = boxW
        into.addView(FrameLayout(c).apply {
            tag = MEDIA_PLATE_TAG   // THE MEDIA'S OWN MIDDLE (iOS .mtMediaMiddle, item 21): the selection circle beside this letter stands level with this plate, not with the caption or the reactions under it
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(v: View, o: android.graphics.Outline) = o.setRoundRect(0, 0, v.width, v.height, v.dp(12).toFloat())
            }
            clipToOutline = true
            if (pic == null) setBackgroundColor(Color.rgb(51, 51, 51))   // iOS Color(white: 0.2): a picture still on its way
            if (narrow && pic != null) addView(ImageView(c).apply {
                blurView = this
                scaleType = ImageView.ScaleType.CENTER_CROP
                setImageBitmap(full?.blur ?: WallPlacer.mirrorBlur(pic)); setColorFilter(Color.argb(56, 0, 0, 0))   // iOS .overlay(black 0.22)
            }, FrameLayout.LayoutParams(MATCH, MATCH))
            if (pic != null) addView(ImageView(c).apply {
                picView = this
                scaleType = if (narrow) ImageView.ScaleType.FIT_CENTER else ImageView.ScaleType.CENTER_CROP
                setImageBitmap(pic)
            }, FrameLayout.LayoutParams(if (narrow) fit.first else MATCH, MATCH, Gravity.CENTER))
            if (full == null && f != null && pic != null) BubblePicture.load(c, f, kind, 800) { s ->
                picView?.setImageBitmap(s.pic)
                blurView?.setImageBitmap(s.blur)
            }
            // automatic download off: the attachment waits for a tap (iOS queuePendingMedia), the platform's arrow down on it
            if (f == null && Media.waiting(c, m)) addView(c.icon(R.drawable.ic_arrow_circle_down, Color.WHITE).apply {
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(140, 0, 0, 0)) }
                setPadding(c.dp(10), c.dp(10), c.dp(10), c.dp(10))
            }, FrameLayout.LayoutParams(c.dp(52), c.dp(52), Gravity.CENTER))
            else if (f == null) addView(android.widget.ProgressBar(c).also { spinner = it }, FrameLayout.LayoutParams(c.dp(36), c.dp(36), Gravity.CENTER))
            else if (kind == "vid") addView(c.icon(R.drawable.ic_play_fill, Color.WHITE).apply {
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(140, 0, 0, 0)) }
                setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12))
            }, FrameLayout.LayoutParams(c.dp(52), c.dp(52), Gravity.CENTER))
            // ONE INDICATOR ON THE PLATE (iOS mediaProgressOverlay, MontanaBubble.swift:341-356 at 2155): the pill top-left over the dim
            addView(TransferMark(c, m.mid, null, spinner), FrameLayout.LayoutParams(MATCH, MATCH))
            // a tap on a riding letter is harmless (iOS primaryTap: «the letter keeps riding»)
            if (f != null) setOnClickListener { if (!Transfers.riding(m.mid)) (c as? MainActivity)?.let { a -> openMedia(a, f, kind) } }
            // A FILM PLAYS FROM ITS FIRST PIECES (iOS onTapVideo, 25.09): the player opens on its loader at once; no manifest -- the download
            else if (kind == "vid") setOnClickListener { if ((c as? MainActivity)?.let { a -> Streams.play(a, m) } != true && Media.waiting(c, m)) Media.tapped(c, m) }
            else if (Media.waiting(c, m)) setOnClickListener { Media.tapped(c, m) }
        }, LinearLayout.LayoutParams(boxW, fit.second).apply { bottomMargin = c.dp(4) })
    } else {
        val name = man?.optString("n")?.ifEmpty { null } ?: ("file." + (man?.optString("e") ?: ""))
        val size = man?.optLong("sz") ?: 0L
        into.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            addView(FrameLayout(c).apply {
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(70, 255, 255, 255)) }
                if (f == null && Media.waiting(c, m)) addView(c.icon(R.drawable.ic_arrow_circle_down, tint), FrameLayout.LayoutParams(c.dp(24), c.dp(24), Gravity.CENTER))
                else if (f == null) addView(android.widget.ProgressBar(c), FrameLayout.LayoutParams(c.dp(26), c.dp(26), Gravity.CENTER))
                else addView(c.icon(R.drawable.ic_set_doc, tint), FrameLayout.LayoutParams(c.dp(22), c.dp(22), Gravity.CENTER))
            }, lp(c.dp(44), c.dp(44)).apply { marginEnd = c.dp(10) })
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(name, 15f, tint, bold = true).apply { maxWidth = c.dp(190); singleLineEllipsis() })   // USER-DATA: the file's name
                addView(c.text(android.text.format.Formatter.formatShortFileSize(c, size), 13f, BubbleStyle.time(m.mine)))
            })
            if (f != null) setOnClickListener { (c as? MainActivity)?.let { a -> openMedia(a, f, kind) } }
            else if (Media.waiting(c, m)) setOnClickListener { Media.tapped(c, m) }
        }, LinearLayout.LayoutParams(WRAP, WRAP).apply { bottomMargin = c.dp(4) })
    }
    if (m.state == -1) into.addView(c.text(c.getString(R.string.media_failed), 12f, SysColor.red))
    val cap = man?.optString("cap")?.takeIf { it.isNotEmpty() }
    // A CARD'S PHOTO (iOS: a build that knows the mark draws the photo alone, and offers its words to the contacts — MTCardContactBadge)
    val card = cap?.let { BusinessCard.lines(it) }
    if (card != null && !m.mine) into.addView(c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        addView(FrameLayout(c).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(115, 0, 0, 0)) }
            addView(c.icon(R.drawable.ic_person_add, Color.WHITE, 18), FrameLayout.LayoutParams(c.dp(18), c.dp(18), Gravity.CENTER))
        }, lp(c.dp(40), c.dp(40)).apply { marginEnd = c.dp(8) })
        addView(c.text(c.getString(R.string.bc_add_contacts), 15f, tint), lp(WRAP, WRAP))
        pressable { (c as? MainActivity)?.let { a -> cardToContacts(a, card) } }
    }, lp(WRAP, WRAP))
    else if (card == null) cap?.let { into.addView(c.text(it, 16f, tint).apply { maxWidth = capRoom }) }   // USER-DATA: the caption
}

/**
 * A CORRESPONDENT'S PICTURE OR FILM, WHOLE ON DISK (iOS the guard before MTSaveMediaBadge, MontanaBubble.swift 865-880): not a
 * round note (it plays, it does not save) and not a business card's photo (its own badge offers the contacts instead).
 */
private fun saveMediaFile(m: Msg): Pair<java.io.File, Boolean>? {
    if (m.mine || !m.text.startsWith(Marks.MEDIA)) return null
    val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
    val f = m.file?.let { java.io.File(it) }?.takeIf { it.exists() } ?: return null
    val byExt = when (f.extension.lowercase()) { "jpg", "jpeg", "png", "gif", "webp", "heic", "heif" -> "img"; "mp4", "mov", "m4v", "webm", "3gp" -> "vid"; else -> "doc" }
    val kind = man?.optString("k")?.ifEmpty { null } ?: byExt
    if (kind != "img" && kind != "vid") return null
    if (kind == "vid" && man?.optBoolean("r") == true) return null
    val cap = man?.optString("cap")?.takeIf { it.isNotEmpty() }
    if (cap != null && BusinessCard.lines(cap) != null) return null
    return f to (kind == "vid")
}

/** A PLATE'S FILES (iOS saveBesideBadge, MontanaBubble.swift 871-878): every letter of it a picture or film on disk, or no circle. */
private fun saveMediaFiles(row: List<Msg>): List<Pair<java.io.File, Boolean>>? {
    val files = row.map { saveMediaFile(it) ?: return null }
    return files.takeIf { it.isNotEmpty() }
}

/**
 * SAVED TO THE LIBRARY, the notebook and the one road (iOS MontanaSavedToPhotos, MontanaMedia.swift:1275+, the author's word
 * 11.09): the badge asks here, saves here, and a saved name shows no badge again.
 */
private object SavedMedia {
    private fun key(name: String) = "savedToPhotos.$name"
    fun has(name: String): Boolean = Prefs.bool(key(name), false)
    fun save(c: Context, f: java.io.File, video: Boolean): Boolean {
        val values = android.content.ContentValues().apply {
            put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, f.name)
            put(android.provider.MediaStore.MediaColumns.MIME_TYPE, android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(f.extension.lowercase())
                ?: if (video) "video/mp4" else "image/jpeg")
            if (android.os.Build.VERSION.SDK_INT >= 29) put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, if (video) "Movies/Montana" else "Pictures/Montana")
        }
        val collection = if (video) android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI else android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val uri = runCatching { c.contentResolver.insert(collection, values) }.getOrNull() ?: return false
        val ok = runCatching { c.contentResolver.openOutputStream(uri)?.use { out -> f.inputStream().use { it.copyTo(out) } }; true }.getOrDefault(false)
        if (ok) Prefs.setBool(key(f.name), true)
        return ok
    }
}

/**
 * THE CIRCLE ITSELF (iOS MTSaveMediaBadge, MontanaBubble.swift:1891-1923): the tray arrow; a tap saves every file the circle
 * carries -- one picture, or all of a plate's -- and a picture saved before is not saved twice; then the green diskette stays.
 * Files all saved before show the diskette at once (iOS MontanaSavedToPhotos); a failed save offers the arrow again.
 */
/** The round of glass beside a channel's post (iOS MTChannelShareRound): the forward arrow on 30 across, the finger's 44 around it. */
private fun shareRound(c: Context, onTap: () -> Unit): View = FrameLayout(c).apply {
    addView(FrameLayout(c).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(GLASS_TONE); setStroke(c.dp(1), Color.argb(46, 255, 255, 255)) }
        addView(c.icon(R.drawable.ic_reply, Color.WHITE, 15).apply { scaleX = -1f }, FrameLayout.LayoutParams(c.dp(15), c.dp(15), Gravity.CENTER))
    }, FrameLayout.LayoutParams(c.dp(30), c.dp(30), Gravity.CENTER))
    contentDescription = c.getString(R.string.share)
    pressable { onTap() }
}

private fun saveMediaBadge(act: MainActivity, files: List<Pair<java.io.File, Boolean>>): View {
    val c: Context = act
    val circle = FrameLayout(c).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(115, 0, 0, 0)) }
    }
    var phase = if (files.all { SavedMedia.has(it.first.name) }) 2 else 0   // 0 offered, 1 saving, 2 saved
    fun draw() {
        circle.removeAllViews()
        when (phase) {
            1 -> circle.addView(android.widget.ProgressBar(c).apply { indeterminateTintList = android.content.res.ColorStateList.valueOf(Color.WHITE) },
                FrameLayout.LayoutParams(c.dp(18), c.dp(18), Gravity.CENTER))
            2 -> circle.addView(FloppyGlyph(c), FrameLayout.LayoutParams(c.dp(18), c.dp(18), Gravity.CENTER))
            else -> circle.addView(c.icon(R.drawable.ic_save_media, Color.WHITE, 17), FrameLayout.LayoutParams(c.dp(17), c.dp(17), Gravity.CENTER))
        }
    }
    draw()
    circle.setOnClickListener {
        if (phase != 0) return@setOnClickListener
        phase = 1; draw()
        act.background {
            var ok = true
            for ((f, video) in files) if (!SavedMedia.has(f.name) && !SavedMedia.save(c, f, video)) ok = false
            act.onMain { phase = if (ok) 2 else 0; draw() }
        }
    }
    return circle
}

/**
 * THE DISKETTE, the sign of «saved» (iOS MTFloppyGlyph, MontanaBubble.swift:1925-1952): the body with the cut corner in the
 * ladder's green, the shutter on top and the label below in black at 0.55.
 */
private class FloppyGlyph(c: Context) : View(c) {
    private val body = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = MT.green }
    private val ink = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(140, 0, 0, 0) }
    private val path = android.graphics.Path()
    override fun onDraw(canvas: android.graphics.Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        path.reset()
        path.moveTo(0f, 0f); path.lineTo(w * 0.82f, 0f); path.lineTo(w, h * 0.18f); path.lineTo(w, h); path.lineTo(0f, h); path.close()
        canvas.drawPath(path, body)
        canvas.drawRect((w - w * 0.50f) / 2f, 0f, (w + w * 0.50f) / 2f, h * 0.30f, ink)
        canvas.drawRect((w - w * 0.64f) / 2f, h * 0.62f, (w + w * 0.64f) / 2f, h * 0.90f, ink)
    }
}

private const val PLATE_CEILING = 300   // iOS MessageBubble.plateCeiling, points

/** THE PICTURE'S BOX (iOS mediaBox 1390-1397): the long side at the plate's ceiling, the short one never under 130 (in
 *  proportion to a smaller ceiling, iOS MessageBubble.mediaBox 23.09, so a moving picture keeps the photo's own shape rules). */
private fun mediaBox(c: Context, w0: Int, h0: Int, ceiling: Int = PLATE_CEILING): Pair<Int, Int> {
    val w = maxOf(w0, 1).toFloat()
    val h = maxOf(h0, 1).toFloat()
    val long = ceiling.toFloat()
    val minShort = maxOf(1f, 130f * ceiling / PLATE_CEILING)
    return if (h <= w) c.dp(ceiling) to c.dp(Math.round(maxOf(minShort, long * h / w)))
    else c.dp(Math.round(maxOf(minShort, long * w / h))) to c.dp(ceiling)
}

private var gifCeilingCache = -1

/** THE MOVING PICTURE'S CEILING IS THE DEVICE'S, NOT THE WINDOW'S (iOS MessageBubble.gifCeiling, 23.09): 0.6 of the device's
 *  short side, read once for the run so a turn never changes the plate's shape, and never above the plate's own ceiling. */
private fun gifCeilingDp(c: Context): Int {
    if (gifCeilingCache < 0) {
        val dm = c.resources.displayMetrics
        val short = minOf(dm.widthPixels, dm.heightPixels) / dm.density
        gifCeilingCache = minOf(PLATE_CEILING, Math.round(short * 0.6f))
    }
    return gifCeilingCache
}

/**
 * THE PLAY OF A GIF HAS ONE OWNER, BY ITS FILE NAME (iOS MTGifPlay, MontanaGif.swift 47-127 at 2155, the author's word 23.09:
 * «make them play their cycle three times when sent, and then only on a tap -- three cycles -- and a tap at any moment stops
 * them»). The feed rebuilds its bubbles on every receipt, arrival and scroll; the play lives here, not in the bubble, so nothing
 * that rebuilds a bubble resets it. iOS counts frames; the platform's seeking player (Movie) seeks by time, so this book counts
 * the same thing in milliseconds: what is left to play (three cycles = three times the file's duration) and where the file
 * stands. A first showing plays its three cycles once in the file's life (the mark survives a relaunch, 3000 files, iOS ranCap);
 * after that only a tap plays them, from where it stands; a tap on a playing one stops it there. Three cycles end where they
 * began: a natural end rests on the first frame (iOS 23.09, «they stop crookedly»).
 */
internal object GifPlay {
    const val CYCLES = 3
    private const val KEY = "gifFirstRun"
    private const val CAP = 3000
    private var ran: MutableList<String>? = null
    private val left = HashMap<String, Long>()       // milliseconds still to play, by file
    private val standing = HashMap<String, Long>()   // where each stands in its own loop
    @Synchronized private fun load(): MutableList<String> =
        ran ?: Prefs.str(KEY, "").split(",").filter { it.isNotEmpty() }.toMutableList().also { ran = it }
    @Synchronized private fun mark(key: String) {
        val list = load()
        if (list.contains(key)) return
        list.add(key)
        while (list.size > CAP) list.removeAt(0)
        Prefs.setStr(KEY, list.joinToString(","))
    }

    /** What is left to play; a file never shown before is handed its first three cycles (and marked: iOS shown(_:at:)). */
    @Synchronized fun left(key: String, duration: Long): Long {
        left[key]?.let { return it }
        if (load().contains(key)) { left[key] = 0; return 0 }
        val n = CYCLES * maxOf(1L, duration)
        left[key] = n
        mark(key)
        return n
    }
    @Synchronized fun standingAt(key: String): Long = standing[key] ?: 0L
    /** Time went by while it played: it stands further on and has less to play; zero rests it on its first frame. */
    @Synchronized fun played(key: String, dt: Long, duration: Long): Long {
        val l = maxOf(0L, (left[key] ?: 0L) - dt)
        left[key] = l
        standing[key] = if (l == 0L) 0L else ((standing[key] ?: 0L) + dt) % maxOf(1L, duration)
        return l
    }
    /** The finger: a playing file stops where it stands; a standing one plays three cycles from there. True -- it plays now. */
    @Synchronized fun toggle(key: String, duration: Long): Boolean {
        val playing = (left[key] ?: 0L) > 0L
        left[key] = if (playing) 0L else CYCLES * maxOf(1L, duration)
        mark(key)
        return !playing
    }
    /** The file's picture was replaced by its full one (iOS MTGifPlay.renew): it plays its own three cycles again. */
    @Synchronized fun renew(file: String) {
        left.remove(file); standing.remove(file)
        val list = load()
        if (list.remove(file)) Prefs.setStr(KEY, list.joinToString(","))
    }
}

/** The players of the files the feed shows, kept by file and size (new bytes under one name are read anew): a rebuilt bubble
 * does not read its file again. A dozen at most, the oldest let go. */
@Suppress("DEPRECATION")
private object GifMovies {
    private val kept = object : LinkedHashMap<String, android.graphics.Movie>(16, 0.75f, true) {
        override fun removeEldestEntry(e: MutableMap.MutableEntry<String, android.graphics.Movie>?) = size > 12
    }
    @Synchronized fun of(f: java.io.File): android.graphics.Movie? {
        val k = f.path + ":" + f.length()
        kept[k]?.let { return it }
        val m = runCatching { android.graphics.Movie.decodeFile(f.path) }.getOrNull()?.takeIf { it.width() > 0 && it.height() > 0 } ?: return null
        kept[k] = m
        return m
    }
}

/**
 * A LETTER'S MOVING PICTURE (iOS MTGifView/MTGifPlayer, MontanaGif.swift 138-253 at 2155): the platform's own seeking player
 * (android.graphics.Movie) draws the file at the moment the book says, one frame at a time with the screen's own clock; it plays
 * while it is on the screen and while the book has time left for it, and stands still otherwise. THE TOUCH IS THE PLATE'S OWN:
 * this view asks nothing of the finger (iOS isUserInteractionEnabled = false). A file the player cannot read stands as its
 * first frame.
 */
@Suppress("DEPRECATION")
private class GifView(c: Context, private val f: java.io.File) : View(c) {
    private val key = f.name
    private val movie: android.graphics.Movie? = GifMovies.of(f)
    private val still: android.graphics.Bitmap? = if (movie == null) Media.preview(c, f, "img") else null
    private val duration: Long = maxOf(1, movie?.duration() ?: 0).toLong()
    private var last = 0L
    private var ticking = false

    private val tick = object : Runnable {
        override fun run() {
            if (!ticking) return
            val now = android.os.SystemClock.uptimeMillis()
            val dt = if (last == 0L) 0L else now - last
            last = now
            if (GifPlay.played(key, dt, duration) == 0L) { ticking = false; last = 0L }
            invalidate()
            if (ticking) postOnAnimation(this)
        }
    }

    /** Asks the book and plays while it has time left; called on every showing and every tap. */
    fun wake() {
        if (movie == null || !isAttachedToWindow) return
        if (GifPlay.left(key, duration) > 0L && !ticking) { ticking = true; last = 0L; postOnAnimation(tick) }
        invalidate()
    }
    /** The finger (iOS MTGifPlay.toggle): playing stops where it stands, standing plays three cycles from there. */
    fun toggle() {
        if (movie == null) return
        if (!GifPlay.toggle(key, duration)) { ticking = false; last = 0L; invalidate() } else wake()
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); wake() }
    override fun onDetachedFromWindow() { ticking = false; last = 0L; removeCallbacks(tick); super.onDetachedFromWindow() }

    override fun onDraw(canvas: android.graphics.Canvas) {
        val w = movie?.width() ?: still?.width ?: return
        val h = movie?.height() ?: still?.height ?: return
        val k = minOf(width.toFloat() / w, height.toFloat() / h)   // fit, as iOS .resizeAspect
        canvas.save()
        canvas.translate((width - w * k) / 2f, (height - h * k) / 2f)
        canvas.scale(k, k)
        if (movie != null) { movie.setTime((GifPlay.standingAt(key) % duration).toInt()); movie.draw(canvas, 0f, 0f) }
        else still?.let { canvas.drawBitmap(it, 0f, 0f, null) }
        canvas.restore()
    }
}

private fun gifBody(c: Context, m: Msg, f: java.io.File, into: LinearLayout): Int {
    val shape = runCatching {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.path, o)
        if (0 < o.outWidth && 0 < o.outHeight) o.outWidth to o.outHeight else null
    }.getOrNull()
    // A STICKER OF THE HOUSE IS A STICKER, NOT A PICTURE IN A BUBBLE (iOS gifBubble bare, MontanaBubble.swift 1119-1123 at 2155):
    // no fill, no rim, the one size every sticker of ours wears (MTStickerLook)
    val bare = Stickers.house(m)
    val fit = if (bare) Stickers.box(c, shape?.first ?: 1, shape?.second ?: 1) else mediaBox(c, shape?.first ?: 4, shape?.second ?: 3, gifCeilingDp(c))
    into.addView(FrameLayout(c).apply {
        tag = MEDIA_PLATE_TAG
        if (!bare) outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(v: View, o: android.graphics.Outline) = o.setRoundRect(0, 0, v.width, v.height, v.dp(12).toFloat())
        }
        clipToOutline = !bare
        val gif = GifView(c, f)
        addView(gif, FrameLayout.LayoutParams(MATCH, MATCH))
        setOnClickListener { gif.toggle() }
    }, LinearLayout.LayoutParams(fit.first, fit.second).apply { bottomMargin = c.dp(4) })
    return fit.first
}

/** The caption's own bubble width (iOS captionNaturalWidth 1418-1427): the words wrapped inside the ceiling, plus their padding. */
private fun captionWidth(c: Context, words: String, paint: android.text.TextPaint): Int {
    val l = android.text.StaticLayout.Builder.obtain(words, 0, words.length, paint, c.dp(PLATE_CEILING - 20)).build()
    var w = 0f
    for (i in 0 until l.lineCount) w = maxOf(w, l.getLineWidth(i))
    return Math.ceil(w.toDouble()).toInt() + c.dp(20)
}

/** THE FILE WHOLE: a picture on black, a film in the platform's own player; any other file to the system's viewer. */
internal fun openMedia(act: MainActivity, f: java.io.File, kind: String) {
    val c: Context = act
    if (kind == "doc") { openDocument(act, f); return }   // a document opens in its own page (iOS DocPreview, DocView.kt)
    if (kind != "img" && kind != "vid") {
        val view = Intent(Intent.ACTION_VIEW).setDataAndType(Media.uri(c, f), c.contentResolver.getType(Media.uri(c, f)) ?: "*/*")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        runCatching { act.startActivity(Intent.createChooser(view, null)) }
        return
    }
    // A PICTURE OPENS AMONG THE CONVERSATION'S PICTURES (iOS PhotoPresenter): pages, pinch, a pull down to close (Viewer.kt)
    if (kind == "img") { openPictures(act, f); return }
    // A FILM OPENS IN ITS OWN PLAYER THAT FOLDS INTO A WINDOW OVER THE CHAT (iOS VideoPresenter, picture in picture): FilmActivity
    if (kind == "vid") { FilmActivity.open(act, f); return }
    lateinit var close: () -> Unit
    val page = FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        isClickable = true
        if (kind == "img") addView(ImageView(c).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageBitmap(Media.preview(c, f, "img", 2400))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        else addView(android.widget.VideoView(c).apply {
            setVideoURI(android.net.Uri.fromFile(f))
            setMediaController(android.widget.MediaController(c).also { it.setAnchorView(this) })
            setOnPreparedListener { start() }
        }, FrameLayout.LayoutParams(MATCH, MATCH, Gravity.CENTER))
        addView(c.icon(R.drawable.ic_close, Color.WHITE).apply { setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12)); pressable { close() } },
            FrameLayout.LayoutParams(c.dp(48), c.dp(48), Gravity.TOP or Gravity.START).apply { setMargins(c.dp(8), c.dp(8), 0, 0) })
        addView(c.icon(R.drawable.ic_share, Color.WHITE).apply {
            setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12))
            pressable {
                val send = Intent(Intent.ACTION_SEND).setType(c.contentResolver.getType(Media.uri(c, f)) ?: "*/*")
                    .putExtra(Intent.EXTRA_STREAM, Media.uri(c, f)).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                act.startActivity(Intent.createChooser(send, null))
            }
        }, FrameLayout.LayoutParams(c.dp(48), c.dp(48), Gravity.TOP or Gravity.END).apply { setMargins(0, c.dp(8), c.dp(8), 0) })
    }
    close = act.overlay(page)
}


/** A ROUND NOTE IN ITS BUBBLE (iOS videoNoteBubble): the circle with the note's own first frame; a press plays it large, with sound. */
private fun noteBody(c: Context, m: Msg, f: java.io.File?, man: JSONObject?, into: LinearLayout, chat: Chat?) {
    val side = c.dp(220)
    // the note's first frame follows its row as a picture's does (BubblePicture): the manifest's small frame stands meanwhile
    val full = f?.let { BubblePicture.kept(it, "vid", 600) }
    val pic = full?.pic ?: Media.thumbOf(man)
    into.addView(FrameLayout(c).apply {
        // the poster in the note's window: the circle filled, the badge at the corner the manifest names (iOS MontanaNoteFrame)
        addView(NoteWindow(c, NoteWindow.cornerOf(man?.optString("rb"))).holding(ImageView(c).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            if (pic != null) setImageBitmap(pic) else setBackgroundColor(Color.argb(60, 255, 255, 255))
            if (full == null && f != null) BubblePicture.wear(c, f, "vid", 600, this) { s -> background = null
                setImageBitmap(s.pic) }
        }), FrameLayout.LayoutParams(side, side))
        if (f == null && Media.waiting(c, m)) {
            addView(c.icon(R.drawable.ic_arrow_circle_down, Color.WHITE), FrameLayout.LayoutParams(c.dp(36), c.dp(36), Gravity.CENTER))
            setOnClickListener { Media.tapped(c, m) }   // automatic download off: the round note waits for a tap
        }
        else if (f == null) addView(android.widget.ProgressBar(c), FrameLayout.LayoutParams(c.dp(36), c.dp(36), Gravity.CENTER))
        else setOnClickListener { v ->
            (c as? MainActivity)?.let { a ->
                val loc = IntArray(2); v.getLocationOnScreen(loc)
                // THE FLIGHT'S ORIGIN (iOS onTapNote's noteFrameBox.rect, MontanaBubble.swift:24,34 at build 1598, carried to
                // MontanaFeeds.swift:1365 at 2155): the circle's own place on the screen at the tap, so the open note (playNote
                // below) can grow from here and shrink back there on close.
                playNote(a, m, f, chat, android.graphics.Rect(loc[0], loc[1], loc[0] + v.width, loc[1] + v.height))
            }
        }
    }, LinearLayout.LayoutParams(side, side).apply {
        // THE SECOND CIRCLE HAS ITS ROOM (iOS videoNoteBubble, MontanaBubble.swift:1077-1103 at 2155; atom dceb55962f79, the author's
        // word 24.09: «the dual circles must not leave the screen -- the chat's own side margin, as the media keep»): the badge stands
        // past the circle's square by the window's overhang, and the bubble takes that room on the badge's own sides, read from the
        // manifest's corner -- known before any frame, so nothing moves when the file lands. A bottom badge widens the gap to the stamp.
        val corner = NoteWindow.cornerOf(man?.optString("rb"))
        val over = if (corner == null) 0 else Math.ceil(NoteWindow.OVERHANG * side.toDouble()).toInt()
        val left = corner != null && corner % 2 == 0
        val top = corner != null && corner < 2
        leftMargin = if (left) over else 0
        rightMargin = if (corner != null && !left) over else 0
        topMargin = if (top) over else 0
        bottomMargin = c.dp(4) + if (corner != null && !top) over else 0
    })
    // A note stands without the bubble's plate: the circle is its own shape.
    (into.background as? android.graphics.drawable.Drawable)?.let { into.background = null; into.setPadding(0, 0, 0, 0) }
}

/**
 * THE OPEN NOTE'S HANDLES, while one stands (iOS MontanaVideoDock): its close — a voice that starts closes it — and what the one bar
 * asks of it: rest and play, the place, the speed, the name. Set by the open note, cleared when it closes.
 */
object NoteOpen {
    var mid = ""   // the letter that carries the open note: the bar's way back to its bubble (iOS dock.chat / dock.file)
    var file = ""
    var close: (() -> Unit)? = null
    var toggle: (() -> Unit)? = null
    var seek: ((Double) -> Unit)? = null
    var fraction: (() -> Double)? = null
    var sounding: (() -> Boolean)? = null
    var applyRate: (() -> Unit)? = null
    var title = ""
}

/**
 * THE NOTE'S OPEN SIZE, one rule for the player and the recorder (iOS MontanaNoteOpen.side 1558-1566, the author's word 15.09): as
 * wide as the screen lets the circle and its badge stand whole — the badge reaches past the rim by badgeReach + badgeRadius of the
 * side — never wider than the screen less 36, never taller than it less 40, never under 120.
 */
internal fun noteSide(c: Context): Int {
    val dm = c.resources.displayMetrics
    val w = dm.widthPixels / dm.density
    val h = dm.heightPixels / dm.density
    val reach = ((0.5 + 72.0 / 400.0 / 3) / Math.sqrt(2.0) + 72.0 / 400.0).toFloat()   // iOS badgeReach + badgeRadius, in sides from the centre
    return c.dp(maxOf(120f, minOf((w / 2 - 6) / reach, w - 36, h - 40)).toInt())
}

/** A note is a spoken word: it plays at the voice's speed (iOS: one speed for both); set on a sounding player only. */
private fun speed(p: android.media.MediaPlayer) { runCatching { p.playbackParams = p.playbackParams.setSpeed(Playing.rate) } }

/**
 * THE LETTER'S MOTION (iOS MTLetterMotion, MontanaChatMotion.swift 5-33 at 2155; the birth's own numbers born in 1708 and softened
 * in 1710, MontanaBubble 1511-1520 and 1515-1522 there): one spring for the feed, the person's own -- the springiness and the
 * duration the Appearance page keeps under the iOS keys, bounded as iOS bounds a malformed preference (0…0.4 around 0.18, 0.25…0.8
 * around 0.55; 6-23); the newborn starts 0.9 of its height below its place (12) and fades in over the spring's first half, never
 * past 0.28 (24). The platform's «remove animations» stands for iOS Reduce Motion (MontanaMessageFeed 937).
 */
private object LetterMotion {
    const val RISE = 0.9f
    private fun read(key: String, lo: Double, hi: Double, def: Double): Double = Prefs.dbl(key, def).let { if (it.isFinite()) it.coerceIn(lo, hi) else def }
    val duration: Double get() = read("chatSpringDuration", 0.25, 0.8, 0.55)
    val bounce: Double get() = read("chatSpringBounce", 0.0, 0.4, 0.18)
    val fade: Double get() = minOf(0.28, duration / 2)
    val on: Boolean get() = android.animation.ValueAnimator.areAnimatorsEnabled()
    /** What is left of the way `t` seconds in, on iOS spring(duration:bounce:): the natural frequency 2π/duration, the damping ratio
     *  1 − bounce, set off at rest -- critically damped at bounce 0, as 1710 drew it, with no overshoot. */
    fun left(t: Double, d: Double, b: Double): Double {
        val w = 2 * Math.PI / d
        val z = 1 - b
        if (1.0 <= z) return Math.exp(-w * t) * (1 + w * t)
        val wd = w * Math.sqrt(1 - z * z)
        return Math.exp(-z * w * t) * (Math.cos(wd * t) + z * w / wd * Math.sin(wd * t))
    }
    /** How long the spring runs: until what is left falls to about a thousandth of the way; then the row stands. */
    fun settle(d: Double, b: Double): Double = (if (b <= 0.0) 9.0 else 7.0 / (1 - b)) * d / (2 * Math.PI)
}

/** The words of a day, one owner for the feed's separators and its floating pill (iOS dayLabel, MTDayLabel). */
private fun dayWords(c: Context, at: Long): String =
    if (DateUtils.isToday(at)) c.getString(R.string.today) else DateUtils.formatDateTime(c, at, DateUtils.FORMAT_SHOW_DATE)

private fun roundNote(m: Msg): Boolean {
    if (!m.text.startsWith(Marks.MEDIA)) return false
    val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
    return man?.optString("k") == "vid" && man.optBoolean("r")
}

/**
 * THE FLIGHT (iOS MontanaNoteOpen's origin/grown and MontanaVideoDock's origin/closing, MontanaFeeds.swift:1583-1616 and 1521-1530
 * at 2155, spring(response: 0.32, dampingFraction: 0.85) at line 1613): the circle starts at `scale0`/`dx0`/`dy0` away from the
 * identity transform (the bubble it flew out of) and eases to it on open, back on close -- the same step-response curve as
 * LetterMotion's spring (above), read with its own response and dampingFraction instead of duration and bounce.
 */
private fun noteFly(forward: Boolean, scale0: Float, dx0: Float, dy0: Float, circle: View, dim: View, onEnd: () -> Unit) {
    val duration = LetterMotion.settle(0.32, 0.15)
    android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
        setDuration((duration * 1000).toLong())
        interpolator = android.view.animation.LinearInterpolator()
        addUpdateListener { a ->
            val grown = (1 - LetterMotion.left(a.animatedFraction.toDouble() * duration, 0.32, 0.15)).toFloat().coerceIn(0f, 1f)
            val p = if (forward) grown else 1f - grown
            circle.scaleX = scale0 + (1f - scale0) * p; circle.scaleY = circle.scaleX
            circle.translationX = dx0 * (1f - p); circle.translationY = dy0 * (1f - p)
            dim.alpha = p
        }
        addListener(object : android.animation.AnimatorListenerAdapter() { override fun onAnimationEnd(a: android.animation.Animator) { onEnd() } })
    }.start()
}

/**
 * THE OPEN NOTE (iOS MontanaVideoDock 1375-1537, MontanaNoteOpen 1552-1619; the author's words 15.09 and 18.09): the note rises to
 * the middle of the screen at the side its circle and its badge may take; a tap on it plays and rests it, the play glyph over it at
 * rest; a tap on the dim closes it; its end opens the chat's next note in the feed's order, else closes it. THE STAGE'S OWN DIM AND
 * BLUR (iOS MontanaNoteOpen's black 0.62 at line 1598, the recorder's own blur(10), the author's word 15.09 at build 1608): the feed
 * behind is dimmed and blurred as the recorder's is, and takes no touches. One thing plays: the open note stops a voice, a voice
 * closes the note. NO RING WHILE IT PLAYS (iOS MontanaNoteOpen, MontanaFeeds.swift:1602 at 2155, the author's word 23.09): the clean
 * picture -- the one player bar below keeps the time, the seek, the speed and the close.
 */
private fun playNote(act: MainActivity, m: Msg, f: java.io.File, chat: Chat?, origin: android.graphics.Rect) {
    NoteOpen.close?.invoke()
    VoicePlayer.stop()
    // THEIR ROUND NOTE OPENED WITH ITS SOUND: ITS SENDER LEARNS IT ONCE, SILENTLY (iOS notePlayed, MontanaConversation.swift:3101
    // at build 2155, atom cbd70b2f08ed) -- the road to their «Viewed»; opening the chat alone says nothing.
    if (!m.mine) Thread { Post.notePlayed(m.mid) }.start()
    // A TRACK STEPS ASIDE WITH ITS PLACE (iOS VoicePlayer.stepAside / noteClosed, 26.09): the music rests for the note and plays on after it
    val musicWas = MusicPlayer.playing
    if (musicWas) MusicPlayer.pause()
    val c: Context = act
    val side = noteSide(c)
    val notes = chat?.msgs?.filter { roundNote(it) }?.mapNotNull { m -> m.file?.let { java.io.File(it) }?.takeIf { it.exists() } }.orEmpty()
    var current = f
    var close: () -> Unit = {}
    val tv = TextureView(c)
    val glyph = c.icon(R.drawable.ic_play_fill, Color.argb(230, 255, 255, 255)).apply { visibility = View.GONE }
    var player: android.media.MediaPlayer? = null
    val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
    val window = NoteWindow(c, NoteWindow.cornerOf(man?.optString("rb"))).holding(tv)   // the open note's window, its badge whole (iOS MontanaNoteFrame)
    val circle = FrameLayout(c).apply {
        addView(window, FrameLayout.LayoutParams(side, side, Gravity.CENTER))
        addView(glyph, FrameLayout.LayoutParams(c.dp(54), c.dp(54), Gravity.CENTER))
        setOnClickListener { NoteOpen.toggle?.invoke() }
        visibility = View.INVISIBLE   // the flight sets its first frame (the bubble's own place) before it is ever shown
    }
    val dim = View(c).apply { setBackgroundColor(Color.argb(158, 0, 0, 0)); alpha = 0f }   // iOS black 0.62: fades in with the flight
    val page = FrameLayout(c).apply {
        setOnClickListener { close() }
        addView(dim, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(circle, FrameLayout.LayoutParams(side + c.dp(16), side + c.dp(16), Gravity.CENTER))
        // THE BAR BELOW OWNS SEEK, SPEED AND CLOSE (iOS MontanaNoteOpen, MontanaPlayerBar): the one bar at the foot of the note's stage
        addView(liveBar(act).apply { isClickable = true }, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM).apply { bottomMargin = c.dp(16) })
    }
    var scale0 = 1f; var dx0 = 0f; var dy0 = 0f; var leaving = false
    circle.post {
        // The flight scales the picture's own circle onto the bubble's: the stage's frame stands 16 dp wider than the picture.
        val inner = window.width   // the circle's footprint, as the bubble's origin is
        if (inner == 0 || origin.width() == 0) { circle.visibility = View.VISIBLE; dim.alpha = 1f; return@post }
        val loc = IntArray(2); circle.getLocationOnScreen(loc)
        val fcx = loc[0] + circle.width / 2f; val fcy = loc[1] + circle.height / 2f
        scale0 = origin.width().toFloat() / inner.toFloat()
        dx0 = origin.centerX() - fcx; dy0 = origin.centerY() - fcy
        circle.pivotX = circle.width / 2f; circle.pivotY = circle.height / 2f
        circle.scaleX = scale0; circle.scaleY = scale0
        circle.translationX = dx0; circle.translationY = dy0
        circle.visibility = View.VISIBLE
        noteFly(forward = true, scale0 = scale0, dx0 = dx0, dy0 = dy0, circle = circle, dim = dim) {}
    }
    tv.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(st: android.graphics.SurfaceTexture, sw: Int, sh: Int) {
            player = runCatching { android.media.MediaPlayer().apply {
                setDataSource(current.path); setSurface(android.view.Surface(st)); prepare(); start(); speed(this)
                // the end opens the chat's next note (the voice's own law), else closes this one (iOS 1431-1442)
                setOnCompletionListener { mp ->
                    val i = notes.indexOfFirst { it.path == current.path }
                    val next = if (0 <= i) notes.getOrNull(i + 1) else null
                    if (next == null) close()
                    else runCatching { mp.reset(); mp.setDataSource(next.path); mp.prepare(); mp.start(); speed(mp); current = next; Playing.changed() }.onFailure { close() }
                }
            } }.getOrNull()
            val tick = object : Runnable { override fun run() { val p = player ?: return; Playing.changed(); MainThread.later(100, this) } }
            MainThread.later(50, tick)
        }
        override fun onSurfaceTextureSizeChanged(st: android.graphics.SurfaceTexture, sw: Int, sh: Int) {}
        override fun onSurfaceTextureDestroyed(st: android.graphics.SurfaceTexture): Boolean { player?.runCatching { stop(); release() }; player = null; return true }
        override fun onSurfaceTextureUpdated(st: android.graphics.SurfaceTexture) {}
    }
    // THE STAGE DIMS AND BLURS AS THE RECORDER'S DOES (iOS black 0.62 at MontanaFeeds.swift:1598, blur(10) the author's word
    // 15.09 at build 1608): the cloud stands at once (no page-slide) and blurs what is under it, as act.cloud already does for
    // every other full-screen panel; the dim view above fades in with the flight.
    val done = act.cloud(page) { close() }
    close = {
        if (!leaving) {
            leaving = true
            player?.runCatching { if (isPlaying) pause() }   // iOS MontanaVideoDock.close: pause() first, then the flight back
            // THE FLIGHT BACK (iOS MontanaVideoDock.close, MontanaFeeds.swift:1521-1530 at 2155): the circle shrinks into its
            // bubble first, the player lets go only once that flight has settled.
            noteFly(forward = false, scale0 = scale0, dx0 = dx0, dy0 = dy0, circle = circle, dim = dim) {
                player?.runCatching { stop(); release() }; player = null
                NoteOpen.close = null; NoteOpen.toggle = null; NoteOpen.seek = null; NoteOpen.fraction = null; NoteOpen.sounding = null; NoteOpen.applyRate = null
                done(); if (musicWas && !MusicPlayer.playing) MusicPlayer.resume()
                Playing.changed()
            }
        }
    }
    NoteOpen.close = close
    NoteOpen.mid = m.mid; NoteOpen.file = f.path
    NoteOpen.title = chat?.shown.orEmpty()   // USER-DATA: whose note, as the bar names it
    NoteOpen.toggle = {
        player?.let { p ->
            if (p.isPlaying) { p.pause(); glyph.visibility = View.VISIBLE } else { p.start(); speed(p); glyph.visibility = View.GONE }
            Playing.changed()
        }
    }
    NoteOpen.seek = { f -> player?.let { p -> runCatching { p.seekTo((f * p.duration).toInt()) } }; Playing.changed() }
    NoteOpen.fraction = { player?.let { p -> runCatching { p.currentPosition.toDouble() / maxOf(1, p.duration) }.getOrNull() } ?: 0.0 }
    NoteOpen.sounding = { player?.let { p -> runCatching { p.isPlaying }.getOrNull() } == true }
    NoteOpen.applyRate = { player?.let { p -> if (runCatching { p.isPlaying }.getOrNull() == true) speed(p) } }
    Playing.changed()
}


/**
 * THE PICTURE WITH ITS CAPTION (iOS AttachSheet's album page: «under the album stand the caption field and the send button»):
 * the picked picture or the video's first frame across the page, the field «Caption…» under it, prefilled with what was
 * typed, and the chat's own send key. The cross leaves without sending. iOS picks in its own grid; Android's picker is the
 * system's, so the caption comes on this page right after it.
 */
fun captionPage(act: MainActivity, p: Media.Picked, draft: String, onCancel: () -> Unit, onSend: (String) -> Unit): View {
    val c: Context = act
    val preview: android.graphics.Bitmap? = when (p.kind) {
        "img" -> runCatching {
            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(p.bytes, 0, p.bytes.size, o)
            val side = maxOf(o.outWidth, o.outHeight); var s = 1
            while (side / (s * 2) >= 2048) s *= 2
            BitmapFactory.decodeByteArray(p.bytes, 0, p.bytes.size, BitmapFactory.Options().apply { inSampleSize = s })
        }.getOrNull()
        "vid" -> runCatching {
            val f = java.io.File(c.cacheDir, "cap-preview.${p.ext}").apply { writeBytes(p.bytes) }
            android.media.MediaMetadataRetriever().run { setDataSource(f.path); val b = frameAtTime; release(); f.delete(); b }
        }.getOrNull()
        else -> null
    }
    // THE SAME PLATE AS THE CHAT'S OWN FIELD (iOS MTComposeRow.montanaFieldGlass, MontanaBubble.swift:67,2279 at 2155, the author's
    // word 22.09): one glass, one radius (18) for the caption and the chat row alike — never a field drawn by hand with its own shape.
    val field = EditText(c).apply {
        hint = c.getString(R.string.caption_hint); setText(draft); setSelection(text.length)
        setHintTextColor(MT.gray); setTextColor(Color.WHITE); textSize = 17f
        background = c.glassPlate().apply { cornerRadius = c.dp(18).toFloat() }
        setPadding(c.dp(16), c.dp(9), c.dp(16), c.dp(9))
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        maxLines = 5
    }
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(ImageView(c).apply { setImageBitmap(preview); scaleType = ImageView.ScaleType.FIT_CENTER }, FrameLayout.LayoutParams(MATCH, MATCH))
        if (p.kind == "vid") addView(c.icon(R.drawable.ic_play_fill, Color.WHITE), FrameLayout.LayoutParams(c.dp(56), c.dp(56), Gravity.CENTER))
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true); contentDescription = c.getString(R.string.cancel)
            addView(c.icon(R.drawable.ic_close, Color.WHITE), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable { onCancel() }
        }, FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.TOP or Gravity.START).apply { setMargins(c.dp(14), c.dp(6), 0, 0) })
        addView(c.hstack {
            gravity = Gravity.BOTTOM
            setPadding(dp(10), dp(8), dp(10), dp(10))
            setBackgroundColor(Color.argb(150, 0, 0, 0))
            addView(field, lp(0, WRAP, 1f))
            // THE SAME TIER AS THE CHAT'S OWN SEND KEY (iOS MontanaOctagon.composeHeight == MTInputField.tier, MontanaBubble.swift:2331,
            // 2289 at 2155): 36, not a size picked for this page alone (ChatInputBar.TIER carries the same number).
            addView(ImageView(c).apply {
                setImageResource(R.drawable.send_button); scaleType = ImageView.ScaleType.FIT_CENTER
                contentDescription = c.getString(R.string.send)
                pressable { onSend(field.text.toString().trim()) }
            }, lp(dp(36), dp(36)).apply { marginStart = dp(8) })
        }, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))
        setOnApplyWindowInsetsListener { v, insets ->
            val b = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
            v.setPadding(b.left, b.top, b.right, b.bottom); insets
        }
    }
}

/** The long press reaches the letter's menu through every part of the bubble that takes its own tap. */
/** The tap of a failed bubble (iOS primaryTap's first word): the bubble and every control inside it answer it alike. */
private fun View.tapEverywhere(root: Boolean = true, tap: () -> Unit) {
    if (tag == COMMENTS_TAG) return   // a post's comments keep their own tap: the thread opens, the post does not ride again
    if (root || hasOnClickListeners()) setOnClickListener { tap() }
    if (this is android.view.ViewGroup) for (i in 0 until childCount) getChildAt(i).tapEverywhere(false, tap)
}

/**
 * ONE RESEND FOR EVERY BUBBLE KIND (iOS resendAny): a file seals and rides again; a group's letter rides again on its own copies;
 * words re-knock through the queue under the SAME name -- the receiver keeps one row by the name, so a double tap makes no second.
 * A coin letter's coins came back with its red: the retry takes them again, or a short balance refuses it.
 */
private fun resendAny(act: MainActivity, ref: String, m: Msg) {
    if (!CoinSend.mayRetry(m)) {
        AlertDialog.Builder(act).setTitle(R.string.coin_not_enough).setMessage(R.string.coin_not_enough_sub).setPositiveButton(R.string.ok, null).show()
        return
    }
    if (m.file != null) { Media.resend(act, ref, m); return }
    if (Groups.isKey(ref)) { Thread { Groups.resend(ref, m) }.start(); return }
    Thread { Post.retry(ref, m) }.start()
}

/** The tag of a tray plate's number, found again when a carried plate changes the places. */
private const val TRAY_NUMBER = "trayNumber"

private fun View.holdEverywhere(root: Boolean = true, menu: () -> Unit) {
    if (root || isClickable) setOnLongClickListener { menu(); true }
    if (this is android.view.ViewGroup) for (i in 0 until childCount) getChildAt(i).holdEverywhere(false, menu)
}

/**
 * WHETHER A CONTROL TOOK THE TAP (iOS MTTouchClaim: «a control inside claims its touch, and the tap's action, one turn later, leaves
 * the keyboard to it»): the deepest views under the point, the feed itself aside — one with its own click is a control.
 */
private fun claimsTap(v: View, x: Float, y: Float, top: Boolean = true): Boolean {
    if (!top && v.isEnabled && v.hasOnClickListeners()) return true
    if (v !is android.view.ViewGroup) return false
    for (i in v.childCount - 1 downTo 0) {
        val ch = v.getChildAt(i)
        if (ch.visibility != View.VISIBLE) continue
        val cx = x + v.scrollX - ch.left - ch.translationX
        val cy = y + v.scrollY - ch.top - ch.translationY
        if (0f <= cx && 0f <= cy && cx < ch.width && cy < ch.height && claimsTap(ch, cx, cy, false)) return true
    }
    return false
}
