package quest.montana.app

import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewTreeObserver
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ProgressBar
import java.util.Calendar
import java.util.Date

// ─────────────────────────── the coins' history pages (iOS MTWalletScreen: MTCoinHistoryPage, MTHistoryRow, MTCoinAnalyticsPage, MTHistoryCard, MTExplorerSheet; MontanaPeerInfoScreen: the transactions) ───────────────────────────

/** A page of lines at a time (iOS MTCoinHistoryPage.page): the history grows by it as it is read, never the whole book at the opening. */
private const val HISTORY_PAGE = 120

/** The coins signed as the history writes them (iOS (0 < signed ? "+" : "") + MTCoinText.count(signed)): a plus before the income,
 *  the count's own minus before the spending. */
private fun signedCoins(n: Long): String = (if (0 < n) "+" else "") + CoinText.count(n)

private fun historyLocale(c: Context) = c.resources.configuration.locales[0]
/** A moment's time on this phone's clock, as the panes write it (iOS .formatted(date: .omitted, time: .shortened)). */
private fun historyTime(c: Context, at: Double): String = android.text.format.DateFormat.getTimeFormat(c).format(Date((at * 1000).toLong()))
/** A moment's date and time (iOS .formatted(date: .abbreviated, time: .shortened)): the language's own order, the phone's 12 or 24 hours. */
private fun historyMoment(c: Context, at: Double): String {
    val loc = historyLocale(c)
    val skeleton = if (android.text.format.DateFormat.is24HourFormat(c)) "yMMMdHm" else "yMMMdhm"
    return java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(loc, skeleton), loc).format(Date((at * 1000).toLong()))
}
/** The start of a moment's day on this phone's clock, and of the day before it: by the calendar's own days, a day of 23 or 25 hours one day. */
private fun historyDayStart(ms: Long): Long = Calendar.getInstance().apply {
    timeInMillis = ms; set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
}.timeInMillis
private fun historyDayBefore(day: Long): Long = Calendar.getInstance().apply { timeInMillis = day; add(Calendar.DAY_OF_MONTH, -1) }.timeInMillis
/** A day's title over its operations (iOS MTCoinHistoryPage.dayTitle, MTWalletScreen.swift:869-874): «Today», «Yesterday», else the date in full. */
private fun historyDayTitle(c: Context, day: Long): String {
    val today = historyDayStart(System.currentTimeMillis())
    if (day == today) return c.getString(R.string.today)
    if (day == historyDayBefore(today)) return c.getString(R.string.gl_yesterday)
    return java.text.DateFormat.getDateInstance(java.text.DateFormat.LONG, historyLocale(c)).format(Date(day))   // USER-DATA: a day of the book
}
/** The day's one word over a pane's group (iOS MTDayLabel.of, MontanaMessageFeed.swift:602-620): «Today», «Yesterday», else the day and the month. */
private fun historyDayLabel(c: Context, at: Double): String {
    val ms = (at * 1000).toLong()
    val day = historyDayStart(ms)
    val today = historyDayStart(System.currentTimeMillis())
    if (day == today) return c.getString(R.string.today)
    if (day == historyDayBefore(today)) return c.getString(R.string.gl_yesterday)
    val loc = historyLocale(c)
    return java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(loc, "dMMMM"), loc).format(Date(ms))
}

/**
 * THE EXPLORER (iOS MTExplorerLink, MTExplorerSheet, MTWalletScreen.swift:1015-1025; the author's word 12.10.2026 13:1x MSK: «inside the
 * Explorer at once in the app»): iOS opens the record's page in the platform's own browser sheet over the app. Android has no such sheet
 * without AndroidX, so the page opens in the phone's browser, as every Explorer link of the app does (timeChainsPage).
 */
