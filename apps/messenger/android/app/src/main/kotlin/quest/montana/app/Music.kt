package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.DocumentsContract
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView

// ─────────────────────────── the folders lent to the music (iOS MTMusicFolders) ───────────────────────────

/** A track as a walk found it: where it lies, its file's name, and — once read — its tag's title and its length. */
class Track(val uri: Uri, val file: String) {
    @Volatile var tagTitle: String? = null
    @Volatile var length: Double = 0.0
    val title: String get() = tagTitle ?: file.substringBeforeLast('.')
}

/**
 * THE PLUS LENDS A FOLDER: the platform's own permission for it is kept (the document tree the system's picker hands over,
 * taken as a persistable grant) — nothing is copied, nothing enters a chat, and a file put into the folder later comes in with
 * the next walk (every opening of the page). The folder lent last stands first, as on iOS.
 */
object MusicFolders {
    private const val KEY = "musicFolders"
    private val audio = setOf("mp3", "m4a", "aac", "flac", "wav", "ogg", "oga", "opus", "alac", "aif", "aiff", "wma")
    @Volatile var tracks: List<Track> = emptyList(); private set
    @Volatile var walking = false; private set
    private val known = HashMap<String, Track>()   // what a walk found before, with what was read of it
    val listeners = mutableListOf<() -> Unit>()
    private fun said(act: MainActivity) = act.onMain { listeners.toList().forEach { it() } }

    private fun lent(): List<Uri> = Prefs.str(KEY, "").split('\n').filter { it.isNotEmpty() }.map(Uri::parse)

    fun lend(act: MainActivity, tree: Uri) {
        try { act.contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: SecurityException) {}
        val all = lent().filter { it != tree } + tree
        Prefs.setStr(KEY, all.joinToString("\n"))
        walk(act, picked = true)
    }

    /** Walks every lent folder, at any depth; then reads each new track's tag and length behind the page. */
    fun walk(act: MainActivity, picked: Boolean = false) {
        if (walking) return
        walking = picked; said(act)
        act.background {
            val found = ArrayList<Track>()
            for (tree in lent().reversed()) {
                val here = ArrayList<Track>()
                try { collect(act, tree, DocumentsContract.getTreeDocumentId(tree), here) } catch (_: Exception) {}
                found += here.sortedBy { it.file.lowercase() }
            }
            tracks = found
            walking = false
            said(act)
            for (t in found) if (t.length == 0.0 && t.tagTitle == null) {
                try {
                    MediaMetadataRetriever().apply {
                        setDataSource(act, t.uri)
                        t.tagTitle = extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.takeIf { it.isNotBlank() }
                        t.length = (extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) / 1000.0
                        release()
                    }
                } catch (_: Exception) {}
            }
            said(act)
        }
    }

    private fun collect(c: Context, tree: Uri, doc: String, out: MutableList<Track>) {
        val kids = DocumentsContract.buildChildDocumentsUriUsingTree(tree, doc)
        val cols = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE)
        c.contentResolver.query(kids, cols, null, null, null)?.use { cur ->
            while (cur.moveToNext()) {
                val id = cur.getString(0); val name = cur.getString(1) ?: continue; val mime = cur.getString(2) ?: ""
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) collect(c, tree, id, out)
                else if (mime.startsWith("audio/") || name.substringAfterLast('.', "").lowercase() in audio) {
                    val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                    out += known.getOrPut(uri.toString()) { Track(uri, name) }
                }
            }
        }
    }
}

// ─────────────────────────── the one player (iOS VoicePlayer for the music) ───────────────────────────

/**
 * THE ONE PLAYER: a queue — the list as it stood when a row was tapped, so the next track is the row below — the platform's
 * MediaPlayer with the system's audio focus, and one clock that tells the bar where the track stands. Every change of the
 * track, its rest or its place is told to the system too (MusicService), so the shade, the lock screen and the headphones
 * follow it; the clock's ticks are not — the system runs the position on by itself.
 */
object MusicPlayer {
    var queue: List<Track> = emptyList(); private set
    var index = -1; private set
    var playing = false; private set
    private var mp: MediaPlayer? = null
    private var prepared = false
    private var app: Context? = null
    private val main = Handler(Looper.getMainLooper())
    val listeners = mutableListOf<() -> Unit>()
    private fun said() { listeners.toList().forEach { it() }; Playing.changed() }
    private fun changed() { said(); app?.let { MusicService.sync(it) } }
    val current: Track? get() = queue.getOrNull(index)
    var refused: (() -> Unit)? = null

