package quest.montana.app

import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * STICKERS (iOS MontanaSticker / MontanaStickerScreens), in the two shapes every build already draws without a bubble:
 *   · a glyph — the invisible sticker mark and one emoji (iOS sendSticker: stickerMark + e), drawn large;
 *   · a picture of my own set — an ordinary picture letter whose manifest carries the card sticker's name «montana-card»
 *     (iOS sendStickerFile: kind img, docName MontanaCardPlate.stickerName), drawn in its own square without a bubble.
 * MY OWN SET (iOS MontanaStickerBook): the pictures lie in the app's private storage, the order in the defaults; a picture is
 * named by its own bytes, so the same sticker is kept once and, used again, moves to the front; the ceiling is a person's set.
 * THE SETS OF OTHER PEOPLE travel by the «SP:» words (StickerWire): a sticker of my set carries its passport, my set is given to
 * whoever asks it, the sets of others are met and land in StickerBook, and their page and link (setPage, StickerPack) ask the
 * giver for them. Not yet here: the platform's subject cut — iOS lifts the subject with Vision; Android has no such native road.
 */
object Stickers {
    /** The card sticker's name in a picture's manifest (iOS MontanaCardPlate.stickerName): every build draws it bare. */
    const val CARD = "montana-card"
    private const val SHELF = "stickers.mine"
    private const val CEILING = 120                  // iOS MontanaStickerBook.ceiling
    private const val SIDE = 512                     // iOS MontanaStickerCut.side
    private const val LOOK = 192                     // iOS MTStickerLook.side: the glyph's 64, three times over
    /** The glyphs the panel offers as stickers of their own (iOS the emoji panel's sticker road). */
    private val GLYPHS = listOf("❤️", "😂", "👍", "🔥", "🥰", "😢", "😮", "🙏", "🎉", "😎", "🤔", "👋", "💯", "😘", "🤝", "✨")

    private fun dir(c: Context) = File(c.filesDir, "stickers").apply { mkdirs() }
    /** The person forgotten: their stickers leave with them (Book.wipe); the list of names lived in the person's preferences. */
    fun wipe(c: Context) { File(c.filesDir, "stickers").deleteRecursively(); StickerBook.wipe() }
    fun file(c: Context, name: String) = File(dir(c), name)
    fun names(c: Context): List<String> = Prefs.str(SHELF, "").split('\n').filter { it.isNotEmpty() && file(c, it).exists() }
    private fun keep(list: List<String>) = Prefs.setStr(SHELF, list.joinToString("\n"))

    /** A STICKER USED IS A STICKER KEPT, AND KEPT ONCE (iOS add(png:)): named by its bytes; known — it moves to the front. */
    fun add(c: Context, bytes: ByteArray, ext: String): String {
        val name = "stk_" + Wire.hex(Wire.sha(bytes)).take(16) + "." + ext
        val f = file(c, name)
        if (!f.exists()) f.writeBytes(bytes)
        val list = listOf(name) + names(c).filter { it != name }
        list.drop(CEILING).forEach { file(c, it).delete() }   // the oldest leaves with its file
        keep(list.take(CEILING))
        return name
    }
    fun forget(c: Context, name: String) { keep(names(c).filter { it != name }); if (!StickerBook.othersHold(name)) file(c, name).delete() }
    /**
     * A COPY LAID (iOS MontanaStickerBook, MontanaSticker.swift 128, 171-173: «montana.stickers.mine», names over the media store, laid as
     * a union — SeedScope.unionKeys 6308): the set here stays as it stands, and a sticker of the copy's it lacks joins after it, its
     * picture taken from the copy's store.
     */
    fun lay(c: Context, names: List<String>, store: File) {
        val have = names(c)
        val add = names.distinct().filter { n ->
            n !in have && MontanaBackup.plainName(n) && (file(c, n).isFile || runCatching { File(store, n).copyTo(file(c, n)) }.isSuccess)
        }
        if (add.isNotEmpty()) keep(have + add)
    }

    // ── what a letter is ──

