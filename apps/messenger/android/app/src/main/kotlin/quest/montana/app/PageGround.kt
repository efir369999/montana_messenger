package quest.montana.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

/**
 * MY PAGE'S GROUND ON A CORRESPONDENT'S SCREEN (iOS MTPageGround, MontanaFeeds.swift 321-419 at 2155; the author's word 25.09:
 * «from T3 I opened T1's page and see no background»). The ground rides as my words about myself do: its content is "" for
 * none, "n:" + a drawn ground's name, or "p:" + the picture as it is kept, light — sent as it lies, never encoded at a send.
 * A correspondent's ground is kept exactly as mine is (ChatWall, under their page's key) and drawn on their page; the tag of
 * what I hold of them rides my presence word («G»).
 */
object PageGround {
    const val MARK = "\u200B\u200BPG:"   // iOS groundMark; only to a peer proven to read it
    private const val LIMIT = 4_000_000   // a received picture's bytes, at most
    private const val LIGHT_BUDGET = 3_000_000

    /** The key a correspondent's page ground is kept under, beside the chats' own (iOS MTWallpaper.pageKey(.peer(conv))). */
    fun keyOf(ref: String) = "*page:" + ref
    /** One tag for a ground, on the sender's «is it announced», on the receipt's «now it is», on «what I hold» and in «G». */
    fun tag(g: String): String = if (g.isEmpty()) "0" else Presence.wireTag(g.toByteArray(Charsets.UTF_8))

    /** A light picture: JPEG or HEIC, within the budget a letter's cargo carries with room to spare (iOS isLight). */
    fun isLight(d: ByteArray): Boolean {
        if (d.size < 12 || d.size > LIGHT_BUDGET) return false
        if (d[0] == 0xFF.toByte() && d[1] == 0xD8.toByte() && d[2] == 0xFF.toByte()) return true
        return d[4] == 0x66.toByte() && d[5] == 0x74.toByte() && d[6] == 0x79.toByte() && d[7] == 0x70.toByte()   // «ftyp»: HEIC
    }
    /**
     * THE PAGE'S GROUND, KEPT LIGHT (iOS lightData 271-296; the author's word 25.09: «compress it at once, so that it weighs little
     * and passes easily»): the placed rendering at the screen's side and no larger, JPEG at 0.85 (the iPhone's own fallback; HEIC
     * has no writer on the platform here). A chat's ground stays the lossless PNG of its preview: it never leaves the phone.
     */
    fun keepLight(b: Bitmap): String? {
        val dm = Book.ctx.resources.displayMetrics
        val side = maxOf(dm.widthPixels, dm.heightPixels).toFloat()
        val k = minOf(1f, side / maxOf(b.width, b.height))
        val flat = if (k < 1f) Bitmap.createScaledBitmap(b, maxOf(1, Math.round(b.width * k)), maxOf(1, Math.round(b.height * k)), true) else b
        val out = ByteArrayOutputStream()
        if (!flat.compress(Bitmap.CompressFormat.JPEG, 85, out)) return null
        return keepBytes(out.toByteArray())
    }
    /** A light picture kept as it came — no second encoding, no loss added (iOS MTWallpaper.keep). Anything else is not kept. */
    fun keepBytes(d: ByteArray): String? {
        if (!isLight(d)) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(d, 0, d.size, bounds)
        if (bounds.outWidth <= 0) return null
        val name = "wall_" + UUID.randomUUID() + (if (d[0] == 0xFF.toByte()) ".jpg" else ".heic")
        return runCatching { File(ChatWall.folder(), name).writeBytes(d); name }.getOrNull()
    }

    @Volatile private var made: Triple<String, String, String>? = null   // file, content, tag
    @Volatile private var making: String? = null

    /** My ground's content and its tag; null only while a picture an older build kept heavy is made light, once. */
    fun mine(): Pair<String, String>? = when (val c = ChatWall.choice(ChatWall.PAGE)) {
        ChatWall.Choice.General -> "" to "0"
        is ChatWall.Choice.Named -> ("n:" + c.name).let { it to tag(it) }
        is ChatWall.Choice.Photo -> {
            made?.takeIf { it.first == c.file }?.let { it.second to it.third } ?: run {
                val d = runCatching { File(ChatWall.folder(), c.file).readBytes() }.getOrNull()
                if (d != null && isLight(d)) {
                    val g = "p:" + Base64.encodeToString(d, Base64.NO_WRAP)
                    val t = tag(g)
                    made = Triple(c.file, g, t)
                    Log.d("Montana", "ground_made kept bytes=" + d.size + " tag=" + t)
                    g to t
                } else { lighten(c.file); null }
            }
        }
    }
    /** A picture kept heavy (the PNG of the window) is made light ONCE, off the main thread, worn so, and sent to who lacks it. */
    private fun lighten(file: String) {
        synchronized(this) { if (making == file) return; making = file }
        Thread {
            val kept = ChatWall.image(file)?.let { keepLight(it) }
            synchronized(this) { if (making == file) making = null }
            val now = ChatWall.choice(ChatWall.PAGE)
            if (now !is ChatWall.Choice.Photo || now.file != file) return@Thread   // set anew meanwhile
            if (kept == null) { Log.d("Montana", "ground_made FAILED — the kept picture could not be made light"); return@Thread }
            ChatWall.set(ChatWall.PAGE, ChatWall.Choice.Photo(kept))   // the heavy file leaves with the choice
            Log.d("Montana", "ground_made lightened")
        }.start()
    }
    /** My ground changed on this phone: to every correspondent who reads the word — a picture once it is made. */
    fun changed() { if (mine() != null) broadcast() }