private fun openExplorer(act: MainActivity, url: String) {
    runCatching { act.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}

/** The platform's spinner on a row of its own while the fold is not ready (iOS ProgressView().frame(maxWidth: .infinity, minHeight: 44)). */
private fun Context.historyWait(): View = plate {
    addView(FrameLayout(context).apply {
        addView(ProgressBar(context).apply { indeterminateTintList = ColorStateList.valueOf(MT.gray) }, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
    }, lp(MATCH, dp(44)))
}

/** The list's chevron at a row that leads to a page (iOS NavigationLink in a List). */
private fun Context.historyChevron(): View = icon(R.drawable.ic_chevron_right, Color.rgb(89, 89, 89), 18)

/**
 * ONE LINE OF THE HISTORY (iOS MTHistoryRow, MTWalletScreen.swift:877-909): the glyph on its round of the thin material, who or what,
 * the category and the moment, the signed coins -- the whole row one target. A transfer opens its record in the Explorer; a move between
 * people the transaction's own page, the one a coin letter's bubble opens (coinMovePage); every other line its card. The two that lead
 * to a page of the app wear the list's chevron (iOS NavigationLink), the Explorer's none (iOS Button).
 */
private fun historyRow(act: MainActivity, l: CoinHistory.Line): View {
    val c: Context = act
    val tx = l.tx
    val move = l.source == "sent" || l.source == "received"
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(8), dp(14), dp(8))
        minimumHeight = dp(60)   // iOS frame(minHeight: 44) in the list row's own margins
        addView(FrameLayout(c).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(MT.withAlpha(Color.WHITE, 0.12f)) }   // iOS .thinMaterial in a Circle
            addView(c.icon(l.glyph, Color.WHITE, 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
        }, lp(dp(36), dp(36)))
        gap(12)
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(l.title, 17f).apply { singleLineEllipsis() }, lp())   // USER-DATA: who or what the operation was with
            // USER-DATA: the operation's category and its moment on this phone's clock
            addView(c.text(l.category + " · " + historyTime(c, l.at), 12f, MT.gray).apply { singleLineEllipsis(); setPadding(0, dp(2), 0, 0) }, lp())
        }, lp(0, WRAP, 1f))
        gap(8)
        // USER-DATA: the operation's coins, signed
        addView(c.text(signedCoins(l.signed), 17f, if (0 < l.signed) MT.green else Color.WHITE).apply { fontFeatureSettings = "tnum"; maxLines = 1 }, lp(WRAP, WRAP))
        if (tx == null) addView(c.historyChevron(), lp(dp(18), dp(18)).apply { marginStart = dp(6) })
        pressable {
            when {
                tx != null -> openExplorer(act, CoinTx.LINK + tx)
                move -> act.push { back -> coinMovePage(act, l.ref, l.signed < 0, l.title, back) }
                else -> act.push { back -> historyCardPage(act, l, back) }
            }
        }
    }
}

/** A day's operations on one plate of the list (iOS Section { rows } header: { the day's title, Spacer, the day's coins }); the list's
 *  separator starts under the words, past the glyph, as the platform's does under a row's first text. */
private fun LinearLayout.historyDay(act: MainActivity, d: CoinHistory.Day) {
    val c: Context = act
    addView(c.hstack {
        setPadding(dp(16), dp(22), dp(16), dp(6))
        addView(c.text(historyDayTitle(c, d.id), 13f, MT.gray).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
        addView(c.text(signedCoins(d.sum), 13f, MT.gray).apply { fontFeatureSettings = "tnum"; maxLines = 1 }, lp(WRAP, WRAP))   // USER-DATA: the day's coins, signed
    }, lp())
    addView(c.plate {
        d.lines.forEachIndexed { i, l ->
            if (0 < i) addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(64) })
            addView(historyRow(act, l), lp())
        }
    }, lp())
}

/** THE SEARCH OVER THE CONTACTS (iOS .searchable(text:prompt: «Search contacts»)): the platform's field on its tertiary fill, the
 *  magnifier and the prompt in grey, the words white -- the field the channel's pages draw for iOS .searchable. */
