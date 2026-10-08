package quest.montana.app

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BlendMode
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import android.provider.ContactsContract
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.Patterns
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ScrollView
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File

// ─────────────────────────── the business card (iOS MontanaBusinessCard, MontanaCardFace, MontanaCardNoteView) ───────────────────────────

/**
 * THE BUSINESS CARD IS KEPT (iOS MontanaBusinessCard, the author's word 28.09): one record of the person's own card — the name,
 * the phone, the e-mail and the other ways to reach them — sealed under the device key. A card never kept carries the
 * person's own name. Its words ride a photo's caption under the card's mark, which every build reads.
 */
class BusinessCard(var name: String, var phone: String, var email: String, var other: String) {
    /** The lines the card carries, in its order: the name, then every way to reach the person that is filled in. */
    val lines: List<String> get() = listOf(name.trim()) + (listOf(phone, email) + other.split("\n")).map { it.trim() }.filter { it.isNotEmpty() }
    val text: String get() = lines.joinToString("\n")
    val wire: String get() = MARK + text
    val isEmpty: Boolean get() = lines.all { it.isEmpty() }
    fun keep() = DeviceVault.set(KEY, JSONObject().put("name", name).put("phone", phone).put("email", email).put("other", other).toString().toByteArray(Charsets.UTF_8))

    companion object {
        const val MARK = "\uD83D\uDCC7 "   // iOS MontanaCardPlate.mark
        const val ASPECT = 85.60f / 53.98f       // ISO/IEC 7810 ID-1, the one standard size a card has
        private const val KEY = "businessCard"
        /** The person forgotten: their card leaves with them (Book.wipe). */
        fun forget() = DeviceVault.delete(KEY)
        fun kept(): BusinessCard {
            val o = DeviceVault.get(KEY)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() }
            val card = BusinessCard(o?.optString("name") ?: "", o?.optString("phone") ?: "", o?.optString("email") ?: "", o?.optString("other") ?: "")
            if (card.name.isBlank()) card.name = Prefs.userName
            return card
        }
        /** The card's lines out of a caption that carries the mark (iOS MontanaCardLine.lines). */
        fun lines(caption: String): List<String>? = caption.takeIf { it.startsWith(MARK) }?.removePrefix(MARK)?.split("\n")
    }
}

/** WHAT A LINE OF A CARD IS (iOS MontanaCardLine): a phone, an e-mail, a link or the person's own words, by the platform's own patterns. */
private enum class LineKind { PHONE, EMAIL, LINK, WORDS }
private fun kindOf(line: String): LineKind = when {
    Patterns.EMAIL_ADDRESS.matcher(line).find() -> LineKind.EMAIL
    Patterns.WEB_URL.matcher(line).find() && !Patterns.PHONE.matcher(line).matches() -> LineKind.LINK
    Patterns.PHONE.matcher(line).find() -> LineKind.PHONE
    else -> LineKind.WORDS
}
private fun glyphOf(line: String) = when (kindOf(line)) {
    LineKind.PHONE -> R.drawable.ic_peer_phone; LineKind.EMAIL -> R.drawable.ic_email
    LineKind.LINK -> R.drawable.ic_link; LineKind.WORDS -> R.drawable.ic_set_textbubble
}
/** The ways the face has room for (iOS shown): four lines under the name; a fifth and more stand on the fourth. */
private fun shown(lines: List<String>): List<String> {
    val ways = lines.drop(1).filter { it.isNotEmpty() }
    return if (ways.size <= 4) ways else ways.take(3) + ways.drop(3).joinToString(" · ")
}

private val INK = Color.rgb(41, 28, 5)
private val INK_SOFT = Color.rgb(77, 54, 13)

/**
 * THE CARD'S ONE FACE (iOS MontanaCardFace on MontanaCardPlate, the author's word 07.09: «an expensive gold metal card with the
 * Montana symbol»): brushed gold with a diagonal sheen, the emblem pressed large on the right, a bevelled rim, the name large at
 * the top and each way to reach the person at the bottom behind the glyph of what it is. The page draws it live; the photo is
 * drawn from it full bleed.
 */
