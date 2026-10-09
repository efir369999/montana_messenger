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

/**
 * THE COIN LETTER'S BUBBLE (iOS the coin letter in MontanaBubble): our coin on its face, the number, and which way it went; a tap
 * opens the move it made in this phone's book (iOS onTapCoin, MontanaConversation 2733, MTCoinMovePage).
 */
fun Context.coinPlate(m: Msg, coin: CoinLetter.Coin, mine: Boolean, act: MainActivity? = null, ref: String? = null): View = hstack {
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
    if (act != null && ref != null) pressable {
        val peer = Book.chat(ref)?.shown?.ifBlank { null } ?: context.getString(R.string.peer)
        act.push { back -> coinMovePage(act, CoinSend.wire(m.mid), mine, peer, back) }
    }
}

/** A row of the list with its value at the trailing edge (iOS LabeledContent). */
private fun Context.labeled(title: String, value: String): View = hstack {
    setPadding(dp(16), dp(12), dp(16), dp(12))
    minimumHeight = dp(48)
    addView(text(title, 16f), lp(0, WRAP, 1f))
    addView(text(value, 16f, MT.gray), lp(WRAP, WRAP))   // USER-DATA: a number of coins
}

/** One window of the wall's comments, as iOS lays it (MTWalletScreen.swift:296-309): its minutes large, its span, every comment's
 * moment, its post, whether it is open and its right to a share. */
private fun Context.wallWindowRow(w: WallWindows.Row): View = vstack(Gravity.NO_GRAVITY) {
    setPadding(dp(16), dp(10), dp(16), dp(10))
    addView(text(w.share.toString(), 34f, Color.WHITE, bold = true), lp(WRAP, WRAP))   // USER-DATA: the minutes this comment series minted
    addView(text(w.span, 12f, MT.gray), lp(WRAP, WRAP))   // USER-DATA: the window from its first comment to its last
    addView(text(w.marks.joinToString(" | "), 11f, MT.gray).apply { maxLines = 4; ellipsize = android.text.TextUtils.TruncateAt.END }, lp(MATCH, WRAP))   // USER-DATA: every comment's moment
    addView(text(w.title, 15f).apply { maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END }, lp(MATCH, WRAP))   // USER-DATA: the post whose comments opened the window
    addView(labeled(getString(R.string.coin_window), getString(if (w.open) R.string.coin_window_active else R.string.coin_window_inactive)).apply { setPadding(0, dp(6), 0, dp(6)); minimumHeight = 0 }, lp())
    addView(labeled(getString(R.string.coin_right_share), w.share.toString()).apply { setPadding(0, dp(6), 0, dp(6)); minimumHeight = 0 }, lp())
}

/** A page of the wallet: the bar with the cross or the back chevron, a mark at the trailing edge when it has one, the list that
 * scrolls — a pull of it mints, only where `onPull` names it (iOS MTWalletPage .onPreferenceChange(MTWalletPullKey.self),
 * MTWalletScreen.swift:343-349 and 367-380). */
