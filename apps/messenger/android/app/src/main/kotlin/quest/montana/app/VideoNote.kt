package quest.montana.app

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewOutlineProvider
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * THE ROUND VIDEO NOTE (iOS MontanaVideoNoteCamera): «a square with the circle baked in» — every frame turned upright, cut to
 * its centre square, the 400-point circle drawn over a darkened copy of itself in a 480 file (iOS side 400 / square 480),
 * the front camera a mirror (as the platform hands it, as iOS records it),
 * H.264 at the chosen quality (iOS MontanaNoteQuality: 0.9 / 1.5 / 2.5 Mbit/s), the voice in AAC; the preview IS the file —
 * the one drawing goes to the screen and to the encoder. A tap on the window turns the camera; 6:39 at most (iOS maxSeconds).
 * The platform's own pieces only: Camera2, OpenGL ES, MediaCodec, MediaMuxer, AudioRecord.
 */
class NoteRecorder(private val c: Context, private val preview: TextureView) {
    companion object {
        const val SQUARE = 480
        const val CIRCLE = 400
        const val MAX_SECONDS = 399.0
        fun bitRate() = when (Prefs.str("noteQuality", "medium")) { "low" -> 900_000; "high" -> 2_500_000; else -> 1_500_000 }
        const val INNER = 144        // iOS inner: the badge on the big circle's rim, in file pixels
        /** The badge's centre from the canvas's middle (iOS reach: (side/2 + inner/6)/√2), bottom-right (iOS corner 3). */
        val REACH = ((CIRCLE / 2f + INNER / 6f) / Math.sqrt(2.0)).toFloat()
        /**
         * BOTH CAMERAS AT ONCE, where the hardware runs them (iOS AVCaptureMultiCamSession.isMultiCamSupported): the platform's
         * own list of camera sets that may stream together; the pair is a back and a front camera of one set. null — one camera.
         */
        fun dualPair(c: Context): Pair<String, String>? {
            if (android.os.Build.VERSION.SDK_INT < 30) return null
            val cm = c.getSystemService(CameraManager::class.java) ?: return null
            return runCatching {
                cm.concurrentCameraIds.firstNotNullOfOrNull { set ->
                    val back = set.firstOrNull { cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK }
                    val front = set.firstOrNull { cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT }
                    if (back != null && front != null) back to front else null
                }
            }.getOrNull()
        }
    }

    private val gl = HandlerThread("montana-note").apply { start() }
    private val h = Handler(gl.looper)
    private var egl: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var ctx: EGLContext = EGL14.EGL_NO_CONTEXT
    private var cfg: EGLConfig? = null
    private var encSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var viewSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var dummy: EGLSurface = EGL14.EGL_NO_SURFACE
    private var tex = 0
    private var program = 0
    private var camTexture: SurfaceTexture? = null
    private var cam: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var front = true
    private val mtx = FloatArray(16)
    // THE SECOND CAMERA (iOS dual): its own texture, its latest frame latched as it lands; the big circle composes both
    private var tex2 = 0
    private var camTexture2: SurfaceTexture? = null
    private var cam2: CameraDevice? = null
    private var session2: CameraCaptureSession? = null
    private val mtx2 = FloatArray(16)
    @Volatile private var badgeReady = false
    /** Both cameras: the back fills the circle, the front sits in the badge; a flip swaps them (iOS toggleDual, 18.09). */
    @Volatile var dual = false; private set
    @Volatile private var swapped = false

    // ── THE BADGE UNDER THE FINGER (iOS dragBadge / dragEnded / easeBadge, MontanaFeeds 1811-1831): dragged within its square,
    // it eases to the nearest corner on the rim when let go — a third of the way each frame — and the corner is remembered
    // between notes (iOS «vnoteCorner»). The offset is from the canvas's middle, in file pixels, y down ──
    private var corner = Prefs.str("vnoteCorner", "3").toIntOrNull()?.takeIf { it in 0..3 } ?: 3
    @Volatile private var bx = cornerX(corner)
    @Volatile private var by = cornerY(corner)
    @Volatile private var target: Pair<Float, Float>? = null
    private var grabX = 0f
    private var grabY = 0f
    private fun cornerX(k: Int) = (if (k % 2 == 0) -1 else 1) * REACH
    private fun cornerY(k: Int) = (if (k < 2) -1 else 1) * REACH

