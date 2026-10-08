package quest.montana.app

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * READING A CODE FROM A PICTURE (iOS ScanMeetingView reads with the system's detector; Android offers an app none without a
 * library, so the reading is written here, ISO/IEC 18004 by the letter): the picture's brightness → dark and light by a local
 * threshold → the three finder patterns (1:1:3:1:1) → the grid's size and the alignment pattern → the grid sampled through a
 * perspective transform → the format word (the nearest of the 32 lawful ones) → unmasked, the codewords in their zigzag →
 * blocks de-interleaved and each corrected by Reed–Solomon (Euclid, Chien, Forney) → the segments (numeric, alphanumeric,
 * bytes) read into text. Pure Kotlin — no platform class — so the same file is proven on the Mac against real codes.
 */
object QrReader {

    /** The text of the first code found in a picture of brightness bytes (row-major, `stride` bytes a row), or null. */
    fun read(lum: ByteArray, w: Int, h: Int, stride: Int = w): String? {
        val bits = binarize(lum, w, h, stride)
        val finders = findFinders(bits, w, h)
        if (finders.size < 3) return null
        // The three finders most seen, of the most alike module size, tried in turn.
        val cands = finders.sortedByDescending { it.count }.take(6)
        for (i in cands.indices) for (j in i + 1 until cands.size) for (k in j + 1 until cands.size) {
            val t = listOf(cands[i], cands[j], cands[k])
            val ms = t.map { it.ms }
            if (ms.max() > ms.min() * 1.6f) continue
            // Three corners of a square: two sides alike, the third √2 of them.
            val d = listOf(dist(t[0], t[1]), dist(t[1], t[2]), dist(t[0], t[2])).sorted()
            if (d[1] > d[0] * 1.4f || d[2] < d[1] * 1.15f || d[2] > d[1] * 1.7f) continue
            decodeAt(bits, w, h, t)?.let { return it }
        }
        return null
    }

    // ── dark and light ──

    /** A block threshold (8×8 blocks, each judged against its 5×5 neighbourhood's mean) — steady under uneven light. */
    private fun binarize(lum: ByteArray, w: Int, h: Int, stride: Int): BooleanArray {
        val bs = 8
        val bw = (w + bs - 1) / bs; val bh = (h + bs - 1) / bs
        val avg = IntArray(bw * bh)
        for (by in 0 until bh) for (bx in 0 until bw) {
            var sum = 0; var n = 0; var mn = 255; var mx = 0
            for (y in by * bs until minOf(h, by * bs + bs)) for (x in bx * bs until minOf(w, bx * bs + bs)) {
                val v = lum[y * stride + x].toInt() and 0xFF
                sum += v; n++; if (v < mn) mn = v; if (v > mx) mx = v
            }
            // A flat block takes the side of the light: half its darkest, as the reference readers do.
            avg[by * bw + bx] = if (mx - mn > 24) sum / n else mn / 2
        }
        val out = BooleanArray(w * h)
        for (by in 0 until bh) for (bx in 0 until bw) {
            var s = 0; var n = 0
            for (dy in -2..2) for (dx in -2..2) {
                val x = bx + dx; val y = by + dy
                if (x in 0 until bw && y in 0 until bh) { s += avg[y * bw + x]; n++ }
            }
            val t = s / n
            for (y in by * bs until minOf(h, by * bs + bs)) for (x in bx * bs until minOf(w, bx * bs + bs))
                out[y * w + x] = (lum[y * stride + x].toInt() and 0xFF) <= t
        }
        return out
    }

    // ── the finder patterns ──

    private class Center(var x: Float, var y: Float, var ms: Float, var count: Int = 1)

    private fun ratioOk(c: IntArray): Boolean {
        val total = c.sum()
        if (total < 7) return false
        val m = total / 7f; val v = m / 1.6f
        return abs(c[0] - m) < v && abs(c[1] - m) < v && abs(c[2] - 3 * m) < 3 * v && abs(c[3] - m) < v && abs(c[4] - m) < v
    }