private fun walletFrame(act: MainActivity, title: String, onLead: () -> Unit, cross: Boolean, trailing: View?, body: LinearLayout, onPull: (() -> Unit)? = null): View {
    val c: Context = act
    val bar = FrameLayout(c).apply {
        setPadding(dp(8), 0, dp(8), 0)
        addView(c.icon(if (cross) R.drawable.ic_close else R.drawable.ic_arrow_back_ios_new, Color.WHITE).apply {
            setPadding(dp(10), dp(10), dp(10), dp(10)); contentDescription = c.getString(R.string.coin_close); pressable(onLead)
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(c.text(title, 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        if (trailing != null) addView(trailing, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
    }
    val scroll = ScrollView(c).apply { addView(body.apply { setPadding(dp(16), 0, dp(16), dp(32)) }) }
    val list: View = if (onPull != null) CoinPull(c, scroll) { onPull() } else scroll
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, dp(52)))
            addView(list, lp(MATCH, 0, 1f))
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
    // THE TIMECHAINS (iOS MTTimeChainRows): each source's chain, its length, the first letters of its head and its seal, every chain read
    // whole off the screen's thread — at the opening, then three quiet seconds after the book's moves change (iOS, T1's stalls 04.10)
    var heads: Map<String, TimeChain.Head> = emptyMap()
    var headsDue = false
    var headsAt = -1
    var windows: List<WallWindows.Row> = emptyList()   // the wall's comment windows, read at the opening, at the pull and at the return (iOS refresh 418-419)
    val windowRows = c.vstack(Gravity.NO_GRAVITY)

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
        coin.spinAt(maxOf(Pantheon.speed, if (WalletPull.on) 1 else 0))   // at least once a second while the auto minting runs (iOS MTWalletScreen.swift:73-77)
        badge.text = maxOf(1, place).toString()   // the level the minting multiplies by
        val shownBar = (lit || WalletPull.on) && place < PiLevels.all.size   // iOS MTLevelProgress, MTWalletScreen.swift:124-126
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
        val chains = TimeChain.SOURCES.mapNotNull { s ->
            heads[s]?.takeIf { 0 < it.n }?.let { h -> c.settingsRow(null, 0, c.chainName(s), value = c.chainHead(h, 8)) { act.push { back -> timeChainPage(act, s, back) } } }
        }
        if (chains.isNotEmpty()) rows.section(c.getString(R.string.tc_title), null, *chains.toTypedArray())
        // THE WALL'S MINTING STANDS ON THE WALLET (iOS MTWalletScreen.swift:210-214): the rights the comment windows hold, beside the book and never added into it
        rows.section(c.getString(R.string.coin_minting), c.getString(R.string.coin_counted_here),
            c.labeled(c.getString(R.string.coin_minting_now), windows.filter { it.open }.sumOf { it.share }.toString()),   // USER-DATA: a number of minutes
            c.labeled(c.getString(R.string.coin_wall_rights), windows.sumOf { it.share }.toString()),   // USER-DATA: a number of minutes
            c.labeled(c.getString(R.string.coin_from_pantheon), CoinText.count(CoinBook.tapped)),
            c.labeled(c.getString(R.string.coin_received_n), CoinText.count(CoinBook.received)),
            c.labeled(c.getString(R.string.coin_sent_n), CoinText.count(CoinBook.sent)),
            c.labeled(c.getString(R.string.coin_in_montana), CoinText.montana(b)))
        rows.section(null, null, c.settingsRow(null, 0, c.getString(R.string.coin_history)) { act.push { coinHistoryPage(act, it) } })
    }
    // THE COMMENT WINDOWS OF THE WALL (iOS MTWalletScreen.swift:292-313): each window's minutes, its span, every comment's moment, its
    // post, whether it is open and its right to a share; none stands — «No comments yet». Drawn when the windows are read, not at every coin.
    fun drawWindows() {
        windowRows.removeAllViews()
        val shown: List<View> = if (windows.isEmpty()) listOf(c.text(c.getString(R.string.wall_no_comments), 16f, MT.gray).apply { setPadding(dp(16), dp(14), dp(16), dp(14)) })
            else windows.map { c.wallWindowRow(it) }
        windowRows.section(c.getString(R.string.coin_timechain), c.getString(R.string.coin_right_note), *shown.toTypedArray())
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
    body.addView(windowRows, lp())
    // THE WALL'S COMMENT WINDOWS ARE READ OFF THE SCREEN'S THREAD (iOS refresh, MTWalletScreen.swift:418-419): at the opening, at the
    // pull and at the return to the app — never at every coin
    lateinit var holder: FrameLayout
    fun readWindows() { Thread { val w = WallWindows.all(); MainThread.post { windows = w; if (holder.isAttachedToWindow) { draw(); drawWindows() } } }.start() }
    // THE TOP IS A LIVE SET FROM THE NODES (iOS MTWalletPage .task, MTWalletScreen.swift:361-381): while the wallet stands on the screen
    // the pairs' last words are asked of the nodes every three seconds, one question after the other — their balances ride them
    // (CoinBoard); a round that is no longer the page's own stops
    var asking = 0
    fun askNodes(round: Int) {
        if (round != asking || !holder.isAttachedToWindow) return
        Thread { runCatching { Signal.sweep(quiet = true) }; MainThread.later(3000, Runnable { askNodes(round) }) }.start()
    }
    // THE PULL SWITCHES THE AUTO MINTING ON (iOS MTWalletPage.pulled, MTWalletScreen.swift:404-417): let go past the trigger, the pull
    // mints every second from now on (WalletPull) and the page reads its windows again; the book's own change redraws it (CoinBook.listen).
    val page = walletFrame(act, c.getString(R.string.coin_title), onClose, true, null, body) { WalletPull.fire(); readWindows() }
    // THE LOCK ENDS IT, NOT A GLANCE (iOS .onChange(of: phase), MTWalletScreen.swift:382-386): the app gone from the screen — its window
    // hidden, the screen locked — stops the auto minting and the nodes' questions; a shade or a dialog over it does not. The return reads
    // the windows again and asks the nodes at once.
    holder = object : FrameLayout(c) {
        override fun onWindowVisibilityChanged(visibility: Int) {
            super.onWindowVisibilityChanged(visibility)
            if (visibility == View.VISIBLE) { readWindows(); askNodes(++asking) }
            else if (windowVisibility != View.VISIBLE) { asking++; WalletPull.stop("background") }
        }
    }.apply { addView(page, FrameLayout.LayoutParams(MATCH, MATCH)) }
    val again: () -> Unit = { draw() }
    fun readHeads() { headsAt = CoinBook.size(); TimeChain.heads { h -> heads = h; if (page.isAttachedToWindow) draw() } }
    val moved: () -> Unit = {
        if (!headsDue && CoinBook.size() != headsAt) {
            headsDue = true
            MainThread.later(3000, Runnable { headsDue = false; if (page.isAttachedToWindow) readHeads() })
        }
    }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { CoinBook.listen(again); CoinBook.listen(moved); Pantheon.listen(again); WalletPull.listen(again); draw(); coin.turnOnce() }
        // the page left: the auto minting stops with it and the nodes are asked no more (iOS .onDisappear, MTWalletScreen.swift:387)
        override fun onViewDetachedFromWindow(v: View) { CoinBook.unlisten(again); CoinBook.unlisten(moved); Pantheon.unlisten(again); WalletPull.unlisten(again); asking++; WalletPull.stop("page"); Pantheon.released(); CoinBook.closeWindows() }
    })
    // the book read first, so its past is in the chains before their heads are read (one queue, in order)
    Thread { CoinBook.warm(); MainThread.post { draw(); readHeads() } }.start()
    return holder
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

/** A GROUP OF THE HISTORY (iOS MTCoinGroup, MTWalletScreen.swift:514-540): the moves of one source, one way and one person
 * within one minute — one row with their sum and count. */
private class CoinGroup(val source: String, val first: CoinEntry, var signed: Long, var count: Int, val at: Double) {
    companion object {
        private const val SHOWN = 60
        fun recent(moves: List<CoinEntry>): List<CoinGroup> {
            val out = ArrayList<CoinGroup>()
            var last = ""
            for (e in moves) {
                val source = TimeChain.source(e)
                val key = source + "|" + e.k + "|" + (e.peer ?: "") + "|" + (e.at / 60).toLong()
                if (key == last && out.isNotEmpty()) { out[out.size - 1].signed += e.signed; out[out.size - 1].count++; continue }
                if (out.size == SHOWN) break
                last = key
                out.add(CoinGroup(source, e, e.signed, 1, e.at))
            }
            return out
        }
    }
}

/** A SOURCE'S TOTALS OVER A PERIOD (iOS MTCoinTotal, MTWalletScreen.swift:542-558): what came in by it and what went out. */
private class CoinTotal(val source: String, var into: Long = 0, var out: Long = 0) {
    companion object {
        fun of(moves: List<CoinEntry>): List<CoinTotal> {
            val by = LinkedHashMap<String, CoinTotal>()
            for (e in moves) {
                val s = TimeChain.source(e)
                val x = by.getOrPut(s) { CoinTotal(s) }
                if (0 < e.signed) x.into += e.signed else x.out -= e.signed
            }
            return TimeChain.SOURCES.mapNotNull { by[it] }
        }
    }
}

/** From where to where, as a person reads it (iOS MTWalletPage.route, reused by MTCoinHistoryPage's groups, MTWalletScreen.swift:728). */
private fun Context.coinRoute(e: CoinEntry): String {
    val me = getString(R.string.coin_you)
    fun who(ref: String?): String = ref?.let { Book.chat(it)?.shown?.ifBlank { null } } ?: getString(R.string.peer)
    return when (e.k) {
        CoinEntry.EARN -> (if (e.ref.startsWith(Pantheon.PREFIX)) getString(R.string.coin_pantheon) else getString(R.string.coin_kind_earn)) + " → " + me
        CoinEntry.RECEIVE -> who(e.peer) + " → " + me
        CoinEntry.BURN -> me + " → " + getString(R.string.coin_burned)
        else -> me + " → " + who(e.peer)
    }
}

/** The platform's segmented choice of a period (iOS MTCoinHistoryPage.Period, MTWalletScreen.swift:665-684). */
private enum class HistoryPeriod(val word: Int, val seconds: Double?) {
    HOUR(R.string.history_period_hour, 3600.0), DAY(R.string.history_period_day, 86400.0),
    WEEK(R.string.history_period_week, 604800.0), ALL(R.string.history_period_all, null)
}

/**
 * THE HISTORY'S OWN PAGE (iOS MTCoinHistoryPage, MTWalletScreen.swift:664-746, the author's word 04.10.2026 04:02 MSK: «the history
 * as a link button into it, with the choice of the period and the details of the analysis, grouped neatly»): the platform's
 * segmented choice of the period, each source's coins in and out over it, and the moves grouped by source, way, person and
 * minute — each group opening its source's TimeChain.
 */
fun coinHistoryPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    val lists = c.vstack(Gravity.NO_GRAVITY)
    var period = HistoryPeriod.DAY
    fun drawLists() {
        lists.removeAllViews()
        val since = period.seconds?.let { System.currentTimeMillis() / 1000.0 - it } ?: 0.0
        val moves = CoinBook.moves().filter { since <= it.at }
        if (moves.isEmpty()) {
            lists.addView(c.text(c.getString(R.string.coin_no_moves_period), 16f, MT.gray).apply { setPadding(dp(16), dp(14), dp(16), dp(14)) }, lp())
            return
        }
        lists.section(c.getString(R.string.coin_by_source), null, *CoinTotal.of(moves).map { x ->
            c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(10), dp(16), dp(10))
                minimumHeight = dp(48)
                addView(c.text(c.chainName(x.source), 16f), lp(0, WRAP, 1f))
                addView(c.vstack(Gravity.END) {
                    if (0L < x.into) addView(c.text("+" + CoinText.count(x.into), 15f, MT.green))   // USER-DATA: the coins in by this source
                    if (0L < x.out) addView(c.text("−" + CoinText.count(x.out), 15f, Color.WHITE))   // USER-DATA: the coins out by this source
                }, lp(WRAP, WRAP))
                pressable { act.push { back -> timeChainPage(act, x.source, back) } }
            } as View
        }.toTypedArray())
        lists.section(c.getString(R.string.coin_moves_section), null, *CoinGroup.recent(moves).map { g ->
            c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.hstack {
                    addView(c.text(c.chainName(g.source), 15f, Color.WHITE, bold = true), lp(0, WRAP, 1f))   // USER-DATA: the source the moves came by
                    addView(c.text((if (0L < g.signed) "+" else "") + CoinText.count(g.signed), 15f, if (0L < g.signed) MT.green else Color.WHITE), lp(WRAP, WRAP))   // USER-DATA: the coins the group moved
                }, lp())
                addView(c.text(c.coinRoute(g.first), 13f, MT.gray))   // USER-DATA: where the coins came from and where they went
                addView(c.hstack {
                    addView(c.text(android.text.format.DateFormat.getMediumDateFormat(c).format(Date((g.at * 1000).toLong())) + " " +
                        android.text.format.DateFormat.getTimeFormat(c).format(Date((g.at * 1000).toLong())), 12f, MT.gray), lp(0, WRAP, 1f))   // USER-DATA: the group's newest move
                    addView(c.text("× " + g.count, 12f, MT.gray))   // USER-DATA: how many moves the group holds
                }, lp())
                pressable { act.push { back -> timeChainPage(act, g.source, back) } }
            } as View
        }.toTypedArray())
    }
    body.addView(segmented(c, HistoryPeriod.values().map { it.word to it.name }, period.name) { v -> period = HistoryPeriod.valueOf(v); drawLists() }, lp().apply { bottomMargin = c.dp(8) })
    body.addView(lists, lp())
    drawLists()
    val again: () -> Unit = { drawLists() }
    val page = walletFrame(act, c.getString(R.string.coin_history), onBack, false, null, body)
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { CoinBook.listen(again) }
        override fun onViewDetachedFromWindow(v: View) { CoinBook.unlisten(again) }
    })
    return page
}

