package quest.montana.app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

// ─────────────────────────── the link's card (iOS MTLinkPreview) ───────────────────────────

/**
 * THE CARD OF A LINK (iOS MTLinkPreview): built by the SENDER, who reads the page's own description (og:*); it rides INSIDE
 * the sealed letter as the body's seventh field. The receiver never touches the site before tapping — the only honest reader
 * of a link is the person who chose to share it. u — the link, s — the site, t — the title, d — the description, i — the
 * picture (JPEG base64, the sender's own row only: the node's envelope carries the card without it), p/w/h — where the
 * picture lives and its size.
 */
class LinkCard(val u: String, val s: String?, val t: String?, val d: String?, var i: String? = null, var p: String? = null, var w: Int? = null, var h: Int? = null) {
    val wide get() = (w ?: 0) >= 400 && (h ?: 0) >= 200
    val hasFace get() = !t.isNullOrEmpty() || !d.isNullOrEmpty()
    fun json(withPicture: Boolean = true): String = JSONObject().put("u", u).apply {
        s?.let { put("s", it) }; t?.let { put("t", it) }; d?.let { put("d", it) }
        if (withPicture) i?.let { put("i", it) }
        p?.let { put("p", it) }; w?.let { put("w", it) }; h?.let { put("h", it) }
    }.toString()
    companion object {
        fun parse(s: String?): LinkCard? {
            if (s == null || s.length <= 2) return null
            val o = runCatching { JSONObject(s) }.getOrNull() ?: return null
            fun str(k: String) = o.optString(k).takeIf { it.isNotEmpty() }
            return LinkCard(str("u") ?: return null, str("s"), str("t"), str("d"), str("i"), str("p"),
                o.optInt("w").takeIf { it > 0 }, o.optInt("h").takeIf { it > 0 })
        }
    }
}

object LinkPreview {
    /** THE ONE SWITCH (Settings → Privacy, on by default): off, nothing outside is read and the letter carries the bare link. */
    val enabled get() = Prefs.bool("linkPreviewsEnabled", true)

    private val linkRE = Regex("""https?://[^\s<>"']+""", RegexOption.IGNORE_CASE)
    fun webURLs(text: String): List<String> = linkRE.findAll(text).map { it.value.trimEnd('.', ',', ')', '!', '?', ';', ':') }
        .filter { runCatching { URL(it).host }.getOrNull()?.isNotEmpty() == true }.toList()

    private val read = HashMap<String, LinkCard>()
    private val readNothing = HashSet<String>()

    /** The first link that has a face, each of the first three asked in turn (iOS buildFirstWithFace); whole walk ≤ 4 s. */
    fun build(text: String): LinkCard? {
        val until = System.currentTimeMillis() + 4000
        for (u in webURLs(text).take(3)) {
            if (System.currentTimeMillis() > until) break
            buildFor(u)?.let { return it }
        }
        return null
    }

    /** The page's head only (≤ 64 KB, 3 s), its og:* read by a tiny reader — no browser engine (iOS build(for:)). */
    private fun buildFor(url: String): LinkCard? {
        synchronized(read) { read[url]?.let { return it }; if (url in readNothing) return null }
        val html = fetch(url, 64 * 1024, 3000, stopAtHead = true)?.let { String(it, Charsets.UTF_8) }
        if (html == null) { synchronized(read) { readNothing += url }; return null }
        val host = runCatching { URL(url).host }.getOrNull()
        val card = LinkCard(url, clean(meta(html, "og:site_name") ?: host, 64), clean(meta(html, "og:title") ?: tagTitle(html), 300),
            clean(meta(html, "og:description") ?: meta(html, "description"), 800))
        if (!card.hasFace) { synchronized(read) { readNothing += url }; return null }   // a card with nothing to say is noise
        card.p = (meta(html, "og:image") ?: meta(html, "og:image:secure_url") ?: meta(html, "twitter:image"))
            ?.let { runCatching { URL(URL(url), it).toString() }.getOrNull() }
        synchronized(read) { read[url] = card }
        return card
    }

