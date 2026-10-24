package quest.montana.app

import android.content.Context
import android.graphics.Color
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.EditText
import org.json.JSONObject

// ─────────────────────────── the Money Flow's auto-reactions (iOS MTWalletScreen: MTAutoReactPage; MTWalletCore: MTAutoReact) ───────────────────────────

/**
 * AUTO-REACTIONS OF CHOSEN PEOPLE (iOS MTAutoReact, MTWalletCore.swift:3227-3256; the author's word 06.10.2026 17:3x MSK: «in the Money
 * Flow's settings, on a long press, open a page where I choose whom and how much I want to auto-react to, from my contacts»): a person
 * chosen with a number of coins is paid that many on every letter of theirs born after the choice, within a day of its birth, by the
 * paid reaction's own road (CoinSend.autoGive) -- once a letter, whichever door brings it. A short balance pays nothing and the letter
 * stands as any other.
 */
object AutoReact {
    private const val PREFIX = "autoReact."   // NOT-UI: iOS MTAutoReact.prefix, a conversation's own rule
    /** A letter is fresh for a day from its birth: only such a letter is paid (iOS MTCoinSend.fresh). */
    private const val FRESH_S = 86_400.0
    class Rule(val coins: Long, val since: Double)
    fun rule(conv: String): Rule? {
        val o = runCatching { JSONObject(Prefs.str(PREFIX + conv, "")) }.getOrNull() ?: return null
        val c = o.optLong("c")   // NOT-UI: the rule's keys, as iOS keeps them
        return if (0 < c && o.has("s")) Rule(c, o.getDouble("s")) else null
    }
    /** The coins a person's every new letter is paid; nought lets the person go. The moment of the first choice stays while the number
     *  changes, so a letter between two edits is paid by the rule that stood. */
    fun set(conv: String, coins: Long) {
        if (coins <= 0) { Prefs.setStr(PREFIX + conv, ""); return }
        val since = rule(conv)?.since ?: (System.currentTimeMillis() / 1000.0)
        Prefs.setStr(PREFIX + conv, JSONObject().put("c", coins).put("s", since).toString())
    }
    /**
     * A LETTER OF THE PAIR LANDED (iOS landed, beside a coin letter's credit): a chosen person's fresh letter is paid -- never a coin
     * letter, a chess step or a row of the phone's own, never a letter born before the choice or more than a day ago.
     */
    fun landed(chat: String, mid: String, text: String) {
        val r = rule(chat) ?: return
        if (CoinLetter.parse(text) != null || ChessLetter.parse(text) != null || ChatMint.ownRow(text)) return
        val born = (Marks.birthMs(mid) ?: return) / 1000.0
        if (born < r.since || FRESH_S < System.currentTimeMillis() / 1000.0 - born || !CoinSend.canPay(chat)) return
        val paid = CoinSend.autoGive(r.coins, mid, text, chat)
        Log.d("Montana", "auto_react coins=" + r.coins + " paid=" + (if (paid) 1 else 0))
        if (paid) { val ls = synchronized(paidListeners) { paidListeners.toList() }; MainThread.post { ls.forEach { it(r.coins, chat) } } }
    }

    /** THE COINS I PAID, SEEN IN THE CHAT (iOS MTCoinPaid, MTWalletCore.swift:3258-3272): an auto-reaction's coins and the chat they were
     *  paid in, told to that chat's red minus (MTPayPop); on the screen's thread. */
    private val paidListeners = mutableListOf<(Long, String) -> Unit>()
    fun listenPaid(l: (Long, String) -> Unit) { synchronized(paidListeners) { paidListeners.add(l) } }
    fun unlistenPaid(l: (Long, String) -> Unit) { synchronized(paidListeners) { paidListeners.remove(l) } }
}

/**
 * WHOM THE COINS GO TO BY THEMSELVES (iOS MTAutoReactPage, MTWalletScreen.swift:2066-2120): the person's chats that coins may go to,
 * each with the coins its every new letter is paid, typed beside the face and the name; an emptied field lets the person go. What is
 * typed stands at once. Opened by a hold on the Money Flow's coin.
 */
fun autoReactPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val chats = listedChats().filter { CoinSend.canPay(it.ref) }
    return settingsPage(act, c.getString(R.string.ar_title), onClose, cross = true) {
        val rows = if (chats.isEmpty()) listOf(c.text(c.getString(R.string.no_chats), 17f, MT.gray).apply {
            setPadding(dp(16), dp(12), dp(16), dp(12)); minHeight = dp(48); gravity = Gravity.CENTER_VERTICAL
        }) else chats.map { ch ->
            c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(8), dp(16), dp(8))
                minimumHeight = dp(60)
                // iOS MontanaChatFace: the face of 40, twelve away the name in body type, the glyph the face already shows left out
                addView(c.peerFace(ch.ref, ch.shown, 40), lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
                addView(c.text(spokenName(ch.shown.ifBlank { c.getString(R.string.peer) }), 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the person's name
                // the system's rounded field of coins, the digits at the trailing edge (iOS TextField .roundedBorder, 96 by 44, numberPad)
                addView(EditText(c).apply {
                    hint = "0"
                    setHintTextColor(MT.gray); setTextColor(Color.WHITE)
                    textSize = 17f
                    fontFeatureSettings = "tnum"
                    gravity = Gravity.END or Gravity.CENTER_VERTICAL
                    inputType = InputType.TYPE_CLASS_NUMBER
                    isSingleLine = true
                    background = c.rounded(Color.rgb(28, 28, 30), 6, Color.argb(64, 255, 255, 255))
                    setPadding(dp(8), 0, dp(8), 0)
                    AutoReact.rule(ch.ref)?.let { setText(it.coins.toString()) }   // USER-DATA: the coins chosen for this person
                    addTextChangedListener(object : TextWatcher {
                        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                        override fun afterTextChanged(s: Editable?) {
                            val digits = (s?.toString() ?: "").filter { it.isDigit() }.take(12)
                            AutoReact.set(ch.ref, digits.toLongOrNull() ?: 0L)
                        }
                    })
                }, lp(dp(96), dp(44)).apply { marginStart = dp(12) })
            } as View
        }
        section(c.getString(R.string.ar_header), c.getString(R.string.ar_footer), *rows.toTypedArray())
    }
}