    private fun findFinders(b: BooleanArray, w: Int, h: Int): List<Center> {
        val found = ArrayList<Center>()
        fun dark(x: Int, y: Int) = b[y * w + x]
        /** Along a line from the centre both ways: the five runs, the centre by them, or NaN. */
        fun cross(cx: Int, cy: Int, dx: Int, dy: Int, maxRun: Int): Float {
            val c = IntArray(5)
            fun inside(x: Int, y: Int) = x in 0 until w && y in 0 until h
            var x = cx; var y = cy
            while (inside(x, y) && dark(x, y)) { c[2]++; x -= dx; y -= dy }
            while (inside(x, y) && !dark(x, y) && c[1] <= maxRun) { c[1]++; x -= dx; y -= dy }
            while (inside(x, y) && dark(x, y) && c[0] <= maxRun) { c[0]++; x -= dx; y -= dy }
            val back = c[2]
            x = cx + dx; y = cy + dy
            while (inside(x, y) && dark(x, y)) { c[2]++; x += dx; y += dy }
            while (inside(x, y) && !dark(x, y) && c[3] <= maxRun) { c[3]++; x += dx; y += dy }
            while (inside(x, y) && dark(x, y) && c[4] <= maxRun) { c[4]++; x += dx; y += dy }
            if (!ratioOk(c)) return Float.NaN
            val start = (if (dx != 0) cx else cy) - back + 1
            return start + c[2] / 2f
        }
        fun handle(c: IntArray, endX: Int, y: Int) {
            val cxf = endX - c[4] - c[3] - c[2] / 2f
            val total = c.sum()
            val cyf = cross(cxf.toInt(), y, 0, 1, total)
            if (cyf.isNaN()) return
            val cx2 = cross(cxf.toInt(), cyf.toInt(), 1, 0, total)
            if (cx2.isNaN()) return
            val ms = total / 7f
            val near = found.firstOrNull { abs(it.x - cx2) <= ms * 1.5f && abs(it.y - cyf) <= ms * 1.5f }
            if (near != null) {
                val n = near.count
                near.x = (near.x * n + cx2) / (n + 1); near.y = (near.y * n + cyf) / (n + 1); near.ms = (near.ms * n + ms) / (n + 1); near.count++
            } else found.add(Center(cx2, cyf, ms))
        }
        val c = IntArray(5)
        var y = 0
        while (y < h) {
            c.fill(0); var state = 0
            for (x in 0 until w) {
                if (dark(x, y)) {
                    if (state and 1 == 1) state++          // light run ended: the next dark run
                    c[state]++
                } else if (state and 1 == 0) {             // a dark run ends
                    if (state == 4) {
                        if (ratioOk(c)) handle(c, x, y)
                        shift(c); c[3] = 1; state = 3
                    } else { state++; c[state]++ }
                } else c[state]++
            }
            if (state == 4 && ratioOk(c)) handle(c, w, y)
            y += 2
        }
        return found.filter { it.count >= 2 }
    }
    private fun shift(c: IntArray) { c[0] = c[2]; c[1] = c[3]; c[2] = c[4]; c[3] = 0; c[4] = 0 }

    // ── the grid ──

    private fun dist(a: Center, b: Center) = hypot(a.x - b.x, a.y - b.y)

    private fun decodeAt(b: BooleanArray, w: Int, h: Int, t: List<Center>): String? {
        // The corner opposite the longest side is the top left; the turn of the other two decides which is which.
        val (p0, p1, p2) = t
        val d01 = dist(p0, p1); val d12 = dist(p1, p2); val d02 = dist(p0, p2)
        var a: Center; val tl: Center; var c: Center
        if (d12 >= d01 && d12 >= d02) { tl = p0; a = p1; c = p2 }
        else if (d02 >= d12 && d02 >= d01) { tl = p1; a = p0; c = p2 }
        else { tl = p2; a = p0; c = p1 }
        if ((c.x - tl.x) * (a.y - tl.y) - (c.y - tl.y) * (a.x - tl.x) < 0) { val s = a; a = c; c = s }
        val bl = a; val tr = c
        // THE MODULE MEASURED ALONG THE SIDES (as the reference readers do): a turned code's modules look wider across a row.
        val along = listOf(ringRun(b, w, h, tl, tr), ringRun(b, w, h, tr, tl), ringRun(b, w, h, tl, bl), ringRun(b, w, h, bl, tl)).filter { it > 0 }
        val ms = if (along.size >= 2) along.average().toFloat() else (tl.ms + tr.ms + bl.ms) / 3
        var dim0 = ((dist(tl, tr) / ms).roundToInt() + (dist(tl, bl) / ms).roundToInt()) / 2 + 7
        when (dim0 and 3) { 0 -> dim0++; 2 -> dim0--; 3 -> dim0 -= 2 }
        for (dim in intArrayOf(dim0, dim0 + 4, dim0 - 4)) {
            if (dim < 21 || dim > 177) continue
            sampleAndDecode(b, w, h, tl, tr, bl, ms, dim)?.let { return it }
        }
        return null
    }

