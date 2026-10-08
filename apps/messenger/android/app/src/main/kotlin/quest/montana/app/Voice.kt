package quest.montana.app

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.PowerManager
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import java.io.File

/**
 * THE VOICE TAPE (iOS VoiceRecorder + MontanaVoiceSound): 48 kHz mono, AAC at 64 kbit/s in an .m4a — the same speech through
 * the same door; the platform's own MediaRecorder writes it. The tape rides as a media letter of kind «aud» with its length «du».
 */
object VoiceTape {
    private var rec: MediaRecorder? = null
    private var file: File? = null
    private var began = 0L
    /** THE WAVE IS THE SOUND ITSELF (iOS VoiceRecorder.levels): one slot per 25 ms keeps the loudest reading, linear 0…1. */
    val levels = ArrayList<Float>()
    var onLevel: ((Float) -> Unit)? = null
    private val meter = object : Runnable {
        override fun run() {
            val r = rec ?: return
            if (!paused) {   // a paused tape hears nothing: the wave stands (iOS)
                val a = runCatching { r.maxAmplitude }.getOrDefault(0) / 32767f
                levels.add(a); onLevel?.invoke(a)
            }
            MainThread.later(25, this)
        }
    }
    val seconds: Double get() = if (rec == null) 0.0 else (System.currentTimeMillis() - began - pausedMs - (if (paused) System.currentTimeMillis() - pauseAt else 0)) / 1000.0

    /** THE PAUSE OF A LOCKED TAPE (iOS VoiceRecorder.pause/resume): the platform's recorder stands, the file skips the gap. */
    var paused = false; private set
    private var pauseAt = 0L
    private var pausedMs = 0L
    fun togglePause() {
        val r = rec ?: return
        if (paused) { runCatching { r.resume() }; pausedMs += System.currentTimeMillis() - pauseAt; paused = false }
        else if (runCatching { r.pause() }.isSuccess) { pauseAt = System.currentTimeMillis(); paused = true }
    }

    /** The tape's 60 lines as iOS shapes them (MTWaveform.compute): scaled to a loud slot (92nd percentile), a soft curve (0.7). */
    fun waveform(): FloatArray {
        if (levels.isEmpty()) return FloatArray(0)
        val bars = 60
        val raw = FloatArray(bars) { i ->
            val a = i * levels.size / bars; val b = maxOf(a + 1, (i + 1) * levels.size / bars)
            var acc = 0f; for (j in a until minOf(b, levels.size)) acc += levels[j]; acc / maxOf(1, b - a)
        }
        val sorted = raw.sorted()
        val ref = maxOf(sorted[((sorted.size - 1) * 0.92).toInt()], 1e-6f)
        return FloatArray(bars) { Math.pow(minOf(1f, raw[it] / ref).toDouble(), 0.7).toFloat() }
    }

    fun granted(c: Context) = c.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    /** The tape starts; false when the microphone is not ours (the question is asked, the next hold records). */
    fun start(act: MainActivity): Boolean {
        if (!granted(act)) { act.requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), 7); return false }
        if (rec != null) return false   // one tape at a time: a second start over a rolling one is nothing (iOS VoiceRecorder.start guard, build 1519 / 2155 MontanaMedia.swift:112)
        val f = File(act.cacheDir, "tape-${System.currentTimeMillis()}.m4a")
        return try {
            rec = MediaRecorder(act).apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(48_000)
                setAudioChannels(1)
                setAudioEncodingBitRate(64_000)
                setOutputFile(f.path)
                prepare(); start()
            }
            file = f; began = System.currentTimeMillis(); paused = false; pausedMs = 0
            levels.clear(); MainThread.later(25, meter)
            true
        } catch (_: Exception) { rec?.release(); rec = null; f.delete(); false }
    }

    /** The tape ends: the file and its length in seconds, or null when it was dropped or too short to be a word. */
    fun stop(keep: Boolean): Pair<File, Double>? {
        val r = rec ?: return null
        rec = null
        val secs = seconds
        paused = false
        val ok = runCatching { r.stop() }.isSuccess
        r.release()
        val f = file; file = null
        if (!keep || !ok || secs < 0.6 || f == null) { f?.delete(); return null }
        return f to secs
    }
}

