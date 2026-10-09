package quest.montana.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.util.LruCache
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import java.io.File
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// ─────────────────────────── the plate of a media group (iOS MTMosaic, groupBubble) ───────────────────────────

/**
 * THE MOSAIC OF A MEDIA GROUP (iOS MTMosaic.layout, MontanaMedia 1054-1263), line for line. Pure geometry: given the plate's
 * ceiling and the pictures' shapes it returns a rectangle and its outer edges for every tile. Two, three and four pictures take
 * a fixed cut chosen by their shapes (wide / narrow / square-ish); five and more, or any very wide picture, are laid in rows —
 * every split into two, three or four rows of at most three tiles is tried, and the one whose height comes nearest to four
 * thirds of the width wins, a heavier top row and a too-low row counting against it. Tiles stand one point apart.
 */
object Mosaic {
    const val GAP = 1f
    const val TOP = 1; const val BOTTOM = 2; const val LEFT = 4; const val RIGHT = 8; const val INSIDE = 16
    class Tile(val rect: RectF, val pos: Int)
    class Cut(val tiles: List<Tile>, val w: Float, val h: Float)

    /** The schoolbook rounding of Swift's round() (Kotlin's rounds a half to even); every value here is positive. */
    private fun rnd(x: Float) = floor(x + 0.5f)

    /** What folds into a plate: a picture or a film; a round note, a voice, a file and a sticker do not (iOS MTMosaic.folds). */
    fun folds(m: Msg): Boolean {
        if (!m.text.startsWith(Marks.MEDIA)) return false
        val man = Media.manifestOf(m) ?: return false
        if (man.optString("n") == Stickers.CARD) return false
        return when (man.optString("k")) { "img" -> true; "vid" -> !man.optBoolean("r"); else -> false }
    }

