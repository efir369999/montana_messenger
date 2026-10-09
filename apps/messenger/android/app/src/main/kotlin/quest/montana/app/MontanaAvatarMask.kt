package quest.montana.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.media.FaceDetector
import android.os.SystemClock
import android.util.Log
import org.webrtc.CapturerObserver
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.roundToInt

// THE AVATAR MASK OF A VIDEO CALL (iOS MontanaAvatarMask.swift 1-11 in 2155, atom c98a92d589e3; the author's word 30.09: «as a
// mask -- an avatar in a video call»). THE FACE NEVER LEAVES THE PHONE WHILE THE MASK IS ON: the call's camera frames are read
// here, in memory, by the platform's own face finder; the call's video source receives only the avatar's frames, drawn here.
// The one door is the birth of what goes out: the camera's observer (AvatarMask.Door, at both of CallLine's camera births)
// hands every camera frame to the mask first, and a frame the mask takes never reaches the source -- nor the self-view, which
// shows what the peer sees. Nothing new travels: the avatar rides the same lane the camera did, no service of anyone else.
// Energy (iOS 11): the finder and the renderer live only while the mask is on.

/**
 * What the face does, as the platform's finder can say it (iOS MTAvatarFace 23-39): where the head stands -- its middle off the
 * picture's middle and its size, in parts of the picture's shorter side; 0, 0, 1 is the look at rest. android.media.FaceDetector
 * reads the eyes' midpoint and their distance apart, no eyelids and no lips, so iOS's blink and jaw are not read here, and the
 * head is placed and sized by the face where iOS turns it by yaw, pitch and roll.
 */
internal class AvatarFace {
    var x = 0f
    var y = 0f
    var size = 1f

    fun set(x: Float, y: Float, size: Float) { this.x = x; this.y = y; this.size = size }

    /** iOS eased 33-38: the finder's reading shivers from one to the next, the look follows it softly. */
    fun ease(to: AvatarFace, k: Float) { x += (to.x - x) * k; y += (to.y - y) * k; size += (to.size - size) * k }
}

/**
 * THE TRACKER READS THE FRAME THE CALL'S CAMERA ALREADY MADE (iOS MTAvatarTracker 41-104): one camera, one owner -- a second
 * capture session is never born. The reader is the platform's own android.media.FaceDetector, on a small upright RGB_565 copy
 * of the frame's light (iOS reads Vision's landmarks on the frame turned by its rotation, 55-83). Born and let go with the
 * renderer; used on the mask's queue only.
 */
internal class AvatarTracker {
    private var width = 0
    private var height = 0
    private var finder: FaceDetector? = null
    private var copy: Bitmap? = null
    private var light = IntArray(0)
    private val found = arrayOfNulls<FaceDetector.Face>(1)
    private val mid = PointF()
    // The last reading's own words, for the diary (iOS Raw 46-48, call_mask_raw). The pose is written there and not used:
    // whether the platform measures it is read on the phone, not assumed.
    var eyes = 0f
        private set
    var confidence = 0f
        private set
    var poseX = 0f
        private set
    var poseY = 0f
        private set
    var poseZ = 0f
        private set

