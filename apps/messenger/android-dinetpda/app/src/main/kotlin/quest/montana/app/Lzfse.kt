package quest.montana.app

import java.io.ByteArrayOutputStream

// ─────────────────────────── LZFSE as Apple's Compression writes it (the coin vault's pieces: iOS MTCoinVault.seal, MTWalletCore.swift:1069-1077) ───────────────────────────

/**
 * THE VAULT'S PIECES ARE PACKED BY APPLE'S LZFSE (iOS MTCoinVault.seal: the moves' JSON, `compressed(using: .lzfse)`, then the seal).
 * The decoder is the lzfse 1.0 reference (github.com/lzfse/lzfse, Apple Inc., BSD-3-Clause: lzfse_decode_base.c, lzvn_decode_base.c,
 * lzfse_fse.h/.c) step for step: the blocks bvx$ (the end), bvx- (raw), bvxn (LZVN), bvx1 and bvx2 (LZFSE, its tables plain or packed).
 * Stricter than the reference in one way only: a stream that is not whole -- no end, a block short of its bytes, an LZVN block that
 * gives other than it says -- is no stream, where the reference's buffer call answers with whatever it had written. The encoder lays
 * LZVN blocks under 4 096 bytes -- what Apple's own encoder lays for a small input -- and a block that would not shrink raw, so Apple's
 * decoder meets nothing its own encoder does not write. Pure Kotlin, nothing of Android: tools/lzfse_check.sh runs both directions
 * against the reference CLI.
 */
object Lzfse {
    private const val END = 0x24787662    // bvx$
    private const val RAW = 0x2d787662    // bvx-
    private const val V1 = 0x31787662     // bvx1
    private const val V2 = 0x32787662     // bvx2
    private const val LZVN = 0x6e787662   // bvxn
    /** Apple's encoder takes LZVN below 4 096 bytes (LZFSE_ENCODE_LZVN_THRESHOLD); every block of ours stays below it. */
    private const val BLOCK = 4095

    /** The plain bytes, or null when the stream is not whole and valid, or would open past [max] bytes. */
    fun decode(src: ByteArray, max: Int = 64 shl 20): ByteArray? =
        try { Decoder(src, max).run() } catch (_: Bad) { null } catch (_: IndexOutOfBoundsException) { null }

    /** The bytes as one stream: LZVN blocks of 4 095 bytes at most, a block too small or that would not shrink raw, and the end. */
    fun encode(src: ByteArray): ByteArray {
        val o = ByteArrayOutputStream(src.size / 2 + 16)
        var p = 0
        while (p < src.size) {
            val n = minOf(BLOCK, src.size - p)
            val v = if (n < 8) null else lzvn(src, p, n)   // the reference encodes no LZVN below 8 bytes (LZVN_ENCODE_MIN_SRC_SIZE)
            if (v != null && v.size < n) { put32(o, LZVN); put32(o, n); put32(o, v.size); o.write(v) }
            else { put32(o, RAW); put32(o, n); o.write(src, p, n) }
            p += n
        }
        put32(o, END)
        return o.toByteArray()
    }

    private object Bad : RuntimeException() { private fun readResolve(): Any = Bad; override fun fillInStackTrace(): Throwable = this }

    private fun u8(b: ByteArray, i: Int) = b[i].toInt() and 0xff
    private fun le16(b: ByteArray, i: Int) = u8(b, i) or (u8(b, i + 1) shl 8)
    private fun le32(b: ByteArray, i: Int) = u8(b, i) or (u8(b, i + 1) shl 8) or (u8(b, i + 2) shl 16) or (u8(b, i + 3) shl 24)
    private fun le(b: ByteArray, i: Int, n: Int): Long { var v = 0L; for (k in 0 until n) v = v or ((b[i + k].toLong() and 0xff) shl (8 * k)); return v }
    private fun u32(b: ByteArray, i: Int): Int = (le32(b, i).toLong() and 0xffffffffL).let { if (it > Int.MAX_VALUE) throw Bad else it.toInt() }
    private fun put32(o: ByteArrayOutputStream, v: Int) { o.write(v); o.write(v ushr 8); o.write(v ushr 16); o.write(v ushr 24) }
    private fun field(v: Long, at: Int, n: Int): Int = ((v ushr at) and ((1L shl n) - 1)).toInt()
    private fun mask(n: Int) = if (n == 0) 0 else (1 shl n) - 1

