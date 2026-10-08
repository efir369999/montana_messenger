package quest.montana.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.WindowInsets
import android.widget.FrameLayout
import android.widget.ImageView
import java.io.File

// ─────────────────────────── the camera of the gallery's first tile (iOS CameraPicker) ───────────────────────────

/**
 * THE CAMERA (iOS CameraPicker: UIImagePickerController .camera with photos and films, MontanaMedia 2923-2958; MontanaConversation
 * 1737-1739): the platform's camera manner — the picture across the screen, «Video» and «Photo» under it, the round shutter, the
 * turn of the camera; what was taken is looked at once and leaves at the checkmark (the system's «Use Photo»), the cross takes it
 * again. Android's own camera app answers a photo or a film, never both from one door — so this page is the camera (Camera2).
 * The answer: the file and whether it is a film.
 */
@SuppressLint("MissingPermission")
fun cameraPage(act: MainActivity, done: (File, Boolean) -> Unit) {
    val c: Context = act
    val cm = c.getSystemService(CameraManager::class.java) ?: return
    val ids = runCatching { cm.cameraIdList.toList() }.getOrDefault(emptyList())
    fun facing(id: String) = runCatching { cm.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) }.getOrNull()
    val back = ids.firstOrNull { facing(it) == CameraCharacteristics.LENS_FACING_BACK } ?: ids.firstOrNull() ?: return
    val front = ids.firstOrNull { facing(it) == CameraCharacteristics.LENS_FACING_FRONT }
    var id = back
    var video = false
    var recording = false
    var startedAt = 0L
    val thread = HandlerThread("montana-camera").apply { start() }
    val h = Handler(thread.looper)
    var cam: CameraDevice? = null
    var session: CameraCaptureSession? = null
    var reader: ImageReader? = null
    var recorder: MediaRecorder? = null
    var outFile: File? = null
    lateinit var close: () -> Unit
    lateinit var reopen: () -> Unit
    lateinit var review: (File, Boolean) -> Unit
    val dir = File(c.cacheDir, "camera").apply { mkdirs() }

    val preview = TextureView(c)
    val time = c.text("0:00", 15f, Color.WHITE).apply {
        background = c.rounded(SysColor.red, 6); setPadding(c.dp(8), c.dp(2), c.dp(8), c.dp(2)); visibility = View.GONE
    }
    val shutter = ShutterKey(c)
    val modeVideo = c.text(c.getString(R.string.cam_video).uppercase(), 13f, MT.gray, bold = true)
    val modePhoto = c.text(c.getString(R.string.cam_photo).uppercase(), 13f, Color.WHITE, bold = true)
    fun glass(res: Int, label: Int, work: () -> Unit) = FrameLayout(c).apply {
        background = c.glassPlate(oval = true); contentDescription = c.getString(label)
        addView(c.icon(res, Color.WHITE), FrameLayout.LayoutParams(c.dp(22), c.dp(22), Gravity.CENTER))
        pressable(work)
    }
    val flip = glass(R.drawable.ic_camera_rotate, R.string.rec_flip) { if (!recording && front != null) { id = if (id == back) front else back; reopen() } }

    fun characteristics() = cm.getCameraCharacteristics(id)
    fun map() = characteristics().get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
    fun previewSizes(): List<Size> = map()?.getOutputSizes(SurfaceTexture::class.java)?.toList() ?: emptyList()
    fun filmSizes(): List<Size> = map()?.getOutputSizes(MediaRecorder::class.java)?.toList() ?: emptyList()
    fun jpegSizes(): List<Size> = map()?.getOutputSizes(ImageFormat.JPEG)?.toList() ?: emptyList()
    // the shape of the frame: four by three for a photo, sixteen by nine for a film, as the platform's camera
    fun aspectOk(s: Size, wide: Boolean) = if (wide) s.width * 9 == s.height * 16 else s.width * 3 == s.height * 4
    fun pick(all: List<Size>, wide: Boolean, cap: Int): Size? =
        all.filter { aspectOk(it, wide) && it.width <= cap }.maxByOrNull { it.width * it.height } ?: all.maxByOrNull { it.width * it.height }
    // the turn the picture is stored with: the sensor's own, less the phone's (the front camera turns the other way)
    fun turn(): Int {
        val sensor = characteristics().get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        @Suppress("DEPRECATION") val deg = when (act.windowManager.defaultDisplay.rotation) { Surface.ROTATION_90 -> 90; Surface.ROTATION_180 -> 180; Surface.ROTATION_270 -> 270; else -> 0 }
        return if (id == front) (sensor + deg) % 360 else (sensor - deg + 360) % 360
    }
    fun fitPreview() {
        val w = preview.width.takeIf { 0 < it } ?: c.resources.displayMetrics.widthPixels
        val lp = preview.layoutParams as FrameLayout.LayoutParams
        lp.height = if (video) w * 16 / 9 else w * 4 / 3
        preview.layoutParams = lp
    }
    fun release() {
        runCatching { session?.close() }; session = null
        runCatching { cam?.close() }; cam = null
        runCatching { reader?.close() }; reader = null
        runCatching { recorder?.release() }; recorder = null
    }
    /** One session for what the mode needs: the preview with the photo's reader, or the preview with the film's recorder. */
    fun configure(d: CameraDevice) {
        val st = preview.surfaceTexture ?: return
        val pv = pick(previewSizes(), video, 1920) ?: return
        st.setDefaultBufferSize(pv.width, pv.height)
        val surface = Surface(st)
        val targets = ArrayList<Surface>()
        targets.add(surface)
        if (video) {
            val f = File(dir, "film-" + System.currentTimeMillis() + ".mp4")
            val vs = pick(filmSizes(), true, 1920) ?: pv
            val r = (if (31 <= android.os.Build.VERSION.SDK_INT) MediaRecorder(c) else @Suppress("DEPRECATION") MediaRecorder()).apply {
                if (c.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) setAudioSource(MediaRecorder.AudioSource.CAMCORDER)
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setOutputFile(f.path)
                setVideoEncodingBitRate(10_000_000); setVideoFrameRate(30); setVideoSize(vs.width, vs.height)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                if (c.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC); setAudioEncodingBitRate(128_000); setAudioSamplingRate(44_100)
                }
                setOrientationHint(turn())
                prepare()
            }
            recorder = r; outFile = f
            targets.add(r.surface)
        } else {
            val js = pick(jpegSizes(), false, 4032) ?: pv
            val ir = ImageReader.newInstance(js.width, js.height, ImageFormat.JPEG, 2)
            ir.setOnImageAvailableListener({ rd ->
                val img = rd.acquireLatestImage() ?: return@setOnImageAvailableListener
                val buf = img.planes[0].buffer
                val bytes = ByteArray(buf.remaining()).also { buf.get(it) }
                img.close()
                val f = File(dir, "photo-" + System.currentTimeMillis() + ".jpg").apply { writeBytes(bytes) }
                act.onMain { review(f, false) }
            }, h)
            reader = ir
            targets.add(ir.surface)
        }
        d.createCaptureSession(targets, object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(s: CameraCaptureSession) {
                session = s
                runCatching {
                    s.setRepeatingRequest(d.createCaptureRequest(if (video) CameraDevice.TEMPLATE_RECORD else CameraDevice.TEMPLATE_PREVIEW).apply {
                        targets.forEach { if (video || it == surface) addTarget(it) }
                        set(CaptureRequest.CONTROL_AF_MODE, if (video) CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO else CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                    }.build(), null, h)
                }.onFailure { Log.w("Montana", "camera: preview " + it.javaClass.simpleName) }
            }
            override fun onConfigureFailed(s: CameraCaptureSession) { Log.w("Montana", "camera: the session was refused") }
        }, h)
    }
    fun openCamera() {
        if (preview.surfaceTexture == null) return
        runCatching {
            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(d: CameraDevice) { cam = d; runCatching { configure(d) }.onFailure { Log.w("Montana", "camera: configure " + it.javaClass.simpleName) } }
                override fun onDisconnected(d: CameraDevice) { d.close(); if (cam === d) cam = null }
                override fun onError(d: CameraDevice, e: Int) { d.close(); if (cam === d) cam = null; Log.w("Montana", "camera: error " + e) }
            }, h)
        }.onFailure { Log.w("Montana", "camera: open " + it.javaClass.simpleName) }
    }
    reopen = { h.post { release(); act.onMain { fitPreview(); h.post { openCamera() } } } }
    fun paintModes() {
        modeVideo.setTextColor(if (video) Color.WHITE else MT.gray)
        modePhoto.setTextColor(if (video) MT.gray else Color.WHITE)
        shutter.video = video
    }
    fun setMode(v: Boolean) {
        if (recording || v == video) return
        val go = { video = v; paintModes(); reopen() }
        // a film asks for the microphone first; refused, it is a film without its sound
        if (v && c.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) act.askMic { go() } else go()
    }
    modeVideo.setPadding(c.dp(14), c.dp(10), c.dp(14), c.dp(10)); modeVideo.pressable { setMode(true) }
    modePhoto.setPadding(c.dp(14), c.dp(10), c.dp(14), c.dp(10)); modePhoto.pressable { setMode(false) }
    val tick = object : Runnable {
        override fun run() {
            if (!recording) return
            val s = (System.currentTimeMillis() - startedAt) / 1000
            time.text = String.format("%d:%02d", s / 60, s % 60)
            time.postDelayed(this, 500)
        }
    }
    shutter.pressable {
        if (!video) {
            val s = session ?: return@pressable
            val d = cam ?: return@pressable
            val ir = reader ?: return@pressable
            shutter.animate().scaleX(0.9f).scaleY(0.9f).setDuration(80).withEndAction { shutter.animate().scaleX(1f).scaleY(1f).setDuration(80).start() }.start()
            h.post {
                runCatching {
                    s.capture(d.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                        addTarget(ir.surface)
                        set(CaptureRequest.JPEG_ORIENTATION, turn())
                        set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                    }.build(), null, h)
                }.onFailure { Log.w("Montana", "camera: shot " + it.javaClass.simpleName) }
            }
        } else if (!recording) {
            val r = recorder ?: return@pressable
            if (runCatching { r.start() }.isFailure) return@pressable
            recording = true; startedAt = System.currentTimeMillis(); shutter.recording = true
            time.visibility = View.VISIBLE; time.post(tick)
            modeVideo.visibility = View.INVISIBLE; modePhoto.visibility = View.INVISIBLE; flip.visibility = View.INVISIBLE
        } else {
            recording = false; shutter.recording = false; time.visibility = View.GONE
            modeVideo.visibility = View.VISIBLE; modePhoto.visibility = View.VISIBLE; flip.visibility = View.VISIBLE
            val f = outFile
            val ok = runCatching { recorder?.stop() }.isSuccess
            h.post { release(); act.onMain { if (ok && f != null && 0 < f.length()) review(f, true) else reopen() } }
        }
    }
    val bottom = FrameLayout(c).apply {
        addView(c.hstack {
            gravity = Gravity.CENTER
            addView(modeVideo, lp(WRAP, WRAP)); addView(modePhoto, lp(WRAP, WRAP))
        }, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.TOP))
        addView(shutter, FrameLayout.LayoutParams(c.dp(76), c.dp(76), Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM).apply { bottomMargin = c.dp(18) })
        addView(flip, FrameLayout.LayoutParams(c.dp(48), c.dp(48), Gravity.END or Gravity.BOTTOM).apply { bottomMargin = c.dp(32); marginEnd = c.dp(28) })
    }
    val page = FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        isClickable = true
        addView(preview, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.CENTER))
        addView(time, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = c.dp(16) })
        addView(glass(R.drawable.ic_close, R.string.cancel) { close() }, FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.TOP or Gravity.START).apply { setMargins(c.dp(14), c.dp(10), 0, 0) })
        addView(bottom, FrameLayout.LayoutParams(MATCH, c.dp(150), Gravity.BOTTOM))
        setOnApplyWindowInsetsListener { v, ins ->
            val b = ins.getInsets(WindowInsets.Type.systemBars())
            v.setPadding(0, b.top, 0, b.bottom); ins
        }
    }
    // WHAT WAS TAKEN, LOOKED AT ONCE (the system camera's own review): the cross takes it again, the checkmark sends it
    review = { f, film ->
        val look = FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            isClickable = true
            val pic = if (film) Media.preview(c, f, "vid", 1600) else Media.preview(c, f, "img", 2000)
            addView(ImageView(c).apply { scaleType = ImageView.ScaleType.FIT_CENTER; setImageBitmap(pic) }, FrameLayout.LayoutParams(MATCH, MATCH))
            if (film) addView(c.icon(R.drawable.ic_play_fill, Color.WHITE).apply {
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(140, 0, 0, 0)) }
                setPadding(c.dp(16), c.dp(16), c.dp(16), c.dp(16))
                pressable { FilmActivity.open(act, f) }
            }, FrameLayout.LayoutParams(c.dp(64), c.dp(64), Gravity.CENTER))
        }
        lateinit var shut: () -> Unit
        look.addView(glass(R.drawable.ic_close, R.string.cancel) { shut(); f.delete(); reopen() },
            FrameLayout.LayoutParams(c.dp(56), c.dp(56), Gravity.BOTTOM or Gravity.START).apply { setMargins(c.dp(28), 0, 0, c.dp(40)) })
        look.addView(FrameLayout(c).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.WHITE) }
            contentDescription = c.getString(R.string.send)
            addView(c.icon(R.drawable.ic_check, Color.BLACK), FrameLayout.LayoutParams(c.dp(26), c.dp(26), Gravity.CENTER))
            pressable { shut(); close(); done(f, film) }
        }, FrameLayout.LayoutParams(c.dp(56), c.dp(56), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, c.dp(28), c.dp(40)) })
        look.setOnApplyWindowInsetsListener { v, ins -> val b = ins.getInsets(WindowInsets.Type.systemBars()); v.setPadding(0, b.top, 0, b.bottom); ins }
        h.post { release() }
        shut = act.overlay(look)
        look.requestApplyInsets()
    }
    preview.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, hh: Int) { fitPreview(); h.post { openCamera() } }
        override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, hh: Int) {}
        override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean { h.post { release() }; return true }
        override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
    }
    close = act.overlay(page)
    // the page gone by any road — the cross, the checkmark, the platform's back — lets the camera go
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) {}
        override fun onViewDetachedFromWindow(v: View) {
            if (recording) { recording = false; runCatching { recorder?.stop() } }
            h.post { release(); thread.quitSafely() }
        }
    })
    paintModes()
    page.requestApplyInsets()
    // the first «allow» comes after the picture's surface: the camera opens on the answer, not only on the surface
    act.askCamera { granted -> if (!granted) close() else h.post { if (cam == null) openCamera() } }
}

/** THE SHUTTER (the platform camera's own): the white ring; inside a white disc for a photo, a red one for a film, a red square while it rolls. */
private class ShutterKey(c: Context) : View(c) {
    var video = false
        set(v) { field = v; invalidate() }
    var recording = false
        set(v) { field = v; invalidate() }
    private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
    init { contentDescription = c.getString(R.string.cam_photo) }
    override fun onDraw(canvas: android.graphics.Canvas) {
        val d = resources.displayMetrics.density
        val r = width / 2f
        paint.style = android.graphics.Paint.Style.STROKE; paint.strokeWidth = 4 * d; paint.color = Color.WHITE
        canvas.drawCircle(r, r, r - 2 * d, paint)
        paint.style = android.graphics.Paint.Style.FILL
        paint.color = if (video) SysColor.red else Color.WHITE
        if (recording) { val q = 14 * d; canvas.drawRoundRect(r - q, r - q, r + q, r + q, 5 * d, 5 * d, paint) }
        else canvas.drawCircle(r, r, r - 9 * d, paint)
    }
}