    /** From a finder's centre toward another: the finder's edge stands 3.5 modules out (dark 1.5, light 1, dark 1). */
    private fun ringRun(b: BooleanArray, w: Int, h: Int, from: Center, to: Center): Float {
        val len = dist(from, to); if (len < 1) return -1f
        val ux = (to.x - from.x) / len; val uy = (to.y - from.y) / len
        var state = true; var flips = 0; var k = 0f
        while (k < len / 2) {
            val x = (from.x + ux * k).toInt(); val y = (from.y + uy * k).toInt()
            if (x !in 0 until w || y !in 0 until h) return -1f
            val d = b[y * w + x]
            if (d != state) { state = d; flips++; if (flips == 3) return k / 3.5f }
            k += 0.5f
        }
        return -1f
    }

    private fun sampleAndDecode(b: BooleanArray, w: Int, h: Int, tl: Center, tr: Center, bl: Center, ms: Float, dim: Int): String? {
        val ver = (dim - 17) / 4
        // The alignment pattern nearest the bottom right, where the grid says it stands; the fourth corner otherwise.
        val brX = tr.x - tl.x + bl.x; val brY = tr.y - tl.y + bl.y
        var srcBR = dim - 3.5f
        var dstX = brX; var dstY = brY
        if (ver >= 2) {
            val corr = 1f - 3f / (dim - 7)
            val ex = tl.x + corr * (brX - tl.x); val ey = tl.y + corr * (brY - tl.y)
            findAlignment(b, w, h, ex, ey, ms)?.let { (ax, ay) -> dstX = ax; dstY = ay; srcBR = dim - 6.5f }
        }
        val tf = Perspective.quadToQuad(3.5f, 3.5f, dim - 3.5f, 3.5f, srcBR, srcBR, 3.5f, dim - 3.5f,
            tl.x, tl.y, tr.x, tr.y, dstX, dstY, bl.x, bl.y)
        val grid = Array(dim) { BooleanArray(dim) }
        for (gy in 0 until dim) for (gx in 0 until dim) {
            val (px, py) = tf.map(gx + 0.5f, gy + 0.5f)
            val ix = px.toInt(); val iy = py.toInt()
            if (ix !in 0 until w || iy !in 0 until h) return null
            grid[gy][gx] = b[iy * w + ix]
        }
        return decodeGrid(grid) ?: decodeGrid(Array(dim) { y -> BooleanArray(dim) { x -> grid[x][y] } })   // a mirrored reading
    }