/** A source's word in the catalogue, one table for every place that names it (iOS MTTimeChainRows.key). */
fun Context.chainName(source: String): String = getString(when (source) {
    "chess" -> R.string.tc_src_chess
    "pantheon" -> R.string.coin_from_pantheon
    "vpnwall" -> R.string.tc_src_vpnwall
    "vpnpay" -> R.string.tc_src_vpnpay
    "timer" -> R.string.tc_src_timer
    "chats" -> R.string.tc_src_chats
    "groups" -> R.string.tc_src_groups
    "channels" -> R.string.tc_src_channels
    "comments" -> R.string.tc_src_comments
    "wall" -> R.string.tc_src_wall
    "received" -> R.string.coin_received_n
    "spent" -> R.string.tc_src_spent
    "pi" -> R.string.coin_levels
    "calls" -> R.string.tc_src_calls
    "letters" -> R.string.tc_src_letters
    "system" -> R.string.tc_src_system
    else -> R.string.coin_sent_n
})

private fun Context.mono(s: String, sizeSp: Float, color: Int): TextView = text(s, sizeSp, color).apply { typeface = android.graphics.Typeface.MONOSPACE }
/** The platform's seal: whole and green when every seal holds from the genesis, broken and red when one does not (iOS checkmark.seal.fill, xmark.seal.fill). */
private fun Context.sealGlyph(whole: Boolean, sizeDp: Int): View = icon(if (whole) R.drawable.ic_seal_whole else R.drawable.ic_seal_broken, if (whole) MT.green else MT.red, sizeDp)
/** A chain's length and the first letters of its head's seal, then its seal. */
private fun Context.chainHead(h: TimeChain.Head, letters: Int): View = hstack {
    gravity = Gravity.CENTER_VERTICAL
    addView(mono(h.n.toString() + " · " + h.hash.take(letters), 13f, MT.gray), lp(WRAP, WRAP))   // USER-DATA: the chain's length and its head
    gap(6)
    addView(sealGlyph(h.whole, 18), lp(dp(18), dp(18)))
}
/** A seal in full, its title over it; the seal can be selected and copied. */
private fun Context.sealRow(title: String, seal: String): View = vstack(Gravity.NO_GRAVITY) {
    setPadding(dp(16), dp(10), dp(16), dp(10))
    addView(text(title, 15f), lp(WRAP, WRAP))
    addView(mono(seal, 12f, MT.gray).apply { setTextIsSelectable(true) }, lp(MATCH, WRAP))   // USER-DATA: a SHA-256 seal
}
/** A moment on this phone's clock, its date and its time to the second (iOS .abbreviated, .standard). */
private fun chainMoment(at: Double): String =
    java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.MEDIUM).format(Date((at * 1000).toLong()))