    // the L, M, D codes: the low bits read apart and the base of each symbol (lzfse_internal.h 588-614)
    private val L_BITS = intArrayOf(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 5, 8)
    private val L_BASE = intArrayOf(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 28, 60)
    private val M_BITS = intArrayOf(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 5, 8, 11)
    private val M_BASE = intArrayOf(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 24, 56, 312)
    private val D_BITS = intArrayOf(0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7,
        8, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 11, 12, 12, 12, 12, 13, 13, 13, 13, 14, 14, 14, 14, 15, 15, 15, 15)
    private val D_BASE = intArrayOf(0, 1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24, 28, 36, 44, 52, 60, 76, 92, 108, 124, 156, 188, 220, 252,
        316, 380, 444, 508, 636, 764, 892, 1020, 1276, 1532, 1788, 2044, 2556, 3068, 3580, 4092, 5116, 6140, 7164, 8188, 10236, 12284,
        14332, 16380, 20476, 24572, 28668, 32764, 40956, 49148, 57340, 65532, 81916, 98300, 114684, 131068, 163836, 196604, 229372)
    // a packed table's codes (lzfse_decode_v1_freq_value, lzfse_decode_base.c 28-48)
    private val FREQ_BITS = intArrayOf(2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14, 2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14)
    private val FREQ_VALUE = intArrayOf(0, 2, 1, 4, 0, 3, 1, -1, 0, 2, 1, 5, 0, 3, 1, -1, 0, 2, 1, 6, 0, 3, 1, -1, 0, 2, 1, 7, 0, 3, 1, -1)

    // the LZVN opcodes (lzvn_decode_base.c 50-82, the jump table)
    private const val SML_D = 1; private const val MED_D = 2; private const val LRG_D = 3; private const val PRE_D = 4
    private const val SML_M = 5; private const val LRG_M = 6; private const val SML_L = 7; private const val LRG_L = 8
    private const val NOP = 9; private const val EOS = 10; private const val UDEF = 0
    private val OPS = IntArray(256) { o ->
        when {
            o in 0xa0..0xbf -> MED_D
            o == 0xe0 -> LRG_L
            o in 0xe1..0xef -> SML_L
            o == 0xf0 -> LRG_M
            o in 0xf1..0xff -> SML_M
            o in 0x70..0x7f || o in 0xd0..0xdf -> UDEF
            (o and 7) == 7 -> LRG_D
            (o and 7) == 6 -> when { o == 6 -> EOS; o == 14 || o == 22 -> NOP; o < 64 -> UDEF; else -> PRE_D }
            else -> SML_D
        }
    }

    private class Decoder(private val src: ByteArray, private val max: Int) {
        private var out = ByteArray(minOf(max.toLong(), maxOf(64L, src.size.toLong() * 4)).toInt())
        private var n = 0

        private fun room(more: Int) {
            if (more < 0 || more > max - n) throw Bad
            val need = n + more
            if (need > out.size) out = out.copyOf(minOf(max.toLong(), maxOf(need.toLong(), out.size.toLong() * 2)).toInt())
        }

        /** lzfse_decode: one block after the other until the end's own word. */
        fun run(): ByteArray {
            var p = 0
            while (true) {
                if (src.size - p < 4) throw Bad
                when (le32(src, p)) {
                    END -> return out.copyOf(n)
                    RAW -> {
                        if (src.size - p < 8) throw Bad
                        val raw = u32(src, p + 4); p += 8
                        if (raw > src.size - p) throw Bad
                        room(raw); System.arraycopy(src, p, out, n, raw); n += raw; p += raw
                    }
                    LZVN -> {
                        if (src.size - p < 12) throw Bad
                        val raw = u32(src, p + 4); val payload = u32(src, p + 8); p += 12
                        if (payload > src.size - p) throw Bad
                        lzvn(p, p + payload, raw); p += payload
                    }
                    V1, V2 -> p = lzfse(p)
                    else -> throw Bad
                }
            }
        }

