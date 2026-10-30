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

// ─────────────────────────── the wallet's pages (iOS MTWalletScreen: MTWalletPage, MTCoinSendSheet, MTPiLevelsSheet; the history and the analytics: CoinHistoryPages.kt) ───────────────────────────

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

/** A page of the wallet: the bar with the cross or the back chevron, a mark at the trailing edge when it has one, the list that
 * scrolls — a pull of it mints, only where `onPull` names it (iOS MTWalletPage .onPreferenceChange(MTWalletPullKey.self),
 * MTWalletScreen.swift:343-349 and 367-380). */
private fun walletFrame(act: MainActivity, title: String, onLead: () -> Unit, cross: Boolean, trailing: View?, body: LinearLayout,
                        large: Boolean = false, onPull: (() -> Unit)? = null): View {
    val c: Context = act
    val bar = FrameLayout(c).apply {
        setPadding(dp(8), 0, dp(8), 0)
        // the bar's one mark on its round of glass in a 44 frame (iOS MontanaBarMark)
        val mark = FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.coin_close)
            addView(c.icon(if (cross) R.drawable.ic_close else R.drawable.ic_arrow_back_ios_new, Color.WHITE), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable(onLead)
        }
        if (large) {
            // THE TITLE AT THE LEFT, THE CROSS IN THE RIGHT CORNER (iOS .toolbarTitleDisplayMode(.inlineLarge), MTWalletScreen.swift:323-327,
            // the author's word 04.10.2026 13:34 MSK): the large title inline at the bar's leading edge, one mark on the bar
            addView(c.text(title, 28f, Color.WHITE, bold = true).apply { maxLines = 1; setPadding(dp(8), 0, dp(52), 0) },
                FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER_VERTICAL or Gravity.START))
            addView(mark, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
        } else {
            addView(mark, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
            addView(c.text(title, 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
            if (trailing != null) addView(trailing, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
        }
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
    // the person's chain asked at once -- the confirmed line -- then the transfers' records of every pipe (iOS MTWalletScreen 368)
    Thread { if (CoinTx.agrees) { if (CoinTx.WRITES) runCatching { CoinTx.readMine() }; CoinTx.scan("wallet", force = true) } }.start()
    VpnWallMint.count()   // the wallet opened: the VPN wall's seconds since the last count are paid (iOS MTWalletScreen.swift:280)
    val body = c.vstack(Gravity.NO_GRAVITY)
    // PANTHEON ON FIRE STANDS ALWAYS AND BURNS WHILE THE GAME BURNS (iOS MTWalletScreen.swift:66-74, the author's words 08.10.2026
    // 02:2x MSK): the flame in its own colours, the name white at title2 bold, an orange glow round it while the game is lit
    val fireWords = c.text(c.getString(R.string.coin_pantheon), 22f, Color.WHITE, bold = true)
    val fire = c.hstack {
        gravity = Gravity.CENTER
        addView(ImageView(c).apply { setImageResource(R.drawable.ic_flame) }, lp(dp(24), dp(24)))
        gap(6)
        addView(fireWords, lp(WRAP, WRAP))
    }
    // THE CAPTION COMES WITH THE FINGER (iOS 75-84, the author's word 09.10.2026): one line while a finger is on the coin and three
    // seconds after the last one lifts; hidden, it keeps its place, so the coin never moves under the finger
    val hint = c.text(c.getString(R.string.coin_hint), 13f, MT.gray, center = true).apply { alpha = 0f }
    var hintTurn = 0
    fun showHint() { hintTurn++; hint.animate().alpha(1f).setDuration(250).start() }
    fun hideHintSoon() { val turn = ++hintTurn; MainThread.later(3000, Runnable { if (turn == hintTurn) hint.animate().alpha(0f).setDuration(250).start() }) }
    val coin = MintCoin(c, 120)
    val pops = FrameLayout(c)
    val badge = c.text("", 13f, Color.WHITE, bold = true, center = true).apply {
        // THE LEVEL ON THE COIN (iOS MTMintLevelBadge, MTWalletScreen.swift:1133-1142): the platform's count badge, red, 20 high
        background = c.rounded(SysColor.red, 10); setPadding(dp(6), 0, dp(6), 0); minWidth = dp(20); minHeight = dp(20); gravity = Gravity.CENTER
    }
    // THE COIN CATCHES FIRE AT THE TAPS (iOS 138-146): a still orange circle beneath it, its light following the speed; the
    // platform's ring round the coin while the Pantheon burns (iOS 148-150, MTMiniFace.playingRing, 3 pt at 8 outside)
    val glow = View(c).apply {
        background = GradientDrawable().apply {
            gradientType = GradientDrawable.RADIAL_GRADIENT; gradientRadius = c.dp(74).toFloat()
            colors = intArrayOf(MT.orange, MT.orange, Color.TRANSPARENT)
        }
        alpha = 0f
    }
    val ring = View(c).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.TRANSPARENT); setStroke(c.dp(3), MT.blue) }
        visibility = View.INVISIBLE
    }
    val speed = c.text("", 15f, MT.gray, center = true).apply { fontFeatureSettings = "tnum" }
    val bar = ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal).apply {
        max = 1000; progressTintList = android.content.res.ColorStateList.valueOf(MT.blue)
    }
    val toLevel = c.text("", 13f, MT.gray, center = true).apply { fontFeatureSettings = "tnum" }
    // THE PRICE OF A SECOND, FIXED UNDER THE COUNT (iOS MTSecondPrice, MTCurrentMintRate, MTWalletScreen.swift:1080-1088 and 1650-1658)
    val rate = c.text("", 13f, MT.gray, center = true).apply { fontFeatureSettings = "tnum" }
    // THE TOTAL IS THE BOOK'S, THE AVAILABLE THE NETWORK'S (iOS 158-171, the author's words 12.10.2026 15:5x MSK): the figure is every
    // coin the book holds, 48 bold with even digits, the ticker in the same type; under it the part the chain holds for its owner
    val balance = c.text("", 48f, Color.WHITE, bold = true, center = true).apply {
        maxLines = 1; fontFeatureSettings = "tnum"
        setAutoSizeTextTypeUniformWithConfiguration(24, 48, 1, android.util.TypedValue.COMPLEX_UNIT_SP)
    }
    // THE SEED'S BOOK IS ON ITS WAY (iOS 176-178): a phone restored by its words says it is gathering, never a balance of nothing
    val gathering = c.hstack {
        gravity = Gravity.CENTER
        addView(ProgressBar(c).apply { indeterminateTintList = android.content.res.ColorStateList.valueOf(MT.gray) }, lp(dp(16), dp(16)))
        gap(8)
        addView(c.text(c.getString(R.string.coin_gathering), 13f, MT.gray), lp(WRAP, WRAP))
    }
    val inMontana = c.text("", 15f, MT.gray, center = true).apply { fontFeatureSettings = "tnum" }
    val available = c.text("", 15f, MT.gray, center = true).apply { fontFeatureSettings = "tnum" }
    val pi = c.text("", 13f, MT.gray, center = true).apply { fontFeatureSettings = "tnum" }
    // WHAT THE NETWORK CONFIRMED (the owner's word 17.10.2026: «show the real confirmed results, not only the locally computed balance»):
    // the book gathered from the seed's vault, then the person's chain as its node says it; a chain not opened yet offers its opening
    val confirmed = c.text("", 13f, MT.gray, center = true)
    val rows = c.vstack(Gravity.NO_GRAVITY)
    // the wall's comment windows: their minutes stand on the minting's rows, never added into the book (iOS 254-255); the windows
    // themselves stand on the wall (iOS MTBoardChainPage), no more on the wallet
    var windows: List<WallWindows.Row> = emptyList()

    // THE SYSTEM'S BUTTONS, ONE WIDTH (iOS MTWalletScreen.swift:186-235): «Send» and «Top up» on the platform's blue (borderedProminent),
    // every other door bordered -- the blue at a fifth on its ground and the words in the blue -- each a capsule 44 high, headline type
    fun capsule(word: Int, glyph: Int?, filled: Boolean, picture: Boolean = false, onTap: () -> Unit) = c.hstack {
        gravity = Gravity.CENTER
        minimumHeight = dp(44)
        setPadding(dp(12), 0, dp(12), 0)
        background = c.rounded(if (filled) MT.blue else MT.withAlpha(MT.blue, 0.2f), 22)
        if (glyph != null) {
            // OUR SEND, AS IN THE CHATS (iOS MTTimeSendMark(height: 24), the author's word 05.10): the author's picture in its own colours
            if (picture) addView(ImageView(c).apply { setImageResource(glyph); scaleType = ImageView.ScaleType.FIT_CENTER }, lp(dp(17), dp(24)))
            else addView(c.icon(glyph, if (filled) Color.WHITE else MT.blue, 20), lp(dp(20), dp(20)))
            gap(8)
        }
        addView(c.text(c.getString(word), 17f, if (filled) Color.WHITE else MT.blue, bold = true))
        pressable(onTap)
    }
    val send = capsule(R.string.coin_send, R.drawable.time_send, true, picture = true) { act.push { sendCoinsPage(act, it) } }
    // EVERY ROAD OF THE COINS STANDS BEHIND TOP UP (iOS MTCoinTopUpSheet, the author's word 11.10.2026 20:2x MSK)
    val topUp = capsule(R.string.coin_top_up, R.drawable.ic_plus_circle_fill, true) { act.push { coinTopUpPage(act, it) } }
    lateinit var redraw: () -> Unit
    val openChain = capsule(R.string.coin_chain_open_button, null, false) { askGenesis(act) { redraw() } }

    fun draw() {
        // THE TOTAL IS THE BOOK'S (iOS total, MTWalletScreen.swift:47): every coin the book holds, minted and received by every road
        val total = CoinBook.balance
        // THE AVAILABLE, ONE NUMBER EVERYWHERE (iOS MTCoinSplit.available, the author's word 16.10.2026 17:19 MSK) where the chains are written
        val avail = if (CoinTx.WRITES) CoinSplit.available else total
        val gather = !CoinVault.heard && total == 0L
        gathering.visibility = if (gather) View.VISIBLE else View.GONE
        if (CoinTx.WRITES) {
            val m = CoinTx.mine
            confirmed.text = when {
                !CoinVault.heard -> if (gather) "" else c.getString(R.string.coin_book_loading)
                m == null -> c.getString(R.string.coin_chain_asking)
                !m.v3 -> c.getString(R.string.coin_chain_closed)
                else -> c.getString(R.string.coin_confirmed, CoinText.count(m.proven + m.declared), CoinBook.TICKER)   // USER-DATA: the chain's coins
            }
            confirmed.visibility = if (confirmed.text.isEmpty()) View.GONE else View.VISIBLE
            openChain.visibility = if (CoinVault.heard && m != null && !m.v3 && !CoinTx.genesisAllowedCached()) View.VISIBLE else View.GONE
        } else { confirmed.visibility = View.GONE; openChain.visibility = View.GONE }
        val place = PiLevels.place(total)
        val lit = Pantheon.lit
        fireWords.setShadowLayer(if (lit) c.dp(8).toFloat() else 0f, 0f, 0f, if (lit) MT.withAlpha(MT.orange, 0.8f) else Color.TRANSPARENT)
        speed.visibility = if (lit) View.VISIBLE else View.INVISIBLE
        ring.visibility = speed.visibility
        glow.animate().alpha(if (!lit) 0f else if (0 < Pantheon.speed) 0.8f else 0.3f).setDuration(250).start()
        speed.text = Pantheon.speed.toString() + " / " + Pantheon.CEILING   // USER-DATA: the taps of the last second
        coin.spinAt(maxOf(Pantheon.speed, if (WalletPull.on) 1 else 0))   // at least once a second while the auto minting runs (iOS MTWalletScreen.swift:73-77)
        badge.text = if (0 < place) place.toString() else ""   // the level the minting multiplies by (iOS MTMintLevelBadge)
        badge.visibility = if (0 < place) View.VISIBLE else View.INVISIBLE
        val shownBar = (lit || WalletPull.on) && place < PiLevels.all.size   // iOS MTLevelProgress, MTWalletScreen.swift:124-126
        bar.visibility = if (shownBar) View.VISIBLE else View.INVISIBLE
        toLevel.visibility = bar.visibility
        if (place < PiLevels.all.size) {
            val low = if (0 < place) PiLevels.all[place - 1] else 0L
            val high = PiLevels.all[place]
            bar.progress = (((total - low).toDouble() / maxOf(1L, high - low)) * 1000).toInt()
            toLevel.text = c.getString(R.string.coin_to_level, CoinText.count(high - total), place + 1)
        }
        val n = PiLevels.multiplier(total).toInt()
        rate.text = c.resources.getQuantityString(R.plurals.coin_second_rate, n, n)   // USER-DATA: the coins one second mints now
        balance.text = CoinText.count(total) + " " + CoinBook.TICKER   // USER-DATA: the balance and the ticker
        inMontana.text = CoinText.montana(total) + " Ɱ"   // USER-DATA: the balance in Montana
        available.text = c.getString(R.string.coin_available, CoinText.count(avail))   // USER-DATA: the spendable part of the total
        pi.text = "π " + PiLevels.revealed(place) + " · " + place   // USER-DATA: the level of π and π revealed to it
        send.isEnabled = 0 < total; send.alpha = if (0 < total) 1f else 0.4f
        rows.removeAllViews()
        // THE MINTING, ONE VALUE PER ROW (iOS MTWalletScreen.swift:252-299): the wall's rights beside the book and never added into it,
        // then every source the book counts (CoinBook.count, iOS MTCoinCounts)
        rows.section(c.getString(R.string.coin_minting), c.getString(R.string.coin_counted_here),
            c.labeled(c.getString(R.string.coin_minting_now), windows.filter { it.open }.sumOf { it.share }.toString()),   // USER-DATA: a number of minutes
            c.labeled(c.getString(R.string.coin_wall_rights), windows.sumOf { it.share }.toString()),   // USER-DATA: a number of minutes
            c.labeled(c.getString(R.string.coin_from_chats), CoinText.count(CoinBook.earned)),
            c.labeled(c.getString(R.string.coin_from_pantheon), CoinText.count(CoinBook.tapped)),
            c.labeled(c.getString(R.string.coin_from_chess), CoinText.count(CoinBook.played)),
            c.labeled(c.getString(R.string.coin_from_vpn_wall), CoinText.count(CoinBook.walled)),
            c.labeled(c.getString(R.string.coin_burned_n), CoinText.count(CoinBook.burned)),
            c.labeled(c.getString(R.string.coin_received_n), CoinText.count(CoinBook.received)),
            c.labeled(c.getString(R.string.coin_sent_n), CoinText.count(CoinBook.sent)),
            c.labeled(c.getString(R.string.coin_on_reactions), CoinText.count(CoinBook.spent)),
            c.labeled(c.getString(R.string.coin_in_montana), CoinText.montana(total)))
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
                    showHint()
                    val coins = Pantheon.tap()
                    v.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    if (0 < coins) pop(e.getX(i), e.getY(i), coins)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { Pantheon.released(); hideHintSoon() }
            }
            true
        }
        setOnClickListener { Pantheon.tap() }   // the accessibility service's own tap
    }
    // THE WALLET'S HEAD (iOS MTWalletScreen.swift:53-240): one column, 14 between its parts, 20 above and below; a part that comes
    // and goes keeps its place (the author's word 04.10.2026 04:21 MSK: the page does not move under the game)
    val head = c.vstack {
        setPadding(0, dp(20), 0, dp(20))
        addView(fire, lp(WRAP, WRAP))
        gap(14)
        addView(hint, lp(MATCH, WRAP))
        gap(14)
        // THE APPS THAT MINT, ABOVE THE COIN (iOS MTMintingApps, 1115-1131): the row keeps its 30 when none mints
        addView(View(c), lp(MATCH, dp(30)))
        gap(14)
        addView(FrameLayout(c).apply {
            addView(glow, FrameLayout.LayoutParams(dp(148), dp(148), Gravity.CENTER))
            addView(coin, FrameLayout.LayoutParams(dp(120), dp(120), Gravity.CENTER))
            addView(ring, FrameLayout.LayoutParams(dp(136), dp(136), Gravity.CENTER))
            // the badge at the coin's top-trailing corner, 8 in from each side (iOS .offset(x: -8, y: 8))
            addView(badge, FrameLayout.LayoutParams(WRAP, dp(20), Gravity.TOP or Gravity.END).apply { setMargins(0, dp(22), dp(22), 0) })
            addView(pad, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(pops, FrameLayout.LayoutParams(MATCH, MATCH))
        }, lp(dp(148), dp(148)))
        gap(14)
        addView(speed, lp(WRAP, WRAP))
        gap(14)
        addView(c.vstack {
            addView(bar, lp(dp(240), WRAP))
            gap(6)
            addView(toLevel, lp(WRAP, WRAP))
        }, lp(WRAP, WRAP))
        gap(14)
        addView(rate, lp(WRAP, WRAP))
        gap(14)
        addView(balance, lp(MATCH, WRAP))
        addView(gathering, lp(WRAP, WRAP).apply { topMargin = dp(14) })
        gap(14)
        addView(inMontana, lp(WRAP, WRAP))
        gap(14)
        addView(available, lp(WRAP, WRAP))
        gap(14)
        addView(pi, lp(WRAP, WRAP))
        addView(confirmed, lp(WRAP, WRAP).apply { topMargin = dp(14) })
        gap(14)
        addView(c.hstack {
            addView(send, lp(0, WRAP, 1f))
            gap(12)
            addView(topUp, lp(0, WRAP, 1f))
        }, lp(MATCH, WRAP))
        addView(openChain, lp(MATCH, WRAP).apply { topMargin = dp(14) })
        gap(14)
        // THE TIMECHAIN IN PLACE OF A SECOND ACCOUNT (iOS 205-215), THE LEVELS OF π (216-222), THE HISTORY UNDER THEM (223-230)
        addView(capsule(R.string.coin_timechain, R.drawable.ic_link, false) { act.push { timeChainsPage(act, it) } }, lp(MATCH, WRAP))
        gap(14)
        addView(capsule(R.string.coin_levels, R.drawable.ic_list_number, false) { act.push { piLevelsPage(act, it) } }, lp(MATCH, WRAP))
        gap(14)
        addView(capsule(R.string.coin_history, R.drawable.ic_history, false) { act.push { coinHistoryPage(act, it) } }, lp(MATCH, WRAP))
        gap(14)
        // THE ANALYTICS BY ITS OWN BUTTON (iOS 231-239, the author's word 12.10.2026 15:2x MSK: «make the analytics a separate button, so it
        // opens and nothing lags»): under the History, read from the one fold of the history (coinAnalyticsPage, CoinHistory)
        addView(capsule(R.string.coin_analytics, R.drawable.ic_chart_pie, false) { act.push { coinAnalyticsPage(act, it) } }, lp(MATCH, WRAP))
    }
    pops.isClickable = false
    body.addView(head, lp())
    body.addView(rows, lp())
    // THE WALL'S COMMENT WINDOWS ARE READ OFF THE SCREEN'S THREAD (iOS refresh, MTWalletScreen.swift:418-419): at the opening, at the
    // pull and at the return to the app — never at every coin
    lateinit var holder: FrameLayout
    fun readWindows() { Thread { val w = WallWindows.all(); MainThread.post { windows = w; if (holder.isAttachedToWindow) draw() } }.start() }
    // THE TOP IS A LIVE SET FROM THE NODES (iOS MTWalletPage .task, MTWalletScreen.swift:361-381): while the wallet stands on the screen
    // the pairs' last words are asked of the nodes every three seconds, one question after the other — their balances ride them
    // (CoinBoard); a round that is no longer the page's own stops
    var asking = 0
    fun askNodes(round: Int) {
        if (round != asking || !holder.isAttachedToWindow) return
        Thread { runCatching { Signal.sweep(quiet = true) }; runCatching { PersonChain.tick() }; MainThread.later(3000, Runnable { askNodes(round) }) }.start()   // the devices of the words join the seconds of the person (iOS MTWalletScreen 379)
    }
    // THE PULL SWITCHES THE AUTO MINTING ON (iOS MTWalletPage.pulled, MTWalletScreen.swift:404-417): let go past the trigger, the pull
    // mints every second from now on (WalletPull) and the page reads its windows again; the book's own change redraws it (CoinBook.listen).
    val page = walletFrame(act, c.getString(R.string.coin_title), onClose, true, null, body, large = true) { WalletPull.fire(); readWindows() }
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
    redraw = again
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        // the history's fold is ready before its door (iOS .onAppear MTCoinHistory.shared.warm(), MTWalletScreen.swift:360)
        override fun onViewAttachedToWindow(v: View) { CoinBook.listen(again); Pantheon.listen(again); WalletPull.listen(again); draw(); coin.turnOnce(); CoinHistory.warm(c) }
        // the page left: the auto minting stops with it and the nodes are asked no more (iOS .onDisappear, MTWalletScreen.swift:387)
        override fun onViewDetachedFromWindow(v: View) { CoinBook.unlisten(again); Pantheon.unlisten(again); WalletPull.unlisten(again); asking++; WalletPull.stop("page"); Pantheon.released(); CoinBook.closeWindows() }
    })
    Thread { CoinBook.warm(); MainThread.post { draw() } }.start()
    return holder
}