/**
 * ONE VOICE PLAYS AT A TIME (iOS VoicePlayer, the chat's one player): a new voice stops the one before; a tap on the voice that
 * plays rests it and plays it on (iOS: pause, not stop); a queue's next follows the end (iOS auto-next). The voice plays at the
 * one speed of voices and notes (Playing.rate), says whose it is to the one bar (sender), and while it plays a track steps
 * aside with its place and plays on after it (iOS stepAside, 26.09); a voice that starts closes an open note.
 */
object VoicePlayer {
    private var player: MediaPlayer? = null
    var playing: String? = null; private set
    var paused = false; private set
    var sender = ""; private set   // whose voice, as the person sees the name (iOS nowSender)
    private var onStop: (() -> Unit)? = null
    private var progress: ((Int, Int) -> Unit)? = null
    private var musicAside = false

    /** This voice sounds now — not only chosen: a rested voice is chosen and silent. */
    fun sounding(path: String?) = path != null && playing == path && !paused

    fun toggle(path: String, onProgress: (Int, Int) -> Unit, stopped: () -> Unit, then: (() -> Unit)? = null, sender: String = "") {
        if (playing == path) { if (paused) resume() else pause(); return }
        stop()
        NoteOpen.close?.invoke()   // one thing plays: a voice closes the open note (iOS MontanaVideoDock)
        // THE RECEIVER IS THE CATEGORY'S OWN DEFAULT (iOS: no .defaultToSpeaker on the voice's playAndRecord category,
        // ContentView.swift:3244 at build 2155) -- the loudspeaker only by the proximity sensor's own word, armProximity below.
        val p = runCatching { MediaPlayer().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            setDataSource(path); prepare()
        } }.getOrNull() ?: return
        if (MusicPlayer.playing) { MusicPlayer.pause(); musicAside = true }
        player = p; playing = path; paused = false; onStop = stopped; progress = onProgress; this.sender = sender
        p.setOnCompletionListener { stop(); then?.invoke() }
        p.start(); speed(p)
        armProximity()
        tick(path)
        Playing.changed()
    }
    // the speed is set on a sounding player only: on a rested one the platform starts it
    private fun speed(p: MediaPlayer) { runCatching { p.playbackParams = p.playbackParams.setSpeed(Playing.rate) } }
    fun applyRate() { val p = player ?: return; if (!paused) speed(p) }
    private fun tick(path: String) {
        val t = object : Runnable {
            override fun run() {
                val cur = player ?: return
                if (playing != path || paused) return
                runCatching { progress?.invoke(cur.currentPosition, cur.duration) }
                Playing.changed()
                MainThread.later(100, this)
            }
        }
        MainThread.later(0, t)
    }
    // a rested voice gives the ear's sensor back (iOS VoicePlayer.pause, MontanaMedia.swift:442)
    fun pause() { val p = player ?: return; runCatching { p.pause() }; paused = true; disarmProximity(); Playing.changed() }
    fun resume() {
        val p = player ?: return
        val path = playing ?: return
        runCatching { p.start(); speed(p) }; paused = false; armProximity(); tick(path); Playing.changed()
    }
    fun seek(path: String, ms: Int) { if (playing == path) player?.seekTo(ms) }
    fun seekTo(f: Double) { val p = player ?: return; runCatching { p.seekTo((f * p.duration).toInt()) }; Playing.changed() }
    val fraction: Double get() = player?.let { p -> runCatching { p.currentPosition.toDouble() / maxOf(1, p.duration) }.getOrNull() } ?: 0.0
    fun stop() {
        val had = player != null
        player?.runCatching { stop(); release() }
        player = null; playing = null; paused = false; progress = null
        disarmProximity()
        onStop?.invoke(); onStop = null
        // the track that stepped aside for the voice plays on from its place (iOS noteClosed, 26.09)
        if (musicAside) { musicAside = false; if (!MusicPlayer.playing) MusicPlayer.resume() }
        if (had) Playing.changed()
    }

    // ── THE EAR (iOS armProximity/disarmProximity/routeVoice, MontanaMedia.swift:454-479, and the category's own default and
    // override, ContentView.swift:3233-3249 MontanaAudioSession.playVoice / 3269-3278 routeVoice, at build 2155): the receiver
    // is where a voice lands untouched; the proximity sensor's own word is the only thing that lifts it onto the loudspeaker,
    // and only while the phone is away from the ear.
    private fun am() = Book.ctx.getSystemService(AudioManager::class.java)
    private var sensorMgr: SensorManager? = null
    private var proximitySensor: Sensor? = null
    private var earWake: PowerManager.WakeLock? = null
    private var proximityArmed = false
    private val outsidePorts = setOf(AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_HEARING_AID,
        AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER)
    // the headset holds the sound, not the sensor (iOS MontanaAudioRoute.isExternal, MontanaMedia.swift:476)
    private fun externalOutput() = runCatching { am()?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.any { it.type in outsidePorts } == true }.getOrDefault(false)
    private val proximityListener = object : SensorEventListener {
        @Suppress("DEPRECATION")
        override fun onSensorChanged(e: SensorEvent) {
            val near = e.values.isNotEmpty() && e.values[0] < maxOf(1f, proximitySensor?.maximumRange ?: 5f)
            am()?.isSpeakerphoneOn = !near   // the loudspeaker is lifted at the ear (iOS routeVoice, ContentView.swift:3274-3276)
        }
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }
    @Suppress("DEPRECATION")
    private fun armProximity() {
        if (proximityArmed || externalOutput()) return
        proximityArmed = true
        am()?.isSpeakerphoneOn = false   // the receiver is the category's own default (iOS ContentView.swift:3244: no .defaultToSpeaker)
        val sm = Book.ctx.getSystemService(SensorManager::class.java) ?: return
        val sensor = sm.getDefaultSensor(Sensor.TYPE_PROXIMITY) ?: return
        sensorMgr = sm; proximitySensor = sensor
        sm.registerListener(proximityListener, sensor, SensorManager.SENSOR_DELAY_UI)
        val pm = Book.ctx.getSystemService(PowerManager::class.java)
        if (pm?.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK) == true)
            earWake = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "montana:voice-ear").apply { setReferenceCounted(false); acquire() }
    }
    @Suppress("DEPRECATION")
    private fun disarmProximity() {
        if (!proximityArmed) return
        proximityArmed = false
        sensorMgr?.unregisterListener(proximityListener)
        sensorMgr = null; proximitySensor = null
        earWake?.takeIf { it.isHeld }?.release(); earWake = null
        am()?.isSpeakerphoneOn = false
    }
}