/**
 * A TIMECHAIN, LINK BY LINK (iOS MTTimeChainPage, the author's word 04.10.2026 00:46 MSK: «the detailed timechain»): every link of one
 * source's chain, the newest first — its number, its moment, the coins, its seal and the seal it stands on, the move's own name — and
 * whether every seal holds from the genesis.
 */
fun timeChainPage(act: MainActivity, source: String, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    val plate = c.plate {}
    body.addView(plate, lp().apply { topMargin = c.dp(12) })
    TimeChain.chain(source) { links, head ->
        plate.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            minimumHeight = dp(48)
            addView(c.mono(head.n.toString() + " · " + head.hash.take(16), 13f, Color.WHITE), lp(0, WRAP, 1f))   // USER-DATA: the chain's length and its head
            addView(c.sealGlyph(head.whole, 22), lp(dp(22), dp(22)))
        }, lp())
        // the newest five hundred, as the history: the head above counts them all
        for (l in links.asReversed().take(500)) {
            plate.divider()
            plate.addView(c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    addView(c.text("#" + l.n, 15f, Color.WHITE, bold = true), lp(0, WRAP, 1f))   // USER-DATA: the link's number in its chain
                    // USER-DATA: the coins the link moved, signed by its way; a link of the wall's posts moves none
                    if (0L < l.c) addView(c.text((if (l.k in setOf("earn", "receive", "keep")) "+" else "−") + CoinText.count(l.c), 17f, Color.WHITE), lp(WRAP, WRAP))
                }, lp())
                addView(c.text(chainMoment(l.at / 1000.0), 12f, MT.gray), lp(WRAP, WRAP))   // USER-DATA: the link's moment, on this phone's clock
                addView(c.mono(l.hash.take(16) + " ← " + l.prev.take(16), 11f, MT.gray), lp(WRAP, WRAP))   // USER-DATA: the link's seal and the seal it stands on
                addView(c.mono(l.ref, 11f, MT.gray).apply {   // USER-DATA: the move's own name
                    alpha = 0.6f; setSingleLine(true); ellipsize = android.text.TextUtils.TruncateAt.MIDDLE
                }, lp(MATCH, WRAP))
            }, lp())
        }
    }
    return walletFrame(act, c.chainName(source), onBack, false, null, body)
}