        /**
         * AN LZVN BLOCK (lzvn_decode): its payload ends with the eight bytes of the end opcode and gives exactly the bytes the header
         * named; the distance starts at nothing in every block, a match reaches back into the whole output, never before its start.
         */
        private fun lzvn(start: Int, end: Int, raw: Int) {
            room(raw)
            val b = out
            val stop = n + raw
            var s = start; var d = n; var dist = 0
            while (true) {
                if (s >= end) throw Bad
                val opc = u8(src, s)
                val left = end - s
                val len: Int; val l: Int; val m: Int
                when (OPS[opc]) {
                    SML_D -> { len = 2; l = opc ushr 6; m = ((opc ushr 3) and 7) + 3; if (left <= len + l) throw Bad; dist = ((opc and 7) shl 8) or u8(src, s + 1) }
                    MED_D -> {
                        len = 3; l = (opc ushr 3) and 3; if (left <= len + l) throw Bad
                        val o = le16(src, s + 1); m = (((opc and 7) shl 2) or (o and 3)) + 3; dist = o ushr 2
                    }
                    LRG_D -> { len = 3; l = opc ushr 6; m = ((opc ushr 3) and 7) + 3; if (left <= len + l) throw Bad; dist = le16(src, s + 1) }
                    PRE_D -> { len = 1; l = opc ushr 6; m = ((opc ushr 3) and 7) + 3; if (left <= len + l) throw Bad }
                    SML_M -> { len = 1; l = 0; if (left <= len) throw Bad; m = opc and 15 }
                    LRG_M -> { len = 2; l = 0; if (left <= len) throw Bad; m = u8(src, s + 1) + 16 }
                    SML_L -> { len = 1; l = opc and 15; m = 0; if (left <= len + l) throw Bad }
                    LRG_L -> { len = 2; if (left <= 2) throw Bad; l = u8(src, s + 1) + 16; m = 0; if (left <= len + l) throw Bad }
                    NOP -> { if (left <= 1) throw Bad; s += 1; continue }
                    EOS -> { if (left < 8) throw Bad; s += 8; break }
                    else -> throw Bad
                }
                s += len
                if (l > stop - d) throw Bad
                System.arraycopy(src, s, b, d, l); s += l; d += l
                if (0 < m) {
                    if (dist == 0 || dist > d || m > stop - d) throw Bad
                    for (i in d until d + m) b[i] = b[i - dist]   // byte by byte: a match may overlap its own output
                    d += m
                }
            }
            if (s != end || d != stop) throw Bad
            n = d
        }

        /** The 64-bit input stream (fse_in_stream64), read backwards from the end of its payload toward [start]. */
        private class Bits(private val src: ByteArray, private var pos: Int, private val start: Int) {
            private var acc = 0L
            private var nb = 0
            fun init(n: Int) {
                if (n != 0) { if (pos - start < 8) throw Bad; pos -= 8; acc = le(src, pos, 8); nb = n + 64 }
                else { if (pos - start < 7) throw Bad; pos -= 7; acc = le(src, pos, 7); nb = 56 }
                if (nb < 56 || nb >= 64 || (acc ushr nb) != 0L) throw Bad
            }
            fun flush() {
                val bits = (63 - nb) and -8
                val bytes = bits ushr 3
                if (pos - bytes < start) throw Bad
                pos -= bytes
                if (0 < bits) acc = (acc shl bits) or le(src, pos, bytes)
                nb += bits
            }
            fun pull(n: Int): Int {
                if (n < 0 || n > nb) throw Bad
                nb -= n
                val r = acc ushr nb
                acc = if (nb == 0) 0L else acc and ((1L shl nb) - 1)
                return r.toInt()
            }
        }

