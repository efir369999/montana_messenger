package quest.montana.app

import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.Socket
import java.security.MessageDigest

/**
 * A WEB SOCKET IS A PIPE, NOT A LAYOUT (iOS MTWire 1971-2028): the channel's four-byte frame length stays the only layout — a frame
 * leaves as one binary message, the messages read are glued into one stream the frame reader takes exactly as much from. The rise
 * (RFC 6455) — GET with a key, 101 and the key's answer — is an external standard's admission, as the TLS under it ([I-16]): the
 * channel's security is the Noise_PQ above. The client masks every frame it writes; a ping is answered (iOS autoReplyPing); a close
 * is the end of the stream, never an empty frame (iOS 2020-2023). Measured 08.10 13:2x from the Mac: door.montana.quest/ws rises in
 * 0.82 s behind Cloudflare, and its first message is the node's frame — length 1184 and the KEM key.
 */
object Ws {
    private const val GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"   // RFC 6455 1.3

    /** The rise over a socket already secured: the streams of the pipe, or null — the door did not rise. */
    fun open(s: Socket, host: String, path: String): Pair<InputStream, OutputStream>? {
        val key = Base64.encodeToString(MtBindings.nativeRandom(16) ?: return null, Base64.NO_WRAP)
        val out = s.getOutputStream()
        val req = "GET " + path + " HTTP/1.1\r\nHost: " + host + "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
            "Sec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n"
        out.write(req.toByteArray(Charsets.US_ASCII))
        out.flush()
        val inp = s.getInputStream()
        val head = StringBuilder()
        while (!head.endsWith("\r\n\r\n")) {
            val b = inp.read()
            if (b < 0 || 8192 < head.length) return null
            head.append(b.toChar())
        }
        val lines = head.split("\r\n")
        if (lines.firstOrNull()?.split(' ')?.getOrNull(1) != "101") return null
        val want = Base64.encodeToString(MessageDigest.getInstance("SHA-1").digest((key + GUID).toByteArray(Charsets.US_ASCII)), Base64.NO_WRAP)
        val accept = lines.firstOrNull { it.lowercase().startsWith("sec-websocket-accept:") }?.substringAfter(':')?.trim()
        if (accept != want) return null
        val w = WsOut(out)
        return WsIn(inp, w) to w
    }
}

/** Every write is one binary message, masked as a client's must be (iOS: one frame, one message, opcode binary). */
private class WsOut(private val o: OutputStream) : OutputStream() {
    override fun write(b: Int) = write(byteArrayOf(b.toByte()), 0, 1)
    override fun write(b: ByteArray, off: Int, len: Int) = frame(0x2, b.copyOfRange(off, off + len))
    override fun flush() = o.flush()

    @Synchronized fun frame(op: Int, payload: ByteArray) {
        val mask = MtBindings.nativeRandom(4) ?: throw IOException("no mask")
        val h = ByteArrayOutputStream()
        h.write(0x80 or op)
        val n = payload.size
        when {
            n < 126 -> h.write(0x80 or n)
            n < 65536 -> { h.write(0x80 or 126); h.write(n ushr 8); h.write(n and 0xff) }
            else -> { h.write(0x80 or 127); for (i in 7 downTo 0) h.write(((n.toLong() ushr (8 * i)) and 0xff).toInt()) }
        }
        h.write(mask)
        h.write(ByteArray(n) { (payload[it].toInt() xor mask[it % 4].toInt()).toByte() })
        o.write(h.toByteArray())
        o.flush()
    }
}

/** The messages read, glued into one stream; a ping answered, a close the end (iOS readExactly 2003-2028). */
private class WsIn(private val i: InputStream, private val w: WsOut) : InputStream() {
    private var buf = ByteArray(0)
    private var at = 0

    override fun read(): Int {
        val one = ByteArray(1)
        return if (read(one, 0, 1) < 0) -1 else one[0].toInt() and 0xff
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        while (buf.size <= at) { buf = next() ?: return -1; at = 0 }
        val n = minOf(len, buf.size - at)
        System.arraycopy(buf, at, b, off, n)
        at += n
        return n
    }

    private fun byte(): Int { val v = i.read(); if (v < 0) throw EOFException(); return v }

    private fun next(): ByteArray? {
        while (true) {
            val b0 = byte()
            val b1 = byte()
            var n = (b1 and 0x7f).toLong()
            if (n == 126L) n = ((byte() shl 8) or byte()).toLong()
            else if (n == 127L) { n = 0; repeat(8) { n = (n shl 8) or byte().toLong() } }
            if ((2L shl 20) < n) return null   // a message beyond two frames' worth is not this protocol's
            val mask = if ((b1 and 0x80) != 0) ByteArray(4) { byte().toByte() } else null
            val p = ByteArray(n.toInt())
            var got = 0
            while (got < p.size) { val r = i.read(p, got, p.size - got); if (r < 0) return null; got += r }
            if (mask != null) for (k in p.indices) p[k] = (p[k].toInt() xor mask[k % 4].toInt()).toByte()
            when (b0 and 0x0f) {
                0x0, 0x1, 0x2 -> if (p.isNotEmpty()) return p   // a message or its continuation: glued into the stream either way
                0x8 -> return null                             // a close is the end of the stream
                0x9 -> runCatching { w.frame(0xA, p) }          // a ping is answered
                else -> {}                                      // a pong
            }
        }
    }
}