private fun drawFace(c: Context, canvas: Canvas, w: Float, lines: List<String>, corner: Float) {
    val h = w / BusinessCard.ASPECT
    val k = w / 260f
    val box = RectF(0f, 0f, w, h)
    val p = Paint(Paint.ANTI_ALIAS_FLAG)
    canvas.save()
    canvas.clipPath(android.graphics.Path().apply { addRoundRect(box, corner, corner, android.graphics.Path.Direction.CW) })
    p.shader = LinearGradient(0f, 0f, w, h,
        intArrayOf(Color.rgb(158, 115, 36), Color.rgb(237, 194, 92), Color.rgb(252, 230, 148), Color.rgb(224, 173, 69), Color.rgb(168, 120, 33)),
        floatArrayOf(0f, 0.28f, 0.46f, 0.62f, 1f), Shader.TileMode.CLAMP)
    canvas.drawRect(box, p)
    // the symbol pressed into the metal: darker where the stamp pressed
    c.getDrawable(R.drawable.logo)?.let { d ->
        val lh = h * 0.7f
        val lw = lh * d.intrinsicWidth / maxOf(1, d.intrinsicHeight)
        val bmp = Bitmap.createBitmap(maxOf(1, lw.toInt()), maxOf(1, lh.toInt()), Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, bmp.width, bmp.height); d.draw(Canvas(bmp))
        val lp = Paint(Paint.ANTI_ALIAS_FLAG).apply { alpha = (0.32f * 255).toInt(); if (Build.VERSION.SDK_INT >= 29) blendMode = BlendMode.MULTIPLY }
        canvas.drawBitmap(bmp, w - h * 0.08f - bmp.width, (h - bmp.height) / 2f, lp)
    }
    // the bevel of a milled card: a thin light edge along the top left, darker along the bottom right
    p.shader = LinearGradient(0f, 0f, w, h, intArrayOf(Color.argb(140, 255, 255, 255), Color.TRANSPARENT, Color.argb(64, 0, 0, 0)), null, Shader.TileMode.CLAMP)
    p.style = Paint.Style.STROKE; p.strokeWidth = 1.5f * k
    canvas.drawRoundRect(RectF(0.75f * k, 0.75f * k, w - 0.75f * k, h - 0.75f * k), corner, corner, p)
    p.shader = null; p.style = Paint.Style.FILL
    val pad = 16f * k
    fun fit(t: Paint, s: String, size: Float, room: Float, least: Float) {
        t.textSize = size
        while (t.measureText(s) > room && t.textSize > size * least) t.textSize -= size * 0.05f
    }
    val name = lines.firstOrNull() ?: ""
    val tn = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = INK; typeface = Typeface.DEFAULT_BOLD }
    fit(tn, name, 20f * k, w - 2 * pad, 0.5f)
    canvas.drawText(name, pad, pad - tn.ascent(), tn)   // USER-DATA: the card's first line, the name the person wrote
    val ways = shown(lines)
    val tw = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = INK_SOFT; typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD) }
    val lineH = 13f * k * 1.25f + 4f * k
    var y = h - pad - (ways.size - 1) * lineH
    for (way in ways) {
        fit(tw, way, 13f * k, w - 2 * pad - 20f * k, 0.6f)
        c.getDrawable(glyphOf(way))?.mutate()?.let { g ->
            val gs = (10f * k).toInt()
            g.setTint(INK_SOFT)
            g.setBounds(pad.toInt() + ((14f * k - gs) / 2).toInt(), (y - 9.5f * k).toInt(), pad.toInt() + ((14f * k + gs) / 2).toInt(), (y - 9.5f * k).toInt() + gs)
            g.draw(canvas)
        }
        canvas.drawText(way, pad + 20f * k, y, tw)   // USER-DATA: a way to reach the person, as they wrote it
        y += lineH
    }
    canvas.restore()
}