        /** fse_init_value_decoder_table: for every state its bits, its value's bits, the next state's base and the value's base. */
        private class Values(nstates: Int, freq: IntArray, off: Int, count: Int, vbits: IntArray, vbase: IntArray) {
            val tot = IntArray(nstates); val vb = IntArray(nstates); val del = IntArray(nstates); val base = IntArray(nstates)
            init {
                val nClz = Integer.numberOfLeadingZeros(nstates)
                var t = 0
                for (i in 0 until count) {
                    val f = freq[off + i]
                    if (f == 0) continue
                    val k = Integer.numberOfLeadingZeros(f) - nClz
                    val j0 = ((2 * nstates) ushr k) - f
                    for (j in 0 until f) {
                        vb[t] = vbits[i]; base[t] = vbase[i]
                        if (j < j0) { tot[t] = k + vbits[i]; del[t] = ((f + j) shl k) - nstates }
                        else { tot[t] = k - 1 + vbits[i]; del[t] = (j - j0) shl (k - 1) }
                        t++
                    }
                }
            }
        }

        /** fse_init_decoder_table for the literals: an entry is its bits (low byte), its symbol (next byte) and the state's base above. */
        private fun literalTable(freq: IntArray, off: Int): IntArray {
            val t = IntArray(1024)
            val nClz = Integer.numberOfLeadingZeros(1024)
            var at = 0
            for (i in 0 until 256) {
                val f = freq[off + i]
                if (f == 0) continue
                val k = Integer.numberOfLeadingZeros(f) - nClz
                val j0 = (2048 ushr k) - f
                for (j in 0 until f) {
                    t[at++] = if (j < j0) k or (i shl 8) or ((((f + j) shl k) - 1024) shl 16) else (k - 1) or (i shl 8) or (((j - j0) shl (k - 1)) shl 16)
                }
            }
            return t
        }

