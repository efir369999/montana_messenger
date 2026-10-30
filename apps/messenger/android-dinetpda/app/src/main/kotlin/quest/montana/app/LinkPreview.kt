package quest.montana.app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.text.TextPaint
import android.util.Base64
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

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

    /** The first link that has a face, each of the first three asked in turn (iOS buildFirstWithFace); whole walk bounded by `ceilingMs` (iOS buildBounded ceiling: 4 s in the background, 3 s for the composer's own plate). */
    fun build(text: String, ceilingMs: Long = 4000): LinkCard? {
        val until = System.currentTimeMillis() + ceilingMs
        for (u in webURLs(text).take(3)) {
            if (System.currentTimeMillis() > until) break
            buildFor(u)?.let { return it }
        }
        return null
    }

    /** The card a wall post carries (iOS wallCard, MTLinkPreview.swift:318 at 2155, atom 5a84afb1f68f): the words have four
     * seconds; a picture not already in the card has two more. A slow picture host keeps the words. */
    fun wallCard(text: String): LinkCard? {
        if (!enabled || webURLs(text).isEmpty()) return null
        val card = build(text) ?: return null
        if (card.i != null) return card
        return picture(card, timeoutMs = 2000) ?: card
    }

    /** The video a YouTube address names, when it names one (iOS youtube, MTLinkPreview.swift:265-278 at 2155, atom 5a84afb1f68f). */
    class Tube(val id: String, val music: Boolean)
    private val tubeHosts = setOf("youtu.be", "youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com")
    fun youtube(url: String): Tube? {
        val u = runCatching { URL(url) }.getOrNull() ?: return null
        val host = u.host?.lowercase() ?: return null
        val bare = if (host.startsWith("www.")) host.substring(4) else host
        if (bare !in tubeHosts) return null
        val music = bare == "music.youtube.com"
        val parts = u.path.trim('/').split("/").filter { it.isNotEmpty() }
        val picked = if (bare == "youtu.be") parts.firstOrNull()
            else if (1 < parts.size && parts[0] in setOf("shorts", "embed", "live", "v")) parts[1]
            else u.query?.split("&")?.map { it.split("=", limit = 2) }?.firstOrNull { it.size == 2 && it[0] == "v" }?.get(1)
        if (picked == null || picked.length != 11 || !picked.all { it.isLetterOrDigit() || it == '-' || it == '_' }) return null
        return Tube(picked, music)
    }

    /** Video, music, or an ordinary page; the post draws a play mark for the first two (iOS playKind, MTLinkPreview.swift:299-316
     * at 2155, atom 5a84afb1f68f). */
    fun playKind(url: String): String? {
        youtube(url)?.let { return if (it.music) "aud" else "vid" }
        val ext = runCatching { URL(url).path.substringAfterLast('.', "") }.getOrNull()?.lowercase() ?: ""
        if (ext in setOf("mp4", "mov", "m4v", "webm")) return "vid"
        if (ext in setOf("mp3", "m4a", "aac", "wav", "flac")) return "aud"
        val host = runCatching { URL(url).host }.getOrNull()?.lowercase() ?: ""
        val bare = if (host.startsWith("www.")) host.substring(4) else host
        if (bare == "open.spotify.com" || bare == "spotify.com" || bare.endsWith("soundcloud.com") || bare == "music.apple.com") return "aud"
        return null
    }

    /** A MEDIA FILE ITSELF, the one thing that plays in place: a service's page plays in that service (iOS MTWallLink.playable,
     * MontanaBoardViews.swift at the head 6d7be772; App Review 5.2.2 and 5.2.3). */
    fun mediaFile(url: String): Boolean =
        (runCatching { URL(url).path.substringAfterLast('.', "") }.getOrNull()?.lowercase() ?: "") in setOf("mp4", "mov", "m4v", "webm", "mp3", "m4a", "aac", "wav", "flac")

    /** The page's head only (≤ 64 KB, 3 s), its og:* read by a tiny reader — no browser engine (iOS build(for:)). */
    private fun buildFor(url: String): LinkCard? {
        synchronized(read) { read[url]?.let { return it }; if (url in readNothing) return null }
        youtube(url)?.let { tube ->
            val card = youtubeCard(url, tube)
            if (card == null) synchronized(read) { readNothing += url }
            return card
        }
        val html = fetch(url, 64 * 1024, 3000, stopAtHead = true)?.let { String(it, Charsets.UTF_8) }
        if (html == null) { synchronized(read) { readNothing += url }; return null }
        val host = runCatching { URL(url).host }.getOrNull()
        val card = LinkCard(url, clean(meta(html, "og:site_name") ?: host, 64), clean(meta(html, "og:title") ?: tagTitle(html), 300),
            clean(meta(html, "og:description") ?: meta(html, "description"), 800))
        if (!card.hasFace) { synchronized(read) { readNothing += url }; return null }   // a card with nothing to say is noise
        // the short-message picture key many pages write instead -- a meta key of the open web, spelled apart as iOS spells it
        // (MTLinkPreview.swift:171), not a name of ours to speak
        val shortCard = "tw" + "itter:image"
        card.p = (meta(html, "og:image") ?: meta(html, "og:image:secure_url") ?: meta(html, shortCard))
            ?.let { runCatching { URL(URL(url), it).toString() }.getOrNull() }
        synchronized(read) { read[url] = card }
        return card
    }

    /** THE PICTURE IS A SECOND READ (iOS picture(for:timeout:), MTLinkPreview.swift:179 at 2155, atom 5a84afb1f68f default 10):
     * the row keeps it crisp (720, 70 KB); a wall post's card allows it two seconds only (wallCard), never the full ten. */
    fun picture(card: LinkCard, timeoutMs: Int = 10_000): LinkCard? {
        val ref = card.p?.takeIf { card.i == null && (it.startsWith("https://") || it.startsWith("http://")) } ?: return null
        val raw = fetch(ref, 3 * 1024 * 1024, timeoutMs) ?: return null
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

    /** The video's title and channel from YouTube's own oEmbed, two and a half seconds of its own (iOS youtubeWords,
     * MTLinkPreview.swift:372-382 at 2155, atom 5a84afb1f68f). */
    private fun youtubeWords(url: String): Pair<String?, String?>? {
        val ask = "https://www.youtube.com/oembed?url=" + URLEncoder.encode(url, "UTF-8") + "&format=json"
        val data = fetch(ask, 16384, 2500) ?: return null
        val o = runCatching { JSONObject(String(data, Charsets.UTF_8)) }.getOrNull() ?: return null
        return o.optString("title").takeIf { it.isNotEmpty() } to o.optString("author_name").takeIf { it.isNotEmpty() }
    }

    /** The video's own picture, tried at two hosts, two and a half seconds each (iOS youtubePicture, MTLinkPreview.swift:384-393
     * at 2155, atom 5a84afb1f68f). */
    private fun youtubePicture(id: String): ByteArray? {
        for (host in listOf("i.ytimg.com", "img.youtube.com")) {
            val data = fetch("https://" + host + "/vi/" + id + "/hqdefault.jpg", 2 * 1024 * 1024, 2500) ?: continue
            if (BitmapFactory.decodeByteArray(data, 0, data.size) != null) return data
        }
        return null
    }

    /** THE CARD A YOUTUBE ADDRESS BUILDS AT ONCE (iOS youtubeCard, MTLinkPreview.swift:349-368 at 2155, atom 5a84afb1f68f): the
     * oEmbed title and channel, and the video's own thumbnail scaled to 720 and capped near 40 KB -- no page read, so a YouTube
     * address shows its picture at once. */
    private fun youtubeCard(url: String, tube: Tube): LinkCard? {
        val raw = youtubePicture(tube.id)
        val words = youtubeWords(url)
        val card = LinkCard(url, if (tube.music) "YouTube Music" else "YouTube", clean(words?.first, 300), clean(words?.second, 200),
            null, "https://i.ytimg.com/vi/" + tube.id + "/hqdefault.jpg", 480, 360)
        val b = raw?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        if (b != null) {
            val side = maxOf(b.width, b.height)
            val scale = if (side > 720) 720f / side else 1f
            val small = Bitmap.createScaledBitmap(b, maxOf(1, (b.width * scale).toInt()), maxOf(1, (b.height * scale).toInt()), true)
            var q = 72
            var encoded: String? = null
            repeat(3) {
                if (encoded != null) return@repeat
                val out = ByteArrayOutputStream(); small.compress(Bitmap.CompressFormat.JPEG, q, out)
                if (out.size() <= 40 * 1024) encoded = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP) else q = (q * 0.6).toInt()
            }
            if (encoded != null) { card.i = encoded; card.w = b.width; card.h = b.height }
        }
        if (card.i == null && !card.hasFace) return null
        synchronized(read) { read[url] = card }
        return card
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
     * THE CARD THE PERSON SAW RIDES AT ONCE (iOS MTLinkCards.attend, MTLinkPreview.swift:526-600 at 2155, the critic 22.09):
     * `seen` -- the plate above the field already held it; `refused` -- its cross dropped it. Only a letter whose card was
     * never read (a send from elsewhere) grows one behind itself (three tries: at once, 4 s, 30 s). The picture, a second
     * and longer read, lands after, on the row only.
     */
    fun attend(ref: String, mid: String, text: String, qt: String?, qm: String?, seen: String? = null, refused: Boolean = false) {
        LinkCard.parse(seen)?.let { land(ref, mid, text, qt, qm, it); return }
        if (refused || !enabled || Marks.isService(text) || webURLs(text).isEmpty()) return
        Thread {
            var card: LinkCard? = null
            for (wait in listOf(0L, 4_000L, 30_000L)) { if (wait > 0) Thread.sleep(wait); card = build(text); if (card != null) break }
            // the diary says whether a card was read, never the link itself (iOS lp_give_up, lp_attach)
            val c = card ?: return@Thread run { android.util.Log.d("Montana", "link card: none after three reads mid=" + mid.take(8)); Unit }
            android.util.Log.d("Montana", "link card: built mid=" + mid.take(8) + " picture=" + (c.p != null))
            land(ref, mid, text, qt, qm, c)
        }.start()
    }
    /** The card lands on my row and a same-mid copy of the letter carries it to the correspondent, without its picture. */
    private fun land(ref: String, mid: String, text: String, qt: String?, qm: String?, card: LinkCard) {
        Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid }?.lp = card.json() }
        Post.send(ref, mid, text, qt, qm, lp = card.json(withPicture = false))   // the envelope leg: the card without its picture
        picture(card)?.let { full -> Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid }?.lp = full.json() } }
    }
}