/**
 * ONE COIN MOVE ON ITS OWN PAGE (iOS MTCoinMovePage, MTWalletScreen 560-662; the author's words 05.10.2026 «a tap on the coins opens this
 * transaction» and 06.10.2026 16:2x MSK «a Local TimeChain and a Global TimeChain, in which the hashes are one in the network's
 * consensus by the set»): the coins, who they came from or went to, the moment; the link this phone's chain sealed for it, with its
 * seal and the seal before it; the letter's seal, the same on every device that holds the transfer; and the system chain's link when
 * the book had lost the move and the system restored it. The phone's own node and its count of the genesis machines reached (iOS
 * MTNetworkNode) is not on Android, so its row is not drawn rather than drawn empty.
 */
fun coinMovePage(act: MainActivity, ref: String, mine: Boolean, peer: String, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    val kind = if (mine) CoinEntry.SEND else CoinEntry.RECEIVE
    val move = CoinBook.moves().firstOrNull { it.ref == ref && it.k == kind }
    if (move == null) {
        body.addView(c.text(c.getString(R.string.tc_not_yet), 16f, MT.gray).apply { setPadding(dp(16), dp(22), dp(16), dp(14)) }, lp())
        return walletFrame(act, c.getString(R.string.tc_transaction), onBack, false, null, body)
    }
    val amount = c.hstack {
        setPadding(dp(16), dp(12), dp(16), dp(12))
        minimumHeight = dp(48)
        addView(c.text(c.getString(R.string.tc_amount), 16f), lp(0, WRAP, 1f))
        // USER-DATA: the coins the move carried, signed by its way
        addView(c.text((if (mine) "−" else "+") + CoinText.count(move.c), 16f, if (mine) Color.WHITE else MT.green), lp(WRAP, WRAP))
    }
    body.section(c.getString(if (mine) R.string.coin_sent_n else R.string.coin_received_n), null, amount,
        c.labeled(c.getString(if (mine) R.string.tc_to else R.string.tc_from), peer),   // USER-DATA: the person
        c.labeled(c.getString(R.string.tc_date), chainMoment(move.at)))   // USER-DATA: the move's moment on this phone's clock
    // the local link and the system's restoring link stand where iOS puts them, filled when their chains are read
    val local = c.vstack(Gravity.NO_GRAVITY)
    body.addView(local, lp())
    LetterSeal.seal(ref)?.let { seal ->
        body.section(c.getString(R.string.tc_global), c.getString(R.string.tc_global_note), c.sealRow(c.getString(R.string.tc_seal), seal))
    }
    val system = c.vstack(Gravity.NO_GRAVITY)
    body.addView(system, lp())
    TimeChain.read(TimeChain.source(ref, kind)) { links ->
        val l = links.lastOrNull { it.ref == ref } ?: return@read
        local.section(c.getString(R.string.tc_local), null, c.labeled(c.getString(R.string.tc_link), "#" + l.n),   // USER-DATA: the link's number
            c.sealRow(c.getString(R.string.tc_seal), l.hash), c.sealRow(c.getString(R.string.tc_prev_seal), l.prev))
    }
    TimeChain.read("system") { links ->
        val l = links.lastOrNull { it.ref == TimeChain.RESTORE + ref } ?: return@read
        system.section(c.getString(R.string.tc_src_system), null, c.labeled(c.getString(R.string.tc_restored), "#" + l.n),   // USER-DATA: the restoring link's number
            c.sealRow(c.getString(R.string.tc_seal), l.hash))
    }
    return walletFrame(act, c.getString(R.string.tc_transaction), onBack, false, null, body)
}