        /** AN LZFSE BLOCK (lzfse_decode, its bvx1 and bvx2 cases, and lzfse_decode_lmd): the header, the literals, then the L, M, D. */
        private fun lzfse(p0: Int): Int {
            var p = p0
            val freq = IntArray(20 + 20 + 64 + 256)
            val litState = IntArray(4)
            val nLit: Int; val nLitPay: Int; val nMatch: Int; val litBits: Int; val nLmdPay: Int; val lmdBits: Int
            val lState: Int; val mState: Int; val dState: Int; val header: Int
            if (le32(src, p) == V2) {
                if (src.size - p < 32) throw Bad
                val v0 = le(src, p + 8, 8); val v1 = le(src, p + 16, 8); val v2 = le(src, p + 24, 8)
                header = field(v2, 0, 32)
                if (header < 32 || header > src.size - p) throw Bad
                nLit = field(v0, 0, 20); nLitPay = field(v0, 20, 20); nMatch = field(v0, 40, 20); litBits = field(v0, 60, 3) - 7
                for (i in 0..3) litState[i] = field(v1, 10 * i, 10)
                nLmdPay = field(v1, 40, 20); lmdBits = field(v1, 60, 3) - 7
                lState = field(v2, 32, 10); mState = field(v2, 42, 10); dState = field(v2, 52, 10)
                var q = p + 32
                val qEnd = p + header
                if (q != qEnd) {   // tables omitted when the header ends with its fields
                    var acc = 0; var bits = 0
                    for (i in freq.indices) {
                        while (q < qEnd && bits + 8 <= 32) { acc = acc or (u8(src, q) shl bits); bits += 8; q++ }
                        val c = acc and 31
                        val nbits = FREQ_BITS[c]
                        freq[i] = when (nbits) { 8 -> 8 + ((acc ushr 4) and 0xf); 14 -> 24 + ((acc ushr 4) and 0x3ff); else -> FREQ_VALUE[c] }
                        if (nbits > bits) throw Bad
                        acc = acc ushr nbits; bits -= nbits
                    }
                    if (8 <= bits || q != qEnd) throw Bad   // the tables end exactly with the header
                }
            } else {   // bvx1: the C struct as it lies in memory, 770 bytes of fields and 2 of padding
                header = 772
                if (src.size - p < header) throw Bad
                nLit = u32(src, p + 12); nMatch = u32(src, p + 16); nLitPay = u32(src, p + 20); nLmdPay = u32(src, p + 24)
                litBits = le32(src, p + 28)
                for (i in 0..3) litState[i] = le16(src, p + 32 + 2 * i)
                lmdBits = le32(src, p + 40)
                lState = le16(src, p + 44); mState = le16(src, p + 46); dState = le16(src, p + 48)
                for (i in freq.indices) freq[i] = le16(src, p + 50 + 2 * i)
            }
            if (nLitPay.toLong() + nLmdPay > (src.size - p - header).toLong()) throw Bad   // the whole block is at hand
            // lzfse_check_block_header_v1
            if (40000 < nLit || 10000 < nMatch || litState.any { 1024 <= it } || 64 <= lState || 64 <= mState || 256 <= dState) throw Bad
            fun sum(from: Int, to: Int): Int { var s = 0; for (i in from until to) s += freq[i]; return s }
            if (64 < sum(0, 20) || 64 < sum(20, 40) || 256 < sum(40, 104) || 1024 < sum(104, 360)) throw Bad
            p += header
            val litT = literalTable(freq, 104)
            val lv = Values(64, freq, 0, 20, L_BITS, L_BASE)
            val mv = Values(64, freq, 20, 20, M_BITS, M_BASE)
            val dv = Values(256, freq, 40, 64, D_BITS, D_BASE)

            // the literals: four interleaved states over one stream, read backwards from the end of their payload
            p += nLitPay
            val literals = ByteArray(40000 + 64)
            val lb = Bits(src, p, 0).apply { init(litBits) }
            val st = litState.copyOf()
            var i = 0
            while (i < nLit) {
                lb.flush()
                for (k in 0..3) {
                    val e = litT[st[k]]
                    st[k] = ((e shr 16) + lb.pull(e and 0xff)) and 0xffff
                    literals[i + k] = (e ushr 8).toByte()
                }
                i += 4
            }

            // the L, M, D triplets, read backwards from the end of the block
            val lmdStart = p
            p += nLmdPay
            val mb = Bits(src, p, lmdStart).apply { init(lmdBits) }
            var ls = lState; var ms = mState; var ds = dState
            var lit = 0
            var dist = -1   // no previous distance yet: a triplet that leans on one fails
            for (t in 0 until nMatch) {
                mb.flush()
                var sv = mb.pull(lv.tot[ls])
                val l = lv.base[ls] + (sv and mask(lv.vb[ls])); ls = (lv.del[ls] + (sv ushr lv.vb[ls])) and 0xffff
                if (40064 <= lit + l) throw Bad
                sv = mb.pull(mv.tot[ms])
                val m = mv.base[ms] + (sv and mask(mv.vb[ms])); ms = (mv.del[ms] + (sv ushr mv.vb[ms])) and 0xffff
                sv = mb.pull(dv.tot[ds])
                val nd = dv.base[ds] + (sv and mask(dv.vb[ds])); ds = (dv.del[ds] + (sv ushr dv.vb[ds])) and 0xffff
                if (nd != 0) dist = nd
                if ((dist.toLong() and 0xffffffffL) > n.toLong() + l) throw Bad
                room(l + m)
                val b = out
                System.arraycopy(literals, lit, b, n, l); n += l; lit += l
                for (j in n until n + m) b[j] = b[j - dist]
                n += m
            }
            return p
        }
    }

    // ── the encoder: LZVN opcodes over one block, a greedy match by a hash of four bytes ──
    private const val HASH = 12
    private const val DEPTH = 8
    private const val MIN = 4
    private val SML_MAX = intArrayOf(10, 8, 6, 4)   // the longest match a small or a large distance's opcode carries beside 0..3 literals
    private val PRE_MAX = intArrayOf(0, 8, 6, 4)    // and the previous distance's, which carries one literal at least
    private fun hash(b: ByteArray, i: Int): Int = (le32(b, i) * -1640531535) ushr (32 - HASH)