    private fun findAlignment(b: BooleanArray, w: Int, h: Int, ex: Float, ey: Float, ms: Float): Pair<Float, Float>? {
        val m = maxOf(1, ms.roundToInt())
        fun dark(x: Int, y: Int) = x in 0 until w && y in 0 until h && b[y * w + x]
        fun ok(x: Int, y: Int): Boolean {
            if (!dark(x, y)) return false
            for ((dx, dy) in listOf(1 to 0, -1 to 0, 0 to 1, 0 to -1)) {
                var k = 1; while (k <= m * 2 && dark(x + dx * k, y + dy * k)) k++
                if (k > m + m / 2 + 1) return false          // the centre is one module
                var l = 0; while (l <= m * 2 && !dark(x + dx * (k + l), y + dy * (k + l))) l++
                if (l == 0 || l > m + m / 2 + 1) return false  // then one module of light
                if (!dark(x + dx * (k + l), y + dy * (k + l))) return false   // then the dark ring
            }
            return true
        }
        var best: Pair<Float, Float>? = null; var bestD = Float.MAX_VALUE
        val r = (ms * 5).toInt()
        for (y in (ey - r).toInt()..(ey + r).toInt()) for (x in (ex - r).toInt()..(ex + r).toInt()) {
            if (!ok(x, y)) continue
            val d = hypot(x - ex, y - ey)
            if (d < bestD) { bestD = d; best = x + 0.5f to y + 0.5f }
        }
        return best
    }

    // ── the bits ──

    private val FORMATS = IntArray(32) { d -> var rem = d; repeat(10) { rem = (rem shl 1) xor ((rem ushr 9) * 0x537) }; ((d shl 10) or rem) xor 0x5412 }

    private fun decodeGrid(g: Array<BooleanArray>): String? {
        val size = g.size
        fun bit(x: Int, y: Int) = if (g[y][x]) 1 else 0
        var f1 = 0
        for (i in 0..5) f1 = f1 or (bit(8, i) shl i)
        f1 = f1 or (bit(8, 7) shl 6) or (bit(8, 8) shl 7) or (bit(7, 8) shl 8)
        for (i in 9 until 15) f1 = f1 or (bit(14 - i, 8) shl i)
        var f2 = 0
        for (i in 0 until 8) f2 = f2 or (bit(size - 1 - i, 8) shl i)
        for (i in 8 until 15) f2 = f2 or (bit(8, size - 15 + i) shl i)
        var best = -1; var bestD = 99
        for (d in 0 until 32) for (f in intArrayOf(f1, f2)) {
            val dd = Integer.bitCount(FORMATS[d] xor f)
            if (dd < bestD) { bestD = dd; best = d }
        }
        if (bestD > 3) return null
        val eclBits = best ushr 3; val mask = best and 7
        val ecl = when (eclBits) { 1 -> 0; 0 -> 1; 3 -> 2; else -> 3 }   // L M Q H
        val ver = (size - 17) / 4
        val fn = functionMap(ver, size)
        val raw = ArrayList<Int>()
        var cur = 0; var nb = 0
        var right = size - 1
        while (right >= 1) {
            if (right == 6) right = 5
            for (vert in 0 until size) for (j in 0..1) {
                val x = right - j
                val up = ((right + 1) and 2) == 0
                val y = if (up) size - 1 - vert else vert
                if (fn[y][x]) continue
                var v = g[y][x]
                if (masked(mask, x, y)) v = !v
                cur = (cur shl 1) or (if (v) 1 else 0); nb++
                if (nb == 8) { raw.add(cur); cur = 0; nb = 0 }
            }
            right -= 2
        }
        val data = deinterleave(raw, ver, ecl) ?: return null
        return segments(data, ver)
    }

    private fun masked(mask: Int, x: Int, y: Int) = when (mask) {
        0 -> (x + y) % 2 == 0; 1 -> y % 2 == 0; 2 -> x % 3 == 0; 3 -> (x + y) % 3 == 0
        4 -> (x / 3 + y / 2) % 2 == 0; 5 -> x * y % 2 + x * y % 3 == 0
        6 -> (x * y % 2 + x * y % 3) % 2 == 0; else -> ((x + y) % 2 + x * y % 3) % 2 == 0
    }