    fun layout(W: Float, H: Float, sizes: List<Pair<Float, Float>>): Cut {
        val n = sizes.size
        if (n == 0) return Cut(emptyList(), 0f, 0f)
        val g = GAP
        val shape = StringBuilder()
        val ratios = ArrayList<Float>(n)
        var average = 0f
        var stretched = false   // a very wide picture forces the row cut
        for ((pw, ph) in sizes) {
            val r = if (0f < ph) pw / ph else 1f
            shape.append(if (1.2f < r) 'w' else if (r < 0.8f) 'n' else 'q')
            if (2f < r) stretched = true
            average += r
            ratios.add(r)
        }
        average /= n
        val minW = 68f; val minH = 81f
        val plateRatio = W / H
        val tiles = MutableList(n) { Tile(RectF(), 0) }
        fun put(i: Int, x: Float, y: Float, w: Float, h: Float, pos: Int) { tiles[i] = Tile(RectF(x, y, x + w, y + h), pos) }
        val sh = shape.toString()
        if (n == 1) {
            put(0, 0f, 0f, W, floor(min(H, W / ratios[0])), TOP or BOTTOM or LEFT or RIGHT)
        } else if (!stretched && n == 2) {
            if (sh == "ww" && 1.4f * plateRatio < average && abs(ratios[1] - ratios[0]) < 0.2f) {
                val h = floor(min(W / ratios[0], min(W / ratios[1], (H - g) / 2)))
                put(0, 0f, 0f, W, h, TOP or LEFT or RIGHT)
                put(1, 0f, h + g, W, h, BOTTOM or LEFT or RIGHT)
            } else if (sh == "ww" || sh == "qq") {
                val w = (W - g) / 2
                val h = floor(min(w / ratios[0], min(w / ratios[1], H)))
                put(0, 0f, 0f, w, h, TOP or LEFT or BOTTOM)
                put(1, w + g, 0f, w, h, TOP or RIGHT or BOTTOM)
            } else {
                val second = floor(min(0.5f * (W - g), rnd((W - g) / ratios[0] / (1 / ratios[0] + 1 / ratios[1]))))
                val first = W - second - g
                val h = floor(min(H, rnd(min(first / ratios[0], second / ratios[1]))))
                put(0, 0f, 0f, first, h, TOP or LEFT or BOTTOM)
                put(1, first + g, 0f, second, h, TOP or RIGHT or BOTTOM)
            }
        } else if (!stretched && n == 3) {
            if (sh.startsWith("n")) {
                val firstH = H
                val thirdH = min((H - g) * 0.5f, rnd(ratios[1] * (W - g) / (ratios[2] + ratios[1])))
                val secondH = H - thirdH - g
                val rightW = max(minW, min((W - g) * 0.5f, rnd(min(thirdH * ratios[2], secondH * ratios[1]))))
                val leftW = rnd(min(firstH * ratios[0], W - g - rightW))
                put(0, 0f, 0f, leftW, firstH, TOP or LEFT or BOTTOM)
                put(1, leftW + g, 0f, rightW, secondH, RIGHT or TOP)
                put(2, leftW + g, secondH + g, rightW, thirdH, RIGHT or BOTTOM)
            } else {
                val firstH = floor(min(W / ratios[0], (H - g) * 0.66f))
                put(0, 0f, 0f, W, firstH, TOP or LEFT or RIGHT)
                val w = (W - g) / 2
                val secondH = min(H - firstH - g, rnd(min(w / ratios[1], w / ratios[2])))
                put(1, 0f, firstH + g, w, secondH, LEFT or BOTTOM)
                put(2, w + g, firstH + g, w, secondH, RIGHT or BOTTOM)
            }
        } else if (!stretched && n == 4) {
            if (sh.startsWith("w")) {
                val h0 = rnd(min(W / ratios[0], (H - g) * 0.66f))
                put(0, 0f, 0f, W, h0, TOP or LEFT or RIGHT)
                var h = rnd((W - 2 * g) / (ratios[1] + ratios[2] + ratios[3]))
                val w0 = max(minW, min((W - 2 * g) * 0.4f, h * ratios[1]))
                val w2 = max(max(minW, (W - 2 * g) * 0.33f), h * ratios[3])
                val w1 = W - w0 - w2 - 2 * g
                h = max(minH, min(H - h0 - g, h))
                put(1, 0f, h0 + g, w0, h, LEFT or BOTTOM)
                put(2, w0 + g, h0 + g, w1, h, BOTTOM)
                put(3, w0 + w1 + 2 * g, h0 + g, w2, h, RIGHT or BOTTOM)
            } else {
                val h = H
                val w0 = rnd(min(h * ratios[0], (W - g) * 0.6f))
                put(0, 0f, 0f, w0, h, TOP or LEFT or BOTTOM)
                var w = rnd((H - 2 * g) / (1 / ratios[1] + 1 / ratios[2] + 1 / ratios[3]))
                val h0 = floor(w / ratios[1]); val h1 = floor(w / ratios[2])
                val h2 = h - h0 - h1 - 2 * g
                w = max(minW, min(W - w0 - g, w))
                put(1, w0 + g, 0f, w, h0, RIGHT or TOP)
                put(2, w0 + g, h0 + g, w, h1, RIGHT)
                put(3, w0 + g, h0 + h1 + 2 * g, w, h2, RIGHT or BOTTOM)
            }
        } else {
            // The row cut: every picture is brought to a shape near square (a wide set crops the narrow ones, a narrow set the
            // wide ones), then the rows are tried.
            val cropped = ratios.map { r -> max(0.66667f, min(1.7f, if (1.1f < average) max(1f, r) else min(1f, r))) }
            fun rowHeight(from: Int, count: Int): Float { var sum = 0f; for (k in from until from + count) sum += cropped[k]; return (W - (count - 1) * g) / sum }
            val attempts = ArrayList<Pair<List<Int>, List<Float>>>()
            fun add(counts: List<Int>) {
                var start = 0
                val hs = ArrayList<Float>()
                for (k in counts) { hs.add(rowHeight(start, k)); start += k }
                attempts.add(counts to hs)
            }
            for (a in 1 until n) { val b = n - a; if (3 < a || 3 < b) continue; add(listOf(a, b)) }
            if (3 <= n) for (a in 1 until n - 1) for (b in 1 until n - a) {
                val c = n - a - b
                if (3 < a || (if (average < 0.85f) 4 else 3) < b || 3 < c) continue
                add(listOf(a, b, c))
            }
            if (4 <= n) for (a in 1 until n - 2) for (b in 1 until n - a - 1) for (c in 1 until n - a - b) {
                val d = n - a - b - c
                if (3 < a || 3 < b || 3 < c || 3 < d) continue
                add(listOf(a, b, c, d))
            }
            val target = floor(W / 3 * 4)
            var best: Pair<List<Int>, List<Float>>? = null
            var bestDiff = 0f
            for (a in attempts) {
                var total = g * (a.second.size - 1)
                var lowest = Float.MAX_VALUE
                for (h in a.second) { total += floor(h); lowest = min(lowest, floor(h)) }
                var diff = abs(total - target)
                val k = a.first
                if (1 < k.size && (k[1] < k[0] || (2 < k.size && k[2] < k[1]) || (3 < k.size && k[3] < k[2]))) diff *= 1.5f
                if (lowest < minW) diff *= 1.5f
                if (best == null || diff < bestDiff) { best = a; bestDiff = diff }
            }
            val b = best
            if (b != null) {
                var index = 0
                var y = 0f
                b.first.forEachIndexed { i, count ->
                    val lineH = ceil(b.second[i])
                    var x = 0f
                    var row = 0
                    if (i == 0) row = row or TOP
                    if (i == b.first.size - 1) row = row or BOTTOM
                    for (k in 0 until count) {
                        var pos = row
                        if (k == 0) pos = pos or LEFT
                        if (k == count - 1) pos = pos or RIGHT
                        if (row == 0) pos = INSIDE
                        val w = ceil(cropped[index] * lineH)
                        tiles[index] = Tile(RectF(x, y, x + w, y + lineH), pos)
                        x += w + g
                        index++
                    }
                    y += lineH + g
                }
                // The last tile of every row reaches the widest row's edge: the plate is a rectangle.
                var widest = 0f
                index = 0
                for (count in b.first) { index += count; widest = max(widest, tiles[index - 1].rect.right) }
                index = 0
                for (count in b.first) { index += count; val r = tiles[index - 1].rect; r.right = r.left + max(r.width(), widest - r.left) }
            }
        }
        var w = 0f
        var h = 0f
        for (t in tiles) { w = max(w, rnd(t.rect.right)); h = max(h, rnd(t.rect.bottom)) }
        return Cut(tiles, w, h)
    }
}