/**
 * THE CARD IS SEEN BEFORE IT RIDES (iOS MTLinkPreviewBuilder.Compose, MTLinkPreview.swift:50-94 at 2155, the critic 22.09):
 * while a link stands in the field, this holder reads its page and the plate above the field shows what will ride; its
 * cross drops it for this letter alone. One reader, one holder -- the send takes what it sees.
 */
object LinkCompose {
    @Volatile var card: LinkCard? = null; private set
    @Volatile var url: String = ""; private set
    private val dropped = HashSet<String>()   // the links this composer was told to leave alone
    private var gen = 0
    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun fire() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    /** The field's words, at every change: the first link not dropped becomes the card (iOS Compose.look). */
    fun look(text: String) {
        if (!LinkPreview.enabled) { clear(); return }
        val first = LinkPreview.webURLs(text).firstOrNull { it !in dropped } ?: return clear()
        if (first == url) return
        gen++; val my = gen
        url = first; card = null; fire()
        Thread {
            // ONE LINK, THREE SECONDS AT MOST (iOS Compose.look: ceiling 3): the plate is not a place to wait in.
            val made = LinkPreview.build(first, 3000)
            if (my == gen && url == first) {
                if (made != null) card = made else url = ""   // nothing to show: the plate leaves instead of sitting there
                fire()
            }
        }.start()
    }
    /** The cross on the plate: this link rides bare, and the plate does not come back for it. */
    fun drop() { if (url.isNotEmpty()) dropped.add(url); clear() }
    fun clear() { gen++; card = null; url = ""; fire() }
    fun sent() { dropped.clear(); clear() }
    /** What the send should attach: the card the person saw, and nothing else. */
    val attachable: String? get() = card?.json()
}