    /**
     * The finder's sample turned upright by the frame's rotation (the degrees it is turned clockwise to be shown, iOS
     * orientation 74-83) and searched for one face; found -- its place is written into [into] and true is returned.
     */
    fun read(b: VideoFrame.I420Buffer, rotation: Int, into: AvatarFace): Boolean {
        val sw = b.width
        val sh = b.height
        val turned = rotation == 90 || rotation == 270
        val w = if (turned) sh else sw
        val h = if (turned) sw else sh
        if (w < 2 || h < 2 || w % 2 != 0) return false   // the finder takes an even width only
        if (finder == null || copy == null || width != w || height != h) {
            finder = FaceDetector(w, h, 1)
            copy = Bitmap.createBitmap(w, h, Bitmap.Config.RGB_565)
            light = IntArray(w * h); width = w; height = h
        }
        val f = finder ?: return false
        val p = copy ?: return false
        val luma = b.dataY
        val stride = b.strideY
        var i = 0
        for (dy in 0 until h) for (dx in 0 until w) {
            val at = when (rotation) {
                90 -> (sh - 1 - dx) * stride + dy
                180 -> (sh - 1 - dy) * stride + (sw - 1 - dx)
                270 -> dx * stride + (sw - 1 - dy)
                else -> dy * stride + dx
            }
            val l = luma.get(at).toInt() and 0xFF
            light[i++] = Color.rgb(l, l, l)
        }
        p.setPixels(light, 0, w, 0, 0, w, h)
        val n = f.findFaces(p, found)
        val face = found[0]
        if (n < 1 || face == null || face.confidence() < FaceDetector.Face.CONFIDENCE_THRESHOLD) return false
        val side = minOf(w, h).toFloat()
        val apart = face.eyesDistance() / side
        if (apart <= 0f) return false
        face.getMidPoint(mid)
        eyes = apart
        confidence = face.confidence()
        poseX = face.pose(FaceDetector.Face.EULER_X)
        poseY = face.pose(FaceDetector.Face.EULER_Y)
        poseZ = face.pose(FaceDetector.Face.EULER_Z)
        // THE AVATAR'S EYES STAND ON THE PERSON'S EYES: it is sized so its eyes are as far apart as theirs, and its middle
        // stands under their midpoint by its own eyes' height (AvatarLook)
        val k = apart / AvatarLook.EYES_APART
        into.set((mid.x - w / 2f) / side, (mid.y - h / 2f) / side + AvatarLook.EYES_ABOVE * k, k)
        return true
    }
}

/**
 * THE LOOK HAS ONE OWNER (iOS MTAvatarLook 106-146; the author named the avatar, not its style). What stands here is the PROBE
 * look -- a sphere for the head, two small ones for the eyes, a flattened one for the mouth -- drawn as iOS's renderer sees
 * it: the head of radius 1 at the middle, its parts on its face at depth 0.93 (127), the eye four units away (178) and forty
 * degrees wide across the picture's shorter side (175, 217), the platform's default light from the eye (173). It is not the
 * final look: the look the author chooses replaces this object and nothing else (checklist 36, item 1.3).
 */
internal object AvatarLook {
    const val NAME = "probe-sphere"   // iOS name 111
    private const val EYE_DISTANCE = 4.0   // iOS eye.position 178
    private const val FIELD = 40.0         // iOS cam.fieldOfView 175
    private const val FRONT = 0.93         // iOS part position z 127
    /** One unit of the scene at the head's middle, in parts of the picture's shorter side. */
    private val UNIT = 0.5 / Math.tan(Math.toRadians(FIELD / 2))
    private fun across(v: Double) = (UNIT * v / (EYE_DISTANCE - FRONT)).toFloat()
    private val HEAD = (UNIT / Math.sqrt(EYE_DISTANCE * EYE_DISTANCE - 1)).toFloat()   // a sphere of radius 1 seen from 4 (iOS 121)
    private val EYE_X = across(0.35)   // iOS part(0.13, ±0.35, 0.25) 131-132
    private val EYE_Y = across(0.25)
    private val EYE_R = across(0.13)
    private val MOUTH_Y = across(0.38)   // iOS part(0.22, 0, -0.38) 133
    private val MOUTH_R = across(0.22)
    /** Where the eyes stand at rest, the tracker's measure: their distance apart and their height over the head's middle. */
    val EYES_APART = 2 * EYE_X
    val EYES_ABOVE = EYE_Y

    /** The look's own paints (iOS Rig 113-118), held for the renderer's life: nothing is made per frame. */
    class Rig {
        val head = Paint(Paint.ANTI_ALIAS_FLAG)
        val dark = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = grey(0.08) }   // iOS UIColor(white: 0.08) 123
        val shade: RadialGradient
        val place = Matrix()
        val oval = RectF()