    private var focus: AudioFocusRequest? = null
    private fun takeFocus(c: Context) {
        val am = c.getSystemService(AudioManager::class.java)
        focus?.let { am.abandonAudioFocusRequest(it) }
        focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setOnAudioFocusChangeListener { if (it == AudioManager.AUDIOFOCUS_LOSS || it == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) pause() }
            .build().also { am.requestAudioFocus(it) }
    }
    private fun dropFocus() {
        val f = focus ?: return; focus = null
        app?.getSystemService(AudioManager::class.java)?.abandonAudioFocusRequest(f)
    }

    fun play(c: Context, list: List<Track>, i: Int) {
        if (CallSound.refused("music")) return   // the call holds the sound (iOS MontanaMedia 372)
        val a = c.applicationContext
        app = a
        // THE TRACK IN HAND KEEPS ITS MOMENT BEFORE THE NEXT ONE TAKES THE PLAYER (iOS VoicePlayer.toggle:386 at 2155,
        // MTPlayPlaces.keep, the author's word 26.09).
        mp?.takeIf { prepared }?.let { p -> current?.let { t -> PlayPlaces.keep(t.file, p.currentPosition / 1000.0, p.duration / 1000.0, false) } }
        queue = list; index = i
        release()
        val t = current ?: return
        takeFocus(a)
        mp = MediaPlayer().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            // the processor stays awake while it plays: the screen goes dark, the music goes on
            setWakeMode(a, PowerManager.PARTIAL_WAKE_LOCK)
            // A LONG LISTEN GOES ON WHERE IT STOPPED (iOS VoicePlayer.toggle:411-414 at 2155, MTPlayPlaces.at, 26.09).
            setOnPreparedListener { prepared = true; PlayPlaces.at(t.file, it.duration / 1000.0, false)?.let { at -> runCatching { it.seekTo((at * 1000).toInt()) } }; it.start(); playing = true; tick(); changed() }
            setOnCompletionListener { if (index + 1 < queue.size) play(a, queue, index + 1) else { playing = false; seek(0.0); changed() } }
            setOnErrorListener { _, _, _ -> playing = false; changed(); refused?.invoke(); true }
            try { setDataSource(a, t.uri); prepareAsync() } catch (_: Exception) { refused?.invoke() }
        }
        changed()
    }

    fun toggle() { if (playing) pause() else resume() }
    fun pause() {
        // iOS VoicePlayer.pause:444 at 2155, MTPlayPlaces.keep, 26.09
        mp?.takeIf { prepared }?.let { p -> current?.let { t -> PlayPlaces.keep(t.file, p.currentPosition / 1000.0, p.duration / 1000.0, false) } }
        mp?.takeIf { prepared }?.pause(); playing = false; changed()
    }
    fun resume() {
        val p = mp?.takeIf { prepared } ?: return
        if (CallSound.refused("music")) return   // iOS MontanaMedia 482
        app?.let { takeFocus(it) }
        p.start(); playing = true; tick(); changed()
    }
    fun seek(f: Double) { val p = mp?.takeIf { prepared } ?: return; p.seekTo((f * p.duration).toInt()); changed() }
    /** Forward turns the page even on the last track — the first follows (iOS next). */
    fun next() { val a = app ?: return; if (queue.isEmpty()) return; play(a, queue, if (index + 1 < queue.size) index + 1 else 0) }
    /** Back: past three seconds the track starts over, before them the one above plays (iOS prev). */
    fun prev() {
        val a = app ?: return
        if (positionMs > 3000 || index <= 0) seek(0.0) else play(a, queue, index - 1)
    }
    /** The bar's cross: the track stops and the bar leaves (iOS MontanaPlayerBar close). */
    fun stop() {
        // iOS VoicePlayer.release:526 at 2155, MTPlayPlaces.keep, 26.09
        mp?.takeIf { prepared }?.let { p -> current?.let { t -> PlayPlaces.keep(t.file, p.currentPosition / 1000.0, p.duration / 1000.0, false) } }
        release(); dropFocus(); queue = emptyList(); index = -1; changed()
    }

    val fraction: Double get() = mp?.takeIf { prepared && it.duration > 0 }?.let { it.currentPosition.toDouble() / it.duration } ?: 0.0
    val duration: Double get() = mp?.takeIf { prepared }?.duration?.div(1000.0) ?: (current?.length ?: 0.0)
    val positionMs: Long get() = mp?.takeIf { prepared }?.currentPosition?.toLong() ?: 0L

    private fun release() {
        main.removeCallbacksAndMessages(null)
        mp?.release(); mp = null; prepared = false; playing = false
    }
    private fun tick() {
        main.removeCallbacksAndMessages(null)
        if (!playing) return
        said()
        main.postDelayed({ tick() }, 500)
    }
}