private fun Context.historySearch(onQuery: (String) -> Unit): View {
    val field = EditText(this).apply {
        hint = getString(R.string.ch_search_contacts)
        setTextColor(Color.WHITE)
        setHintTextColor(MT.gray)
        textSize = 17f
        background = null
        isSingleLine = true
        imeOptions = EditorInfo.IME_ACTION_SEARCH
        setPadding(0, dp(8), 0, dp(8))
        setOnEditorActionListener { v, _, _ -> v.context.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(v.windowToken, 0); true }
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: Editable?) { onQuery(s?.toString() ?: "") }
        })
    }
    return hstack {
        gravity = Gravity.CENTER_VERTICAL
        background = rounded(Color.argb(61, 118, 118, 128), 10)   // iOS .tertiarySystemFill (dark), the system's search field
        setPadding(dp(8), 0, dp(10), 0)
        addView(icon(R.drawable.ic_search, MT.gray, 18), lp(dp(18), dp(18)))
        gap(6)
        addView(field, lp(0, WRAP, 1f))
    }
}

/**
 * THE HISTORY OF OPERATIONS IN A BANK'S FORMAT (iOS MTCoinHistoryPage, MTWalletScreen.swift:800-875; the author's words 12.10.2026 13:1x
 * MSK: «the history of operations must look like this page in a bank's format, with separators by days, in the order of time, filters
 * by spending and income, with a search by contacts, and inside the Explorer at once in the app»; «the sum of a day's minting -- simply
 * one line for that day»; 15:2x: «at the history's opening the transactions open at once»): the search, the flow, then day after day,
 * newest first, each day with its own sum, a page of lines at a time that grows as it is read. Reads the one fold (CoinHistory).
 */
fun coinHistoryPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    var flow = CoinHistory.Flow.ALL
    var query = ""
    var limit = HISTORY_PAGE
    val lists = c.vstack(Gravity.NO_GRAVITY)
    var more: View? = null
    val seen = Rect()
    lateinit var grow: () -> Unit
    fun draw() {
        lists.removeAllViews()
        more = null
        if (CoinHistory.current() == null) { lists.addView(c.historyWait(), lp().apply { topMargin = c.dp(12) }); return }
        val shown = CoinHistory.shown(flow, query, limit)
        if (shown.days.isEmpty()) {
            lists.section(null, null, c.text(c.getString(R.string.ch_no_operations), 17f, MT.gray).apply {
                setPadding(dp(16), dp(12), dp(16), dp(12)); minHeight = dp(48); gravity = Gravity.CENTER_VERTICAL
            })
            return
        }
        for (d in shown.days) lists.historyDay(act, d)
        if (shown.more) {
            // THE PAGE GROWS AS IT IS READ (iOS 853-858): the next lines come when the last is near, never the whole book at the opening
            val m = c.historyWait()
            more = m
            lists.addView(m, lp().apply { topMargin = c.dp(12) })
            lists.post { grow() }
        }
    }
    grow = {
        val m = more
        if (m != null && m.isAttachedToWindow && m.getGlobalVisibleRect(seen)) { limit += HISTORY_PAGE; draw() }
    }
    val page = settingsPage(act, c.getString(R.string.coin_history), onBack) {
        addView(c.historySearch { q -> if (q != query) { query = q; limit = HISTORY_PAGE; draw() } }, lp().apply { topMargin = dp(8) })
        addView(segmented(c, CoinHistory.Flow.values().map { it.word to it.name }, flow.name) { v ->
            val f = CoinHistory.Flow.valueOf(v)
            if (f != flow) { flow = f; limit = HISTORY_PAGE; draw() }
        }.apply { contentDescription = c.getString(R.string.ch_operations) }, lp().apply { topMargin = dp(12) })   // iOS Picker("Operations", .segmented)
        addView(lists, lp())
    }
    draw()
    // the page reads the fold while it stands and hears every new one (iOS @ObservedObject, onAppear watch, onDisappear unwatch)
    val folded: () -> Unit = { draw() }
    val scrolled = ViewTreeObserver.OnScrollChangedListener { grow() }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) {
            CoinHistory.listen(folded); CoinHistory.watch(c)
            v.viewTreeObserver.addOnScrollChangedListener(scrolled)
            draw()
        }
        override fun onViewDetachedFromWindow(v: View) {
            CoinHistory.unlisten(folded); CoinHistory.unwatch()
            v.viewTreeObserver.takeIf { it.isAlive }?.removeOnScrollChangedListener(scrolled)
        }
    })
    return page
}