    /** Where the function patterns stand (the finders with their separators, timing, alignment, format and version). */
    private fun functionMap(ver: Int, size: Int): Array<BooleanArray> {
        val fn = Array(size) { BooleanArray(size) }
        fun rect(x0: Int, y0: Int, w: Int, h: Int) { for (y in y0 until y0 + h) for (x in x0 until x0 + w) if (x in 0 until size && y in 0 until size) fn[y][x] = true }
        for (i in 0 until size) { fn[6][i] = true; fn[i][6] = true }
        rect(0, 0, 9, 9); rect(size - 8, 0, 8, 9); rect(0, size - 8, 9, 8)
        val al = alignment(ver, size)
        for (i in al.indices) for (j in al.indices) {
            if ((i == 0 && j == 0) || (i == 0 && j == al.size - 1) || (i == al.size - 1 && j == 0)) continue
            rect(al[i] - 2, al[j] - 2, 5, 5)
        }
        if (ver >= 7) { rect(size - 11, 0, 3, 6); rect(0, size - 11, 6, 3) }
        return fn
    }
    private fun alignment(ver: Int, size: Int): IntArray {
        if (ver == 1) return IntArray(0)
        val n = ver / 7 + 2
        val step = if (ver == 32) 26 else (ver * 4 + n * 2 + 1) / (n * 2 - 2) * 2
        val r = IntArray(n); r[0] = 6
        var pos = size - 7
        for (i in n - 1 downTo 1) { r[i] = pos; pos -= step }
        return r
    }

    // The standard's tables, L M Q H (index 0 unused).
    private val ECC = arrayOf(
        intArrayOf(-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30),
        intArrayOf(-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28),
        intArrayOf(-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30),
        intArrayOf(-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30))
    private val BLOCKS = arrayOf(
        intArrayOf(-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25),
        intArrayOf(-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49),
        intArrayOf(-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68),
        intArrayOf(-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81))

    private fun rawModules(ver: Int): Int {
        var r = (16 * ver + 128) * ver + 64
        if (ver >= 2) { val n = ver / 7 + 2; r -= (25 * n - 10) * n - 55; if (ver >= 7) r -= 36 }
        return r
    }

    /** The interleaving undone (the encoder's own loop, run backwards) and every block corrected. */
    private fun deinterleave(raw: List<Int>, ver: Int, ecl: Int): IntArray? {
        val total = rawModules(ver) / 8
        if (raw.size < total) return null
        val nBlocks = BLOCKS[ecl][ver]; val eccLen = ECC[ecl][ver]
        val shortBlocks = nBlocks - total % nBlocks
        val shortLen = total / nBlocks
        val blocks = Array(nBlocks) { IntArray(shortLen + 1) }
        var n = 0
        for (i in 0..shortLen) for (j in 0 until nBlocks) {
            if (i != shortLen - eccLen || j >= shortBlocks) blocks[j][i] = raw[n++]
        }
        val out = ArrayList<Int>()
        for (j in 0 until nBlocks) {
            val dLen = shortLen - eccLen + (if (j < shortBlocks) 0 else 1)
            val cw = IntArray(dLen + eccLen)
            for (k in 0 until dLen) cw[k] = blocks[j][k]
            for (k in 0 until eccLen) cw[dLen + k] = blocks[j][shortLen + 1 - eccLen + k]
            if (!RS.correct(cw, eccLen)) return null
            for (k in 0 until dLen) out.add(cw[k])
        }
        return out.toIntArray()
    }

    /** The segments: numeric, alphanumeric and bytes (UTF-8, as every phone writes a link); ECI is read and passed over. */
    private fun segments(d: IntArray, ver: Int): String? {
        var pos = 0
        fun take(n: Int): Int {
            var v = 0
            repeat(n) { if (pos / 8 >= d.size) return -1; v = (v shl 1) or ((d[pos / 8] ushr (7 - pos % 8)) and 1); pos++ }
            return v
        }
        val bytes = java.io.ByteArrayOutputStream()
        val alnum = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
        while (pos + 4 <= d.size * 8) {
            when (take(4)) {
                0, -1 -> break
                4 -> { val n = take(if (ver <= 9) 8 else 16); repeat(n) { val b = take(8); if (b < 0) return null; bytes.write(b) } }
                2 -> {
                    var n = take(if (ver <= 9) 9 else if (ver <= 26) 11 else 13)
                    while (n >= 2) { val v = take(11); bytes.write(alnum[v / 45].code); bytes.write(alnum[v % 45].code); n -= 2 }
                    if (n == 1) bytes.write(alnum[take(6)].code)
                }
                1 -> {
                    var n = take(if (ver <= 9) 10 else if (ver <= 26) 12 else 14)
                    while (n >= 3) { bytes.write("%03d".format(take(10)).toByteArray()); n -= 3 }
                    if (n == 2) bytes.write("%02d".format(take(7)).toByteArray()) else if (n == 1) bytes.write(take(4).toString().toByteArray())
                }
                7 -> { val first = take(8); if (first and 0x80 != 0) take(if (first and 0x40 != 0) 16 else 8) }
                else -> return null
            }
        }
        return bytes.toByteArray().toString(Charsets.UTF_8).ifEmpty { null }
    }