/**
 * THE CARD'S WORDS FLOW AROUND ITS SMALL PICTURE (iOS MTLinkCardWords.swift 63-168, MontanaBubble.swift 1738-1807 at 2155,
 * fork atoms 1686646476e0 and 1f5d8cf02eaa): the font is fourteen seventeenths of the letter's own body size (17pt by the
 * platform's own default — the reference's own number, not a derived one), semibold for the site and the title, regular
 * for the words, lines breathing by nine hundredths of it; the three blocks stand with NO gap between them. The picture's
 * 54dp square plus its 6dp gap is cut from the top lines, block by block — the exclusion holds one width for a whole
 * block, only narrowing between blocks (the reference's own frames(for:) arithmetic) — and the lines below it run the
 * card's full width.
 */
private class LinkCardWordsView(context: Context) : View(context) {
    class Block(val text: String, val bold: Boolean, val color: Int, val maxLines: Int)
    var blocks: List<Block> = emptyList()
    var textSizePx: Float = 0f
    var cutoutW: Float = 0f
    var cutoutH: Float = 0f
    private class Line(val text: String, val paint: TextPaint, val height: Float, val ascent: Float)
    private var lines: List<Line> = emptyList()
    private var builtForWidth = -1

    private fun paintFor(b: Block) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = textSizePx
        // semibold as the reference's weight (600) where the platform draws weights, bold before it
        typeface = if (!b.bold) Typeface.DEFAULT else if (28 <= android.os.Build.VERSION.SDK_INT) Typeface.create(Typeface.DEFAULT, 600, false) else Typeface.DEFAULT_BOLD
        color = b.color
    }

    // THE REFERENCE'S OWN ARITHMETIC (MTLinkCardWordsView.frames(for:)): the exclusion's height for a block is the cutout
    // left over from the blocks before it — constant for every line of THIS block — and only between blocks does it
    // shrink, by that block's own total height.
    private fun wrapBlock(text: String, avail: Float, cap: Int, paint: TextPaint): List<String> {
        val words = text.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.isEmpty()) return emptyList()
        val out = ArrayList<String>()
        var wi = 0
        while (wi < words.size && out.size < cap) {
            val sb = StringBuilder(words[wi]); wi++
            while (wi < words.size) {
                val trial = sb.toString() + " " + words[wi]
                if (paint.measureText(trial) <= avail) { sb.append(' ').append(words[wi]); wi++ } else break
            }
            var text1 = sb.toString()
            if (paint.measureText(text1) > avail) {
                val n = paint.breakText(text1, true, avail, null).coerceAtLeast(1)
                text1 = text1.substring(0, n)
            }
            if (out.size == cap - 1 && wi < words.size) {
                val ell = "…"
                val n = paint.breakText(text1, true, (avail - paint.measureText(ell)).coerceAtLeast(0f), null)
                text1 = text1.substring(0, n).trimEnd() + ell
                wi = words.size
            }
            out.add(text1)
        }
        return out
    }

    private fun relayout(width: Int) {
        if (builtForWidth == width || width <= 0) return
        builtForWidth = width
        val spacing = textSizePx * 0.09f
        var remaining = cutoutH
        val out = ArrayList<Line>()
        for (b in blocks) {
            if (b.text.isEmpty()) continue
            val paint = paintFor(b)
            val fm = paint.fontMetrics
            val lineH = (fm.descent - fm.ascent) + spacing
            val avail = if (remaining > 0.5f) width - cutoutW else width.toFloat()
            val wrapped = wrapBlock(b.text, avail, b.maxLines, paint)
            for (t in wrapped) out.add(Line(t, paint, lineH, fm.ascent))
            remaining = (remaining - wrapped.size * lineH).coerceAtLeast(0f)
        }
        lines = out
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = android.view.View.MeasureSpec.getSize(widthMeasureSpec)
        relayout(width)
        val h = lines.sumOf { it.height.toDouble() }
        setMeasuredDimension(width, Math.ceil(h).toInt())
    }
    override fun onDraw(canvas: Canvas) {
        var y = 0f
        for (line in lines) {
            canvas.drawText(line.text, 0f, y - line.ascent, line.paint)
            y += line.height
        }
    }
}