/**
 * WHERE A LONG LISTEN STOPPED (iOS MTPlayPlaces, MontanaMedia.swift:647-666 at 2155, the author's word 26.09: «the mini
 * player must remember the place where it stopped playing and not be reset by recording or listening to a voice or a
 * video message»): a track of ten minutes and more, a voice of five, keeps its moment -- between five seconds in and
 * five before its end -- and the next play of the same file starts there. One key of the preferences, written when a
 * listen stops, never by the clock, bounded to the newest two hundred.
 */
object PlayPlaces {
    private const val KEY = "playPlaces"
    private const val MOST = 200
    private fun long(of: Double, voice: Boolean) = of >= (if (voice) 300.0 else 600.0)
    private fun all(): org.json.JSONObject = runCatching { org.json.JSONObject(Prefs.str(KEY, "{}")) }.getOrDefault(org.json.JSONObject())
    fun keep(file: String, at: Double, of: Double, voice: Boolean) {
        if (file.isEmpty() || !long(of, voice)) return
        val o = all()
        if (at > 5 && at < of - 5) o.put(file, org.json.JSONArray().put(at).put(System.currentTimeMillis() / 1000.0)) else o.remove(file)
        if (o.length() > MOST) {
            val oldest = o.keys().asSequence().sortedBy { o.getJSONArray(it).optDouble(1, 0.0) }.take(o.length() - MOST).toList()
            for (k in oldest) o.remove(k)
        }
        Prefs.setStr(KEY, o.toString())
    }
    fun at(file: String, of: Double, voice: Boolean): Double? {
        if (!long(of, voice)) return null
        val t = all().optJSONArray(file)?.optDouble(0, -1.0) ?: return null
        return t.takeIf { it > 5 && it < of - 5 }
    }
}

