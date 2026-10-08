package quest.montana.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * THE ONE SHARE OF ONE'S CARD (iOS MontanaCardShare): the code page's «Share» and the contacts page's round button hand out
 * the same message — the words, then the link on its own line — through the system's own share sheet, nothing between the
 * tap and it. The kind is the one the code page chose (permanent by default).
 */
fun shareCard(act: MainActivity) {
    val permanent = Prefs.str("cardKind", "perm") == "perm"
    act.background {
        val link = if (permanent) MontanaCard.offerPermanent(act) else MontanaCard.offerShort(act)
        act.onMain {
            if (link == null) { android.widget.Toast.makeText(act, R.string.card_failed, android.widget.Toast.LENGTH_LONG).show(); return@onMain }
            val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, MontanaCard.inviteMessage(act, permanent) + "\n" + link)
            act.startActivity(Intent.createChooser(send, null))
        }
    }
}

/**
 * THE CODE (iOS MontanaCodeView): my face, what the code does, the code itself with the mark at its centre, the two kinds as
 * tabs, the word on the link's term, the link — byte for byte what the code carries, selectable — «Copy link» and «Share».
 * The card is drawn only when this view stands: a card on the screen unasked is a key handed to whoever walks past.
 * `onExpand`: standing in the empty chat list, a tap on the code opens the whole page.
 */
class CardView(private val act: MainActivity, private val onExpand: (() -> Unit)? = null) {
    val view: LinearLayout
    private val qr = QrView(act)
    private val note = act.text("", 12f, MT.gray, center = true)
    private val link = act.text("", 16f, Color.WHITE, bold = true, center = true)
    // iOS CopyLinkButton: the caption's bold in the accent's white, green while «Link copied» stands (2 s)
    private val copy = act.text(act.getString(R.string.copy_link), 12f, Color.WHITE, bold = true)
    private var current: String? = null
    private val permanent get() = Prefs.str("cardKind", "perm") == "perm"