/** A month of the book in the phone's language (iOS Date.FormatStyle().month(.wide).year()). */
private fun analyticsMonth(c: Context, month: Long): String {
    val loc = historyLocale(c)
    return java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(loc, "MMMMy"), loc).format(Date(month))
}
/** A month as a chip (iOS MTCoinAnalyticsPage.chip, MTWalletScreen.swift:964-967): the platform's bordered capsule, 44 high -- the blue
 *  when chosen, the secondary colour otherwise. */
private fun Context.analyticsChip(words: String, on: Boolean, onTap: () -> Unit): View =
    text(words, 15f, if (on) MT.blue else MT.secondary, center = true).apply {
        background = rounded(MT.withAlpha(if (on) MT.blue else MT.gray, 0.2f), 22)
        setPadding(dp(24), 0, dp(24), 0)
        minHeight = dp(44)
        maxLines = 1
        pressable(onTap)
    }
/** One side of the period (iOS MTCoinAnalyticsPage.total, MTWalletScreen.swift:968-977): its word and glyph in the secondary colour, its
 *  coins in large bold type that narrows to fit, on the regular material of a rounded rectangle of 14. */
private fun Context.analyticsTotal(title: Int, coins: Long, glyph: Int): View = vstack(Gravity.NO_GRAVITY) {
    background = rounded(GLASS_TONE, 14)
    setPadding(dp(12), dp(12), dp(12), dp(12))
    minimumHeight = dp(68)   // iOS frame(minHeight: 44) and the padding of 12
    addView(hstack {
        addView(icon(glyph, MT.gray, 15), lp(dp(15), dp(15)))
        gap(6)
        addView(text(getString(title), 15f, MT.gray).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
    }, lp())
    // USER-DATA: the period's coins of this side
    addView(text(CoinText.count(coins), 20f, Color.WHITE, bold = true).apply {
        maxLines = 1; fontFeatureSettings = "tnum"
        setAutoSizeTextTypeUniformWithConfiguration(10, 20, 1, TypedValue.COMPLEX_UNIT_SP)   // iOS minimumScaleFactor(0.5)
    }, lp().apply { topMargin = dp(6) })
}
/** A source's share of the period (iOS MTCoinAnalyticsPage, MTWalletScreen.swift:943-956): its word, its coins signed, and the platform's
 *  linear progress of the coins it moved among all the period moved -- in the page's tint, the label colour of the wallet's stack. */
private fun Context.analyticsShare(a: CoinHistory.Share, moved: Long): View = vstack(Gravity.NO_GRAVITY) {
    setPadding(dp(16), dp(10), dp(16), dp(10))
    minimumHeight = dp(44)
    addView(hstack {
        addView(text(a.name, 15f).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: where the coins came from or went
        // USER-DATA: the coins of this source over the period, signed
        addView(text(signedCoins(a.signed), 15f, if (0 < a.signed) MT.green else Color.WHITE).apply { fontFeatureSettings = "tnum"; maxLines = 1 },
            lp(WRAP, WRAP).apply { marginStart = dp(8) })
    }, lp())
    addView(ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
        max = 1000
        progress = (a.moved.toDouble() / maxOf(1L, moved) * 1000).toInt().coerceIn(0, 1000)
        progressTintList = ColorStateList.valueOf(Color.WHITE)
    }, lp().apply { topMargin = dp(6) })
}

/**
 * THE ANALYTICS BY ITS OWN BUTTON (iOS MTCoinAnalyticsPage, MTWalletScreen.swift:911-978; the author's word 12.10.2026 15:2x MSK: «make
 * the analytics a separate button so it opens and nothing lags»): the months as chips, and every month; the spending and the income;
 * where the coins came from and went, each source with its share -- read from the one fold of the history (CoinHistory), never from
 * the book at the page's pass.
 */
fun coinAnalyticsPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    var month: Long? = null
    val chips = c.hstack()
    val roll = HorizontalScrollView(c).apply { isHorizontalScrollBarEnabled = false; addView(chips) }
    val totals = c.hstack()
    val rest = c.vstack(Gravity.NO_GRAVITY)
    fun draw() {
        val fold = CoinHistory.current()
        val m = month?.let { id -> fold?.months?.firstOrNull { it.id == id } } ?: fold?.whole
        val moved = CoinHistory.plus(m?.spending ?: 0L, m?.income ?: 0L)
        // THE MONTHS AS CHIPS (iOS 922-932): every month the book holds a move in, the newest first, and all of them; the row keeps its
        // place under the finger when a chip is chosen
        val x = roll.scrollX
        chips.removeAllViews()
        chips.addView(c.analyticsChip(c.getString(R.string.ch_every_month), month == null) { month = null; draw() }, lp(WRAP, WRAP))
        fold?.months?.forEach { mo ->
            // USER-DATA: a month of the book, in the phone's language
            chips.addView(c.analyticsChip(analyticsMonth(c, mo.id), month == mo.id) { month = mo.id; draw() }, lp(WRAP, WRAP).apply { marginStart = c.dp(8) })
        }
        roll.post { roll.scrollTo(x, 0) }
        totals.removeAllViews()
        totals.addView(c.analyticsTotal(R.string.ch_spending, m?.spending ?: 0L, R.drawable.ic_call_made), lp(0, WRAP, 1f))
        totals.gap(12)
        totals.addView(c.analyticsTotal(R.string.ch_income, m?.income ?: 0L, R.drawable.ic_call_received), lp(0, WRAP, 1f))
        rest.removeAllViews()
        if (fold == null) rest.addView(c.historyWait(), lp().apply { topMargin = c.dp(12) })
        val shares = m?.shares.orEmpty()
        if (shares.isNotEmpty()) rest.section(null, null, *shares.map { c.analyticsShare(it, moved) }.toTypedArray())
    }
    val page = settingsPage(act, c.getString(R.string.coin_analytics), onBack) {
        addView(roll, lp().apply { topMargin = dp(8) })
        addView(totals, lp().apply { topMargin = dp(12) })
        addView(rest, lp())
    }
    draw()
    val folded: () -> Unit = { draw() }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { CoinHistory.listen(folded); CoinHistory.watch(c); draw() }
        override fun onViewDetachedFromWindow(v: View) { CoinHistory.unlisten(folded); CoinHistory.unwatch() }
    })
    return page
}

