package quest.montana.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * THE VOICE READ AS TEXT, ON THIS PHONE (iOS MTVoiceTranscript, b2fe4814 at 2315; the author's word 21.10.2026 09:15 UTC: «voice
 * transcription natively, by the system»). The system's own recogniser on the device (SpeechRecognizer.createOnDeviceSpeechRecognizer,
 * Android 13+) hears the voice's own file: the file is opened by the system's decoder (MediaCodec) into 16 kHz mono PCM and poured
 * into the recogniser through a pipe (EXTRA_AUDIO_SOURCE), with punctuation and the chat's names and frequent words as context.
 * ON THE DEVICE ONLY: a server recogniser would carry a private voice to a third party -- a phone that cannot read the language on
 * itself says so and sends nothing. The words live in memory beside the voice's file (a file never changes while the letter lives)
 * and die with the process: a deleted chat leaves no text of its voices on disk. One owner: the bubble asks, this reads and answers.
 */
object VoiceText {
    sealed class Reading {
        object Working : Reading()
        class Text(val words: String) : Reading()
        object Silent : Reading()        // the recogniser heard no words
        object Refused : Reading()       // the person said no to the microphone the recogniser needs
        object Unsupported : Reading()   // this phone cannot read this language on itself
    }

    private const val KEPT = 400   // BOUND-OK: the readings of one run, the oldest goes first (iOS kept)
    private const val RATE = 16000
    private val readings = LinkedHashMap<String, Reading>()
    /** The voices whose words stand open under their capsule (iOS transcriptOpen, held here: our feed builds its bubbles again). */
    val open = HashSet<String>()
    private val listeners = ArrayList<() -> Unit>()
    private val main = Handler(Looper.getMainLooper())

    fun reading(file: String): Reading? = readings[file]
    fun listen(f: () -> Unit) { listeners.add(f) }
    fun unlisten(f: () -> Unit) { listeners.remove(f) }
    private fun told() { listeners.toList().forEach { it() } }

    /** The glyph is drawn only where a reading can happen on the device at all. */
    private var can: Boolean? = null
    fun canRead(c: Context): Boolean = can ?: (Build.VERSION.SDK_INT >= 33 &&
        runCatching { SpeechRecognizer.isOnDeviceRecognitionAvailable(c.applicationContext) }.getOrDefault(false)).also { can = it }

    /** A touch on the glyph: open reads the voice once, a second touch folds the words (iOS transcriptGlyph). */
    fun toggle(c: Context, file: String, hints: () -> List<String>) {
        if (!open.add(file)) { open.remove(file); told(); return }
        read(c, file, hints())
        told()
    }

    /** Reads the voice once; a finished text is kept, a reading that failed is tried again on the next ask. */
    fun read(c: Context, file: String, hints: List<String>) {
        when (readings[file]) { Reading.Working, is Reading.Text -> return; else -> {} }
        if (Build.VERSION.SDK_INT < 33) return keep(file, Reading.Unsupported, 0, hints.size)
        keep(file, Reading.Working, -1, 0)
        val started = System.currentTimeMillis()
        val go = { allowed: Boolean ->
            if (!allowed) keep(file, Reading.Refused, started, hints.size)
            else Thread {
                val pcm = runCatching { decode(file) }.getOrNull()
                main.post {
                    if (pcm == null || pcm.isEmpty()) keep(file, Reading.Silent, started, hints.size)
                    // a system that will not give its recogniser after all says so in a word, never by falling
                    else runCatching { recognise(c.applicationContext, pcm, hints) { keep(file, it, started, hints.size) } }
                        .onFailure { keep(file, Reading.Unsupported, started, hints.size) }
                }
            }.apply { name = "voice-text" }.start()
        }
        if (c.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) go(true)
        else (c as? MainActivity)?.askMic { go(it) } ?: go(false)
    }

    private fun keep(file: String, r: Reading, started: Long, hints: Int) {
        readings.remove(file)
        readings[file] = r
        while (readings.size > KEPT) readings.remove(readings.keys.first())
        // never the words themselves: the diary leaves the phone
        if (started >= 0) Log.i("Montana", "voice_text " + word(r) + " ms=" + (System.currentTimeMillis() - started) + " hints=" + hints)
        told()
    }

    private fun word(r: Reading) = when (r) {
        Reading.Working -> "working"
        is Reading.Text -> "text chars=" + r.words.length
        Reading.Silent -> "silent"
        Reading.Refused -> "refused"
        Reading.Unsupported -> "unsupported"
    }