/**
 * THE TIMECHAIN PAGE (iOS MTTimeChainsPage, MTWalletScreen.swift:1507-1645): the wallet's own chains and the level of π they reveal,
 * the chats' and calls' chains, the Explorer, and what an observer checks. Every chain is read whole off the screen's thread -- at the
 * opening, then three quiet seconds after the book's moves change (iOS MTTimeChainRows, T1's stalls 04.10). The person's chain and
 * the global level join this page with the levels' stage (iOS MTPersonChain).
 */
fun timeChainsPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    // the chats' and calls' chains, the third chain of time; every other source is the wallet's own (iOS talk, own)
    val talk = listOf("chats", "groups", "channels", "comments", "wall", "calls", "letters")
    val own = TimeChain.SOURCES.filter { it != "pi" && it !in talk }
    var heads: Map<String, TimeChain.Head> = emptyMap()
    var headsDue = false
    var headsAt = -1
    fun chainRows(sources: List<String>): List<View> = sources.mapNotNull { s ->
        heads[s]?.takeIf { 0 < it.n }?.let { h -> c.settingsRow(null, 0, c.chainName(s), value = c.chainHead(h, 8)) { act.push { back -> timeChainPage(act, s, back) } } }
    }
    fun draw() {
        body.removeAllViews()
        val place = PiLevels.place(CoinBook.balance)
        // THE GLOBAL LEVEL (iOS 1520-1527): the lower of the person's level and the wallet's, large
        body.section(null, c.getString(R.string.tc_glevel_footer), c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(10), dp(16), dp(10))
            minimumHeight = dp(52)
            addView(c.icon(R.drawable.ic_language, Color.WHITE, 22), lp(dp(22), dp(22)).apply { marginEnd = dp(12) })
            addView(c.text(c.getString(R.string.tc_glevel), 17f), lp(0, WRAP, 1f))
            addView(c.text(PersonChain.global(PersonChain.level, CoinBook.balance).toString(), 28f, Color.WHITE, bold = true).apply { fontFeatureSettings = "tnum" }, lp(WRAP, WRAP))   // USER-DATA: the Global Level
        })
        // THE PERSON (iOS 1528-1559): the chain's level, its seconds on the network, the way to the next level, its links
        val lv = PersonChain.level
        val secs = PersonChain.seconds
        val person = mutableListOf(
            c.labeled(c.getString(R.string.tc_level), lv?.toString() ?: "—"),   // USER-DATA: the person's level, a dash below one second
            c.labeled(c.getString(R.string.tc_time_online), spanWords(c, secs)))   // USER-DATA: the seconds the chain counts
        if (lv != null && lv < 62) {
            val from = 1L shl lv
            person += c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.text(c.getString(R.string.tc_next_level), 15f, MT.gray), lp())
                addView(ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal).apply {
                    max = 1000; progress = (((secs - from).toDouble() / from) * 1000).toInt().coerceIn(0, 1000)
                    progressTintList = android.content.res.ColorStateList.valueOf(MT.blue)
                }, lp().apply { topMargin = dp(6) })
            }
        }
        person += c.settingsRow(null, 0, c.getString(R.string.tc_links),
            value = c.mono(PersonChain.links.size.toString() + " · " + (PersonChain.links.lastOrNull()?.hash ?: TimeChain.GENESIS).take(8), 13f, MT.gray)) {
            act.push { back -> timeChainPage(act, "person", back) }
        }
        body.section(c.getString(R.string.tc_person), c.getString(R.string.tc_person_footer), *person.toTypedArray())
        body.section(c.getString(R.string.tc_wallet), c.getString(R.string.tc_wallet_footer),
            c.labeled(c.getString(R.string.tc_level_pi), place.toString() + " · π " + PiLevels.revealed(place)),   // USER-DATA: the level and π to it
            c.settingsRow(null, 0, c.getString(R.string.coin_levels)) { act.push { back -> timeChainPage(act, "pi", back) } },
            *chainRows(own).toTypedArray())
        val chats = chainRows(talk)
        if (chats.isNotEmpty()) body.section(c.getString(R.string.tc_talk), c.getString(R.string.tc_talk_footer), *chats.toTypedArray())
        // THE EXPLORER (iOS 1585-1594, the author's word 11.10.2026 20:2x MSK): the public page that reads a transfer's record from the
        // nodes and checks its signature
        body.section(null, c.getString(R.string.tc_explorer_footer), c.settingsRow(R.drawable.ic_search, MT.blue, c.getString(R.string.tc_explorer), chevron = false) {
            runCatching { c.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(CoinTx.EXPLORER))) }
        })
        // FOR AN OBSERVER (iOS 1595-1640): the frozen vectors this build holds -- the coin rules' own and the vault's keys; the
        // person's level and the top's key join them with their stages
        val hold = CoinTx.agrees && CoinVault.keyKAT()
        body.section(c.getString(R.string.tc_observer), c.getString(R.string.tc_observer_footer), c.hstack {
            setPadding(dp(16), dp(12), dp(16), dp(12))
            minimumHeight = dp(48)
            gravity = Gravity.CENTER_VERTICAL
            addView(c.text(c.getString(R.string.tc_vectors), 16f), lp(0, WRAP, 1f))
            addView(c.sealGlyph(hold, 20), lp(dp(20), dp(20)))
        })
    }
    fun readHeads() { headsAt = CoinBook.size(); TimeChain.heads { h -> heads = h; if (body.isAttachedToWindow) draw() } }
    val moved: () -> Unit = {
        if (!headsDue && CoinBook.size() != headsAt) {
            headsDue = true
            MainThread.later(3000, Runnable { headsDue = false; if (body.isAttachedToWindow) readHeads() })
        }
    }
    val page = walletFrame(act, c.getString(R.string.coin_timechain), onBack, false, null, body)
    // the person's seconds move the head's numbers (iOS @ObservedObject person): read again at most once a second
    var drawDue = false
    val personMoved: () -> Unit = { if (!drawDue) { drawDue = true; MainThread.later(1000, Runnable { drawDue = false; if (body.isAttachedToWindow) draw() }) } }
    body.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { CoinBook.listen(moved); PersonChain.listen(personMoved) }
        override fun onViewDetachedFromWindow(v: View) { CoinBook.unlisten(moved); PersonChain.unlisten(personMoved) }
    })
    draw()
    // the book read first, so its past is in the chains before their heads are read (one queue, in order)
    Thread { CoinBook.warm(); MainThread.post { readHeads() } }.start()
    return page
}