/**
 * A VOICE MESSAGE IS A CAPSULE OF OUR LETTERS' GLASS (iOS voiceCapsuleBubble, MontanaBubble 948-1069 at build 2155; the author's
 * words 28.09): the letter's own fill and rim at the call bubble's height (rowPlate 54) in the shape of a capsule; in it the play
 * glyph on the round of glass (40, MTVoiceRound), the voice's wave as long as the voice — 60 points and 8 a second, never under 76
 * nor past four fifths of the window less 111 — in 2-point lines at a 4-point pitch, light blue on one's own and white on theirs,
 * whole at rest and filling while it plays; its length, the place while it plays. A tap anywhere on the capsule plays and rests it;
 * the finger on the wave takes the place. Under it the microphone with the length and the stamp stand on their quiet pills
 * (MTVoicePill, letterBubble).
 */
fun voiceBody(c: Context, m: Msg, du: Double, into: LinearLayout, wave: FloatArray? = null, chat: Chat? = null) {
    val tint = BubbleStyle.text(m.mine)
    val path = m.file?.takeIf { File(it).exists() }
    fun fmt(ms: Int) = "%d:%02d".format(ms / 60000, (ms / 1000) % 60)
    // The length is the sender's word; a letter without it is measured from the file itself.
    val total = if (du > 0) (du * 1000).toInt() else path?.let { p ->
        runCatching { android.media.MediaMetadataRetriever().use { r -> r.setDataSource(p); r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toInt() } }.getOrNull()
    } ?: 0
    val d = c.resources.displayMetrics.density
    val window = c.resources.displayMetrics.widthPixels / d
    val waveDp = minOf(maxOf(76f, window * 0.8f - 111f), maxOf(76f, 60f + total / 1000f * 8f))
    val ink = if (m.mine) Color.rgb(158, 222, 255) else Color.WHITE   // iOS (0.62, 0.87, 1.0) on one's own, white on theirs
    val time = c.text(fmt(total), 13f, MT.withAlpha(BubbleStyle.text(m.mine), 0.85f)).apply { fontFeatureSettings = "tnum" }
    val bar = WaveView(c).apply {
        bars = resampleWave(wave, maxOf(8, (waveDp / 4).toInt()))
        barDp = 2f
        played = ink; rest = MT.withAlpha(ink, if (VoicePlayer.playing == path && path != null) 0.4f else 0.9f)
    }
    val mark = ImageView(c).apply {
        setImageResource(if (VoicePlayer.sounding(path)) R.drawable.ic_pause_fill else R.drawable.ic_play_fill)
        imageTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
        background = c.voiceRoundPlate()   // the round of glass with the quiet prism sheen (iOS MTVoiceRound)
        setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12))
        alpha = if (path == null) 0.4f else 1f
    }
    mark.setOnClickListener {
        // automatic download off, a voice of theirs waits: the play key asks for it (iOS: a tap starts the queued download)
        val p = path ?: run { if (Media.waiting(c, m)) Media.tapped(c, m); return@setOnClickListener }
        // USER-DATA: whose voice it is, as the one bar names it (iOS nowSender)
        val who = if (m.mine) Prefs.userName.trim() else chat?.shown.orEmpty()
        VoicePlayer.toggle(p, onProgress = { cur, dur -> bar.progress = cur.toFloat() / maxOf(1, dur); time.text = fmt(cur) },
            stopped = { mark.setImageResource(R.drawable.ic_play_fill); bar.progress = 0f; bar.rest = MT.withAlpha(ink, 0.9f); time.text = fmt(total) }, sender = who)
        bar.rest = MT.withAlpha(ink, 0.4f)
        mark.setImageResource(if (VoicePlayer.sounding(p)) R.drawable.ic_pause_fill else R.drawable.ic_play_fill)
        // their voice played here: its sender is told once, silently (iOS notePlayed) — the road to their «Listened»
        if (!m.mine && VoicePlayer.playing == p) Thread { Post.notePlayed(m.mid) }.start()
    }
    // THE FINGER'S PLACE STARTS THE VOICE (iOS onSeek, MontanaBubble.swift:844 at build 2155, atom 5cc9cb3879cf): already
    // sounding, the touch only seeks it; at rest, the chosen place starts it -- no place is left waiting for the round's button.
    bar.onSeek = { f ->
        if (path != null) {
            val to = (f * total).toInt()
            if (VoicePlayer.sounding(path)) VoicePlayer.seek(path, to) else { mark.performClick(); VoicePlayer.seek(path, to) }
        }
    }
    // the bar rests and plays this voice too: the play mark follows what the one player does (iOS: the bubble reads the one player)
    val follow: () -> Unit = {
        mark.setImageResource(if (VoicePlayer.sounding(path)) R.drawable.ic_pause_fill else R.drawable.ic_play_fill)
        val chosen = path != null && VoicePlayer.playing == path
        val want = MT.withAlpha(ink, if (chosen) 0.4f else 0.9f)
        if (bar.rest != want) bar.rest = want
    }
    mark.addOnAttachStateChangeListener(object : android.view.View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: android.view.View) { Playing.listen(follow) }
        override fun onViewDetachedFromWindow(v: android.view.View) { Playing.unlisten(follow) }
    })
    // the capsule: the letter's own plate is laid down and the capsule wears it, the pills stand under it on the feed
    into.background = null
    into.setPadding(0, 0, 0, 0)
    into.addView(c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        background = BubbleStyle.capsule(c, m.mine)
        minimumHeight = c.dp(54)
        setPadding(c.dp(8), 0, c.dp(14), 0)
        addView(android.widget.FrameLayout(c).apply { addView(mark, android.widget.FrameLayout.LayoutParams(c.dp(40), c.dp(40), Gravity.CENTER)) }, lp(c.dp(44), c.dp(44)))
        addView(if (path == null) android.widget.ProgressBar(c).apply { isIndeterminate = true } else bar,
            lp(if (path == null) c.dp(28) else c.dp(waveDp.toInt()), WRAP).apply { marginStart = c.dp(3) })
        addView(time, lp(WRAP, WRAP).apply { marginStart = c.dp(8) })
        setOnClickListener { mark.performClick() }   // the whole capsule plays (iOS primaryTap: «a tap anywhere on the bubble»)
    }, LinearLayout.LayoutParams(WRAP, WRAP))
}