    /** The context the recogniser is given: the people's names, whole and by word, then the chat's own frequent words -- at most a
     *  hundred, as the platform advises (iOS hints). */
    fun hints(names: List<String>, texts: List<String>): List<String> {
        val out = ArrayList<String>()
        val seen = HashSet<String>()
        fun put(w: String) { val k = w.lowercase(); if (k.isNotEmpty() && seen.add(k)) out.add(w) }
        val apart = Regex("[^\\p{L}]+")
        for (n in names) {
            val whole = n.trim()
            put(whole)
            for (part in whole.split(apart)) if (part.length >= 2) put(part)
        }
        val count = HashMap<String, Int>()
        for (t in texts.takeLast(500)) if (t.isNotEmpty() && !t.startsWith(Marks.MEDIA))
            for (w in t.split(apart)) if (w.length >= 4) count.merge(w.lowercase(), 1, Int::plus)
        val frequent = count.filter { it.value >= 2 }.entries.sortedWith(compareBy({ -it.value }, { it.key }))
        for (e in frequent) { if (out.size >= 100) break; put(e.key) }
        return out.take(100)
    }

    /** The voice's file through the system's decoder: 16-bit PCM, its channels folded into one, at 16 kHz. */
    private fun decode(file: String): ByteArray? {
        val ex = MediaExtractor()
        try {
            ex.setDataSource(file)
            val track = (0 until ex.trackCount).firstOrNull { ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true } ?: return null
            ex.selectTrack(track)
            val fmt = ex.getTrackFormat(track)
            val codec = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(fmt, null, null, 0)
            codec.start()
            var rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val raw = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inDone = false
            try {
                while (true) {
                    if (!inDone) {
                        val i = codec.dequeueInputBuffer(10_000)
                        if (i >= 0) {
                            val n = ex.readSampleData(codec.getInputBuffer(i)!!, 0)
                            if (n < 0) { codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inDone = true }
                            else { codec.queueInputBuffer(i, 0, n, ex.sampleTime, 0); ex.advance() }
                        }
                    }
                    val o = codec.dequeueOutputBuffer(info, 10_000)
                    if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        codec.outputFormat.let { rate = it.getInteger(MediaFormat.KEY_SAMPLE_RATE); channels = it.getInteger(MediaFormat.KEY_CHANNEL_COUNT) }
                    } else if (o >= 0) {
                        val b = codec.getOutputBuffer(o)!!
                        val chunk = ByteArray(info.size)
                        b.position(info.offset); b.get(chunk)
                        raw.write(chunk)
                        codec.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                }
            } finally { codec.stop(); codec.release() }
            return toMono16k(raw.toByteArray(), rate, maxOf(1, channels))
        } finally { ex.release() }
    }

    private fun toMono16k(pcm: ByteArray, rate: Int, channels: Int): ByteArray {
        val frames = pcm.size / 2 / channels
        fun at(f: Int): Float {
            var sum = 0
            for (ch in 0 until channels) { val i = (f * channels + ch) * 2; sum += (pcm[i].toInt() and 0xFF) or (pcm[i + 1].toInt() shl 8) }
            return sum.toFloat() / channels
        }
        val outFrames = (frames.toLong() * RATE / maxOf(1, rate)).toInt()
        val out = ByteArray(outFrames * 2)
        for (k in 0 until outFrames) {
            val x = k.toDouble() * rate / RATE
            val a = x.toInt().coerceAtMost(frames - 1)
            val b = (a + 1).coerceAtMost(frames - 1)
            val s = (at(a) + (at(b) - at(a)) * (x - a).toFloat()).toInt().coerceIn(-32768, 32767)
            out[2 * k] = s.toByte(); out[2 * k + 1] = (s shr 8).toByte()
        }
        return out
    }

    /** The recogniser on the device, its segments gathered until the source ends; on the screen's thread, as the system asks. */
    private fun recognise(c: Context, pcm: ByteArray, hints: List<String>, done: (Reading) -> Unit) {
        if (Build.VERSION.SDK_INT < 33) return done(Reading.Unsupported)
        val pipe = ParcelFileDescriptor.createPipe()
        val sr = SpeechRecognizer.createOnDeviceSpeechRecognizer(c)
        val heard = StringBuilder()
        var over = false
        val language = c.resources.configuration.locales[0].toLanguageTag()
        val ask = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
            if (hints.isNotEmpty()) putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(hints))
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0])
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, RATE)
            putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
        }
        fun take(b: Bundle?) {
            val t = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim().orEmpty()
            if (t.isNotEmpty()) { if (heard.isNotEmpty()) heard.append(' '); heard.append(t) }
        }
        fun end(r: Reading?) {
            if (over) return
            over = true
            runCatching { pipe[0].close() }
            runCatching { sr.destroy() }
            val words = heard.toString().trim()
            done(r ?: if (words.isEmpty()) Reading.Silent else Reading.Text(words))
        }
        sr.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(p: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(v: Float) {}
            override fun onBufferReceived(b: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(b: Bundle?) {}
            override fun onEvent(t: Int, b: Bundle?) {}
            override fun onSegmentResults(b: Bundle) { take(b) }
            override fun onEndOfSegmentedSession() { end(null) }
            override fun onResults(b: Bundle?) { take(b); end(null) }
            override fun onError(e: Int) {
                Log.i("Montana", "voice_text recogniser error=$e")
                when (e) {
                    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> end(Reading.Unsupported)
                    // the language's model is not on the phone yet: the system is asked to bring it, the next touch reads again
                    SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> { runCatching { sr.triggerModelDownload(ask) }; end(Reading.Unsupported) }
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> end(Reading.Refused)
                    else -> end(if (heard.isEmpty()) Reading.Silent else null)
                }
            }
        })
        sr.startListening(ask)
        // the voice poured into the pipe on its own thread; the pipe's end closed tells the recogniser the voice is over
        Thread {
            runCatching { ParcelFileDescriptor.AutoCloseOutputStream(pipe[1]).use { out -> out.write(pcm) } }
        }.apply { name = "voice-text-pour" }.start()
        // a recogniser that never answers does not leave the glyph turning: the voice's own length and half a minute more
        main.postDelayed({ end(null) }, pcm.size / 2L * 1000 / RATE + 30_000)
    }
}