    /** A point of the canvas (from its middle, in file pixels) stands on the badge. */
    fun onBadge(x: Float, y: Float): Boolean = dual && (x - bx) * (x - bx) + (y - by) * (y - by) <= (INNER / 2f) * (INNER / 2f)
    fun grabBadge() { grabX = bx; grabY = by; target = null }
    fun dragBadge(dx: Float, dy: Float) {
        bx = (grabX + dx).coerceIn(-REACH, REACH)
        by = (grabY + dy).coerceIn(-REACH, REACH)
        target = null
    }
    fun dropBadge() {
        val k = (if (bx > 0) 1 else 0) + (if (by > 0) 2 else 0)
        corner = k
        Prefs.setStr("vnoteCorner", k.toString())
        target = cornerX(k) to cornerY(k)
    }
    private fun easeBadge() {
        val t = target ?: return
        val dx = t.first - bx; val dy = t.second - by
        if (kotlin.math.abs(dx) < 0.5f && kotlin.math.abs(dy) < 0.5f) { bx = t.first; by = t.second; target = null }
        else { bx += dx * 0.35f; by += dy * 0.35f }
    }

    private var video: MediaCodec? = null
    private var audio: MediaCodec? = null
    private var record: AudioRecord? = null
    private var muxer: MediaMuxer? = null
    private var vTrack = -1; private var aTrack = -1
    private var muxing = false
    private val muxLock = Any()
    private var startNs = 0L
    @Volatile private var running = false
    private var audioThread: Thread? = null
    lateinit var file: File; private set
    val elapsed: Double get() = if (startNs == 0L) 0.0 else (clock()) / 1e9

    /**
     * THE PAUSE (iOS MontanaVideoNoteCamera.togglePause): while it stands no frame and no sound is written, and the file's
     * clock skips it — no frozen stretch inside; the window still shows the camera.
     */
    @Volatile var paused = false; private set
    private var pauseAt = 0L
    @Volatile private var pausedNs = 0L
    /** The file's clock: the time since the start less every pause so far. */
    private fun clock(): Long = System.nanoTime() - startNs - pausedNs - (if (paused) System.nanoTime() - pauseAt else 0L)
    fun togglePause() {
        if (!running) return
        if (paused) { pausedNs += System.nanoTime() - pauseAt; paused = false } else { pauseAt = System.nanoTime(); paused = true }
    }

    /** The tape starts: the camera, the encoders and the drawing; false when a piece refused. */
    fun start(): Boolean = try {
        file = File(c.cacheDir, "vnote_${System.currentTimeMillis()}.mp4")
        setupCodecs()
        val ready = java.util.concurrent.CountDownLatch(1)
        var ok = false
        h.post { ok = runCatching { setupGl(); openCamera(); true }.getOrDefault(false); ready.countDown() }
        ready.await()
        if (ok) { running = true; startNs = System.nanoTime(); startAudio() }
        ok
    } catch (_: Exception) { release(); false }