    private fun manifestOf(m: Msg): JSONObject? = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
    private fun isPicture(m: Msg) = m.text.startsWith(Marks.MEDIA) && manifestOf(m)?.optString("n") == CARD
    /** A STICKER OF THE HOUSE (iOS gifBubble, MontanaBubble.swift 1121 at 2155): a moving picture on the document road whose name
     * says «stick_» — drawn bare and at a sticker's size on both sides; a build that knows neither name shows the file plate. */
    fun house(m: Msg): Boolean = m.text.startsWith(Marks.MEDIA) &&
        (manifestOf(m)?.optString("n")?.startsWith("stick_") == true || m.file?.let { File(it).name.startsWith("stick_") } == true)
    /** A sticker stands without a bubble: a glyph sticker, a picture that says it is the card sticker, a sticker of the house, or a
     * letter of one to three emoji alone (iOS bigEmojiText). */
    fun bare(m: Msg): Boolean = m.text.startsWith(Marks.STICKER) || isPicture(m) || house(m) || (m.file == null && bigEmoji(m.text) != null)

    /** THE GLYPH'S ONE SIZE (iOS MTStickerLook.glyph = 64): a sticker is three of it across. */
    private const val GLYPH = 64f

    /**
     * THE BIG-GLYPH LETTER (iOS bigEmojiText, MontanaBubble.swift 31-52 at 2155): a panel sticker, or a typed letter of emoji alone, at
     * most three of them, stands at the glyph's size without a bubble. A character is an emoji as iOS judges it: one of its scalars
     * shows as emoji by default, or several scalars with an emoji among them (❤️, a keycap), or a flag's two letters.
     */
    fun bigEmoji(text: String): String? {
        if (text.startsWith(Marks.STICKER)) return text.removePrefix(Marks.STICKER)
        val t = text.trim()
        if (t.isEmpty() || Build.VERSION.SDK_INT < 28) return null
        val it = android.icu.text.BreakIterator.getCharacterInstance()
        it.setText(t)
        var glyphs = 0
        var a = it.first()
        var b = it.next()
        while (b != android.icu.text.BreakIterator.DONE) {
            val ch = t.substring(a, b)
            if (ch.isNotBlank()) { if (!isEmoji(ch)) return null; glyphs++ }
            a = b; b = it.next()
        }
        return if (glyphs in 1..3) t else null
    }

    private fun isEmoji(ch: String): Boolean {
        val cps = ch.codePoints().toArray()
        if (cps.any { android.icu.lang.UCharacter.hasBinaryProperty(it, android.icu.lang.UProperty.EMOJI_PRESENTATION) }) return true
        if (cps.size > 1 && cps.any { android.icu.lang.UCharacter.hasBinaryProperty(it, android.icu.lang.UProperty.EMOJI) }) return true
        return cps.size >= 2 && cps.all { it in 0x1F1E6..0x1F1FF }
    }
    /** The one size every sticker of ours wears (iOS MTStickerLook.box): the picture fitted into the sticker's square. */
    fun box(c: Context, w: Int, h: Int): Pair<Int, Int> {
        val side = c.dp(LOOK)
        val k = side.toFloat() / maxOf(w, h, 1)
        return (w * k).toInt().coerceAtLeast(1) to (h * k).toInt().coerceAtLeast(1)
    }

    /** The sticker's own face inside the letter's column; false — not a sticker, the bubble draws it as ever. */
    fun body(c: Context, m: Msg, into: LinearLayout): Boolean {
        val glyph = if (m.file == null) bigEmoji(m.text) else null
        if (glyph != null) {
            // USER-DATA: the sticker's glyph, or the letter's own emoji
            into.addView(c.text(glyph, GLYPH).apply { includeFontPadding = false }, LinearLayout.LayoutParams(WRAP, WRAP))
            return true
        }
        if (!isPicture(m)) return false
        val f = m.file?.let { File(it) }?.takeIf { it.exists() }
        val pic = f?.let { Media.preview(c, it, "img", SIDE) } ?: Media.thumbOf(manifestOf(m))
        val box = c.dp(LOOK)
        val (w, h) = if (pic == null) box to box else {
            val k = box.toFloat() / maxOf(pic.width, pic.height)
            (pic.width * k).toInt().coerceAtLeast(1) to (pic.height * k).toInt().coerceAtLeast(1)
        }
        into.addView(FrameLayout(c).apply {
            addView(ImageView(c).apply { scaleType = ImageView.ScaleType.FIT_CENTER; pic?.let { setImageBitmap(it) } }, FrameLayout.LayoutParams(w, h))
            if (f == null) addView(android.widget.ProgressBar(c), FrameLayout.LayoutParams(c.dp(30), c.dp(30), Gravity.CENTER))
        }, LinearLayout.LayoutParams(WRAP, WRAP).apply { bottomMargin = c.dp(2) })
        if (m.state == -1) into.addView(c.text(c.getString(R.string.media_failed), 12f, SysColor.red))
        return true
    }