/** «m:ss», or «h:mm:ss» past an hour (iOS fmtDuration). */
fun fmtDuration(s: Double): String {
    val t = s.toInt().coerceAtLeast(0)
    return if (t >= 3600) String.format("%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) else String.format("%d:%02d", t / 60, t % 60)
}

// ─────────────────────────── the one bar (iOS MontanaPlayerBar, MTMiniFace) ───────────────────────────

/**
 * WHAT PLAYS, ONE ANSWER (iOS MontanaPlayerBar.standing, the one gate): an open note, else a voice, else a track — the bar shows
 * the first that stands; every player says its changes here, and every bar redraws from here. The speed is one for voices and
 * notes (iOS voiceRate: 1 → 1.5 → 2, kept across launches).
 */
object Playing {
    enum class Kind { TRACK, VOICE, NOTE }
    val kind: Kind? get() = when {
        NoteOpen.close != null -> Kind.NOTE
        VoicePlayer.playing != null -> Kind.VOICE
        MusicPlayer.current != null -> Kind.TRACK
        else -> null
    }
    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    fun changed() { MainThread.post { synchronized(listeners) { listeners.toList() }.forEach { it() } } }
    var rate: Float
        get() = Prefs.str("voiceRate", "1").toFloatOrNull() ?: 1f
        set(v) = Prefs.setStr("voiceRate", v.toString())
    /** One tap around 1 → 1.5 → 2 (iOS onSide), heard at once by the voice and the note. */
    fun nextRate() {
        rate = if (2f <= rate) 1f else if (1.5f <= rate) 2f else 1.5f
        VoicePlayer.applyRate(); NoteOpen.applyRate?.invoke(); changed()
    }
    fun rateWord() = if (rate == 1f) "1×" else if (rate == 2f) "2×" else "1.5×"   // USER-DATA: a number, not a word
    /** A TAPE HOLDS WHAT PLAYS, THE OPEN NOTE CLOSES (iOS MontanaPlayerBar.standDown, MontanaMusicPlayer.swift:1026-1035 at
     *  2155): a voice tape always rests whatever sounds; a note's camera keeps a track that was already playing
     *  (`keepingMusic`, read by the caller before anything stands down) and rests a voice message regardless -- the
     *  chat's own stepAside (Conversation.kt:2424-2426, 2498) already lets a rested track play on once the tape ends. */
    fun standDown(keepingMusic: Boolean = false) {
        NoteOpen.close?.invoke()
        VoicePlayer.pause()
        if (!keepingMusic) MusicPlayer.pause()
    }
}

/**
 * THE ONE MINI PLAYER (iOS MTMiniFace, the author's word 22.09): one face for the track, the voice and the video note — the play on
 * its round glass plate, the long glass plate that is the scrubber with the name running inside it, at its end the track's timer
 * (its two faces) or, for a voice and a note, the speed; for a track the fifteen-second skips beside it; and the cross. On a row of
 * the music list it stands still. The playing track wears the platform's thin blue ring.
 */
class MiniFace(ctx: Context, private val bar: Boolean) : LinearLayout(ctx) {
    private val h = dp(44)
    val play = FrameLayout(ctx)
    private val playGlyph = ctx.icon(R.drawable.ic_play_fill, Color.rgb(204, 204, 204))
    private val plate = FrameLayout(ctx)
    private val fill = View(ctx).apply { setBackgroundColor(Color.argb(41, 255, 255, 255)) }
    private val title = ctx.text("", 15f).apply { singleLineEllipsis() }
    private val side = ctx.text("", 13f, MT.gray)
    private var remaining = false
    private var scrub: Double? = null
    private var prevBtn: View? = null
    private var nextBtn: View? = null
    private var closeBtn: View? = null
    var onSeek: (Double) -> Unit = {}
    // A HOLD ON THE MINI COPIES ITS NAME AT ONCE (iOS MTNameCopy, MontanaMusicPlayer.swift:1141-1159 and 1267-1309 at 2155, the
    // author's word 29.09 ~23:10: «at a long press, at the speed our menu opens in the chat, the track's name is copied»): the
    // bar's plate alone -- a still row of the list answers no touch of its own (still, below).
    private var displayTitle = ""
    private var copiedUntil = 0L
    private var longPressed = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val longPressRunnable = Runnable { longPressed = true; copyTitle() }
    private companion object { const val HOLD_MS = 220L }   // iOS montanaLongPress, MontanaNetFrames.swift:9 at 2155

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(4), dp(12), dp(4))
        play.background = ctx.glassPlate(oval = true)
        play.addView(playGlyph, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
        addView(play, LayoutParams(h, h))
        // THE TRACK BEFORE AND THE TRACK AFTER (iOS MTMiniFace.onPrev/onNext, MontanaMusicPlayer.swift:1206-1238 at 2155, the
        // author's word 29.09 on build 2000: «the buttons should have switched to the next track, not seek»): the queue's own
        // turn, as the lock screen's buttons (MusicPlayer.prev/next) -- a track's bar alone, never a voice's or a note's.
        if (bar) prevBtn = square(R.drawable.ic_skip_prev) { MusicPlayer.prev() }.also { addView(it, LayoutParams(h, h).apply { marginStart = dp(10) }) }
        plate.background = ctx.glassPlate()
        plate.clipToOutline = true
        plate.outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(v: View, o: android.graphics.Outline) = o.setRoundRect(0, 0, v.width, v.height, v.height / 2f)
        }
        plate.addView(fill, FrameLayout.LayoutParams(0, MATCH))
        plate.addView(title, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.CENTER_VERTICAL).apply { marginStart = dp(16); marginEnd = dp(64) })
        plate.addView(side, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER_VERTICAL or Gravity.END).apply { marginEnd = dp(14) })
        addView(plate, LayoutParams(0, h, 1f).apply { marginStart = dp(10) })
        if (bar) {
            nextBtn = square(R.drawable.ic_skip_next) { MusicPlayer.next() }.also { addView(it, LayoutParams(h, h).apply { marginStart = dp(10) }) }
            closeBtn = square(R.drawable.ic_close) {
                when (Playing.kind) { Playing.Kind.NOTE -> NoteOpen.close?.invoke(); Playing.Kind.VOICE -> VoicePlayer.stop(); else -> MusicPlayer.stop() }
            }.also { addView(it, LayoutParams(h, h).apply { marginStart = dp(10) }) }
            play.pressable {
                when (Playing.kind) {
                    Playing.Kind.NOTE -> NoteOpen.toggle?.invoke()
                    Playing.Kind.VOICE -> if (VoicePlayer.paused) VoicePlayer.resume() else VoicePlayer.pause()
                    else -> MusicPlayer.toggle()
                }
            }
            onSeek = { f -> when (Playing.kind) { Playing.Kind.NOTE -> NoteOpen.seek?.invoke(f); Playing.Kind.VOICE -> VoicePlayer.seekTo(f); else -> MusicPlayer.seek(f) } }
            // THE PLATE IS THE SCRUBBER: the finger holds the value while it moves, the player is asked once, at the release; a tap
            // on the side room is the side's — the timer's two faces for a track, the speed for a voice and a note (iOS onSide)
            var downX = 0f; var downY = 0f
            // A FINGER THAT NEVER MOVED MAY HOLD, AND ASKS FOR NO SEEK (iOS MontanaSliderView.slop/moved, MontanaMusicPlayer.swift:
            // 1267-1309 at 2155): the first eight points are the tap's room -- standing in it, the plate's hold copies the name
            // (copyTitle) instead of the platform's old context menu, which 2155 no longer carries; leaving it is a swipe.
            plate.setOnTouchListener { v, e ->
                val f = (e.x / v.width).toDouble().coerceIn(0.0, 1.0)
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        v.parent.requestDisallowInterceptTouchEvent(true); scrub = null; longPressed = false
                        downX = e.x; downY = e.y
                        mainHandler.postDelayed(longPressRunnable, HOLD_MS)   // the chat bubble's own threshold (iOS montanaLongPress)
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (scrub == null && kotlin.math.abs(e.x - downX) < dp(8) && kotlin.math.abs(e.y - downY) < dp(8)) true
                        else { mainHandler.removeCallbacks(longPressRunnable); scrub = f; show(f); true }
                    }
                    MotionEvent.ACTION_UP -> {
                        mainHandler.removeCallbacks(longPressRunnable)
                        val held = scrub; scrub = null
                        if (longPressed) longPressed = false
                        else if (held != null) onSeek(held)
                        else if (e.x > v.width - dp(64)) { if (Playing.kind == Playing.Kind.TRACK) { remaining = !remaining; live() } else Playing.nextRate() }
                        true
                    }
                    MotionEvent.ACTION_CANCEL -> { mainHandler.removeCallbacks(longPressRunnable); scrub = null; true }
                    else -> false
                }
            }
        }
    }

    /** The title shown now, unless the copied word still stands in its room (iOS MTCopiedWord, 2 s, MTNameCopy.shown). */
    private fun showTitle() {
        if (System.currentTimeMillis() < copiedUntil) return
        title.text = displayTitle
    }
    /** THE HOLD COPIES THE NAME (iOS MTNameCopy.copy, MontanaMusicPlayer.swift:1146-1158 at 2155): the name to the clipboard, the
     * platform's success haptic, and for two seconds the name's room says the catalogue's «Copied» after the platform's check, in
     * the name's own colour (MTCopiedWord, 1163-1167). */
    private fun copyTitle() {
        val name = displayTitle
        if (name.isEmpty()) return
        context.getSystemService(android.content.ClipboardManager::class.java)
            ?.setPrimaryClip(android.content.ClipData.newPlainText("", name))
        performHapticFeedback(if (android.os.Build.VERSION.SDK_INT >= 30) android.view.HapticFeedbackConstants.CONFIRM else android.view.HapticFeedbackConstants.LONG_PRESS)
        val check = context.getDrawable(R.drawable.ic_check)?.mutate()?.apply { setTint(Color.WHITE); val k = title.textSize.toInt(); setBounds(0, 0, k, k) }
        title.setCompoundDrawablesRelative(check, null, null, null); title.compoundDrawablePadding = dp(4)
        title.text = context.getString(R.string.copied)
        copiedUntil = System.currentTimeMillis() + 2000
        mainHandler.postDelayed({ if (copiedUntil <= System.currentTimeMillis()) { title.setCompoundDrawablesRelative(null, null, null, null); showTitle() } }, 2000)
    }

    private fun square(res: Int, onTap: () -> Unit) = FrameLayout(context).apply {
        background = context.glassPlate(oval = true)
        addView(context.icon(res, Color.rgb(204, 204, 204)), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
        pressable(onTap)
    }

    /** A still row of the list: the name, the length, the ring when it is the one that plays. */
    fun still(t: Track, isCurrent: Boolean, playingNow: Boolean) {
        displayTitle = t.title; showTitle()   // USER-DATA: the track's own name
        side.text = if (t.length > 0) fmtDuration(t.length) else ""   // USER-DATA: a length, digits
        playGlyph.setImageResource(if (playingNow) R.drawable.ic_pause_fill else R.drawable.ic_play_fill)
        ring(isCurrent)
    }

    /** The bar: whatever plays (Playing.kind), its name and its place on the plate. */
    fun live() {
        val kind = Playing.kind ?: return
        val track = kind == Playing.Kind.TRACK
        prevBtn?.visibility = if (track) View.VISIBLE else View.GONE
        nextBtn?.visibility = if (track) View.VISIBLE else View.GONE
        val sounding = when (kind) {
            Playing.Kind.NOTE -> NoteOpen.sounding?.invoke() == true
            Playing.Kind.VOICE -> !VoicePlayer.paused
            Playing.Kind.TRACK -> MusicPlayer.playing
        }
        displayTitle = when (kind) {   // USER-DATA: the track's own name, or the speaker's name as the person sees it
            Playing.Kind.NOTE -> NoteOpen.title
            Playing.Kind.VOICE -> VoicePlayer.sender
            Playing.Kind.TRACK -> MusicPlayer.current?.title.orEmpty()
        }
        showTitle()
        playGlyph.setImageResource(if (sounding) R.drawable.ic_pause_fill else R.drawable.ic_play_fill)
        // THE THIN BLUE RING ON EVERY PAGE (iOS MTMiniFace.playingRing, the author's word 29.09): the bar wears it fixed,
        // wherever it floats -- never conditioned, as the still row's own ring is, on «is this the one that plays».
        ring(true)
        if (scrub == null) show(when (kind) {
            Playing.Kind.NOTE -> NoteOpen.fraction?.invoke() ?: 0.0
            Playing.Kind.VOICE -> VoicePlayer.fraction
            Playing.Kind.TRACK -> MusicPlayer.fraction
        })
    }

    private fun show(f: Double) {
        if (bar && Playing.kind != Playing.Kind.TRACK) side.text = Playing.rateWord()
        else {
            val d = MusicPlayer.duration
            side.text = if (d <= 0) "" else if (remaining) "-" + fmtDuration(d - f * d) else fmtDuration(f * d)   // USER-DATA: a time
        }
        val lp = fill.layoutParams as FrameLayout.LayoutParams
        val w = (plate.width * f).toInt()
        if (lp.width != w) { lp.width = w; fill.layoutParams = lp }
    }

    private fun ring(on: Boolean) {
        val blue = if (on) MT.blue else null
        fun oval() = blue?.let { GradientDrawable().apply { shape = GradientDrawable.OVAL; setStroke(dp(1), it) } }
        play.foreground = oval()
        plate.foreground = blue?.let { GradientDrawable().apply { cornerRadius = dp(100).toFloat(); setStroke(dp(1), it) } }
        // EVERY BUTTON WEARS THE RING (iOS MTMiniFace.trackButton/onClose overlay, MontanaMusicPlayer.swift:1213-1244 at 2155,
        // the author's word 29.09 on build 2000: «all the buttons in the system's outline, as the play and the central one»).
        prevBtn?.foreground = oval()
        nextBtn?.foreground = oval()
        closeBtn?.foreground = oval()
    }
}

