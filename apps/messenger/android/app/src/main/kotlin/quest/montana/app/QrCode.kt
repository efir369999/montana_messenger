package quest.montana.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import kotlin.math.abs
import kotlin.math.max

/**
 * THE QR CODE, DRAWN BY THE APP ITSELF (iOS draws it with the platform's CIQRCodeGenerator; Android's platform has no QR
 * encoder, and a library is not taken in). ISO/IEC 18004: byte mode, the smallest version that holds the text, Reed–Solomon
 * error correction — M under a mark at the centre, L without one (iOS MontanaQR: «a code that carries a mark is built with
 * correction M») — and the mask of the least penalty.
 */
class QrCode private constructor(val size: Int, private val modules: Array<BooleanArray>) {
    fun dark(x: Int, y: Int) = modules[y][x]

    enum class Ecc(val format: Int, val ordinal2: Int) { L(1, 0), M(0, 1) }

    companion object {
        fun encode(text: String, ecc: Ecc): QrCode? {
            val data = text.toByteArray(Charsets.UTF_8)
            for (ver in 1..40) {
                val ccBits = if (ver <= 9) 8 else 16
                val capacity = dataCodewords(ver, ecc) * 8
                val used = 4 + ccBits + data.size * 8
                if (used <= capacity) return build(ver, ecc, data, ccBits, capacity)
            }
            return null
        }

        // The standard's own tables (index 0 unused): error-correction codewords per block, and the number of blocks.
        private val ECC_PER_BLOCK = arrayOf(
            intArrayOf(-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30),
            intArrayOf(-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28))
        private val BLOCKS = arrayOf(
            intArrayOf(-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25),
            intArrayOf(-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49))

        private fun rawModules(ver: Int): Int {
            var r = (16 * ver + 128) * ver + 64
            if (ver >= 2) {
                val n = ver / 7 + 2
                r -= (25 * n - 10) * n - 55
                if (ver >= 7) r -= 36
            }
            return r
        }
        private fun dataCodewords(ver: Int, e: Ecc) = rawModules(ver) / 8 - ECC_PER_BLOCK[e.ordinal2][ver] * BLOCKS[e.ordinal2][ver]

        private fun build(ver: Int, ecc: Ecc, data: ByteArray, ccBits: Int, capacity: Int): QrCode {
            // The bit stream: mode 0100, the count, the bytes, the terminator, then the pad bytes.
            val bits = ArrayList<Boolean>(capacity)
            fun put(v: Int, n: Int) { for (i in n - 1 downTo 0) bits += (v ushr i) and 1 == 1 }
            put(4, 4); put(data.size, ccBits)
            for (b in data) put(b.toInt() and 0xFF, 8)
            put(0, minOf(4, capacity - bits.size))
            put(0, (8 - bits.size % 8) % 8)
            var pad = 0xEC
            while (bits.size < capacity) { put(pad, 8); pad = pad xor (0xEC xor 0x11) }
            val words = ByteArray(bits.size / 8) { i -> var v = 0; for (j in 0 until 8) if (bits[i * 8 + j]) v = v or (1 shl (7 - j)); v.toByte() }

            // The blocks and their Reed–Solomon codewords, interleaved.
            val nBlocks = BLOCKS[ecc.ordinal2][ver]
            val eccLen = ECC_PER_BLOCK[ecc.ordinal2][ver]
            val raw = rawModules(ver) / 8
            val shortBlocks = nBlocks - raw % nBlocks
            val shortLen = raw / nBlocks
            val divisor = rsDivisor(eccLen)
            val blocks = ArrayList<ByteArray>()
            var k = 0
            for (i in 0 until nBlocks) {
                val dLen = shortLen - eccLen + (if (i < shortBlocks) 0 else 1)
                val dat = words.copyOfRange(k, k + dLen); k += dLen
                val block = ByteArray(shortLen + 1)
                dat.copyInto(block)
                rsRemainder(dat, divisor).copyInto(block, shortLen + 1 - eccLen)
                blocks += block
            }
            val all = ByteArray(raw)
            var n = 0
            for (i in 0..shortLen) for (j in blocks.indices) {
                if (i != shortLen - eccLen || j >= shortBlocks) { all[n++] = blocks[j][i] }
            }

            val size = ver * 4 + 17
            val m = Array(size) { BooleanArray(size) }
            val fn = Array(size) { BooleanArray(size) }
            fun set(x: Int, y: Int, d: Boolean) { m[y][x] = d; fn[y][x] = true }
            for (i in 0 until size) { set(6, i, i % 2 == 0); set(i, 6, i % 2 == 0) }
            fun finder(cx: Int, cy: Int) {
                for (dy in -4..4) for (dx in -4..4) {
                    val x = cx + dx; val y = cy + dy
                    if (x in 0 until size && y in 0 until size) { val d = max(abs(dx), abs(dy)); set(x, y, d != 2 && d != 4) }
                }
            }
            finder(3, 3); finder(size - 4, 3); finder(3, size - 4)
            val align = alignment(ver, size)
            for (i in align.indices) for (j in align.indices) {
                if ((i == 0 && j == 0) || (i == 0 && j == align.size - 1) || (i == align.size - 1 && j == 0)) continue
                for (dy in -2..2) for (dx in -2..2) set(align[i] + dx, align[j] + dy, max(abs(dx), abs(dy)) != 1)
            }
            fun format(mask: Int) {
                val d = ecc.format shl 3 or mask
                var rem = d
                repeat(10) { rem = (rem shl 1) xor ((rem ushr 9) * 0x537) }
                val b = (d shl 10 or rem) xor 0x5412
                fun bit(i: Int) = (b ushr i) and 1 == 1
                for (i in 0..5) set(8, i, bit(i))
                set(8, 7, bit(6)); set(8, 8, bit(7)); set(7, 8, bit(8))
                for (i in 9 until 15) set(14 - i, 8, bit(i))
                for (i in 0 until 8) set(size - 1 - i, 8, bit(i))
                for (i in 8 until 15) set(8, size - 15 + i, bit(i))
                set(8, size - 8, true)
            }
            format(0)
            if (ver >= 7) {
                var rem = ver
                repeat(12) { rem = (rem shl 1) xor ((rem ushr 11) * 0x1F25) }
                val b = ver shl 12 or rem
                for (i in 0 until 18) {
                    val bit = (b ushr i) and 1 == 1
                    val a = size - 11 + i % 3; val c = i / 3
                    set(a, c, bit); set(c, a, bit)
                }
            }
            // The codewords, in the zigzag of two columns.
            var bi = 0
            var right = size - 1
            while (right >= 1) {
                if (right == 6) right = 5
                for (vert in 0 until size) for (j in 0..1) {
                    val x = right - j
                    val up = ((right + 1) and 2) == 0
                    val y = if (up) size - 1 - vert else vert
                    if (!fn[y][x] && bi < all.size * 8) {
                        m[y][x] = ((all[bi ushr 3].toInt() ushr (7 - (bi and 7))) and 1) == 1
                        bi++
                    }
                }
                right -= 2
            }
            // The mask of the least penalty.
            fun masked(mask: Int, x: Int, y: Int) = when (mask) {
                0 -> (x + y) % 2 == 0; 1 -> y % 2 == 0; 2 -> x % 3 == 0; 3 -> (x + y) % 3 == 0
                4 -> (x / 3 + y / 2) % 2 == 0; 5 -> x * y % 2 + x * y % 3 == 0
                6 -> (x * y % 2 + x * y % 3) % 2 == 0; else -> ((x + y) % 2 + x * y % 3) % 2 == 0
            }
            fun apply(mask: Int) { for (y in 0 until size) for (x in 0 until size) if (!fn[y][x] && masked(mask, x, y)) m[y][x] = !m[y][x] }
            var best = 0; var bestScore = Int.MAX_VALUE
            for (mask in 0..7) {
                apply(mask); format(mask)
                val s = penalty(m, size)
                if (s < bestScore) { bestScore = s; best = mask }
                apply(mask)
            }
            apply(best); format(best)
            return QrCode(size, m)
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

        private fun penalty(m: Array<BooleanArray>, size: Int): Int {
            var p = 0
            fun line(get: (Int) -> Boolean) {
                var run = 1
                for (i in 1..size) {
                    if (i < size && get(i) == get(i - 1)) run++
                    else { if (run >= 5) p += 3 + run - 5; run = 1 }
                }
                val pat = booleanArrayOf(true, false, true, true, true, false, true)
                for (i in 0..size - 7) {
                    if ((0 until 7).all { get(i + it) == pat[it] }) {
                        val before = (1..4).all { i - it < 0 || !get(i - it) }
                        val after = (7..10).all { i + it >= size || !get(i + it) }
                        if (before || after) p += 40
                    }
                }
            }
            for (y in 0 until size) line { m[y][it] }
            for (x in 0 until size) line { m[it][x] }
            for (y in 0 until size - 1) for (x in 0 until size - 1) {
                val c = m[y][x]
                if (c == m[y][x + 1] && c == m[y + 1][x] && c == m[y + 1][x + 1]) p += 3
            }
            var dark = 0
            for (row in m) for (v in row) if (v) dark++
            val total = size * size
            p += ((abs(dark * 20 - total * 10) + total - 1) / total - 1) * 10
            return p
        }

        private fun gfMul(a: Int, b: Int): Int {
            var z = 0
            for (i in 7 downTo 0) {
                z = (z shl 1) xor ((z ushr 7) * 0x11D)
                z = z xor (((b ushr i) and 1) * a)
            }
            return z
        }
        private fun rsDivisor(degree: Int): IntArray {
            val r = IntArray(degree); r[degree - 1] = 1
            var root = 1
            for (i in 0 until degree) {
                for (j in r.indices) {
                    r[j] = gfMul(r[j], root)
                    if (j + 1 < r.size) r[j] = r[j] xor r[j + 1]
                }
                root = gfMul(root, 0x02)
            }
            return r
        }
        private fun rsRemainder(data: ByteArray, divisor: IntArray): ByteArray {
            val r = IntArray(divisor.size)
            for (b in data) {
                val factor = (b.toInt() and 0xFF) xor r[0]
                for (i in 0 until r.size - 1) r[i] = r[i + 1]
                r[r.size - 1] = 0
                for (i in r.indices) r[i] = r[i] xor gfMul(divisor[i], factor)
            }
            return ByteArray(r.size) { r[it].toByte() }
        }
    }
}

/**
 * The code on the screen: every module a WHOLE number of pixels (iOS MontanaQR: «a module must occupy a whole number of
 * device pixels» — a fractional rescale merges or drops module rows for a camera), centred in the view, black on white.
 */
class QrView(c: Context) : View(c) {
    var code: QrCode? = null
        set(v) { field = v; invalidate() }
    private val paint = Paint().apply { color = Color.BLACK; isAntiAlias = false }
    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(Color.WHITE)
        val q = code ?: return
        val px = minOf(width, height) / q.size
        if (px <= 0) return
        val ox = (width - px * q.size) / 2f; val oy = (height - px * q.size) / 2f
        for (y in 0 until q.size) for (x in 0 until q.size) if (q.dark(x, y))
            canvas.drawRect(ox + x * px, oy + y * px, ox + (x + 1) * px, oy + (y + 1) * px, paint)
    }
}