/** The voice's words under its capsule, in the letter's own fill; what the recogniser could not do, said in a word (iOS
 *  voiceTranscript). It follows the one owner: shown while its voice stands open and the reading is over. */
fun voiceWordsView(c: Context, file: String, mine: Boolean): android.view.View = android.widget.TextView(c).apply {
    textSize = 15f
    maxWidth = c.dp(260)
    setPadding(c.dp(12), c.dp(8), c.dp(12), c.dp(8))
    background = BubbleStyle.plate(c, mine, 16)
    val ink = BubbleStyle.text(mine)
    val show = {
        val r = VoiceText.reading(file)
        visibility = if (file in VoiceText.open && r != null && r != VoiceText.Reading.Working) android.view.View.VISIBLE else android.view.View.GONE
        when (r) {
            // USER-DATA: the voice's own words, read on this phone
            is VoiceText.Reading.Text -> { text = r.words; setTextColor(ink); setTextIsSelectable(true) }
            VoiceText.Reading.Refused -> { setText(R.string.voice_text_refused); setTextColor(MT.withAlpha(ink, 0.7f)) }
            VoiceText.Reading.Unsupported -> { setText(R.string.voice_text_unsupported); setTextColor(MT.withAlpha(ink, 0.7f)) }
            else -> { setText(R.string.voice_text_silent); setTextColor(MT.withAlpha(ink, 0.7f)) }
        }
    }
    show()
    addOnAttachStateChangeListener(object : android.view.View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: android.view.View) { show(); VoiceText.listen(show) }
        override fun onViewDetachedFromWindow(v: android.view.View) { VoiceText.unlisten(show) }
    })
}

/** THE QUOTE GLYPH BESIDE THE PLATES (iOS transcriptGlyph): it reads the voice on this phone and lays its words under the capsule; a
 *  second touch folds them. While the reading works, a small turning ring stands in its place. */
fun voiceTextGlyph(c: Context, file: String, hints: () -> List<String>): android.view.View = android.widget.FrameLayout(c).apply {
    val glyph = c.icon(R.drawable.ic_quote_bubble, android.graphics.Color.WHITE, 12)
    val turning = android.widget.ProgressBar(c).apply {
        isIndeterminate = true
        indeterminateTintList = android.content.res.ColorStateList.valueOf(android.graphics.Color.WHITE)
    }
    val plate = android.widget.FrameLayout(c).apply {
        background = android.graphics.drawable.GradientDrawable().apply {
            cornerRadius = c.dp(100).toFloat(); setColor(android.graphics.Color.argb(97, 0, 0, 0)); setStroke(1, android.graphics.Color.argb(46, 255, 255, 255))
        }
        setPadding(c.dp(8), c.dp(3), c.dp(8), c.dp(3))
        addView(glyph, android.widget.FrameLayout.LayoutParams(c.dp(12), c.dp(12), android.view.Gravity.CENTER))
        addView(turning, android.widget.FrameLayout.LayoutParams(c.dp(12), c.dp(12), android.view.Gravity.CENTER))
    }
    // the finger's 44 points around the plate; the row keeps the plates' height
    addView(plate, android.widget.FrameLayout.LayoutParams(android.widget.FrameLayout.LayoutParams.WRAP_CONTENT, android.widget.FrameLayout.LayoutParams.WRAP_CONTENT, android.view.Gravity.CENTER))
    minimumWidth = c.dp(44)
    val show = {
        val working = VoiceText.reading(file) == VoiceText.Reading.Working
        turning.visibility = if (working) android.view.View.VISIBLE else android.view.View.GONE
        glyph.visibility = if (working) android.view.View.INVISIBLE else android.view.View.VISIBLE
        val opened = file in VoiceText.open
        glyph.setImageResource(if (opened) R.drawable.ic_quote_bubble_fill else R.drawable.ic_quote_bubble)
        contentDescription = c.getString(if (opened) R.string.voice_text_hide else R.string.voice_text_read)
    }
    show()
    setOnClickListener { VoiceText.toggle(c, file, hints) }
    addOnAttachStateChangeListener(object : android.view.View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: android.view.View) { show(); VoiceText.listen(show) }
        override fun onViewDetachedFromWindow(v: android.view.View) { VoiceText.unlisten(show) }
    })
}
