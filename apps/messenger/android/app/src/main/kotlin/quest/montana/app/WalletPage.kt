package quest.montana.app

import android.animation.ValueAnimator
import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.graphics.drawable.GradientDrawable
import android.text.InputFilter
import android.text.InputType
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewOutlineProvider
import android.view.animation.LinearInterpolator
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import java.util.Date

// ─────────────────────────── the wallet's pages (iOS MTWalletScreen: MTWalletPage, MTCoinSendSheet, MTPiLevelsSheet, MTCoinHistoryPage) ───────────────────────────

/**
 * OUR COIN, the one drawing of it (iOS MTMintCoin): the author's two faces, byte for byte (CoinFace, CoinBack), in a circle. It
 * stands on its face at rest, makes one whole turn when asked, and spins at a speed while a game mints; the back is mirrored
 * behind, as iOS draws it.
 */
class MintCoin(c: Context, private val sideDp: Int) : ImageView(c) {
    private var spin: ValueAnimator? = null
    private var turnsPerSecond = 0f
    init {
        setImageResource(R.drawable.coin_face)
        scaleType = ScaleType.CENTER_CROP
        outlineProvider = object : ViewOutlineProvider() { override fun getOutline(v: View, o: Outline) { o.setOval(0, 0, v.width, v.height) } }
        clipToOutline = true
        cameraDistance = 8000f * resources.displayMetrics.density
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private fun face(angle: Float) {
        val t = ((angle % 360f) + 360f) % 360f
        val front = t < 90f || 270f < t
        setImageResource(if (front) R.drawable.coin_face else R.drawable.coin_back)
        scaleX = if (front) 1f else -1f
        rotationY = t
    }
    /** One whole turn from wherever the coin stands (iOS turnOnce). */
    fun turnOnce() {
        if (spin != null) return
        ValueAnimator.ofFloat(0f, 360f).apply {
            duration = 1100
            addUpdateListener { face(it.animatedValue as Float) }
            start()
        }
    }
    /** Turns at `perSecond` turns per 1.4 s (iOS MTCoinDial); zero rests the coin on its face. */
    fun spinAt(perSecond: Int) {
        if (perSecond.toFloat() == turnsPerSecond) return
        turnsPerSecond = perSecond.toFloat()
        spin?.cancel(); spin = null
        if (perSecond <= 0) { face(0f); return }
        val from = rotationY
        spin = ValueAnimator.ofFloat(from, from + 360f).apply {
            duration = (1400 / perSecond).toLong()
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { face(it.animatedValue as Float) }
            start()
        }
    }
    override fun onDetachedFromWindow() { spin?.cancel(); spin = null; turnsPerSecond = 0f; super.onDetachedFromWindow() }
}

/** THE COINS THAT MOVED, SIGNED (iOS MTCoinDelta): the minus on red, the plus on green, white on its capsule. */
fun Context.coinDelta(coins: Long): View = text((if (coins < 0) "−" else "+") + CoinText.count(coins).removePrefix("-"), 20f, Color.WHITE, bold = true).apply {
    background = rounded(if (coins < 0) MT.red else MT.green, 14)
    setPadding(dp(10), dp(3), dp(10), dp(3))
    maxLines = 1
}

/** THE COIN LETTER'S BUBBLE (iOS the coin letter in MontanaBubble): our coin on its face, the number, and which way it went. */
fun Context.coinPlate(m: Msg, coin: CoinLetter.Coin, mine: Boolean): View = hstack {
    gravity = Gravity.CENTER_VERTICAL
    addView(MintCoin(context, 44), lp(dp(44), dp(44)))
    gap(12)
    val back = CoinSend.returned(m)
    addView(vstack(Gravity.NO_GRAVITY) {
        // USER-DATA: the number of coins the letter carries
        if (back) addView(text(CoinText.count(coin.c), 20f, BubbleStyle.text(mine), bold = true), lp(WRAP, WRAP))
        else addView(coinDelta(if (mine) -coin.c else coin.c), lp(WRAP, WRAP))
        val words = if (mine) (if (back) R.string.coin_letter_back else R.string.coin_letter_sent) else R.string.coin_letter_received
        addView(text(getString(words), 15f, BubbleStyle.text(mine)).apply { setPadding(0, dp(2), 0, 0) }, lp(WRAP, WRAP))
    }, lp(WRAP, WRAP))
}

/** A row of the list with its value at the trailing edge (iOS LabeledContent). */
private fun Context.labeled(title: String, value: String): View = hstack {
    setPadding(dp(16), dp(12), dp(16), dp(12))
    minimumHeight = dp(48)
    addView(text(title, 16f), lp(0, WRAP, 1f))
    addView(text(value, 16f, MT.gray), lp(WRAP, WRAP))   // USER-DATA: a number of coins
}

/** A page of the wallet: the bar with the cross or the back chevron, a mark at the trailing edge when it has one, the list that scrolls. */
private fun walletFrame(act: MainActivity, title: String, onLead: () -> Unit, cross: Boolean, trailing: View?, body: LinearLayout): View {
    val c: Context = act
    val bar = FrameLayout(c).apply {
        setPadding(dp(8), 0, dp(8), 0)
        addView(c.icon(if (cross) R.drawable.ic_close else R.drawable.ic_arrow_back_ios_new, Color.WHITE).apply {
            setPadding(dp(10), dp(10), dp(10), dp(10)); contentDescription = c.getString(R.string.coin_close); pressable(onLead)
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(c.text(title, 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        if (trailing != null) addView(trailing, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
    }
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, dp(52)))
            addView(ScrollView(c).apply { addView(body.apply { setPadding(dp(16), 0, dp(16), dp(32)) }) }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

/**
 * THE WALLET (iOS MTWalletPage, «TimeCoin»): our coin where the card stood — Pantheon on Fire under the finger, every touch of the
 * coin its own, a +N rising from each touch that minted —, the book's balance in large type with the ticker, the same balance in
 * Montana, the level of π and π revealed to it, Send and the levels of π; under them the minting's counts and the history.
 */
fun walletPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    val fire = c.text(c.getString(R.string.coin_pantheon), 22f, MT.orange, bold = true, center = true)
    val coin = MintCoin(c, 120)
    val pops = FrameLayout(c)
    val badge = c.text("", 13f, Color.WHITE, bold = true, center = true).apply {
        background = c.rounded(MT.blue, 11); setPadding(dp(7), dp(1), dp(7), dp(1)); minWidth = dp(22)
    }
    val speed = c.text("", 15f, MT.gray, center = true)
    val bar = ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal).apply {
        max = 1000; progressTintList = android.content.res.ColorStateList.valueOf(MT.blue)
    }
    val toLevel = c.text("", 13f, MT.gray, center = true)
    val balance = c.text("", 44f, Color.WHITE, bold = true, center = true).apply { maxLines = 1; setAutoSizeTextTypeUniformWithConfiguration(20, 44, 1, android.util.TypedValue.COMPLEX_UNIT_SP) }
    val inMontana = c.text("", 15f, MT.gray, center = true)
    val pi = c.text("", 13f, MT.gray, center = true)
    val rows = c.vstack(Gravity.NO_GRAVITY)

    fun capsule(word: Int, glyph: Int?, filled: Boolean, onTap: () -> Unit) = c.hstack {
        gravity = Gravity.CENTER
        minimumHeight = dp(44)
        background = if (filled) c.rounded(MT.blue, 22) else c.rounded(Color.TRANSPARENT, 22, MT.blue)
        if (glyph != null) { addView(c.icon(glyph, if (filled) Color.WHITE else MT.blue, 20), lp(dp(20), dp(20))); gap(8) }
        addView(c.text(c.getString(word), 17f, if (filled) Color.WHITE else MT.blue, bold = true))
        pressable(onTap)
    }
    val send = capsule(R.string.coin_send, R.drawable.ic_paperplane, true) { act.push { sendCoinsPage(act, it) } }

    fun draw() {
        val b = CoinBook.balance
        val place = PiLevels.place(b)
        val lit = Pantheon.lit
        fire.visibility = if (lit) View.VISIBLE else View.INVISIBLE
        speed.visibility = fire.visibility
        speed.text = Pantheon.speed.toString() + " / " + Pantheon.CEILING   // USER-DATA: the taps of the last second
        coin.spinAt(Pantheon.speed)
        badge.text = maxOf(1, place).toString()   // the level the minting multiplies by
        val shownBar = lit && place < PiLevels.all.size
        bar.visibility = if (shownBar) View.VISIBLE else View.INVISIBLE
        toLevel.visibility = bar.visibility
        if (place < PiLevels.all.size) {
            val low = if (0 < place) PiLevels.all[place - 1] else 0L
            val high = PiLevels.all[place]
            bar.progress = (((b - low).toDouble() / maxOf(1L, high - low)) * 1000).toInt()
            toLevel.text = c.getString(R.string.coin_to_level, CoinText.count(high - b), place + 1)
        }
        balance.text = CoinText.count(b) + " " + CoinBook.TICKER   // USER-DATA: the balance and the ticker
        inMontana.text = CoinText.montana(b) + " Ɱ"   // USER-DATA: the balance in Montana
        pi.text = "π " + PiLevels.revealed(place) + " · " + place   // USER-DATA: the level of π and π revealed to it
        send.isEnabled = 0 < b; send.alpha = if (0 < b) 1f else 0.4f
        rows.removeAllViews()
        rows.section(c.getString(R.string.coin_minting), c.getString(R.string.coin_counted_here),
            c.labeled(c.getString(R.string.coin_from_pantheon), CoinText.count(CoinBook.tapped)),
            c.labeled(c.getString(R.string.coin_received_n), CoinText.count(CoinBook.received)),
            c.labeled(c.getString(R.string.coin_sent_n), CoinText.count(CoinBook.sent)),
            c.labeled(c.getString(R.string.coin_in_montana), CoinText.montana(b)))
        rows.section(null, null, c.settingsRow(null, 0, c.getString(R.string.coin_history)) { act.push { coinHistoryPage(act, it) } })
    }

    // THE COIN TAKES EVERY FINGER (iOS MTCoinTapPad): each finger that lands mints, its +N rising where it touched; the page holds
    // still under the game (the scroll is not given the finger while it is on the coin)
    fun pop(x: Float, y: Float, coins: Long) {
        val t = c.text("+" + CoinText.count(coins), 17f, Color.WHITE, bold = true).apply {   // USER-DATA: the coins one touch minted
            background = c.rounded(Color.argb(170, 40, 40, 44), 14); setPadding(dp(8), dp(2), dp(8), dp(2))
        }
        pops.addView(t, FrameLayout.LayoutParams(WRAP, WRAP))
        t.x = x - c.dp(20); t.y = y - c.dp(14)
        t.animate().translationYBy(-c.dp(48).toFloat()).alpha(0f).setDuration(900).withEndAction { pops.removeView(t) }.start()
        while (5 < pops.childCount) pops.removeViewAt(0)
    }
    val pad = FrameLayout(c).apply {
        contentDescription = c.getString(R.string.coin_a11y)
        isClickable = true
        setOnTouchListener { v, e ->
            val i = e.actionIndex
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                    v.parent?.requestDisallowInterceptTouchEvent(true)
                    Pantheon.touched()
                    val coins = Pantheon.tap()
                    v.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    if (0 < coins) pop(e.getX(i), e.getY(i), coins)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> Pantheon.released()
            }
            true
        }
        setOnClickListener { Pantheon.tap() }   // the accessibility service's own tap
    }
    val head = c.vstack {
        setPadding(0, dp(12), 0, dp(20))
        addView(fire, lp(WRAP, WRAP))
        gap(10)
        addView(FrameLayout(c).apply {
            addView(coin, FrameLayout.LayoutParams(dp(120), dp(120), Gravity.CENTER))
            addView(badge, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.END).apply { setMargins(0, dp(10), dp(10), 0) })
            addView(pad, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(pops, FrameLayout.LayoutParams(MATCH, MATCH))
        }, lp(dp(144), dp(144)))
        gap(10)
        addView(speed, lp(WRAP, WRAP))
        gap(6)
        addView(bar, lp(dp(240), WRAP))
        addView(toLevel, lp(WRAP, WRAP))
        gap(10)
        addView(balance, lp(MATCH, WRAP))
        addView(inMontana, lp(WRAP, WRAP))
        gap(4)
        addView(pi, lp(WRAP, WRAP))
        gap(16)
        addView(c.hstack {
            addView(send, lp(0, WRAP, 1f))
            gap(12)
            addView(capsule(R.string.coin_levels, null, false) { act.push { piLevelsPage(act, it) } }, lp(0, WRAP, 1f))
        }, lp(MATCH, WRAP))
    }
    pops.isClickable = false
    body.addView(head, lp())
    body.addView(rows, lp())
    val page = walletFrame(act, c.getString(R.string.coin_title), onClose, true, null, body)
    val again: () -> Unit = { draw() }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { CoinBook.listen(again); Pantheon.listen(again); draw(); coin.turnOnce() }
        override fun onViewDetachedFromWindow(v: View) { CoinBook.unlisten(again); Pantheon.unlisten(again); Pantheon.released(); CoinBook.closeWindows() }
    })
    Thread { CoinBook.warm(); MainThread.post { draw() } }.start()
    return page
}

/**
 * SEND COINS (iOS MTCoinSendSheet): the levels of π as the amounts, a box chosen stands beside every chat picked; each chat its own
 * field, the system's, the coins typed there are what that chat gets; our send at the trailing edge. A short balance refuses
 * and nothing leaves; one recipient's chat opens after the send.
 */
fun sendCoinsPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    val picked = LinkedHashMap<String, EditText>()
    val fields = LinkedHashMap<String, EditText>()
    val marks = HashMap<String, ImageView>()
    var chosen = 1L
    val total = c.labeled(c.getString(R.string.coin_total), "0")
    fun coinsOf(f: EditText) = f.text.toString().toLongOrNull() ?: 0L
    fun drawTotal() {
        var sum = 0L
        for (f in picked.values) sum += coinsOf(f)
        ((total as LinearLayout).getChildAt(1) as TextView).text = CoinText.count(sum)
        total.visibility = if (picked.isEmpty()) View.GONE else View.VISIBLE
    }
    fun mark(ref: String) {
        val on = ref in picked
        marks[ref]?.apply {
            setImageResource(if (on) R.drawable.ic_set_check_circle else 0)
            background = if (on) null else GradientDrawable().apply { shape = GradientDrawable.OVAL; setStroke(c.dp(1.5f), MT.gray) }
            setColorFilter(MT.blue)
        }
    }
    fun toggle(ref: String) {
        val f = fields[ref] ?: return
        if (ref in picked) { picked.remove(ref); f.setText("") }
        else { picked[ref] = f; if (coinsOf(f) == 0L) f.setText(chosen.toString()); f.requestFocus() }
        mark(ref); drawTotal()
    }
    // the levels of π as the amounts (iOS: the thirteen boxes when sending)
    val boxes = c.hstack {
        for (n in PiLevels.all) {
            addView(c.text(PiLevels.short(c, n), 15f, Color.WHITE, bold = true).apply {   // USER-DATA: a level's coins, short
                background = c.rounded(Color.rgb(77, 77, 77), 16); setPadding(dp(12), dp(6), dp(12), dp(6))
                val can = n <= CoinBook.balance
                alpha = if (can) 1f else 0.4f
                if (can) pressable { chosen = n; for (f in picked.values) f.setText(n.toString()); drawTotal() }
            }, lp(WRAP, WRAP).apply { marginEnd = dp(6) })
        }
    }
    body.addView(HorizontalScrollView(c).apply { isHorizontalScrollBarEnabled = false; addView(boxes); setPadding(0, dp(12), 0, dp(6)) }, lp())
    body.addView(total, lp())
    val people = Book.all().filter { CoinSend.canPay(it.ref) }
    val list = c.plate {
        if (people.isEmpty()) addView(c.text(c.getString(R.string.coin_no_chats), 16f, MT.gray).apply { setPadding(dp(16), dp(14), dp(16), dp(14)) }, lp())
        people.forEachIndexed { i, ch ->
            if (0 < i) divider()
            val field = EditText(c).apply {
                inputType = InputType.TYPE_CLASS_NUMBER
                filters = arrayOf(InputFilter.LengthFilter(15))
                hint = "0"
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                setTextColor(Color.WHITE); setHintTextColor(MT.gray)
                background = c.rounded(Color.rgb(44, 44, 46), 8)
                setPadding(dp(8), 0, dp(8), 0)
                addTextChangedListener(object : android.text.TextWatcher {
                    override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                    override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                    override fun afterTextChanged(s: android.text.Editable?) {
                        // coins typed pick the chat, a field emptied lets it go
                        val n = s?.toString()?.toLongOrNull() ?: 0L
                        if (0L < n) picked[ch.ref] = this@apply else picked.remove(ch.ref)
                        mark(ch.ref); drawTotal()
                    }
                })
            }
            fields[ch.ref] = field
            val pick = ImageView(c).apply { setPadding(dp(10), dp(10), dp(10), dp(10)) }
            marks[ch.ref] = pick
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(8), dp(8), dp(8))
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    addView(c.peerFace(ch.ref, ch.shown, 40), lp(dp(40), dp(40)))
                    gap(12)
                    addView(c.text(ch.shown.ifBlank { c.getString(R.string.peer) }, 16f).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
                    minimumHeight = dp(44)
                    pressable { toggle(ch.ref) }
                }, lp(0, WRAP, 1f))
                addView(field, lp(dp(96), dp(44)))
                addView(pick, lp(dp(44), dp(44)).apply { marginStart = dp(4) })
                pick.pressable { toggle(ch.ref) }
            }, lp())
            mark(ch.ref)
        }
    }
    body.addView(c.text(c.getString(R.string.coin_choose_chats), 13f, MT.gray).apply { setPadding(dp(16), dp(22), dp(16), dp(6)) }, lp())
    body.addView(list, lp())
    drawTotal()
    lateinit var close: () -> Unit
    val go = c.icon(R.drawable.ic_paperplane, MT.blue).apply {
        setPadding(dp(10), dp(10), dp(10), dp(10)); contentDescription = c.getString(R.string.coin_send)
        pressable {
            val to = picked.filter { 0L < coinsOf(it.value) }
            var sum = 0L
            for (f in to.values) sum += coinsOf(f)
            if (to.isEmpty() || CoinBook.balance < sum) {
                AlertDialog.Builder(act).setTitle(R.string.coin_not_enough).setMessage(R.string.coin_not_enough_sub).setPositiveButton(R.string.ok, null).show()
                return@pressable
            }
            val went = to.keys.filter { ref -> CoinSend.transfer(ref, coinsOf(to.getValue(ref))) }
            if (went.isEmpty()) {
                AlertDialog.Builder(act).setTitle(R.string.coin_not_enough).setMessage(R.string.coin_not_enough_sub).setPositiveButton(R.string.ok, null).show()
                return@pressable
            }
            close()
            // one recipient's chat opens at once (iOS MontanaOutsideOpen.chat); many close the page
            if (went.size == 1) act.push { back -> conversationPage(act, went[0], back) }
        }
    }
    close = onClose
    return walletFrame(act, c.getString(R.string.coin_send_title), onClose, true, go, body)
}

