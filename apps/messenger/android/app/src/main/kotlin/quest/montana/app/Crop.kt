package quest.montana.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.FrameLayout
import java.io.ByteArrayOutputStream

/**
 * The avatar crop (iOS MTAvatarCropView / MTFrameCropView): the picked photo under the face's frame —
 * pinch and pan set what the frame keeps, the photo always covering it. «Done» renders exactly the
 * frame's square onto 640×640 (a JPEG, black where nothing is painted): what you see is what everyone gets.
 * The frame is the face's figure; under the native skin (the default) that figure is the circle.
 */
class CropView(ctx: Context, private val image: Bitmap) : View(ctx) {
    private var zoom = 1f            // 1…5, over the fill-scale
    private var panX = 0f
    private var panY = 0f
    private var side = 0f            // the frame's side on the screen
    private var base = 1f            // the fill-scale: the photo just covers the frame
    private val draw = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val dim = Paint().apply { color = Color.argb(153, 0, 0, 0) }        // black 0.6 outside the frame
    private val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply {                     // the rim: white 0.8, 1.5pt
        style = Paint.Style.STROKE; color = Color.argb(204, 255, 255, 255); strokeWidth = context.dp(1.5).toFloat().coerceAtLeast(1f)
    }
    private val scaler = ScaleGestureDetector(ctx, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(d: ScaleGestureDetector): Boolean {
            zoom = (zoom * d.scaleFactor).coerceIn(1f, 5f); cover(); invalidate(); return true
        }
    })
    private var lastX = 0f
    private var lastY = 0f
    private var pointer = -1

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        // The frame's side: the width less the margins, never so tall that it meets the bars.
        side = minOf(w - dp(48f), h - 2 * dp(56f)).toFloat().coerceAtLeast(dp(120f).toFloat())
        base = maxOf(side / image.width, side / image.height)
        cover()
    }
    private fun dp(v: Float) = context.dp(v)

    /** THE PHOTO COVERS THE FRAME, ALWAYS: the pan is bounded by how much of the picture lies beyond it. */
    private fun cover() {
        val mx = maxOf(0f, (image.width * base * zoom - side) / 2)
        val my = maxOf(0f, (image.height * base * zoom - side) / 2)
        panX = panX.coerceIn(-mx, mx); panY = panY.coerceIn(-my, my)
    }

    private fun imageRect(): RectF {
        val s = base * zoom
        val w = image.width * s; val h = image.height * s
        val cx = width / 2f + panX; val cy = height / 2f + panY
        return RectF(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
    }
    private fun frameRect() = RectF(width / 2f - side / 2, height / 2f - side / 2, width / 2f + side / 2, height / 2f + side / 2)

    override fun onDraw(c: Canvas) {
        c.drawColor(Color.BLACK)
        c.drawBitmap(image, null, imageRect(), draw)
        // Everything outside the frame darkens; the frame itself stays clear.
        val f = frameRect()
        val hole = Path().apply { addOval(f, Path.Direction.CW); fillType = Path.FillType.INVERSE_WINDING }
        c.drawPath(hole, dim)
        c.drawOval(f, rim)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        scaler.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { pointer = e.getPointerId(0); lastX = e.x; lastY = e.y }
            MotionEvent.ACTION_MOVE -> if (!scaler.isInProgress) {
                val i = e.findPointerIndex(pointer)
                if (i >= 0) {
                    panX += e.getX(i) - lastX; panY += e.getY(i) - lastY
                    lastX = e.getX(i); lastY = e.getY(i)
                    cover(); invalidate()
                }
            }
            MotionEvent.ACTION_POINTER_UP -> {
                // the finger that stays leads the pan
                val gone = e.actionIndex
                if (e.getPointerId(gone) == pointer) {
                    val keep = if (gone == 0) 1 else 0
                    pointer = e.getPointerId(keep); lastX = e.getX(keep); lastY = e.getY(keep)
                }
            }
        }
        return true
    }

    /** Exactly what the frame's square holds, onto 640×640, as a JPEG (iOS MTAvatarCropView.render). */
    fun render(): ByteArray {
        val out = Bitmap.createBitmap(640, 640, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        c.drawColor(Color.BLACK)   // a JPEG has no transparency: what is not painted must be black, never white
        val f = frameRect(); val r = imageRect()
        val k = 640f / side
        c.drawBitmap(image, null, RectF((r.left - f.left) * k, (r.top - f.top) * k, (r.right - f.left) * k, (r.bottom - f.top) * k), draw)
        return ByteArrayOutputStream().also { out.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
    }
}

/** The crop page: the photo under the frame, the cross top left, the checkmark top right (the bar's own places). */
fun cropPage(act: MainActivity, image: Bitmap, onDone: (ByteArray?) -> Unit): View {
    val c = act
    val crop = CropView(c, image)
    fun mark(res: Int, tint: Int, gravity: Int, onTap: () -> Unit) = c.icon(res, tint).apply {
        setPadding(dp(10), dp(10), dp(10), dp(10))
        background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.OVAL; setColor(Color.argb(140, 28, 28, 30))
        }
        pressable(onTap)
        layoutParams = FrameLayout.LayoutParams(dp(44), dp(44), gravity).apply { setMargins(dp(12), dp(4), dp(12), 0) }
    }
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(crop, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(mark(R.drawable.ic_close, Color.WHITE, Gravity.TOP or Gravity.START) { onDone(null) })
        addView(mark(R.drawable.ic_check, MT.gold, Gravity.TOP or Gravity.END) { onDone(crop.render()) })
    }
}