    // ── leaving ──

    /**
     * A STICKER ANSWERS A LETTER LIKE ANY WORD DOES (iOS sendSticker → sendMessage's replyingTo, sendStickerFile's answered,
     * MontanaConversation.swift:4240-4243 and 4509-4515 at 2316; atom 0d501f110022): the open chat hands over the letter its plate
     * holds, and the plate goes. A moving picture answers nobody (iOS sendGifFile / sendGifFound leave replyingTo where it stands).
     */
    var answering: ((String) -> Msg?)? = null
    private fun answered(ref: String): Pair<String, String>? = answering?.invoke(ref)?.let { letterWords(Book.ctx, it).take(200) to it.mid }

    /** A glyph sticker: one letter of the mark and the emoji, the quote with it as with any word (iOS sendSticker). */
    fun sendGlyph(ref: String, e: String) {
        val text = Marks.STICKER + e
        val q = answered(ref)
        if (Groups.isKey(ref)) { Groups.send(ref, text, q?.first, q?.second); return }   // a group's letter rides the group's carrier
        val mid = Marks.mintMid()
        Book.edit(ref) { it.msgs.add(Msg(mid, text, true, Marks.birthMs(mid) ?: System.currentTimeMillis(), qt = q?.first, qm = q?.second)) }
        Post.send(ref, mid, text, q?.first, q?.second)
    }

    /**
     * A picture of my set leaves by the picture road with the card sticker's name, and moves to the front of the set; its passport
     * follows under the letter's own name, so the other side knows the set it is of (iOS sendStickerFile + MontanaStickerWire.sendPassport).
     */
    fun sendPicture(c: Context, ref: String, name: String) {
        val f = file(c, name).takeIf { it.exists() } ?: return
        val bytes = f.readBytes()
        add(c, bytes, f.extension)
        val mid = Marks.mintMid()
        // the plate stands over the sticker here at once; the picture road carries no reply, the quote rides the passport (iOS 22.09)
        val q = answered(ref)
        Thread {
            Media.send(c, ref, Media.Picked(bytes, "img", f.extension, CARD), "", named = mid, plate = q)
            if (Book.chat(ref)?.msgs?.any { it.mid == mid } == true) StickerWire.sendPassport(ref, mid, bytes, q)   // a refused letter has no passport
        }.start()
    }

    /** ANY STICKER LETTER CAN BE RE-CUT, MINE OR THEIRS (iOS onEditSticker: MontanaMessageMenu.swift:474-476 and
     * MontanaConversation.swift:2251-2254 at 2155, neither narrowed to m.isFromMe): the editor opens on that very
     * picture and what the check keeps is a NEW sticker of my own set — the letter it came from is never touched.
     * Android narrows only to a picture already on this phone (the file assembled). */
    fun editable(m: Msg): Boolean = isPicture(m) && m.file != null

    /** THE STICKER'S OWN SET (iOS onViewSet / onCopyLink, MontanaConversation.swift:2387-2402 at 2314): a letter of mine
     * belongs to this phone's set; a letter of another carries its passport, and the passport names the set. */
    fun viewable(m: Msg): Boolean = isPicture(m)
    fun setOf(m: Msg): String = if (m.mine) "" else StickerBook.passport(m.mid)?.pack ?: ""