/** A tile cut to its own corners: the plate's outer corner is round, a corner that meets another tile only softened (iOS corners). */
private class CornerTile(c: Context, pos: Int, outer: Float, inner: Float) : FrameLayout(c) {
    private val radii: FloatArray
    private val path = Path()
    private val box = RectF()
    init {
        fun r(a: Int, b: Int) = if ((pos and a) != 0 && (pos and b) != 0) outer else inner
        val tl = r(Mosaic.TOP, Mosaic.LEFT); val tr = r(Mosaic.TOP, Mosaic.RIGHT)
        val br = r(Mosaic.BOTTOM, Mosaic.RIGHT); val bl = r(Mosaic.BOTTOM, Mosaic.LEFT)
        radii = floatArrayOf(tl, tl, tr, tr, br, br, bl, bl)
    }
    override fun dispatchDraw(canvas: Canvas) {
        box.set(0f, 0f, width.toFloat(), height.toFloat())
        path.reset(); path.addRoundRect(box, radii, Path.Direction.CW)
        val keep = canvas.save()
        canvas.clipPath(path)
        super.dispatchDraw(canvas)
        canvas.restoreToCount(keep)
    }
}

/** The tiles' pictures, decoded off a redraw's way once and kept by their file (the feed redraws on every receipt). */
private val albumCache = Caches.kept("album", object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
    override fun sizeOf(key: String, value: Bitmap) = value.byteCount
})

/** THE PLATE'S CEILING (iOS plateCeiling, at this app's picture width) and the ceiling of its height, four thirds of it. */
private const val PLATE_DP = 240f

/**
 * THE PLATE OF A MEDIA GROUP (iOS groupBubble / groupTile, MontanaBubble 1428-1524): the tiles at the frames the mosaic cut,
 * one point apart, in the sender's order; a film's tile wears its play sign; a tile still on its way its spinner, a waiting one
 * the arrow down, a failed own one the red mark; under them the one caption. A tap on a tile is that very letter's tap: a
 * picture opens among the chat's pictures, a film in its player, a waiting file is asked for.
 */