/**
 * TOP UP: EVERY ROAD OF THE COINS (iOS MTCoinTopUpSheet and MTCoinRules, MTWalletScreen.swift:1661-1706, the author's words 08.10.2026
 * «crystal clear» and 11.10.2026 20:2x MSK; App Review 2.3.1(a)): how coins come and how they go, each rule as the code keeps it,
 * and what the coins are not. Nothing here buys anything.
 */
fun coinTopUpPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    fun words(res: Int): View = c.text(c.getString(res), 16f).apply { setPadding(dp(16), dp(12), dp(16), dp(12)) }
    fun labelled(glyph: Int, res: Int): View = c.hstack {
        gravity = Gravity.TOP
        setPadding(dp(16), dp(12), dp(16), dp(12))
        addView(c.icon(glyph, MT.blue, 22), lp(dp(22), dp(22)).apply { marginEnd = dp(14); topMargin = dp(1) })
        addView(c.text(c.getString(res), 16f), lp(0, WRAP, 1f))
    }
    val n = PiLevels.multiplier(CoinBook.balance).toInt()
    body.section(c.getString(R.string.coin_rate_now), null,
        c.text(c.resources.getQuantityString(R.plurals.coin_second_rate, n, n), 16f).apply { fontFeatureSettings = "tnum"; setPadding(dp(16), dp(12), dp(16), dp(12)) },   // USER-DATA: the coins one second mints now
        words(R.string.coin_rule_level))
    body.section(c.getString(R.string.coin_rules_calls), null,
        labelled(R.drawable.ic_peer_phone, R.string.coin_rule_calls), words(R.string.coin_rule_calls_each), words(R.string.coin_rule_calls_total))
    body.section(c.getString(R.string.coin_rules_more), null,
        labelled(R.drawable.ic_hand_tap, R.string.coin_rule_tap), labelled(R.drawable.ic_arrow_circle_down, R.string.coin_rule_hold),
        labelled(R.drawable.ic_bar_chats, R.string.coin_rule_messages), labelled(R.drawable.ic_app_groups, R.string.coin_rule_groups),
        labelled(R.drawable.ic_hub, R.string.coin_rule_vpn))
    body.section(c.getString(R.string.coin_rules_games), null,
        labelled(R.drawable.ic_checkerboard, R.string.coin_rule_chess), labelled(R.drawable.ic_timer, R.string.coin_rule_timer),
        labelled(R.drawable.ic_person_2, R.string.coin_rule_people))
    body.section(c.getString(R.string.coin_rules_money), null, words(R.string.coin_rule_money))
    return walletFrame(act, c.getString(R.string.coin_top_up), onClose, true, null, body)
}