    // ── Reed–Solomon over GF(256), x⁸+x⁴+x³+x²+1, the generator's roots α⁰…α^(n−1) ──

    private object RS {
        private val exp = IntArray(512); private val log = IntArray(256)
        init { var x = 1; for (i in 0 until 255) { exp[i] = x; log[x] = i; x = x shl 1; if (x and 0x100 != 0) x = x xor 0x11D }; for (i in 255 until 512) exp[i] = exp[i - 255] }
        fun mul(a: Int, b: Int) = if (a == 0 || b == 0) 0 else exp[log[a] + log[b]]
        fun inv(a: Int) = exp[255 - log[a]]

        // Polynomials with the highest degree first, as the reference decoder keeps them.
        private fun norm(p: IntArray): IntArray { var i = 0; while (i < p.size - 1 && p[i] == 0) i++; return if (i == 0) p else p.copyOfRange(i, p.size) }
        private fun deg(p: IntArray) = p.size - 1
        private fun zero(p: IntArray) = p[0] == 0
        private fun eval(p: IntArray, x: Int): Int { if (x == 0) return p[p.size - 1]; var r = 0; for (c in p) r = mul(r, x) xor c; return r }
        private fun add(a: IntArray, b: IntArray): IntArray {
            if (zero(a)) return b; if (zero(b)) return a
            val (s, l) = if (a.size > b.size) b to a else a to b
            val r = l.copyOf(); val d = l.size - s.size
            for (i in s.indices) r[i + d] = r[i + d] xor s[i]
            return norm(r)
        }
        private fun times(a: IntArray, b: IntArray): IntArray {
            if (zero(a) || zero(b)) return intArrayOf(0)
            val r = IntArray(a.size + b.size - 1)
            for (i in a.indices) for (j in b.indices) r[i + j] = r[i + j] xor mul(a[i], b[j])
            return norm(r)
        }
        private fun scale(a: IntArray, s: Int) = norm(IntArray(a.size) { mul(a[it], s) })
        private fun mono(degree: Int, c: Int): IntArray { if (c == 0) return intArrayOf(0); val r = IntArray(degree + 1); r[0] = c; return r }

        /** Corrects the codeword in place; false when it cannot be corrected. */
        fun correct(cw: IntArray, twoS: Int): Boolean {
            val poly = norm(cw.copyOf())
            val syn = IntArray(twoS)
            var clean = true
            for (i in 0 until twoS) { val e = eval(poly, exp[i]); syn[twoS - 1 - i] = e; if (e != 0) clean = false }
            if (clean) return true
            // Euclid's algorithm towards the locator σ and the evaluator ω.
            var rLast = mono(twoS, 1); var r = norm(syn)
            if (deg(rLast) < deg(r)) { val t = rLast; rLast = r; r = t }
            var tLast = intArrayOf(0); var t = intArrayOf(1)
            while (2 * deg(r) >= twoS) {
                val rLastLast = rLast; val tLastLast = tLast
                rLast = r; tLast = t
                if (zero(rLast)) return false
                r = rLastLast
                var q = intArrayOf(0)
                val dlt = inv(rLast[0])
                while (deg(r) >= deg(rLast) && !zero(r)) {
                    val dd = deg(r) - deg(rLast)
                    val sc = mul(r[0], dlt)
                    q = add(q, mono(dd, sc))
                    r = add(r, times(rLast, mono(dd, sc)))
                }
                t = add(times(q, tLast), tLastLast)
                if (deg(r) >= deg(rLast)) return false
            }
            val s0 = t[t.size - 1]
            if (s0 == 0) return false
            val sigma = scale(t, inv(s0)); val omega = scale(r, inv(s0))
            // Chien: the error places.
            val nErr = deg(sigma)
            val locs = IntArray(nErr)
            if (nErr == 1) locs[0] = sigma[0]
            else { var e = 0; var i = 1; while (i < 256 && e < nErr) { if (eval(sigma, i) == 0) { locs[e++] = inv(i) }; i++ }; if (e != nErr) return false }
            // Forney: the error values.
            for (i in 0 until nErr) {
                val xi = inv(locs[i])
                var den = 1
                for (j in 0 until nErr) if (j != i) den = mul(den, mul(locs[j], xi) xor 1)
                val mag = mul(eval(omega, xi), inv(den))
                val p = cw.size - 1 - log[locs[i]]
                if (p < 0) return false
                cw[p] = cw[p] xor mag
            }
            return true
        }
    }