internal fun albumBody(c: Context, members: List<Msg>, into: LinearLayout) {
    val d = c.resources.displayMetrics.density
    val pics = members.map { m ->
        val man = Media.manifestOf(m)
        val kind = man?.optString("k") ?: "img"
        val f = m.file?.let { File(it) }?.takeIf { it.exists() }
        val key = (f?.path ?: ("th:" + m.mid))
        albumCache.get(key) ?: (f?.let { Media.preview(c, it, kind, 600) } ?: Media.thumbOf(man))?.also { b -> if (f != null) albumCache.put(key, b) }
    }
    val sizes = pics.map { b -> if (b != null && 0 < b.width && 0 < b.height) b.width.toFloat() to b.height.toFloat() else 1f to 1f }
    val cut = Mosaic.layout(PLATE_DP, PLATE_DP * 4 / 3, sizes)
    val plate = FrameLayout(c)
    members.forEachIndexed { i, m ->
        if (cut.tiles.size <= i) return@forEachIndexed
        val t = cut.tiles[i]
        val man = Media.manifestOf(m)
        val kind = man?.optString("k") ?: "img"
        val f = m.file?.let { File(it) }?.takeIf { it.exists() }
        val tile = CornerTile(c, t.pos, 12 * d, 3 * d)
        tile.addView(ImageView(c).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            val pic = pics[i]
            if (pic != null) setImageBitmap(pic) else setBackgroundColor(Color.rgb(51, 51, 51))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        fun sign(res: Int, side: Int) = c.icon(res, Color.WHITE).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(140, 0, 0, 0)) }
            val pad = side / 4; setPadding(pad, pad, pad, pad)
        }
        val side = c.dp(min(44f, max(28f, t.rect.width() * 0.22f)))
        if (f == null && Media.waiting(c, m)) tile.addView(sign(R.drawable.ic_arrow_circle_down, side), FrameLayout.LayoutParams(side, side, Gravity.CENTER))
        else if (f == null) tile.addView(android.widget.ProgressBar(c), FrameLayout.LayoutParams(c.dp(28), c.dp(28), Gravity.CENTER))
        else if (kind == "vid") tile.addView(sign(R.drawable.ic_play_fill, side), FrameLayout.LayoutParams(side, side, Gravity.CENTER))
        if (m.mine && m.state == -1) tile.addView(c.failedMark(), FrameLayout.LayoutParams(c.dp(16), c.dp(16), Gravity.TOP or Gravity.END).apply { setMargins(0, c.dp(6), c.dp(6), 0) })
        if (f != null) tile.setOnClickListener { (c as? MainActivity)?.let { a -> openMedia(a, f, kind) } }
        else if (Media.waiting(c, m)) tile.setOnClickListener { Media.tapped(c, m) }
        plate.addView(tile, FrameLayout.LayoutParams(ceil(t.rect.width() * d).toInt(), ceil(t.rect.height() * d).toInt()).apply {
            leftMargin = (t.rect.left * d).toInt(); topMargin = (t.rect.top * d).toInt()
        })
    }
    into.addView(plate, LinearLayout.LayoutParams((cut.w * d).toInt(), (cut.h * d).toInt()).apply { bottomMargin = c.dp(4) })
    if (members.any { it.mine && it.state == -1 }) into.addView(c.text(c.getString(R.string.media_failed), 12f, SysColor.red))
    // THE ONE CAPTION (iOS groupCaption): the words ride with the first letter of the pick
    members.firstNotNullOfOrNull { m -> Media.manifestOf(m)?.optString("cap")?.takeIf { it.isNotEmpty() } }?.let { cap ->
        into.addView(c.text(cap, 16f, BubbleStyle.text(members[0].mine)).apply { maxWidth = (cut.w * d).toInt() })   // USER-DATA: the caption
    }
}

/**
 * THE FEED'S ROWS (iOS buildRows, MontanaConversation 2431-2464): the neighbours sharing one group key fold into the row of their
 * first letter and stand in the sender's order, not in the order of arrival. A letter of another kind between them, a stranger's
 * key, or the other side's letter ends the fold; ten is the ceiling.
 */
internal fun feedRows(msgs: List<Msg>): List<List<Msg>> {
    val out = ArrayList<List<Msg>>(msgs.size)
    var start = 0
    while (start < msgs.size) {
        val m = msgs[start]
        val key = if (Mosaic.folds(m)) MediaGroup.of(m)?.key else null
        var j = start + 1
        if (key != null) while (j < msgs.size && j - start < MediaGroup.CEILING && msgs[j].mine == m.mine && Mosaic.folds(msgs[j]) && MediaGroup.of(msgs[j])?.key == key) j++
        out.add(if (2 <= j - start) msgs.subList(start, j).sortedBy { MediaGroup.of(it)?.index ?: 0 } else listOf(m))
        start = if (2 <= j - start) j else start + 1
    }
    return out
}