/** A row with its value at the trailing edge (iOS LabeledContent), as the transaction's page draws it. */
private fun Context.historyValue(title: String, value: String): View = hstack {
    setPadding(dp(16), dp(12), dp(16), dp(12))
    minimumHeight = dp(48)
    addView(text(title, 16f), lp(0, WRAP, 1f))
    addView(text(value, 16f, MT.gray).apply { fontFeatureSettings = "tnum" }, lp(WRAP, WRAP).apply { marginStart = dp(8) })
}

/**
 * AN OPERATION'S OWN CARD (iOS MTHistoryCard, MTWalletScreen.swift:980-1013; the author's word 12.10.2026 13:1x MSK: «the analytics of
 * each operation»): what it was, with whom, how many coins and when; a day's minting says how many moves it folds. The person's own
 * coin chain opens in the Explorer while this run holds the coin key (CoinTx.cachedKeyTag, never derived here).
 */
fun historyCardPage(act: MainActivity, l: CoinHistory.Line, onBack: () -> Unit): View {
    val c: Context = act
    return settingsPage(act, c.getString(R.string.ch_operation), onBack) {
        val rows = mutableListOf(
            c.historyValue(c.getString(R.string.tc_amount), signedCoins(l.signed)),   // USER-DATA: the operation's coins, signed
            c.historyValue(c.getString(R.string.ch_kind), l.title),   // USER-DATA: who or what the operation was with
            c.historyValue(c.getString(R.string.ch_category), l.category),   // USER-DATA: the operation's category
            c.historyValue(c.getString(R.string.ch_when), historyMoment(c, l.at)))   // USER-DATA: the operation's moment on this phone's clock
        if (1 < l.count) rows += c.historyValue(c.getString(R.string.ch_operations), l.count.toString())   // USER-DATA: how many moves the line folds
        section(null, null, *rows.toTypedArray())
        CoinTx.cachedKeyTag?.let { from ->
            section(null, c.getString(R.string.ch_key_chain_footer), c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(10), dp(16), dp(10))
                minimumHeight = dp(48)
                addView(c.icon(R.drawable.ic_search, Color.WHITE, 22), lp(dp(22), dp(22)).apply { marginEnd = dp(14) })
                addView(c.text(c.getString(R.string.ch_open_explorer), 17f), lp(0, WRAP, 1f))
                pressable { openExplorer(act, CoinTx.EXPLORER + "#key=" + from) }   // iOS MTCoinTx.keyLink: the key's whole chain
            })
        }
    }
}