/** THE LEVELS OF π (iOS MTPiLevelsSheet): the next level to reach on top, then the levels reached, thirteen at a time, each with π revealed. */
fun piLevelsPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    val place = PiLevels.place(CoinBook.balance)
    val top = minOf(PiLevels.all.size, place + 1)
    val levels = (maxOf(1, top - PiLevels.SHOWN + 1)..top).reversed()
    body.addView(c.plate {
        levels.forEachIndexed { i, n ->
            if (0 < i) divider()
            val coins = PiLevels.all[n - 1]
            val reached = n <= place
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(10), dp(16), dp(10))
                minimumHeight = dp(52)
                if (n == place) setBackgroundColor(Color.argb(56, Color.red(MT.blue), Color.green(MT.blue), Color.blue(MT.blue)))
                addView(c.text(n.toString(), 17f, Color.WHITE, bold = true), lp(dp(28), WRAP))   // USER-DATA: the level's number
                gap(12)
                addView(c.vstack(Gravity.NO_GRAVITY) {
                    addView(c.text("π " + PiLevels.revealed(n), 17f, Color.WHITE, bold = true))   // USER-DATA: π revealed to this level
                    addView(c.text(PiLevels.short(c, coins) + " · " + CoinText.montana(coins) + " Ɱ", 12f, MT.gray))   // USER-DATA
                }, lp(0, WRAP, 1f))
                if (reached) addView(c.icon(R.drawable.ic_set_check_circle, MT.blue, 22), lp(dp(22), dp(22)))
                alpha = if (reached) 1f else 0.55f
            }, lp())
        }
    }, lp().apply { topMargin = c.dp(12) })
    return walletFrame(act, c.getString(R.string.coin_levels), onClose, true, null, body)
}