    // ── the perspective (the reference readers' quadrilateral-to-quadrilateral map) ──

    private class Perspective(val a11: Float, val a21: Float, val a31: Float, val a12: Float, val a22: Float, val a32: Float, val a13: Float, val a23: Float, val a33: Float) {
        fun map(x: Float, y: Float): Pair<Float, Float> {
            val d = a13 * x + a23 * y + a33
            return (a11 * x + a21 * y + a31) / d to (a12 * x + a22 * y + a32) / d
        }
        fun adjoint() = Perspective(a22 * a33 - a23 * a32, a23 * a31 - a21 * a33, a21 * a32 - a22 * a31,
            a13 * a32 - a12 * a33, a11 * a33 - a13 * a31, a12 * a31 - a11 * a32,
            a12 * a23 - a13 * a22, a13 * a21 - a11 * a23, a11 * a22 - a12 * a21)
        fun times(o: Perspective) = Perspective(
            a11 * o.a11 + a21 * o.a12 + a31 * o.a13, a11 * o.a21 + a21 * o.a22 + a31 * o.a23, a11 * o.a31 + a21 * o.a32 + a31 * o.a33,
            a12 * o.a11 + a22 * o.a12 + a32 * o.a13, a12 * o.a21 + a22 * o.a22 + a32 * o.a23, a12 * o.a31 + a22 * o.a32 + a32 * o.a33,
            a13 * o.a11 + a23 * o.a12 + a33 * o.a13, a13 * o.a21 + a23 * o.a22 + a33 * o.a23, a13 * o.a31 + a23 * o.a32 + a33 * o.a33)
        companion object {
            fun squareToQuad(x0: Float, y0: Float, x1: Float, y1: Float, x2: Float, y2: Float, x3: Float, y3: Float): Perspective {
                val dx3 = x0 - x1 + x2 - x3; val dy3 = y0 - y1 + y2 - y3
                if (dx3 == 0f && dy3 == 0f) return Perspective(x1 - x0, x2 - x1, x0, y1 - y0, y2 - y1, y0, 0f, 0f, 1f)
                val dx1 = x1 - x2; val dx2 = x3 - x2; val dy1 = y1 - y2; val dy2 = y3 - y2
                val den = dx1 * dy2 - dx2 * dy1
                val a13 = (dx3 * dy2 - dx2 * dy3) / den; val a23 = (dx1 * dy3 - dx3 * dy1) / den
                return Perspective(x1 - x0 + a13 * x1, x3 - x0 + a23 * x3, x0, y1 - y0 + a13 * y1, y3 - y0 + a23 * y3, y0, a13, a23, 1f)
            }
            fun quadToQuad(x0: Float, y0: Float, x1: Float, y1: Float, x2: Float, y2: Float, x3: Float, y3: Float,
                           u0: Float, v0: Float, u1: Float, v1: Float, u2: Float, v2: Float, u3: Float, v3: Float) =
                squareToQuad(u0, v0, u1, v1, u2, v2, u3, v3).times(squareToQuad(x0, y0, x1, y1, x2, y2, x3, y3).adjoint())
        }
    }
}