/** THE FLOATING PLAYER at the foot of the chats, the feed and the music (iOS MontanaPlayerBar): shown while anything plays. */
fun miniBar(act: MainActivity): MiniFace = MiniFace(act, bar = true).apply { visibility = View.GONE }

/** The one bar where a page stands on its own (the chat above its field, the open note): it follows Playing while attached. */
fun liveBar(act: MainActivity): MiniFace = miniBar(act).apply {
    val update: () -> Unit = { val on = Playing.kind != null; visibility = if (on) View.VISIBLE else View.GONE; if (on) live() }
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Playing.listen(update); update() }
        override fun onViewDetachedFromWindow(v: View) { Playing.unlisten(update) }
    })
}

// ─────────────────────────── the music page (iOS MusicTabView) ───────────────────────────

/**
 * THE MUSIC PAGE: every track of the lent folders as a row in the mini's face, newest folder first; the whole row is one
 * target — a still track plays with the list as its queue, the playing one rests or plays on. The plus at the bottom right
 * lends a folder through the system's own picker and turns while the folder just picked is walked.
 */
class MusicPage(private val act: MainActivity) {
    val view: FrameLayout = FrameLayout(act)
    private val rows = LinearLayout(act).apply { orientation = LinearLayout.VERTICAL; setPadding(0, 0, 0, act.dp(140)) }
    private val empty = act.text(act.getString(R.string.no_music), 17f, MT.gray, center = true)
    private val plus = FrameLayout(act)
    private val spinner = ProgressBar(act).apply { indeterminateTintList = android.content.res.ColorStateList.valueOf(Color.rgb(204, 204, 204)); visibility = View.GONE }
    private val plusGlyph = act.icon(R.drawable.ic_plus, Color.rgb(204, 204, 204))
    private val faces = HashMap<String, MiniFace>()
    private var lastRing: String? = null
    private var lastPlaying = false