        init {
            // THE DEFAULT LIGHT FROM THE EYE (iOS autoenablesDefaultLighting 173): a sphere lit from where it is seen is
            // brightest at its middle and dark at its outline, as the cosine to the eye -- sqrt(1 - r * r) at r of the outline
            val at = floatArrayOf(0f, 0.4f, 0.6f, 0.8f, 0.9f, 0.97f, 1f)
            val colors = IntArray(at.size) { grey(0.92 * Math.sqrt(1.0 - at[it] * at[it])) }   // iOS UIColor(white: 0.92) 122
            shade = RadialGradient(0f, 0f, 1f, colors, at, Shader.TileMode.CLAMP)
            head.shader = shade
        }
    }

    private fun grey(level: Double): Int { val v = (level * 255).roundToInt().coerceIn(0, 255); return Color.rgb(v, v, v) }

    /**
     * The pose drawn (iOS pose 140-145): the head at [cx], [cy]; [side] is the shorter side's pixels times the face's size.
     * Open eyes and a shut mouth -- the platform's finder reads no eyelids or lips, so blink and jaw stand at rest (1, 0.15).
     */
    fun draw(rig: Rig, c: Canvas, cx: Float, cy: Float, side: Float) {
        val r = HEAD * side
        rig.place.setScale(r, r)
        rig.place.postTranslate(cx, cy)
        rig.shade.setLocalMatrix(rig.place)
        c.drawCircle(cx, cy, r, rig.head)
        val ex = EYE_X * side
        val ey = cy - EYE_Y * side
        val er = EYE_R * side
        rig.oval.set(cx - ex - er, ey - er, cx - ex + er, ey + er)
        c.drawOval(rig.oval, rig.dark)
        rig.oval.set(cx + ex - er, ey - er, cx + ex + er, ey + er)
        c.drawOval(rig.oval, rig.dark)
        val my = cy + MOUTH_Y * side
        val mr = MOUTH_R * side
        val mh = mr * 0.15f   // iOS mouth.scale y 0.15 + 0.85 * jawOpen, 144
        rig.oval.set(cx - mr, my - mh, cx + mr, my + mh)
        c.drawOval(rig.oval, rig.dark)
    }
}

/**
 * THE RENDERER (iOS MTAvatarRenderer 148-259): the look drawn off screen by the platform's own Canvas into a picture the size
 * of the frame, and turned into the frame the video lane takes as it takes a camera's -- I420 in direct buffers from a pool,
 * each given back when the lane lets its frame go (iOS's pixel buffer pool 227-247). Born when the mask turns on, let go when
 * it turns off; used on the mask's queue only.
 */
internal class AvatarRenderer {
    val tracker = AvatarTracker()   // born and let go with the renderer: the finder lives only while the mask is on
    private val rig = AvatarLook.Rig()
    private var width = 0
    private var height = 0
    private var picture: Bitmap? = null
    private var canvas: Canvas? = null
    private var argb = IntArray(0)
    private var planeY = ByteArray(0)
    private var planeU = ByteArray(0)
    private var planeV = ByteArray(0)
    private val pool = ArrayDeque<Slot>()

    private class Slot(val w: Int, val h: Int) {
        val y: ByteBuffer = ByteBuffer.allocateDirect(w * h)
        val u: ByteBuffer = ByteBuffer.allocateDirect(w / 2 * (h / 2))
        val v: ByteBuffer = ByteBuffer.allocateDirect(w / 2 * (h / 2))
    }

    /** iOS draw 192-225: the picture cleared to black (204), the look posed and drawn, handed out as the lane's own frame. */
    fun draw(f: AvatarFace, w: Int, h: Int): VideoFrame.Buffer? {
        if (picture == null || width != w || height != h) {
            val made = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            picture = made
            canvas = Canvas(made)
            argb = IntArray(w * h); planeY = ByteArray(w * h); planeU = ByteArray(w / 2 * (h / 2)); planeV = ByteArray(w / 2 * (h / 2))
            synchronized(pool) { width = w; height = h; pool.clear() }
        }
        val p = picture ?: return null
        val c = canvas ?: return null
        c.drawColor(Color.BLACK)
        val side = minOf(w, h).toFloat()
        AvatarLook.draw(rig, c, w / 2f + f.x * side, h / 2f + f.y * side, side * f.size)
        p.getPixels(argb, 0, w, 0, 0, w, h)
        toI420(w, h)
        val s = synchronized(pool) { pool.removeFirstOrNull() } ?: Slot(w, h)
        fill(s.y, planeY)
        fill(s.u, planeU)
        fill(s.v, planeV)
        return JavaI420Buffer.wrap(w, h, s.y, w, s.u, w / 2, s.v, w / 2) { give(s) }
    }

    private fun give(s: Slot) { synchronized(pool) { if (s.w == width && s.h == height) pool.addLast(s) } }

    private fun fill(into: ByteBuffer, from: ByteArray) { into.clear(); into.put(from); into.rewind() }