    // ── what I hold of theirs ──
    private fun held(ref: String): Pair<String, Double>? {
        val p = Prefs.str("pgHeld." + ref, "").split("@", limit = 2)
        return if (p.size == 2) p[1].toDoubleOrNull()?.let { p[0] to it } else null
    }
    /** The tag of a correspondent's ground on my screen, «0» for none — said in my presence word («G»). */
    fun heldTag(ref: String): String = held(ref)?.first ?: "0"

    /** A correspondent's ground arrived: kept as mine is, the latest word winning; an older word changes nothing. */
    fun note(ref: String, g: String, at: Double) {
        held(ref)?.let { if (at < it.second) return }
        var choice: ChatWall.Choice = ChatWall.Choice.General
        if (g.startsWith("n:")) {
            val n = g.removePrefix("n:")
            if (ChatWall.names.any { it.first == n }) choice = ChatWall.Choice.Named(n)
        } else if (g.startsWith("p:")) {
            runCatching { Base64.decode(g.removePrefix("p:"), Base64.DEFAULT) }.getOrNull()
                ?.takeIf { it.size <= LIMIT }?.let { keepBytes(it) }?.let { choice = ChatWall.Choice.Photo(it) }
        }
        ChatWall.set(keyOf(ref), choice)
        Prefs.setStr("pgHeld." + ref, tag(g) + "@" + at)
        Log.d("Montana", "ground_rx from=" + ref.take(10) + " kind=" + (if (g.isEmpty()) "none" else g.take(1)))
    }

    // ── who reads the word: proven by their own build, never inferred (iOS groundCapable / noteGroundCapable) ──
    fun capable(ref: String) = Prefs.bool("pgcap_" + ref, false)
    /** THE FIRST PROOF IS ANSWERED WITH MINE (iOS 788-791): my ground word, «none» too, is my proof to them. */
    fun noteCapable(ref: String) {
        if (capable(ref)) return
        Prefs.setBool("pgcap_" + ref, true)
        Log.d("Montana", "ground_capable peer=" + ref.take(10))
        Thread { sendIfNeeded(ref, force = true) }.start()
    }

    /**
     * MY PAGE'S GROUND, AS STATE (iOS sendGroundIfNeeded 1554-1570): one silent letter of kind «ground» in the one queue, repeated
     * until the peer's receipt, and only the receipt writes the mark; only to a peer whose build reads the word, never to a blocked one.
     */
    fun sendIfNeeded(ref: String, force: Boolean = false) {
        if (Book.secret(ref) == null || PeerSafety.isBlocked(ref) || !capable(ref)) return
        val now = mine() ?: return
        val held = Prefs.str("annGround." + ref, "").ifEmpty { null }
        if (held == now.second) return                          // receipted with this ground
        if (held == null && now.second == "0" && !force) return  // nothing was ever shown, and nothing is shown now
        if (Post.inFlight("G", ref, now.second)) return          // on its way
        val mid = Marks.mintMid()
        Post.flight("G", ref, now.second, mid)
        Post.send(ref, mid, MARK + JSONObject().put("g", now.first).put("at", System.currentTimeMillis() / 1000.0).toString())
        Log.d("Montana", "ground_tx to=" + ref.take(10) + " tag=" + now.second + " bytes=" + now.first.length)
    }
    fun broadcast() { for (ref in Book.refs()) sendIfNeeded(ref) }

    /** The tag of the ground a peer's presence word says it holds of mine, after the wall's digits; a build before it names nothing. */
    fun groundHeld(payload: String): String? {
        val n = payload.indexOf('N'); if (n < 0) return null
        var j = n + 1
        while (j < payload.length && payload[j].isDigit()) j++
        if (j < payload.length && payload[j] == 'A') { j++; while (j < payload.length && payload[j].isDigit()) j++ }
        if (j >= payload.length || payload[j] != 'W') return null
        j++; while (j < payload.length && payload[j].isDigit()) j++
        if (j >= payload.length || payload[j] != 'G') return null
        return payload.substring(j + 1).takeWhile { it.isDigit() }.ifEmpty { null }
    }
}