    init {
        view.addView(ScrollView(act).apply { addView(rows) }, FrameLayout.LayoutParams(MATCH, MATCH))
        view.addView(empty, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        plus.background = act.glassPlate(oval = true)
        plus.addView(plusGlyph, FrameLayout.LayoutParams(act.dp(28), act.dp(28), Gravity.CENTER))
        plus.addView(spinner, FrameLayout.LayoutParams(act.dp(26), act.dp(26), Gravity.CENTER))
        plus.pressable { act.pickFolder { it?.let { tree -> MusicFolders.lend(act, tree) } } }
        view.addView(plus, FrameLayout.LayoutParams(act.dp(56), act.dp(56), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, act.dp(16), act.dp(36)) })
        MusicFolders.listeners += { if (view.isAttachedToWindow || view.parent != null) fill() }
        MusicPlayer.listeners += { ringChanged() }
        // a track refused while the app is away (the next one, from the shade) is only not played: no window without a page
        MusicPlayer.refused = { if (!act.isFinishing && !act.isDestroyed) AlertDialog.Builder(act).setMessage(R.string.track_refused).setPositiveButton(R.string.ok, null).show() }
        fill()
    }

    /** The bar stands: the plus steps above it (iOS .padding(.bottom, 46 + reserve)). */
    fun reserve(on: Boolean) {
        (plus.layoutParams as FrameLayout.LayoutParams).bottomMargin = act.dp(if (on) 96 else 36)
        plus.requestLayout()
    }