/** A transfer on the bar's own glass (iOS MontanaPeerInfoScreen.glassRow, MontanaPeerInfoScreen.swift:876-890): the square plate with
 *  the glyph, the long plate with the move's kind and its moment, the coins signed at its end -- the rows the pane's files and voices wear. */
private fun Context.transferRow(l: CoinHistory.Line, onTap: () -> Unit): View = hstack {
    gravity = Gravity.CENTER_VERTICAL
    addView(FrameLayout(context).apply {
        background = glassPlate().apply { cornerRadius = dp(16).toFloat() }
        addView(icon(l.glyph, MT.barGlyph), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
    }, lp(dp(56), dp(56)).apply { marginEnd = dp(10) })
    addView(hstack {
        gravity = Gravity.CENTER_VERTICAL
        background = glassPlate().apply { cornerRadius = dp(16).toFloat() }
        setPadding(dp(14), 0, dp(14), 0)
        addView(vstack(Gravity.NO_GRAVITY) {
            addView(text(l.category, 16f).apply { singleLineEllipsis() })   // USER-DATA: the move's kind -- coins sent or received -- in the person's language
            addView(text(historyTime(context, l.at), 12f, MT.gray))   // USER-DATA: the move's moment on this phone's clock
        }, lp(0, WRAP, 1f))
        // USER-DATA: the move's coins, signed
        addView(text(signedCoins(l.signed), 17f, if (0 < l.signed) MT.green else Color.WHITE).apply { fontFeatureSettings = "tnum"; maxLines = 1 },
            lp(WRAP, WRAP).apply { marginStart = dp(8) })
    }, lp(0, dp(56), 1f))
    pressable(onTap)
}

/**
 * THE TRANSFERS WITH THIS PERSON (iOS MontanaPeerInfoScreen.transactions, MontanaPeerInfoScreen.swift:817-874; the author's word 12.10.2026
 * 15:2x MSK: «on the correspondent's page add after the wall a section of transactions, to see only what was sent to and received from
 * the correspondent»): the coins sent to them and received from them under every conversation of the pair (SamePair), newest first,
 * cut by day as every pane is, each on the bar's own glass; a transfer opens its record in the Explorer, a coin letter its
 * transaction's page. Read from the one fold of the coins (CoinHistory), never from the book here.
 */
fun transactionsPane(act: MainActivity, ref: String, name: String, into: LinearLayout, empty: () -> View) {
    val c: Context = act
    if (CoinHistory.current() == null) {
        into.addView(FrameLayout(c).apply {
            setPadding(0, c.dp(36), 0, c.dp(36))
            addView(ProgressBar(c).apply { indeterminateTintList = ColorStateList.valueOf(MT.gray) }, FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
        }, lp())
        return
    }
    val lines = CoinHistory.with((SamePair.folded(ref) + ref).filter { it.isNotEmpty() }.toSet())
    if (lines.isEmpty()) { into.addView(empty(), lp()); return }
    var day: String? = null
    for (l in lines) {
        val d = historyDayLabel(c, l.at)
        if (d != day) { day = d; into.addView(c.text(d, 12f, MT.gray), lp().apply { topMargin = c.dp(14); bottomMargin = c.dp(6) }) }   // USER-DATA: the day's word
        into.addView(c.transferRow(l) {
            val tx = l.tx
            if (tx != null) openExplorer(act, CoinTx.LINK + tx)
            else act.push { back -> coinMovePage(act, l.ref, l.signed < 0, name, back) }
        }, lp().apply { bottomMargin = c.dp(8) })
    }
}
