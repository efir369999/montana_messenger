package quest.montana.app

import android.annotation.SuppressLint
import android.app.AlertDialog
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.Toast

/**
 * THE SCANNER (iOS ScanMeetingView over QRScannerView): the back camera over the whole page, the title and the close mark at
 * the top, the words at the foot on their dark plate, «Paste a link» above them for a link that came by another road
 * (Android's own: the iPhone opens such a link from the system). Every frame's brightness goes to our own reader (QrReader)
 * off the main thread — one at a time, the frames between are let go. The platform's own Camera2, no library.
 *
 * A code that is not an introduction says nothing about anyone: the camera keeps looking, silently (iOS 506-508). An
 * introduction is met while the scanner stands (iOS 510-525): opened, the page closes and the chat opens after it; not
 * opened, the verdict is said over the scanner, and closing it lets the camera take a code again (iOS 535-538).
 */
/**
 * With [onCode] the scanner reads for someone else (iOS SafetyNumberView's scan): every code read is handed to it off the main
 * thread; «true» ends the scan and closes the page, «false» keeps the camera looking. No invitation is opened, no link pasted.
 */
fun scannerPage(act: MainActivity, onClose: () -> Unit, onCode: ((String) -> Boolean)? = null): View {
    val c: Context = act
    val texture = TextureView(c)
    var cam: CameraDevice? = null
    var session: CameraCaptureSession? = null
    var reader: ImageReader? = null
    val thread = HandlerThread("montana-scan").apply { start() }
    val bg = Handler(thread.looper)
    val busy = java.util.concurrent.atomic.AtomicBoolean(false)
    val done = java.util.concurrent.atomic.AtomicBoolean(false)

    // A CAMERA THAT DOES NOT OPEN IS SAID (iOS showCameraOff, showCameraUnavailable 342-369): a black page with no word reads as
    // a broken app. The platform's empty state — the struck camera, the words, and the one road to Settings when the person
    // refused the camera.
    val blankState = c.vstack(Gravity.CENTER_HORIZONTAL).apply { visibility = View.GONE }
    fun blank(words: Int, road: Boolean, why: String) = act.onMain {
        Log.w("Montana", "scanner: " + why)
        blankState.removeAllViews()
        blankState.addView(c.icon(R.drawable.ic_video_slash, MT.gray, 56))
        blankState.addView(c.text(c.getString(words), 20f, Color.WHITE, bold = true, center = true),
            android.widget.LinearLayout.LayoutParams(WRAP, WRAP).apply { topMargin = c.dp(16) })
        if (road) blankState.addView(c.text(c.getString(R.string.open_settings), 17f, Color.BLACK, bold = true, center = true).apply {
            background = c.rounded(Color.WHITE, 22)
            setPadding(c.dp(22), c.dp(12), c.dp(22), c.dp(12))
            pressable {
                runCatching { act.startActivity(android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    android.net.Uri.parse("package:" + c.packageName))) }
            }
        }, android.widget.LinearLayout.LayoutParams(WRAP, WRAP).apply { topMargin = c.dp(20) })
        blankState.visibility = View.VISIBLE
    }

    fun release() {
        runCatching { session?.close() }; runCatching { cam?.close() }; runCatching { reader?.close() }
        session = null; cam = null; reader = null
        thread.quitSafely()
    }

    // THE MEETING IS ANSWERED WHERE IT WAS ASKED (iOS ScanMeetingView 510-538, 23.09): the scanner closed the moment a link was
    // read, and an expired or refused code was told in a passing word over a page already gone — the person opened the scanner
    // again to hold the right code.
    fun meet(link: String) {
        if (!done.compareAndSet(false, true)) return
        act.background {
            val o = Meeting.meet(act, link)
            act.onMain {
                if (o is Meeting.Outcome.Opened) {
                    release(); onClose()
                    // the page leaves first, the chat comes after it (iOS 1052: 0.35 s)
                    MainThread.later(350) { act.push { close -> conversationPage(act, SamePair.root(o.ref), close) } }
                } else AlertDialog.Builder(act).setMessage(Meeting.verdict(o)).setPositiveButton(R.string.ok, null)
                    .setOnDismissListener { done.set(false) }.show()
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun open(st: SurfaceTexture, vw: Int, vh: Int) {
        val cm = c.getSystemService(CameraManager::class.java)
        val id = cm.cameraIdList.firstOrNull { cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK }
            ?: return blank(R.string.camera_unavailable, false, "no camera")
        val map = cm.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?: return blank(R.string.camera_unavailable, false, "the camera gave no picture sizes")
        // A 16:9 picture near 1280×720: enough modules for any card code, light enough for every frame.
        val sizes = map.getOutputSizes(ImageFormat.YUV_420_888)
        val size = sizes.filter { it.width * 9 == it.height * 16 && it.width <= 1920 }.minByOrNull { kotlin.math.abs(it.width - 1280) } ?: sizes.first()
        st.setDefaultBufferSize(size.width, size.height)
        fitCrop(texture, size, vw, vh)
        val r = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2)
        reader = r
        r.setOnImageAvailableListener({ ir ->
            val img = ir.acquireLatestImage() ?: return@setOnImageAvailableListener
            if (done.get() || !busy.compareAndSet(false, true)) { img.close(); return@setOnImageAvailableListener }
            val p = img.planes[0]
            val w = img.width; val h = img.height; val stride = p.rowStride
            val buf = p.buffer
            val lum = ByteArray(buf.remaining()); buf.get(lum)
            img.close()
            val text = runCatching { QrReader.read(lum, w, h, stride) }.getOrNull()
            busy.set(false)
            if (text != null && onCode != null) {
                if (onCode(text) && done.compareAndSet(false, true)) act.onMain { onClose() }
            } else if (text != null && Meeting.looksLikeInvitation(text)) meet(text)
        }, bg)
        runCatching {
            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(d: CameraDevice) {
                    cam = d
                    val preview = Surface(st)
                    @Suppress("DEPRECATION")
                    d.createCaptureSession(listOf(preview, r.surface), object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(s: CameraCaptureSession) {
                            session = s
                            val req = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                                addTarget(preview); addTarget(r.surface)
                                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                            }.build()
                            runCatching { s.setRepeatingRequest(req, null, bg) }
                        }
                        override fun onConfigureFailed(s: CameraCaptureSession) { blank(R.string.camera_unavailable, false, "the session refused the scanner output") }
                    }, bg)
                }
                override fun onDisconnected(d: CameraDevice) { d.close() }
                override fun onError(d: CameraDevice, e: Int) { d.close(); blank(R.string.camera_unavailable, false, "camera error " + e) }
            }, bg)
        }.onFailure { blank(R.string.camera_unavailable, false, "the camera did not open: " + it.javaClass.simpleName) }
    }

    texture.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
            if (c.checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) open(st, w, h)
        }
        override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
        override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean { release(); return true }
        override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
    }

    val page = FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        isClickable = true
        keepScreenOn = true   // the screen stays awake while the scanner looks (iOS MontanaScreenAwake 412, 18.09)
        addView(texture, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(blankState, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER).apply { setMargins(c.dp(24), 0, c.dp(24), 0) })
        // The title and the close mark (iOS: the sheet's inline title, the close mark as its cancellation).
        addView(FrameLayout(c).apply {
            addView(c.text(c.getString(if (onCode == null) R.string.scan_code else R.string.scan_qr), 17f, Color.WHITE, bold = true, center = true).apply {
                setShadowLayer(8f, 0f, 0f, Color.BLACK)
            }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
            addView(c.icon(R.drawable.ic_close, Color.WHITE).apply {
                setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12))
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(120, 0, 0, 0)) }
                pressable { release(); onClose() }
            }, FrameLayout.LayoutParams(c.dp(48), c.dp(48), Gravity.CENTER_VERTICAL or Gravity.START).apply { leftMargin = c.dp(16) })
        }, FrameLayout.LayoutParams(MATCH, c.dp(48), Gravity.TOP).apply { topMargin = c.dp(16) })
        // At the foot: «Paste a link», and under it the words on their dark plate (iOS 527-531: 40 above the edge).
        if (onCode == null) addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
            addView(c.text(c.getString(R.string.paste_link), 16f, Color.BLACK, bold = true, center = true).apply {
                background = c.rounded(Color.WHITE, 22)
                setPadding(c.dp(22), c.dp(12), c.dp(22), c.dp(12))
                pressable {
                    val clip = c.getSystemService(ClipboardManager::class.java).primaryClip
                    val t = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(c)?.toString()?.trim().orEmpty()
                    val link = Regex("(https://\\S+|montana://\\S+)").find(t)?.value ?: t
                    if (Meeting.looksLikeInvitation(link)) meet(link)
                    else Toast.makeText(c, R.string.no_invite_in_clipboard, Toast.LENGTH_SHORT).show()
                }
            }, android.widget.LinearLayout.LayoutParams(WRAP, WRAP))
            addView(c.text(c.getString(R.string.scan_hint), 17f, Color.WHITE, center = true).apply {
                background = c.rounded(Color.argb(153, 0, 0, 0), 10)
                setPadding(c.dp(10), c.dp(10), c.dp(10), c.dp(10))
            }, android.widget.LinearLayout.LayoutParams(WRAP, WRAP).apply { topMargin = c.dp(16) })
        }, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM).apply { setMargins(c.dp(24), 0, c.dp(24), c.dp(40)) })
    }
    // THE CAMERA IS ASKED FIRST, AND A REFUSAL HAS A ROAD (iOS 375-389).
    if (c.checkSelfPermission(android.Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
        act.askCamera { granted ->
            if (granted && texture.isAvailable) texture.surfaceTexture?.let { open(it, texture.width, texture.height) }
            else if (!granted) blank(R.string.camera_off, true, "the camera is off for this app")
        }
    }
    return page
}

/** The camera's picture fills the page without stretching (a centre crop of the portrait-turned 16:9 frame). */
private fun fitCrop(tv: TextureView, size: Size, vw: Int, vh: Int) {
    val contentAspect = size.height.toFloat() / size.width   // the frame turned upright
    val viewAspect = vw.toFloat() / vh
    val m = Matrix()
    if (viewAspect < contentAspect) m.setScale(contentAspect / viewAspect, 1f, vw / 2f, vh / 2f)
    else m.setScale(1f, viewAspect / contentAspect, vw / 2f, vh / 2f)
    tv.post { tv.setTransform(m) }
}