    fun fill() {
        val list = MusicFolders.tracks
        spinner.visibility = if (MusicFolders.walking) View.VISIBLE else View.GONE
        plusGlyph.visibility = if (MusicFolders.walking) View.GONE else View.VISIBLE
        empty.visibility = if (list.isEmpty()) View.VISIBLE else View.GONE
        rows.removeAllViews()
        list.forEachIndexed { i, t ->
            val face = faces.getOrPut(t.uri.toString()) { MiniFace(act, bar = false) }
            (face.parent as? LinearLayout)?.removeView(face)
            val cur = MusicPlayer.current?.uri == t.uri
            face.still(t, cur, cur && MusicPlayer.playing)
            face.setOnClickListener {
                if (MusicPlayer.current?.uri == t.uri) MusicPlayer.toggle() else MusicPlayer.play(act, MusicFolders.tracks, i)
            }
            face.play.setOnClickListener { face.performClick() }
            rows.addView(face, LinearLayout.LayoutParams(MATCH, WRAP))
        }
    }

    /** The clock ticks every half second; the rows are drawn again only when the playing track or its rest changes. */
    private fun ringChanged() {
        val now = MusicPlayer.current?.uri?.toString()
        if (now == lastRing && MusicPlayer.playing == lastPlaying) return
        lastRing = now; lastPlaying = MusicPlayer.playing
        MusicFolders.tracks.forEach { t -> faces[t.uri.toString()]?.still(t, t.uri.toString() == now, t.uri.toString() == now && MusicPlayer.playing) }
    }
}