/**
 * THE WAVE (iOS MTVoiceBubble's lines / the recorder's swell): one rounded line per slot. Played — the lines behind the
 * progress in the letter's own colour; `live` — the newest lines of a tape still being spoken, each as tall as its loudness.
 */
class WaveView(c: Context) : View(c) {
    var bars = FloatArray(0); set(v) { field = v; invalidate() }
    var progress = 0f; set(v) { field = v; invalidate() }
    var played = Color.WHITE
    var rest = Color.GRAY; set(v) { field = v; invalidate() }
    var barDp = 3f   // the line's width; the capsule's wave draws 2 at a 4-point pitch (iOS 1044)
    var onSeek: ((Float) -> Unit)? = null
    private var live: ArrayList<Float>? = null
    private var peak = 4000f / 32767   // iOS referenceFull: −18 dBFS is the whole height
    private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { strokeCap = android.graphics.Paint.Cap.ROUND }

    /** The swell of a tape being spoken: each new loudness pushes a line in from the right. */
    fun push(a: Float) {
        val l = live ?: ArrayList<Float>().also { live = it }
        l.add(a); peak = maxOf(peak, a)
        val room = maxOf(1, width / (dp(3) + dp(2)))
        while (l.size > room) l.removeAt(0)
        invalidate()
    }