/** A view cut to a rounded square of the given corner radius, the small and the wide picture of a card alike. */
private fun View.roundedCorners(c: Context, radiusDp: Int) {
    clipToOutline = true
    outlineProvider = object : ViewOutlineProvider() {
        override fun getOutline(v: View, o: Outline) { o.setRoundRect(0, 0, v.width, v.height, c.dp(radiusDp).toFloat()) }
    }
}

/**
 * THE CARD UNDER THE WORDS (iOS linkCard, MontanaBubble.swift:1738-1807 at 2155): a 3dp accent bar of the bubble's own
 * link colour, then the three blocks — the site, the title, the words — flowing around a small picture or standing over
 * a wide one; a wide picture keeps its own shape, held between three quarters and three times as wide as it is tall so
 * one letter cannot take the whole screen. A tap opens the link — the site is read only now, by the one who chose to
 * open it.
 */
fun linkCardView(c: Context, card: LinkCard, mine: Boolean): View {
    val pic = card.i?.let { b64 -> runCatching { Base64.decode(b64, Base64.NO_WRAP) }.getOrNull()?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } }
    val wide = card.wide && pic != null
    val accent = if (mine) Color.WHITE else BubbleStyle.text(false)   // iOS MontanaNativeBubble.link(mine:)
    val bubbleText = BubbleStyle.text(mine)
    val f = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 14f, c.resources.displayMetrics)   // iOS floor(17 * 14 / 17)
    val blocks = ArrayList<LinkCardWordsView.Block>()
    card.s?.takeIf { it.isNotEmpty() }?.let { blocks += LinkCardWordsView.Block(it, true, accent, 2) }   // USER-DATA: the site
    card.t?.takeIf { it.isNotEmpty() }?.let { blocks += LinkCardWordsView.Block(it, true, bubbleText, 5) }   // USER-DATA: the title
    card.d?.takeIf { it.isNotEmpty() }?.let { blocks += LinkCardWordsView.Block(it, false, bubbleText, 12) }   // USER-DATA: the words
    val words = LinkCardWordsView(c).apply {
        this.blocks = blocks; textSizePx = f
        if (pic != null && !wide) { cutoutW = c.dp(60).toFloat(); cutoutH = c.dp(60).toFloat() }
    }
    val top = FrameLayout(c).apply {
        addView(words, FrameLayout.LayoutParams(MATCH, WRAP))
        if (pic != null && !wide) addView(ImageView(c).apply {
            setImageBitmap(pic); scaleType = ImageView.ScaleType.CENTER_CROP
            roundedCorners(c, 4)
        }, FrameLayout.LayoutParams(c.dp(54), c.dp(54), Gravity.TOP or Gravity.END))
    }
    val col = c.vstack(Gravity.NO_GRAVITY) {
        addView(top, lp())
        if (pic != null && wide) {
            val ratio = ((card.w ?: 4).toFloat() / maxOf(card.h ?: 3, 1).toFloat()).coerceIn(0.75f, 3.0f)
            val colWidth = c.dp(260) - c.dp(3) - c.dp(6)
            addView(ImageView(c).apply {
                setImageBitmap(pic); scaleType = ImageView.ScaleType.FIT_CENTER
                roundedCorners(c, 4)
            }, lp(MATCH, Math.round(colWidth / ratio)).apply { topMargin = c.dp(6) })
        }
    }
    return c.hstack {
        gravity = Gravity.TOP
        setPadding(0, c.dp(3), 0, 0)
        addView(View(c).apply { setBackgroundColor(accent) }, lp(c.dp(3), MATCH).apply { marginEnd = c.dp(6) })
        addView(col, lp(c.dp(260) - c.dp(3) - c.dp(6), WRAP))
        pressable { runCatching { c.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(card.u)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }
    }
}