    private fun lzvn(src: ByteArray, from: Int, n: Int): ByteArray {
        val end = from + n
        val o = ByteArrayOutputStream(n + 16)
        val head = IntArray(1 shl HASH) { -1 }
        val chain = IntArray(n)
        fun put(at: Int) { val h = hash(src, at); chain[at - from] = head[h]; head[h] = at }
        var lit = from; var i = from; var prev = 0   // every block starts with no previous distance (the decoder's d_prev = 0)
        while (i + MIN <= end) {
            var best = 0; var bestD = 0
            var c = head[hash(src, i)]
            var depth = 0
            while (0 <= c && depth++ < DEPTH) {
                val d = i - c
                if (0xffff < d) break
                var len = 0
                while (i + len < end && src[c + len] == src[i + len]) len++
                if (best < len || (len == best && d == prev)) { best = len; bestD = d }
                c = chain[c - from]
            }
            if (MIN <= best) {
                match(o, src, lit, i - lit, best, bestD, prev)
                prev = bestD
                val stop = minOf(i + best, end - MIN + 1)
                var j = i
                while (j < stop) { put(j); j++ }
                i += best; lit = i
            } else { put(i); i++ }
        }
        literals(o, src, lit, end - lit)
        o.write(6); repeat(7) { o.write(0) }   // the end opcode and its seven bytes
        return o.toByteArray()
    }

    /** Literals alone: 1110LLLL for up to fifteen, 11100000 LLLLLLLL for sixteen to 271. */
    private fun literals(o: ByteArrayOutputStream, src: ByteArray, at: Int, count: Int) {
        var p = at; var left = count
        while (0 < left) {
            val k = minOf(left, 271)
            if (16 <= k) { o.write(0xe0); o.write(k - 16) } else o.write(0xe0 or k)
            o.write(src, p, k); p += k; left -= k
        }
    }

    /** Up to three literals ride the match's own opcode; the match's rest goes by the previous distance (1111MMMM, 11110000 MMMMMMMM). */
    private fun match(o: ByteArrayOutputStream, src: ByteArray, at: Int, count: Int, len: Int, d: Int, prev: Int) {
        var l = count
        if (3 < l) { literals(o, src, at, l); l = 0 }
        val litAt = at + count - l
        var m = len
        val first: Int
        when {
            d == prev && l == 0 -> first = 0
            d == prev -> { first = minOf(m, PRE_MAX[l]); o.write((l shl 6) or ((first - 3) shl 3) or 6); o.write(src, litAt, l) }   // LLMMM110
            d <= 16383 && (SML_MAX[l] < m || 1535 < d) -> {   // 101LLMMM DDDDDDMM DDDDDDDD
                first = minOf(m, 34)
                val x = first - 3
                val w = (d shl 2) or (x and 3)
                o.write(0xa0 or (l shl 3) or (x ushr 2)); o.write(w and 0xff); o.write(w ushr 8); o.write(src, litAt, l)
            }
            d <= 1535 -> { first = minOf(m, SML_MAX[l]); o.write((l shl 6) or ((first - 3) shl 3) or (d ushr 8)); o.write(d and 0xff); o.write(src, litAt, l) }   // LLMMMDDD DDDDDDDD
            else -> { first = minOf(m, SML_MAX[l]); o.write((l shl 6) or ((first - 3) shl 3) or 7); o.write(d and 0xff); o.write(d ushr 8); o.write(src, litAt, l) }   // LLMMM111 DDDDDDDD DDDDDDDD
        }
        m -= first
        while (0 < m) {
            val k = minOf(m, 271)
            if (16 <= k) { o.write(0xf0); o.write(k - 16) } else o.write(0xf0 or k)
            m -= k
        }
    }
}