    /** The set's link to the clipboard (iOS onCopyLink): the passport's set and title, or my own set's. */
    fun copyLink(c: Context, m: Msg) {
        val port = if (m.mine) null else StickerBook.passport(m.mid)
        copyLink(c, port?.pack ?: StickerBook.mineId, port?.title ?: "Montana")
    }
    private fun copyLink(c: Context, pack: String, title: String) {
        c.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("", StickerPack.link(pack, title)))
        Log.d("Montana", "sticker_link copied pack=" + pack.take(8))
    }

    /** EDIT STICKER (iOS MontanaStickerEditor via the .stickerEdit sheet, MontanaConversation 2139-2149): the letter's own
     * picture opens in the editor; what the check keeps is a NEW sticker of my set, sent at once — the letter it came from
     * is never touched. */
    fun editFromLetter(act: MainActivity, ref: String, m: Msg) {
        val c: Context = act
        val f = m.file?.let { File(it) }?.takeIf { it.exists() } ?: return
        act.background {
            val b = BitmapFactory.decodeFile(f.path)
            if (b != null) act.onMain { editor(act, b) { bytes, ext -> val n = add(c, bytes, ext); sendPicture(c, ref, n) } }
        }
    }

    /** Light or not a sticker (iOS MontanaStickerCut.encode, HEIC 0.8): the platform's own light format with transparency. */
    private fun encode(b: Bitmap): Pair<ByteArray, String> {
        val out = ByteArrayOutputStream()
        @Suppress("DEPRECATION")
        val fmt = if (Build.VERSION.SDK_INT >= 30) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP
        return if (b.compress(fmt, 80, out) && out.size() > 0) out.toByteArray() to "webp"
        else ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray() to "png"
    }

    // ── the panel ──

    /**
     * A SET AS A PAGE (iOS MontanaStickerSetPage, MontanaStickerScreens.swift:172-282 at 2314; opened by the panel's settings
     * glass and by «View sticker set» on a sticker letter), four in a row. A tap sends one into this conversation; our cross at
     * the left, the set's link at the right. The page shows ANY set: `pack` empty is this phone's own — the glyphs over it, the
     * plus that makes one from a photo, a hold that drops one, «Delete all»; another's set is the one its passport or link named,
     * asked of its giver once per opening while it is not whole, filling as its pages land, the places still on the way standing
     * empty, and «Remove set» takes it off this phone. Nobody else is asked: the link carries no address.
     */
    fun setPage(act: MainActivity, ref: String, pack: String = "") {
        val c: Context = act
        val mine = pack.isEmpty() || pack == StickerBook.mineId
        val title = if (mine) c.getString(R.string.stickers) else StickerBook.pack(pack)?.title ?: "Montana"   // USER-DATA: the set's own title
        lateinit var close: () -> Unit
        val grid = GridLayout(c).apply { columnCount = 4; setPadding(c.dp(10), c.dp(6), c.dp(10), c.dp(16)) }
        val empty = c.text(c.getString(R.string.stickers_empty), 15f, MT.gray, center = true).apply { setPadding(c.dp(24), c.dp(28), c.dp(24), c.dp(28)) }
        fun list(): List<String> = if (mine) names(c) else StickerBook.pack(pack)?.names?.filter { file(c, it).exists() } ?: emptyList()
        fun waiting(): Int = if (mine) 0 else StickerBook.pack(pack)?.let { maxOf(0, it.expected - it.names.size) } ?: 0
        val foot = c.vstack(Gravity.NO_GRAVITY) {}
        fun fill() {
            grid.removeAllViews()
            val list = list()
            empty.visibility = if (mine && list.isEmpty()) View.VISIBLE else View.GONE
            val cell = (c.resources.displayMetrics.widthPixels - c.dp(20)) / 4
            for (n in list) grid.addView(ImageView(c).apply {
                scaleType = ImageView.ScaleType.FIT_CENTER
                setPadding(c.dp(8), c.dp(8), c.dp(8), c.dp(8))
                act.background { BitmapFactory.decodeFile(file(c, n).path, BitmapFactory.Options().apply { inSampleSize = 2 })?.let { b -> act.onMain { setImageBitmap(b) } } }
                pressable { close(); sendPicture(c, ref, n) }
                if (mine) setOnLongClickListener {
                    AlertDialog.Builder(c).setMessage(R.string.sticker_delete_q)
                        .setPositiveButton(R.string.delete) { _, _ -> forget(c, n); fill() }
                        .setNegativeButton(R.string.cancel, null).show()
                    true
                }
            }, GridLayout.LayoutParams().apply { width = cell; height = cell })
            // what has not arrived yet stands as an empty place, not as a word: the eye sees how much is still on the way
            repeat(waiting()) {
                grid.addView(View(c).apply { background = c.rounded(Color.argb(13, 255, 255, 255), 12) },
                    GridLayout.LayoutParams().apply { width = cell - c.dp(12); height = cell - c.dp(12); setMargins(c.dp(6), c.dp(6), c.dp(6), c.dp(6)) })
            }
            // THE RED ROW AT THE FOOT (iOS «Delete all» / «Remove set»), behind the platform's own question
            foot.removeAllViews()
            if (list.isNotEmpty()) foot.addView(c.text(c.getString(if (mine) R.string.sticker_delete_all else R.string.sticker_remove_set), 16f, MT.red, center = true).apply {
                setPadding(c.dp(16), c.dp(14), c.dp(16), c.dp(14))
                pressable {
                    AlertDialog.Builder(c).setMessage(if (mine) R.string.sticker_delete_all else R.string.sticker_remove_set)
                        .setPositiveButton(R.string.delete) { _, _ ->
                            if (mine) { names(c).forEach { forget(c, it) }; fill() } else { StickerBook.drop(pack); close() }
                        }
                        .setNegativeButton(R.string.cancel, null).show()
                }
            }, lp())
        }
        val glyphs = HorizontalScrollView(c).apply {
            isHorizontalScrollBarEnabled = false
            addView(c.hstack {
                setPadding(c.dp(10), 0, c.dp(10), 0)
                for (e in GLYPHS) addView(c.text(e, 34f).apply { setPadding(c.dp(8), c.dp(6), c.dp(8), c.dp(6)); pressable { close(); sendGlyph(ref, e) } })   // USER-DATA: none, the glyphs are ours
            })
        }
        fun mark(res: Int, label: Int, onTap: () -> Unit) = FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(label)
            addView(c.icon(res, Color.rgb(204, 204, 204)), FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
            pressable(onTap)
        }
        val sheet = c.vstack(Gravity.NO_GRAVITY) {
            background = c.rounded(Color.rgb(20, 20, 22), 22)
            isClickable = true
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(6))
                addView(mark(R.drawable.ic_close, R.string.cancel) { close() }, lp(c.dp(40), c.dp(40)))
                addView(c.text(title, 17f, bold = true, center = true).apply { maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END }, lp(0, WRAP, 1f))
                // THE SET'S LINK (iOS the page's link mark): its name and title, no address
                addView(mark(R.drawable.ic_link, R.string.copy_link) {
                    if (mine) copyLink(c, StickerBook.mineId, "Montana") else copyLink(c, pack, title)
                }, lp(c.dp(40), c.dp(40)).apply { if (mine) marginEnd = c.dp(8) })
                // THE PLUS MAKES ONE FROM A PHOTO (iOS MontanaStickerEditor): the system's picker, then the frame
                if (mine) addView(mark(R.drawable.ic_plus, R.string.sticker_make) {
                    act.pickPhoto { uri -> if (uri != null) act.background { load(c, uri)?.let { b -> act.onMain { editor(act, b) { bytes, ext -> close(); fill(); val n = add(c, bytes, ext); sendPicture(c, ref, n) } } } } }
                }, lp(c.dp(40), c.dp(40)))
            }, lp())
            if (mine) addView(glyphs, lp())
            addView(View(c).apply { setBackgroundColor(Color.argb(40, 255, 255, 255)) }, lp(MATCH, 1).apply { topMargin = c.dp(6) })
            addView(ScrollView(c).apply { addView(c.vstack(Gravity.NO_GRAVITY) { addView(empty, lp()); addView(grid, lp()) }) }, lp(MATCH, (c.resources.displayMetrics.heightPixels * 0.42).toInt()))
            addView(foot, lp())
        }
        val page = FrameLayout(c).apply {
            setBackgroundColor(Color.argb(120, 0, 0, 0))
            isClickable = true
            setOnClickListener { close() }
            addView(sheet, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))
        }
        fill()
        val shut = act.overlay(page)
        StickerBook.onChange = { fill() }
        close = { StickerBook.onChange = null; shut() }
        // A SET WE DO NOT HOLD IS ASKED OF THE ONE WHO GAVE IT, once per opening (iOS askGiver)
        if (!mine && (waiting() > 0 || list().isEmpty())) StickerBook.giver(pack)?.let { g -> act.background { StickerWire.ask(pack, g) } }
    }

    /** The picked photo, stood upright by its own EXIF turn and no larger than the frame needs. */
    private fun load(c: Context, uri: Uri): Bitmap? = runCatching {
        if (Build.VERSION.SDK_INT >= 28) android.graphics.ImageDecoder.decodeBitmap(android.graphics.ImageDecoder.createSource(c.contentResolver, uri)) { d, info, _ ->
            d.allocator = android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE
            val big = maxOf(info.size.width, info.size.height)
            if (big > 2048) d.setTargetSize(info.size.width * 2048 / big, info.size.height * 2048 / big)
        } else c.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = 2 }) }
    }.getOrNull()

    /**
     * THE STICKER EDITOR (iOS MontanaStickerEditor): the photo in a square frame, moved and scaled by the finger; what stands
     * in the frame is the sticker, on a transparent ground where the photo does not reach. The cross leaves, the check keeps.
     */
    private fun editor(act: MainActivity, image: Bitmap, onDone: (ByteArray, String) -> Unit) {
        val c: Context = act
        lateinit var close: () -> Unit
        val canvas = StickerCanvas(c, image)
        val page = FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            isClickable = true
            addView(canvas, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(c.icon(R.drawable.ic_close, Color.WHITE).apply { setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12)); pressable { close() } },
                FrameLayout.LayoutParams(c.dp(48), c.dp(48), Gravity.TOP or Gravity.START).apply { setMargins(c.dp(8), c.dp(8), 0, 0) })
            addView(c.icon(R.drawable.ic_check, Color.WHITE).apply {
                setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12))
                pressable { val shot = canvas.render(SIDE); close(); act.background { val (b, ext) = encode(shot); act.onMain { onDone(b, ext) } } }
            }, FrameLayout.LayoutParams(c.dp(48), c.dp(48), Gravity.TOP or Gravity.END).apply { setMargins(0, c.dp(8), c.dp(8), 0) })
        }
        close = act.overlay(page)
    }
}