/** The face as a view of the page, drawn live as it will leave. */
private class CardFaceView(c: Context, var lines: List<String>) : View(c) {
    override fun onMeasure(ws: Int, hs: Int) {
        val w = MeasureSpec.getSize(ws)
        setMeasuredDimension(w, (w / BusinessCard.ASPECT).toInt())
    }
    override fun onDraw(canvas: Canvas) = drawFace(context, canvas, width.toFloat(), lines, 14f * width / 260f)
}

/** THE CARD AS A PHOTO OF THE STANDARD SIZE (iOS photo(), the author's word 28.09): full bleed, 1600 by 1008 pixels. */
fun cardPhoto(c: Context, card: BusinessCard): ByteArray {
    val w = 1600
    val bmp = Bitmap.createBitmap(w, Math.round(w / BusinessCard.ASPECT), Bitmap.Config.ARGB_8888)
    drawFace(c, Canvas(bmp), w.toFloat(), card.lines, 0f)
    val out = ByteArrayOutputStream()
    bmp.compress(Bitmap.CompressFormat.JPEG, 90, out)
    return out.toByteArray()
}

/**
 * WHAT A CARD SAYS, SAVED TO THE CONTACTS (iOS MontanaCardContact): the platform's own new-contact page, filled from the card's
 * lines — the name, every phone, e-mail and link in its own field — and saved by the person's own tap; the app writes nothing.
 */