    override fun onTouchEvent(e: android.view.MotionEvent): Boolean {
        val s = onSeek ?: return false
        if (e.actionMasked == android.view.MotionEvent.ACTION_DOWN || e.actionMasked == android.view.MotionEvent.ACTION_MOVE) {
            parent?.requestDisallowInterceptTouchEvent(true)
            s((e.x / width).coerceIn(0f, 1f))
        }
        return true
    }

    override fun onMeasure(w: Int, h: Int) = setMeasuredDimension(MeasureSpec.getSize(w), dp(28))

    override fun onDraw(canvas: android.graphics.Canvas) {
        val w = barDp * resources.displayMetrics.density; val gap = dp(2).toFloat()
        paint.strokeWidth = w
        val mid = height / 2f; val maxH = height - w
        val l = live
        if (l != null) {
            paint.color = played
            var x = width - w / 2
            for (i in l.indices.reversed()) {
                val h = maxOf(w, minOf(1f, l[i] / peak) * maxH)
                canvas.drawLine(x, mid - h / 2 + w / 2, x, mid + h / 2 - w / 2, paint)
                x -= w + gap; if (x < 0) break
            }
            return
        }
        if (bars.isEmpty()) return
        val step = width.toFloat() / bars.size
        bars.forEachIndexed { i, v ->
            val x = i * step + step / 2
            paint.color = if ((i + 0.5f) / bars.size <= progress) played else rest
            val h = maxOf(w, v * maxH)
            canvas.drawLine(x, mid - h / 2 + w / 2, x, mid + h / 2 - w / 2, paint)
        }
        paint.strokeWidth = minOf(w, step * 0.6f)
    }
}

/** The voice's samples as the capsule's lines: each line the loudest of its share of the samples; a flat quiet line with none. */
fun resampleWave(src: FloatArray?, n: Int): FloatArray {
    if (src == null || src.isEmpty()) return FloatArray(n) { 0.25f }
    return FloatArray(n) { i ->
        val a = i * src.size / n
        val b = maxOf(a + 1, (i + 1) * src.size / n)
        var top = 0f
        for (j in a until minOf(b, src.size)) top = maxOf(top, src[j])
        top
    }
}