/** THE HISTORY (iOS MTCoinHistoryPage): every move of the book, the newest first — from where to where, the signed coins and the moment. */
fun coinHistoryPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    val me = c.getString(R.string.coin_you)
    fun who(ref: String?): String = ref?.let { Book.chat(it)?.shown?.ifBlank { null } } ?: c.getString(R.string.peer)
    val moves = CoinBook.moves().take(500)
    body.addView(c.plate {
        if (moves.isEmpty()) addView(c.text(c.getString(R.string.coin_no_moves), 16f, MT.gray).apply { setPadding(dp(16), dp(14), dp(16), dp(14)) }, lp())
        moves.forEachIndexed { i, e ->
            if (0 < i) divider()
            val route = when (e.k) {
                CoinEntry.EARN -> (if (e.ref.startsWith(Pantheon.PREFIX)) c.getString(R.string.coin_pantheon) else c.getString(R.string.coin_kind_earn)) + " → " + me
                CoinEntry.RECEIVE -> who(e.peer) + " → " + me
                CoinEntry.BURN -> me + " → " + c.getString(R.string.coin_burned)
                else -> me + " → " + who(e.peer)
            }
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.vstack(Gravity.NO_GRAVITY) {
                    addView(c.text(route, 15f).apply { singleLineEllipsis() })   // USER-DATA: who the coins went between
                    addView(c.text(android.text.format.DateFormat.getMediumDateFormat(c).format(Date((e.at * 1000).toLong())) + " " +
                        android.text.format.DateFormat.getTimeFormat(c).format(Date((e.at * 1000).toLong())), 12f, MT.gray))
                }, lp(0, WRAP, 1f))
                addView(c.coinDelta(e.signed), lp(WRAP, WRAP))
            }, lp())
        }
    }, lp().apply { topMargin = c.dp(12) })
    return walletFrame(act, c.getString(R.string.coin_history), onBack, false, null, body)
}