fun cardToContacts(act: MainActivity, lines: List<String>) {
    val rows = ArrayList<ContentValues>()
    for (line in lines.drop(1)) when (kindOf(line)) {
        LineKind.PHONE -> rows.add(ContentValues().apply { put(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
            put(ContactsContract.CommonDataKinds.Phone.NUMBER, line); put(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE) })
        LineKind.EMAIL -> rows.add(ContentValues().apply { put(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE)
            put(ContactsContract.CommonDataKinds.Email.ADDRESS, line) })
        LineKind.LINK -> rows.add(ContentValues().apply { put(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Website.CONTENT_ITEM_TYPE)
            put(ContactsContract.CommonDataKinds.Website.URL, line) })
        LineKind.WORDS -> {}
    }
    val i = Intent(ContactsContract.Intents.Insert.ACTION).setType(ContactsContract.RawContacts.CONTENT_TYPE)
        .putExtra(ContactsContract.Intents.Insert.NAME, lines.firstOrNull() ?: "")
        .putParcelableArrayListExtra(ContactsContract.Intents.Insert.DATA, rows)
    runCatching { act.startActivity(i) }
}

/** The card's contact as a file (iOS CNContactVCardSerialization): vCard 3.0 of the name and the ways. */
private fun vcard(lines: List<String>): String {
    fun esc(s: String) = s.replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;")
    val b = StringBuilder("BEGIN:VCARD\r\nVERSION:3.0\r\n")
    val name = lines.firstOrNull() ?: ""
    b.append("FN:").append(esc(name)).append("\r\nN:").append(esc(name)).append(";;;;\r\n")
    for (line in lines.drop(1)) when (kindOf(line)) {
        LineKind.PHONE -> b.append("TEL;TYPE=CELL:").append(esc(line)).append("\r\n")
        LineKind.EMAIL -> b.append("EMAIL:").append(esc(line)).append("\r\n")
        LineKind.LINK -> b.append("URL:").append(esc(line)).append("\r\n")
        LineKind.WORDS -> {}
    }
    return b.append("END:VCARD\r\n").toString()
}

/**
 * THE CARD'S PAGE (iOS MontanaCardNoteView, the author's word 28.09): the card's face at the top, drawn live as it will leave, and
 * under it the platform's own fields — the name (the person's own until they write another), the phone, the e-mail and the
 * other ways — and the note of what the card is. Kept after a typing pause and when the page goes. In a chat the mark top right
 * sends the card as a photo (`onSend`); from the side panel it shares the photo and the card's contact.
 */
fun businessCardPage(act: MainActivity, onClose: () -> Unit, onSend: ((BusinessCard) -> Unit)? = null): View {
    val c: Context = act
    val card = BusinessCard.kept()
    val face = CardFaceView(c, card.lines)
    var changed = false
    val keepSoon = Runnable { if (changed) { changed = false; card.keep() } }
    lateinit var mark: View
    fun field(hint: Int, value: String, type: Int, lines: Int = 1, set: (String) -> Unit) = EditText(c).apply {
        setText(value)   // USER-DATA: the card's own words
        this.hint = c.getString(hint)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = null
        inputType = type
        if (lines > 1) { maxLines = lines; isSingleLine = false } else isSingleLine = true
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: Editable?) {
                set(s?.toString() ?: "")
                face.lines = card.lines; face.invalidate()
                mark.alpha = if (card.isEmpty) 0.4f else 1f
                changed = true
                face.removeCallbacks(keepSoon); face.postDelayed(keepSoon, 700)
            }
        })
    }
    fun share() {
        if (card.isEmpty) return
        card.keep()
        val dir = Media.dir(c)   // the app's one door to its files answers from the media folder alone (MediaProvider)
        val photo = File(dir, "business-card.jpg").apply { writeBytes(cardPhoto(c, card)) }
        val base = (card.lines.firstOrNull() ?: "").replace("/", " ").replace(":", " ").trim().ifEmpty { "card" }
        val vcf = File(dir, base + ".vcf").apply { writeText(vcard(card.lines)) }
        val send = Intent(Intent.ACTION_SEND_MULTIPLE).setType("*/*")
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(Media.uri(c, photo), Media.uri(c, vcf)))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        runCatching { act.startActivity(Intent.createChooser(send, null)) }
    }
    mark = c.icon(if (onSend != null) R.drawable.ic_paperplane else R.drawable.ic_share, if (onSend != null) SysColor.blue else Color.WHITE).apply {
        setPadding(dp(10), dp(10), dp(10), dp(10))
        contentDescription = c.getString(if (onSend != null) R.string.send else R.string.share)
        alpha = if (card.isEmpty) 0.4f else 1f
        pressable { if (!card.isEmpty) { if (onSend != null) { card.keep(); onSend(card) } else share() } }
    }
    val bar = FrameLayout(c).apply {
        setPadding(dp(8), 0, dp(8), 0)
        addView(c.icon(if (onSend != null) R.drawable.ic_close else R.drawable.ic_arrow_back_ios_new, Color.WHITE).apply {
            setPadding(dp(10), dp(10), dp(10), dp(10)); pressable { if (changed) { changed = false; card.keep() }; onClose() }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(c.text(c.getString(R.string.app_card), 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        addView(mark, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
    }
    val body = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(dp(16), dp(8), dp(16), dp(32))
        addView(FrameLayout(c).apply { addView(face, FrameLayout.LayoutParams(dp(300), WRAP, Gravity.CENTER_HORIZONTAL)) }, lp())
        gap(16)
        addView(c.plate { addView(field(R.string.bc_name, card.name, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PERSON_NAME or InputType.TYPE_TEXT_FLAG_CAP_WORDS) { card.name = it }, lp()) }, lp())
        gap(16)
        addView(c.plate {
            addView(field(R.string.bc_phone, card.phone, InputType.TYPE_CLASS_PHONE) { card.phone = it }, lp())
            addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(16) })
            addView(field(R.string.bc_email, card.email, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS) { card.email = it }, lp())
            addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(16) })
            addView(field(R.string.bc_other, card.other, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE, lines = 4) { card.other = it }, lp())
        }, lp())
        addView(c.text(c.getString(R.string.bc_note), 12f, MT.gray).apply { setPadding(dp(16), dp(8), dp(16), 0) }, lp())
    }
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, dp(52)))
            addView(ScrollView(c).apply { addView(body) }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {}
            override fun onViewDetachedFromWindow(v: View) { if (changed) { changed = false; card.keep() } }
        })
    }
}