    /** THE PICTURE IS A SECOND READ (iOS picture(for:)): ten seconds of its own; the row keeps it crisp (720, 70 KB). */
    fun picture(card: LinkCard): LinkCard? {
        val ref = card.p?.takeIf { card.i == null && (it.startsWith("https://") || it.startsWith("http://")) } ?: return null
        val raw = fetch(ref, 3 * 1024 * 1024, 10_000) ?: return null
        val b = BitmapFactory.decodeByteArray(raw, 0, raw.size) ?: return null
        val side = maxOf(b.width, b.height)
        val scale = if (side > 720) 720f / side else 1f
        val small = Bitmap.createScaledBitmap(b, maxOf(1, (b.width * scale).toInt()), maxOf(1, (b.height * scale).toInt()), true)
        var q = 75
        repeat(3) {
            val out = ByteArrayOutputStream(); small.compress(Bitmap.CompressFormat.JPEG, q, out)
            if (out.size() <= 70 * 1024) {
                return LinkCard(card.u, card.s, card.t, card.d, Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP), card.p, b.width, b.height)
            }
            q = (q * 0.6).toInt()
        }
        return null
    }

    private fun fetch(url: String, limit: Int, timeoutMs: Int, stopAtHead: Boolean = false): ByteArray? = runCatching {
        val c = URL(url).openConnection() as HttpURLConnection   // the public page being shared, read by its sender — not a delivery road
        c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
        c.setRequestProperty("User-Agent", "Mozilla/5.0 (Android) MontanaPreview/1")
        c.instanceFollowRedirects = true
        try {
            if (c.responseCode !in 200..299) return@runCatching null
            val out = ByteArrayOutputStream()
            val buf = ByteArray(8192)
            val started = System.currentTimeMillis()
            c.inputStream.use { ins ->
                while (out.size() < limit && System.currentTimeMillis() - started < timeoutMs + 1500) {
                    val n = ins.read(buf); if (n < 0) break
                    out.write(buf, 0, n)
                    if (stopAtHead && out.toString("ISO-8859-1").contains("</head", ignoreCase = true)) break
                }
            }
            out.toByteArray()
        } finally { c.disconnect() }
    }.getOrNull()

    private val metaTagRE = Regex("""<meta(\s[^>]*)>""", RegexOption.IGNORE_CASE)
    private val attrRE = Regex("""([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))""")
    private fun meta(html: String, prop: String): String? {
        for (m in metaTagRE.findAll(html)) {
            val a = HashMap<String, String>()
            for (x in attrRE.findAll(m.groupValues[1])) a[x.groupValues[1].lowercase()] = x.groupValues.drop(2).firstOrNull { it.isNotEmpty() } ?: ""
            val key = a["property"] ?: a["name"] ?: continue
            if (key.lowercase() != prop) continue
            val v = decode(a["content"] ?: continue)
            if (v.isNotBlank()) return v
        }
        return null
    }
    private fun tagTitle(html: String) = Regex("""<title[^>]*>([^<]{1,300})</title>""", RegexOption.IGNORE_CASE).find(html)?.groupValues?.get(1)?.let { decode(it) }
    private fun decode(s: String) = listOf("&amp;" to "&", "&quot;" to "\"", "&#39;" to "'", "&apos;" to "'", "&lt;" to "<", "&gt;" to ">", "&nbsp;" to " ", "&#x27;" to "'")
        .fold(s) { v, (a, b) -> v.replace(a, b) }
    private fun clean(s: String?, cap: Int) = s?.replace("\n", " ")?.trim()?.takeIf { it.isNotEmpty() }?.take(cap)

    /**
     * THE CARD ATTENDS A LETTER OF MINE (iOS MTLinkCards.attend): after the letter left, its link is read (three tries: at once,
     * 4 s, 30 s); the card lands on my row and a same-mid copy of the letter carries it to the correspondent. The picture comes
     * after, on the row only.
     */
    fun attend(ref: String, mid: String, text: String, qt: String?, qm: String?) {
        if (!enabled || Marks.isService(text) || webURLs(text).isEmpty()) return
        Thread {
            var card: LinkCard? = null
            for (wait in listOf(0L, 4_000L, 30_000L)) { if (wait > 0) Thread.sleep(wait); card = build(text); if (card != null) break }
            // the diary says whether a card was read, never the link itself (iOS lp_give_up, lp_attach)
            val c = card ?: return@Thread run { android.util.Log.d("Montana", "link card: none after three reads mid=" + mid.take(8)); Unit }
            android.util.Log.d("Montana", "link card: built mid=" + mid.take(8) + " picture=" + (c.p != null))
            Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid }?.lp = c.json() }
            Post.send(ref, mid, text, qt, qm, lp = c.json(withPicture = false))   // the envelope leg: the card without its picture
            picture(c)?.let { full -> Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid }?.lp = full.json() } }
        }.start()
    }
}

/**
 * THE CARD UNDER THE WORDS (iOS the link card in the bubble): a bar of the bubble's words' colour, the site in bold, the title,
 * the description in three lines; a wide picture lies across under them, a small one stands beside. A tap opens the link —
 * the site is read only now, by the one who chose to open it.
 */
fun linkCardView(c: Context, card: LinkCard, mine: Boolean): View {
    val words = c.vstack(Gravity.NO_GRAVITY) {
        card.s?.let { addView(c.text(it, 13f, BubbleStyle.text(mine), bold = true).apply { singleLineEllipsis() }, lp()) }   // USER-DATA: the site
        card.t?.let { addView(c.text(it, 14f, BubbleStyle.text(mine), bold = true).apply { maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END }, lp()) }
        card.d?.let { addView(c.text(it, 13f, BubbleStyle.time(mine)).apply { maxLines = 3; ellipsize = android.text.TextUtils.TruncateAt.END }, lp()) }
    }
    val pic = card.i?.let { b64 -> runCatching { Base64.decode(b64, Base64.NO_WRAP) }.getOrNull()?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } }
    return c.hstack {
        setPadding(0, dp(4), 0, dp(2))
        addView(View(c).apply { setBackgroundColor(BubbleStyle.text(mine)) }, lp(dp(2), MATCH).apply { marginEnd = dp(8) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            if (pic != null && !card.wide) addView(c.hstack {
                addView(words, lp(0, WRAP, 1f))
                addView(ImageView(c).apply { setImageBitmap(pic); scaleType = ImageView.ScaleType.CENTER_CROP }, lp(dp(56), dp(56)).apply { marginStart = dp(8) })
            }, lp()) else addView(words, lp())
            if (pic != null && card.wide) addView(ImageView(c).apply { setImageBitmap(pic); adjustViewBounds = true; scaleType = ImageView.ScaleType.FIT_CENTER },
                lp().apply { topMargin = dp(6) })
        }, LinearLayout.LayoutParams(dp(240), LinearLayout.LayoutParams.WRAP_CONTENT))
        pressable { runCatching { c.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(card.u)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }
    }
}