/**
 * THE FIRST IRREVERSIBLE WRITE ASKS THE PERSON (the owner's word 17.10.2026; Android's own, iOS opens the chain unasked): the chain's
 * GENESIS is the first record of this coin key in the network's public journal and can never be taken back. The dialog says what it
 * announces -- the book until the v2 cut, nothing after it -- and what the phone writes by itself once the chain is open. «Open» lets
 * the phone lay it now (CoinTx.allowGenesis) and goes on with `then`; «Not now» changes nothing.
 */
fun askGenesis(act: MainActivity, then: () -> Unit) {
    val now = CoinTx.mine?.now ?: (System.currentTimeMillis() / 1000)
    val before = now < CoinRules.V2_CUT
    val book = CoinBook.balance
    val shown = if (before) minOf(maxOf(0L, book), CoinRules.genesisCap) else maxOf(0L, book)
    AlertDialog.Builder(act)
        .setTitle(R.string.coin_genesis_title)
        .setMessage(act.getString(if (before) R.string.coin_genesis_body_before else R.string.coin_genesis_body_after, CoinText.count(shown), CoinBook.TICKER))
        .setPositiveButton(R.string.coin_genesis_open) { _, _ -> CoinTx.allowGenesis(); then() }
        .setNegativeButton(R.string.coin_genesis_later, null)
        .show()
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
                val can = n <= (if (CoinTx.WRITES) CoinSplit.available else CoinBook.balance)
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
        var going = false
        pressable {
            if (going) return@pressable   // one walk of the transfers at a time: a second tap sends nothing twice
            val to = picked.filter { 0L < coinsOf(it.value) }
            var sum = 0L
            for (f in to.values) sum += coinsOf(f)
            val available = if (CoinTx.WRITES) CoinSplit.available else CoinBook.balance
            if (to.isEmpty() || available < sum) {
                AlertDialog.Builder(act).setTitle(R.string.coin_not_enough).setMessage(R.string.coin_not_enough_sub).setPositiveButton(R.string.ok, null).show()
                return@pressable
            }
            if (CoinTx.WRITES) {
                // THE RECORDS ON THE NODES, ONE AFTER ANOTHER (iOS MTWalletScreen.send 2027-2066): each recipient's record laid and its
                // letter told, off the screen's thread; the page leaves when one went, and a record still waiting is said, never sent again
                val each = to.mapValues { coinsOf(it.value) }
                val walk = {
                    going = true; alpha = 0.4f
                    act.background {
                        val results = each.map { (ref, n) -> ref to CoinSend.transferResult(ref, n) }
                        act.onMain {
                            going = false; alpha = 1f
                            val went = results.filter { it.second is CoinSend.Transfer.Sent }.map { it.first }
                            val pending = results.any { it.second == CoinSend.Transfer.Pending }
                            if (pending) AlertDialog.Builder(act).setTitle(R.string.coin_pending_title).setMessage(R.string.coin_pending_sub).setPositiveButton(R.string.ok, null).show()
                            else if (went.isEmpty()) AlertDialog.Builder(act).setTitle(R.string.coin_not_enough).setMessage(R.string.coin_not_enough_sub).setPositiveButton(R.string.ok, null).show()
                            if (went.isEmpty()) return@onMain
                            close()
                            if (went.size == 1 && !pending) act.push { back -> conversationPage(act, went[0], back) }
                        }
                    }
                }
                // a chain not opened yet is opened first, by the person's own yes (askGenesis): the transfer's reconcile lays the GENESIS
                val m = CoinTx.mine
                if (m != null && !m.v3 && !CoinTx.genesisAllowedCached()) askGenesis(act) { walk() } else walk()
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

/**
 * A SPAN OF TIME AS THE SYSTEM WRITES IT (iOS Duration.formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated))):
 * the units that are not zero, abbreviated, in the person's language; nothing but «0 sec» for none.
 */
private fun spanWords(c: Context, seconds: Long): String {
    val s = maxOf(0L, seconds)
    val parts = listOf(s / 86_400 to android.icu.util.MeasureUnit.DAY, s % 86_400 / 3600 to android.icu.util.MeasureUnit.HOUR,
        s % 3600 / 60 to android.icu.util.MeasureUnit.MINUTE, s % 60 to android.icu.util.MeasureUnit.SECOND)
        .filter { it.first > 0 }.ifEmpty { listOf(0L to android.icu.util.MeasureUnit.SECOND) }
        .map { android.icu.util.Measure(it.first, it.second) }
    val locale = c.resources.configuration.locales[0]
    return android.icu.text.MeasureFormat.getInstance(locale, android.icu.text.MeasureFormat.FormatWidth.SHORT).formatMeasures(*parts.toTypedArray())
}