/**
 * THE FRAME OVER THE PHOTO (iOS MTZoomPicture): the photo fits the square at first and may be scaled up to five times and
 * moved; unlike the face's crop it may stand smaller than the frame — the rest of the square is the sticker's air.
 */
private class StickerCanvas(ctx: Context, private val image: Bitmap) : View(ctx) {
    private var zoom = 1f
    private var panX = 0f
    private var panY = 0f
    private var side = 0f
    private var fit = 1f
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val dim = Paint().apply { color = Color.argb(153, 0, 0, 0) }
    private val air = Paint().apply { color = Color.rgb(36, 36, 38) }
    private val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = Color.argb(51, 255, 255, 255); strokeWidth = context.dp(1).toFloat().coerceAtLeast(1f) }
    private val scaler = ScaleGestureDetector(ctx, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(d: ScaleGestureDetector): Boolean { zoom = (zoom * d.scaleFactor).coerceIn(1f, 5f); invalidate(); return true }
    })
    private var lastX = 0f
    private var lastY = 0f
    private var pointer = -1

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        side = (minOf(w, h) - context.dp(24)).toFloat().coerceAtLeast(context.dp(120).toFloat())
        fit = side / maxOf(image.width, image.height)
    }
    private fun frame() = RectF(width / 2f - side / 2, height / 2f - side / 2, width / 2f + side / 2, height / 2f + side / 2)
    /** Where the photo stands on the screen: centred in the frame, then scaled and moved by the finger. */
    private fun matrix(into: RectF, k: Float): Matrix = Matrix().apply {
        val s = fit * zoom * k
        postTranslate(-image.width / 2f, -image.height / 2f)
        postScale(s, s)
        postTranslate(into.centerX() + panX * k, into.centerY() + panY * k)
    }

    override fun onDraw(c: Canvas) {
        val f = frame()
        val round = Path().apply { addRoundRect(f, context.dp(20).toFloat(), context.dp(20).toFloat(), Path.Direction.CW) }
        c.save(); c.clipPath(round); c.drawRect(f, air); c.restore()
        c.drawBitmap(image, matrix(f, 1f), paint)
        c.save(); c.clipOutPath(round); c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), dim); c.restore()
        c.drawPath(round, rim)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        scaler.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { pointer = e.getPointerId(0); lastX = e.x; lastY = e.y }
            MotionEvent.ACTION_POINTER_UP -> { pointer = -1 }
            MotionEvent.ACTION_MOVE -> {
                val i = e.findPointerIndex(pointer)
                if (i >= 0 && !scaler.isInProgress) {
                    panX += e.getX(i) - lastX; panY += e.getY(i) - lastY
                    val lim = side / 2 + fit * zoom * maxOf(image.width, image.height) / 2   // the photo never leaves the frame whole
                    panX = panX.coerceIn(-lim, lim); panY = panY.coerceIn(-lim, lim)
                    invalidate()
                }
                if (i >= 0) { lastX = e.getX(i); lastY = e.getY(i) } else { pointer = e.getPointerId(0); lastX = e.getX(0); lastY = e.getY(0) }
            }
        }
        return true
    }

    /** What stands in the frame, to the pixel, on a transparent square of `px` (iOS MTStickerCanvas.png). */
    fun render(px: Int): Bitmap {
        val out = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val k = px / side
        Canvas(out).drawBitmap(image, matrix(RectF(0f, 0f, px.toFloat(), px.toFloat()), k), paint)
        return out
    }
}