    /** The drawn picture in the lane's own form (BT.601, studio range): a luma for each pixel, a chroma pair for each square of four. */
    private fun toI420(w: Int, h: Int) {
        for (i in 0 until w * h) {
            val q = argb[i]
            planeY[i] = (((66 * red(q) + 129 * green(q) + 25 * blue(q) + 128) shr 8) + 16).toByte()
        }
        val cw = w / 2
        for (j in 0 until h / 2) for (i in 0 until cw) {
            val a = 2 * j * w + 2 * i
            val r = (red(argb[a]) + red(argb[a + 1]) + red(argb[a + w]) + red(argb[a + w + 1])) shr 2
            val g = (green(argb[a]) + green(argb[a + 1]) + green(argb[a + w]) + green(argb[a + w + 1])) shr 2
            val b = (blue(argb[a]) + blue(argb[a + 1]) + blue(argb[a + w]) + blue(argb[a + w + 1])) shr 2
            planeU[j * cw + i] = (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte()
            planeV[j * cw + i] = (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte()
        }
    }

    private fun red(q: Int) = (q shr 16) and 0xFF
    private fun green(q: Int) = (q shr 8) and 0xFF
    private fun blue(q: Int) = q and 0xFF
}

/**
 * THE MASK HAS ONE OWNER (iOS MTAvatarMask 261-362): whether it is on, the one door a camera frame passes, the renderer's life.
 * The call screen's mark asks it; the end of the call and the end of video put it out (CallLine.stop, CallLine.drop). [masked]
 * is its mirror for the screen (iOS CallUIModel.masked, MontanaCall.swift 5469).
 */
object AvatarMask {
    private const val LONG_SIDE = 960   // iOS longSide 266-267: the avatar needs no more pixels than a small screen
    private const val READ_SIDE = 320   // the finder's copy: its long side
    private const val READ_MS = 250L   // the finder reads at most four times a second; the last place is held between
    private const val FOLD_MS = 10_000L   // iOS markFolded window 10 (333, 339)
    private val lock = Any()
    private var on = false
    private var busy = false
    private var renderer: AvatarRenderer? = null
    private var firstFrame = true
    private var readAt = 0L   // on the camera's own thread only
    private val queue = Executors.newSingleThreadExecutor { r -> Thread(r, "montana.call.mask") }
    // Read and written on the mask's queue only (iOS 275-278)
    private val face = AvatarFace()
    private val target = AvatarFace()
    private var faceSeen = false
    private var drawn = 0
    private val faceLine = Fold("call_mask_face")
    private val rawLine = Fold("call_mask_raw")

    /** iOS CallUIModel.masked: the screen's mirror, written on the main thread by set() alone. */
    @Volatile var masked = false
        private set

    val isOn: Boolean get() = synchronized(lock) { on }

    fun toggle(why: String) = set(!isOn, why)

    /**
     * iOS set 288-304. On: the renderer is born first. Off: it is let go; the frame in flight on the queue finishes and is not
     * sent. The platform's Canvas draws on every phone, so iOS's refusal of a mask that cannot draw (no Metal) has no case here.
     */
    fun set(want: Boolean, why: String) {
        if (want == isOn) return
        val made = if (want) AvatarRenderer() else null
        synchronized(lock) { on = want; renderer = made; firstFrame = true }
        Log.d("Montana", "call_mask " + (if (want) "on" else "off") + " by=" + why + " look=" + AvatarLook.NAME + " tracker=face-detector")
        MainThread.post { masked = want; CallLine.changed?.invoke() }
    }

    /**
     * THE ONE DOOR (iOS take 306-325). Off: false, and the frame goes to the source as always. On: true -- the frame is the
     * mask's; it is read here and never reaches the source. While the previous frame is still being drawn this one is dropped:
     * the phone's own pace sets the avatar's rate. The finder's small copy is cut here, on the camera's own thread, where its
     * picture lives.
     */
    private fun take(frame: VideoFrame, sink: CapturerObserver): Boolean {
        val r = synchronized(lock) {
            if (!on) return false
            if (busy) return true
            val made = renderer ?: return true
            busy = true
            made
        }
        val rotation = frame.rotation
        val ns = frame.timestampNs
        val w = frame.rotatedWidth
        val h = frame.rotatedHeight
        val now = SystemClock.elapsedRealtime()
        val sample = if (now - readAt < READ_MS) null else { readAt = now; runCatching { cut(frame.buffer) }.getOrNull() }
        queue.execute { draw(sample, rotation, ns, w, h, r, sink) }
        return true
    }

    /** The finder's copy: the camera's frame scaled to a small one and read out, its long side READ_SIDE, both sides even. */
    private fun cut(b: VideoFrame.Buffer): VideoFrame.I420Buffer? {
        val long = maxOf(b.width, b.height)
        if (long <= 0) return null
        val k = minOf(READ_SIDE, long)
        val sw = b.width * k / long / 2 * 2
        val sh = b.height * k / long / 2 * 2
        if (sw < 2 || sh < 2) return null
        val small = b.cropAndScale(0, 0, b.width, b.height, sw, sh)
        val i420: VideoFrame.I420Buffer? = small.toI420()
        small.release()
        return i420
    }

    private fun draw(sample: VideoFrame.I420Buffer?, rotation: Int, ns: Long, w0: Int, h0: Int, r: AvatarRenderer, sink: CapturerObserver) {
        if (sample != null) {
            val seen = runCatching { r.tracker.read(sample, rotation, target) }.getOrDefault(false)
            sample.release()
            if (!seen) target.set(0f, 0f, 1f)
            if (seen != faceSeen) { faceSeen = seen; faceLine.mark(if (seen) "seen" else "lost") }
        }
        // iOS 330: the look follows a found face by 0.6 a frame and goes back to rest by 0.15 -- here the finder's last
        // reading is held between its readings
        face.ease(target, if (faceSeen) 0.6f else 0.15f)
        drawn++
        if (faceSeen && drawn % 30 == 1) {   // iOS 336-340
            val t = r.tracker
            rawLine.mark(String.format(Locale.ROOT, "eyes=%.2f conf=%.2f pose=%.1f,%.1f,%.1f x=%.2f y=%.2f size=%.2f",
                t.eyes, t.confidence, t.poseX, t.poseY, t.poseZ, face.x, face.y, face.size))
        }
        // iOS 341-350: the picture upright, its long side held to 960, both sides even
        var w = w0
        var h = h0
        val long = maxOf(w, h)
        if (long > LONG_SIDE) { w = w * LONG_SIDE / long; h = h * LONG_SIDE / long }
        w -= w % 2
        h -= h % 2
        val out = if (w > 0 && h > 0) runCatching { r.draw(face, w, h) }.getOrNull() else null
        // THE SOURCE IS FED UNDER THE LOCK (iOS 352-359 sends after it): Android's camera thread feeds the source past the
        // door the moment the mask goes off, and the two must never feed it at once -- a camera frame waits for this one at
        // take(), then finds the mask off.
        var first = false
        val sent = synchronized(lock) {
            busy = false
            first = firstFrame && out != null
            if (on && out != null) {
                firstFrame = false
                val f = VideoFrame(out, 0, ns)   // upright already: rotation 0 and the camera's own time (iOS 359)
                sink.onFrameCaptured(f)
                f.release()
                true
            } else false
        }
        if (!sent) out?.release()
        if (sent && first) Log.d("Montana", "call_mask first frame size=" + w + "x" + h + " face=" + (if (faceSeen) 1 else 0))
    }

    /** THE DOOR STANDS BETWEEN THE CAMERA AND THE CALL'S SOURCE (iOS FrameCountingCapturerDelegate, MontanaCall.swift 7221-7225):
     * the camera's start and stop pass as they were; its frame is offered to the mask first. */
    class Door(private val sink: CapturerObserver) : CapturerObserver {
        override fun onCapturerStarted(success: Boolean) = sink.onCapturerStarted(success)
        override fun onCapturerStopped() = sink.onCapturerStopped()
        override fun onFrameCaptured(frame: VideoFrame) { if (!take(frame, sink)) sink.onFrameCaptured(frame) }
    }

    /** iOS MontanaP2PTrace.markFolded (MontanaP2PTelemetry.swift 150-170): the first line of a volley is written at once, the
     * rest of ten seconds are counted and closed by one line of their own. */
    private class Fold(private val event: String) {
        private var n = 0
        private var at = 0L
        private var last = ""

        @Synchronized fun mark(kv: String) {
            val now = SystemClock.elapsedRealtime()
            if (n > 0 && now - at < FOLD_MS) { n++; last = kv; return }
            n = 1; at = now; last = kv
            Log.d("Montana", event + " " + kv)
            MainThread.later(FOLD_MS) { close() }
        }

        @Synchronized private fun close() {
            if (n > 1) Log.d("Montana", event + " n=" + (n - 1) + " more " + last)
            n = 0
        }
    }
}