    init {
        val c: Context = act
        val face = c.avatar(SelfFace.load(c), Prefs.userName, 84)
        val box = FrameLayout(c).apply {
            background = c.rounded(Color.WHITE, 22)
            setPadding(dp(16), dp(16), dp(16), dp(16))
            addView(qr, FrameLayout.LayoutParams(dp(258), dp(258)))
            // THE MARK AT THE CENTRE (iOS SymbolOfTime on a white rounded plate) — the code is built with correction M under it.
            addView(FrameLayout(c).apply {
                background = c.rounded(Color.WHITE, 9)
                addView(ImageView(c).apply {
                    setImageResource(R.drawable.symbol_of_time); scaleType = ImageView.ScaleType.CENTER_CROP
                    outlineProvider = object : ViewOutlineProvider() { override fun getOutline(v: View, o: Outline) = o.setRoundRect(0, 0, v.width, v.height, v.dp(7).toFloat()) }
                    clipToOutline = true
                }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER))
            }, FrameLayout.LayoutParams(dp(54), dp(54), Gravity.CENTER))
            if (onExpand != null) pressable(onExpand)
        }
        link.typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        link.paintFlags = link.paintFlags or android.graphics.Paint.UNDERLINE_TEXT_FLAG
        link.setTextIsSelectable(true)
        copy.setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_link, 0, 0, 0)
        copy.compoundDrawableTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
        copy.compoundDrawablePadding = c.dp(8)
        copy.setPadding(c.dp(12), c.dp(10), c.dp(12), c.dp(10))
        copy.pressable {
            val l = current ?: return@pressable
            (c.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Montana", l))
            fun look(word: Int, glyph: Int, tint: Int) {
                copy.text = c.getString(word)
                copy.setTextColor(tint)
                copy.setCompoundDrawablesRelativeWithIntrinsicBounds(glyph, 0, 0, 0)
                copy.compoundDrawableTintList = android.content.res.ColorStateList.valueOf(tint)
            }
            look(R.string.link_copied, R.drawable.ic_check, MT.green)
            copy.postDelayed({ look(R.string.copy_link, R.drawable.ic_link, Color.WHITE) }, 2000)
        }
        val share = c.hstack {
            gravity = Gravity.CENTER
            // iOS: «Share» on the accent, which is white since the gold left iOS; the words black
            background = c.rounded(Color.WHITE, 11)
            setPadding(0, dp(10), 0, dp(10))
            addView(c.icon(R.drawable.ic_share, Color.BLACK), lp(dp(20), dp(20)))
            gap(8)
            addView(c.text(c.getString(R.string.share), 15f, Color.BLACK, bold = true))
            pressable { shareCard(act) }
        }
        view = c.vstack {
            setPadding(0, dp(20), 0, dp(20))
            addView(face, lp(dp(84), dp(84)))
            gap(14)
            addView(c.text(c.getString(R.string.code_caption), 12f, MT.gray, center = true).apply { setPadding(dp(24), 0, dp(24), 0) }, lp())
            gap(14)
            addView(box, lp(WRAP, WRAP))
            gap(14)
            // The two kinds as tabs under the code (iOS: the voice look's own picker).
            addView(kinds(c), lp().apply { setMargins(dp(36), 0, dp(36), 0) })
            gap(14)
            addView(note.apply { setPadding(dp(24), 0, dp(24), 0) }, lp())
            gap(10)
            addView(link.apply { setPadding(dp(20), 0, dp(20), 0) }, lp())
            gap(6)
            addView(copy, lp(WRAP, WRAP))
            gap(8)
            addView(share, lp().apply { setMargins(dp(36), 0, dp(36), 0) })
            gap(10)
            // «SCAN» (iOS MontanaCodeView onScan): the other side's code read by the camera opens the meeting.
            addView(c.hstack {
                gravity = Gravity.CENTER
                background = c.rounded(MT.plate, 11)   // iOS Color(white: 0.12)
                setPadding(0, dp(10), 0, dp(10))
                addView(c.icon(R.drawable.ic_qr_scan, Color.WHITE), lp(dp(20), dp(20)))
                gap(8)
                addView(c.text(c.getString(R.string.scan), 15f, Color.WHITE, bold = true))
                pressable { act.push { close -> scannerPage(act, close) } }
            }, lp().apply { setMargins(dp(36), 0, dp(36), 0) })
        }
        draw()
    }

    private fun kinds(c: Context): View {
        val row = c.hstack { background = c.rounded(Color.argb(40, 118, 118, 128), 9); setPadding(c.dp(2), c.dp(2), c.dp(2), c.dp(2)) }
        fun fill() {
            row.removeAllViews()
            listOf(R.string.card_perm to "perm", R.string.card_temp to "temp").forEach { (word, value) ->
                val on = Prefs.str("cardKind", "perm") == value
                row.addView(c.text(c.getString(word), 15f, Color.WHITE, bold = on, center = true).apply {
                    setPadding(0, c.dp(8), 0, c.dp(8))
                    if (on) background = c.rounded(Color.rgb(99, 99, 102), 7)
                    pressable { if (!on) { Prefs.setStr("cardKind", value); fill(); draw() } }
                }, lp(0, WRAP, 1f))
            }
        }
        fill()
        return row
    }

    /** The card of the chosen kind, drawn off the main thread (the core draws its key and the vault seals it). */
    fun draw() {
        val perm = permanent
        act.background {
            val l = if (perm) MontanaCard.offerPermanent(act) else MontanaCard.offerShort(act)
            val code = l?.let { QrCode.encode(it, QrCode.Ecc.M) }
            act.onMain {
                current = l
                qr.code = code
                link.text = l ?: act.getString(R.string.card_failed)   // USER-DATA: the link itself
                note.text = if (perm) act.getString(R.string.card_perm_note)
                            else MontanaCard.renewsAt()?.let { act.getString(R.string.card_renews,
                                java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT).format(java.util.Date(it))) } ?: ""
            }
        }
    }
}

/**
 * THE PAGE CLOSES WHEN THE ONE WHO SCANNED IT WRITES (iOS MontanaCodeView onMet 4287-4289, MontanaQRFullView 4606, the author's
 * word 23.09): a first letter came through this phone's card — the code has done its work, and the page that holds it closes.
 */
object CodeMet {
    @Volatile var close: (() -> Unit)? = null
    fun met() { val c = close ?: return; MainThread.post { c() } }
}

/** THE CODE'S OWN PAGE (iOS MontanaQRFullView 4596-4617): the checkmark top right, the one scroll, the column at its centre, on my page's ground. */
fun cardPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))   // my page's ground, as every page wears it (iOS 4615)
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { CodeMet.close = onClose }
            override fun onViewDetachedFromWindow(v: View) { if (CodeMet.close === onClose) CodeMet.close = null }
        })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(FrameLayout(c).apply {
                addView(c.icon(R.drawable.ic_check, Color.WHITE).apply { setPadding(dp(10), dp(10), dp(10), dp(10)); pressable(onClose) },
                    FrameLayout.LayoutParams(dp(48), dp(48), Gravity.CENTER_VERTICAL or Gravity.END).apply { marginEnd = dp(8) })
            }, lp(MATCH, dp(52)))
            addView(ScrollView(c).apply { isFillViewport = true; addView(CardView(act).view) }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}