    private fun setupCodecs() {
        fun format(high: MediaCodecInfo.CodecProfileLevel?) = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, SQUARE, SQUARE).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate())
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            if (high != null) { setInteger(MediaFormat.KEY_PROFILE, high.profile); setInteger(MediaFormat.KEY_LEVEL, high.level) }
        }
        // THE PICTURE AT ITS BEST (iOS 1687: H.264 High, CABAC, at the chosen rate): the High profile where this encoder carries it;
        // an encoder that refuses it is laid again with the platform's own profile, as before
        val enc = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val high = runCatching { enc.codecInfo.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).profileLevels
            .firstOrNull { it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh } }.getOrNull()
        runCatching { enc.configure(format(high), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE) }
            .onFailure { enc.reset(); enc.configure(format(null), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE) }
        Log.d("Montana", "vnote_codec profile=" + (if (high != null) "high" else "default"))
        video = enc
        val af = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, 48_000, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 64_000)   // the spoken word's own quality (iOS MontanaVoiceSound)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        audio = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply { configure(af, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE) }
        muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    }

    // ── the drawing ──

    private fun setupGl() {
        egl = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val v = IntArray(2); EGL14.eglInitialize(egl, v, 0, v, 1)
        val attrs = intArrayOf(EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, 0x3142 /* EGL_RECORDABLE_ANDROID */, 1, EGL14.EGL_NONE)
        val cs = arrayOfNulls<EGLConfig>(1); val n = IntArray(1)
        EGL14.eglChooseConfig(egl, attrs, 0, cs, 0, 1, n, 0)
        cfg = cs[0]
        ctx = EGL14.eglCreateContext(egl, cfg, EGL14.EGL_NO_CONTEXT, intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
        val vc = video!!
        encSurface = EGL14.eglCreateWindowSurface(egl, cfg, vc.createInputSurface(), intArrayOf(EGL14.EGL_NONE), 0)
        vc.start()
        preview.surfaceTexture?.let { viewSurface = EGL14.eglCreateWindowSurface(egl, cfg, Surface(it), intArrayOf(EGL14.EGL_NONE), 0) }
        EGL14.eglMakeCurrent(egl, encSurface, encSurface, ctx)
        val t = IntArray(2); GLES20.glGenTextures(2, t, 0); tex = t[0]; tex2 = t[1]
        for (x in t) {
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, x)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        }
        camTexture2 = SurfaceTexture(tex2).apply {
            setDefaultBufferSize(1280, 720)
            // the badge camera only leaves its latest frame (iOS lastSmall); the big one composes on its own frames
            setOnFrameAvailableListener({ st -> if (!closing && runCatching { st.updateTexImage() }.isSuccess) { st.getTransformMatrix(mtx2); badgeReady = true } }, h)
        }
        program = link(VS, FS)
        camTexture = SurfaceTexture(tex).apply {
            setDefaultBufferSize(1280, 720)
            setOnFrameAvailableListener({ draw() }, h)
        }
    }

    private val quad: FloatBuffer = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
        put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)); position(0)
    }

    @Volatile private var closing = false
    private fun draw() {
        // A frame the camera sent after the tape ended finds the drawing gone: it is let go, never drawn.
        if (closing || egl == EGL14.EGL_NO_DISPLAY) return
        val st = camTexture ?: return
        if (runCatching { st.updateTexImage() }.isFailure) return
        st.getTransformMatrix(mtx)
        easeBadge()
        fun pass(t: Int, m: FloatArray, badge: Boolean) {
            val pos = GLES20.glGetAttribLocation(program, "aPos")
            GLES20.glEnableVertexAttribArray(pos)
            GLES20.glVertexAttribPointer(pos, 2, GLES20.GL_FLOAT, false, 0, quad)
            GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(program, "uTex"), 1, false, m, 0)
            GLES20.glUniform1f(GLES20.glGetUniformLocation(program, "uCrop"), 720f / 1280f)
            GLES20.glUniform1f(GLES20.glGetUniformLocation(program, "uMirror"), 0f)
            GLES20.glUniform1f(GLES20.glGetUniformLocation(program, "uRadius"), if (badge) 0.5f else CIRCLE / 2f / SQUARE)
            GLES20.glUniform1f(GLES20.glGetUniformLocation(program, "uBadge"), if (badge) 1f else 0f)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, t)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }
        fun paint(s: EGLSurface, w: Int, hh: Int) {
            EGL14.eglMakeCurrent(egl, s, s, ctx)
            GLES20.glViewport(0, 0, w, hh)
            GLES20.glUseProgram(program)
            if (dual && badgeReady) {
                // THE RING ON A RING (iOS nested): the big camera's circle, then the badge nested in its rim, where the finger left it
                val big = if (swapped) tex2 else tex; val bigM = if (swapped) mtx2 else mtx
                val small = if (swapped) tex else tex2; val smallM = if (swapped) mtx else mtx2
                pass(big, bigM, false)
                val k = w / SQUARE.toFloat()
                val cx = SQUARE / 2f + bx; val cy = SQUARE / 2f + by   // y down, as iOS says the offset
                val side = (INNER * k).toInt()
                GLES20.glViewport(((cx - INNER / 2f) * k).toInt(), ((SQUARE - cy - INNER / 2f) * k).toInt(), side, side)
                GLES20.glEnable(GLES20.GL_BLEND); GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
                pass(small, smallM, true)
                GLES20.glDisable(GLES20.GL_BLEND)
                return
            }
            val pos = GLES20.glGetAttribLocation(program, "aPos")
            GLES20.glEnableVertexAttribArray(pos)
            GLES20.glVertexAttribPointer(pos, 2, GLES20.GL_FLOAT, false, 0, quad)
            GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(program, "uTex"), 1, false, mtx, 0)
            // The upright frame is 9:16; its centre square spans 9/16 of its height.
            GLES20.glUniform1f(GLES20.glGetUniformLocation(program, "uCrop"), 720f / 1280f)
            // THE FRONT CAMERA IS A MIRROR, as iOS keeps it (orient(mirrored: pos == .front)): the platform already hands the
            // front camera's frames mirrored to a SurfaceTexture, so a second turn here made the picture go the other way.
            GLES20.glUniform1f(GLES20.glGetUniformLocation(program, "uMirror"), 0f)
            GLES20.glUniform1f(GLES20.glGetUniformLocation(program, "uRadius"), CIRCLE / 2f / SQUARE)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }
        if (viewSurface != EGL14.EGL_NO_SURFACE) { paint(viewSurface, preview.width, preview.height); EGL14.eglSwapBuffers(egl, viewSurface) }
        if (running && !paused) {
            paint(encSurface, SQUARE, SQUARE)
            EGLExt.eglPresentationTimeANDROID(egl, encSurface, clock())
            EGL14.eglSwapBuffers(egl, encSurface)
            drain(video!!, false, isVideo = true)
            if (elapsed >= MAX_SECONDS) onMax?.invoke()
        }
    }
    var onMax: (() -> Unit)? = null

    private fun link(vs: String, fs: String): Int {
        fun sh(type: Int, src: String) = GLES20.glCreateShader(type).also { GLES20.glShaderSource(it, src); GLES20.glCompileShader(it) }
        return GLES20.glCreateProgram().also { p ->
            GLES20.glAttachShader(p, sh(GLES20.GL_VERTEX_SHADER, vs)); GLES20.glAttachShader(p, sh(GLES20.GL_FRAGMENT_SHADER, fs)); GLES20.glLinkProgram(p)
        }
    }

    // ── the camera ──

    private fun openCamera() {
        val cm = c.getSystemService(CameraManager::class.java)
        val want = if (front) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
        val id = cm.cameraIdList.firstOrNull { cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == want } ?: cm.cameraIdList.first()
        openInto(id, camTexture!!, { cam = it }, { session = it })
    }

    /** One camera streaming into one texture (the big one's, or the badge's). */
    @SuppressLint("MissingPermission")
    private fun openInto(id: String, st: SurfaceTexture, keepCam: (CameraDevice) -> Unit, keepSession: (CameraCaptureSession) -> Unit) {
        val cm = c.getSystemService(CameraManager::class.java)
        val out = Surface(st)
        cm.openCamera(id, object : CameraDevice.StateCallback() {
            override fun onOpened(d: CameraDevice) {
                if (closing) { d.close(); return }
                keepCam(d)
                @Suppress("DEPRECATION")
                d.createCaptureSession(listOf(out), object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(s: CameraCaptureSession) {
                        keepSession(s)
                        runCatching {
                            s.setRepeatingRequest(d.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                                addTarget(out); set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                            }.build(), null, h)
                        }
                    }
                    override fun onConfigureFailed(s: CameraCaptureSession) {}
                }, h)
            }
            override fun onDisconnected(d: CameraDevice) { d.close() }
            override fun onError(d: CameraDevice, e: Int) { d.close() }
        }, h)
    }

    /** The other camera; the tape runs on through the turn (iOS flip). With both on, the flip swaps the circle and the badge. */
    fun flip() = h.post {
        if (dual) { swapped = !swapped; return@post }
        runCatching { session?.close() }; runCatching { cam?.close() }
        front = !front
        openCamera()
    }

    /**
     * BOTH CAMERAS (iOS toggleDual): on — the back camera fills the circle and the front one sits in the badge (a set the
     * platform lets stream together); off — the badge's camera closes and the circle's stays. The tape runs on through it.
     */
    fun toggleDual() = h.post {
        if (dual) {
            dual = false; badgeReady = false
            runCatching { session2?.close() }; runCatching { cam2?.close() }; session2 = null; cam2 = null
            if (swapped) { swapped = false; front = true; runCatching { session?.close() }; runCatching { cam?.close() }; openCamera() }
            return@post
        }
        val (back, frontId) = dualPair(c) ?: return@post
        runCatching { session?.close() }; runCatching { cam?.close() }
        front = false; swapped = false
        openInto(back, camTexture!!, { cam = it }, { session = it })
        openInto(frontId, camTexture2!!, { cam2 = it }, { session2 = it })
        dual = true
    }

    // ── the voice ──

    @SuppressLint("MissingPermission")
    private fun startAudio() {
        val min = AudioRecord.getMinBufferSize(48_000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val r = AudioRecord(MediaRecorder.AudioSource.MIC, 48_000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, 8192))
        record = r
        val ac = audio!!
        ac.start(); r.startRecording()
        audioThread = Thread {
            val buf = ByteArray(4096)
            var samples = 0L
            while (true) {
                val n = r.read(buf, 0, buf.size)
                val stop = !running
                if (paused && !stop) { drain(ac, false, isVideo = false); continue }   // the paused sound is heard and let go
                val i = ac.dequeueInputBuffer(10_000)
                if (i >= 0) {
                    val ib = ac.getInputBuffer(i)!!
                    ib.clear()
                    val len = if (n > 0) minOf(n, ib.remaining()) else 0
                    ib.put(buf, 0, len)
                    val pts = samples * 1_000_000L / 48_000
                    ac.queueInputBuffer(i, 0, len, pts, if (stop) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                    samples += len / 2
                }
                drain(ac, stop, isVideo = false)
                if (stop) break
            }
        }.apply { start() }
    }

    // ── the file ──

    private fun drain(codec: MediaCodec, eos: Boolean, isVideo: Boolean) {
        val info = MediaCodec.BufferInfo()
        while (true) {
            val o = codec.dequeueOutputBuffer(info, if (eos) 10_000 else 0)
            if (o == MediaCodec.INFO_TRY_AGAIN_LATER) { if (!eos) return else continue }
            if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                synchronized(muxLock) {
                    val m = muxer ?: return
                    if (isVideo) vTrack = m.addTrack(codec.outputFormat) else aTrack = m.addTrack(codec.outputFormat)
                    if (vTrack >= 0 && aTrack >= 0 && !muxing) { m.start(); muxing = true }
                }
                continue
            }
            if (o < 0) continue
            val ob = codec.getOutputBuffer(o)!!
            if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
            synchronized(muxLock) {
                if (muxing && info.size > 0) { ob.position(info.offset); ob.limit(info.offset + info.size); muxer?.writeSampleData(if (isVideo) vTrack else aTrack, ob, info) }
            }
            codec.releaseOutputBuffer(o, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
        }
    }

    /** The tape ends: the file and its length, or null when dropped, too short, or nothing was written. */
    fun stop(keep: Boolean): Pair<File, Double>? {
        if (!running) { release(); return null }
        val secs = elapsed
        running = false
        runCatching { audioThread?.join(3000) }
        val done = java.util.concurrent.CountDownLatch(1)
        h.post {
            runCatching { video?.signalEndOfInputStream(); drain(video!!, true, isVideo = true) }
            // THE FILE IS CLOSED BEFORE IT IS HANDED ON: the muxer writes its index (moov) at stop, and a file read before
            // that is a heap of samples no player opens.
            synchronized(muxLock) { runCatching { if (muxing) muxer?.stop() }; runCatching { muxer?.release() }; muxer = null }
            done.countDown()
        }
        done.await(5, java.util.concurrent.TimeUnit.SECONDS)
        val wrote = synchronized(muxLock) { muxing.also { muxing = false } }
        release()
        if (!keep || !wrote || secs < 1.0 || !file.exists()) { runCatching { file.delete() }; return null }
        return file to secs
    }

    private fun release() {
        closing = true
        runCatching { record?.stop() }; runCatching { record?.release() }; record = null
        runCatching { audio?.stop() }; runCatching { audio?.release() }; audio = null
        h.post {
            runCatching { session?.close() }; runCatching { cam?.close() }
            runCatching { session2?.close() }; runCatching { cam2?.close() }
            camTexture?.setOnFrameAvailableListener(null); camTexture2?.setOnFrameAvailableListener(null)
            runCatching { video?.stop() }; runCatching { video?.release() }; video = null
            synchronized(muxLock) { runCatching { if (muxing) muxer?.stop() }; runCatching { muxer?.release() }; muxer = null; muxing = false }
            runCatching { camTexture?.release() }; runCatching { camTexture2?.release() }
            if (egl != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglMakeCurrent(egl, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                for (s in listOf(encSurface, viewSurface, dummy)) if (s != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(egl, s)
                EGL14.eglDestroyContext(egl, ctx); EGL14.eglTerminate(egl)
                egl = EGL14.EGL_NO_DISPLAY
            }
            gl.quitSafely()
        }
    }

    private val VS = """
        attribute vec2 aPos;
        varying vec2 vUv;
        void main() { vUv = aPos * 0.5 + 0.5; gl_Position = vec4(aPos, 0.0, 1.0); }
    """.trimIndent()

    // The centre square of the upright frame; the circle live, outside it the same picture darkened (iOS: over its own copy).
    private val FS = """
        #extension GL_OES_EGL_image_external : require
        precision mediump float;
        varying vec2 vUv;
        uniform samplerExternalOES sTex;
        uniform mat4 uTex;
        uniform float uCrop;
        uniform float uMirror;
        uniform float uRadius;
        uniform float uBadge;
        void main() {
            vec2 q = vUv;
            if (uMirror > 0.5) q.x = 1.0 - q.x;
            vec2 src = vec2(q.x, 0.5 + (q.y - 0.5) * uCrop);
            vec4 col = texture2D(sTex, (uTex * vec4(src, 0.0, 1.0)).xy);
            float d = distance(vUv, vec2(0.5));
            float edge = smoothstep(uRadius, uRadius - 0.004, d);
            if (uBadge > 0.5) {
                // the badge: its own circle over the big one, a light rim around it, nothing outside
                float rim = smoothstep(uRadius - 0.05, uRadius - 0.04, d);
                gl_FragColor = vec4(mix(col.rgb, vec3(1.0), rim * 0.85), edge);
            } else {
                gl_FragColor = mix(vec4(col.rgb * 0.28, 1.0), col, edge);
            }
        }
    """.trimIndent()
}

/** THE NOTE'S RING (iOS MontanaNoteRing): the minute's progress around the window. */
class NoteRing(c: Context) : View(c) {
    var progress = 0f; set(v) { field = v; invalidate() }
    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = Color.argb(70, 255, 255, 255) }
    private val bar = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = Color.WHITE; strokeCap = Paint.Cap.ROUND }
    override fun onDraw(canvas: Canvas) {
        val w = dp(4).toFloat(); track.strokeWidth = w; bar.strokeWidth = w
        val r = RectF(w, w, width - w, height - w)
        canvas.drawOval(r, track)
        canvas.drawArc(r, -90f, 360f * progress.coerceIn(0f, 1f), false, bar)
    }
}

/** A view cut round (the note's window and the bubble's circle). */
fun View.round(): View = apply {
    outlineProvider = object : ViewOutlineProvider() { override fun getOutline(v: View, o: Outline) = o.setOval(0, 0, v.width, v.height) }
    clipToOutline = true
}
