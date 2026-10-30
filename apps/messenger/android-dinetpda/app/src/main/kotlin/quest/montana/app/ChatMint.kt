package quest.montana.app

import android.util.Log

/**
 * THE LETTERS THAT EARN (iOS MTChatMint, MTWalletCore.swift:155-302; MTCoinSend.mintLetter, 3046-3055). Every letter of a pair's own
 * conversation -- mine or my correspondent's, words or media -- mints the level's coins on this phone once by its wire name, whatever
 * the chat's Money Flow (the author's word 11.10.2026 21:2x MSK); the correspondent's phone mints its own for the same letter. A group's
 * or a channel's letter earns while its feed is open when its bubble holds words alone, more than thirteen characters with the spaces,
 * and its coins stand in that conversation's own chain. Only letters born since this phone's coin came on (the first walk turns it on),
 * and only once the seed's book was heard -- a phone opened by its words pays nothing again before the vault answered, so a letter
 * waits and is paid by the book that already holds it. A name earns once ever: the book keeps it («earn:» and the name).
 */
object ChatMint {
    private const val SINCE_KEY = "chatCoinSince"   // NOT-UI: iOS sinceKey, the seconds the coin came on; zero while off
    /** A walk from the newest letter stops this far before the coin's moment: a long chat costs only the letters born since. */
    private const val MARGIN_S = 600.0
    /** A group's and a channel's letter earns past this many characters (iOS groupLetterFloor). */
    const val GROUP_FLOOR = 13

    private fun since(): Double = Prefs.str(SINCE_KEY, "").toDoubleOrNull() ?: 0.0
    /** The coin switched on or off: the letters born from now on earn while it stays on (iOS turned). */
    fun turned(on: Boolean) = Prefs.setStr(SINCE_KEY, if (on) (System.currentTimeMillis() / 1000.0).toString() else "0")

    /**
     * A row of the phone's own, never a letter (iOS MTRowLetter.ownRow and the service mark): a call's row, a missed call's, a group's
     * event, the Money Flow's row -- a word of the wire. A media letter, a voice, a sticker and a long letter wear a mark and are letters.
     */
    internal fun ownRow(text: String): Boolean = Marks.isService(text) && !text.startsWith(Marks.MEDIA) && !text.startsWith(Marks.VOICE)
        && !text.startsWith(Marks.STICKER) && !text.startsWith(Marks.LONG)
    /** A bubble of words alone: no file, sticker, coin letter or chess step, no row of the phone's own (iOS isText). */
    private fun isText(text: String): Boolean = !Marks.isService(text) && CoinLetter.parse(text) == null && ChessLetter.parse(text) == null

    /**
     * The letters of a chat, oldest first as the book keeps them (iOS credit): a pair's mints every bubble its level's coins
     * (oneEach), a group's or a channel's passes the floor and names its conversation. The coins it minted.
     */
    fun credit(letters: List<Msg>, floor: Int? = null, key: String? = null): Long {
        if (!CoinVault.heard) return 0
        var since = since()
        if (since == 0.0) { turned(true); since = since() }   // a coin never turned on earns from this moment
        var paid = 0L
        var names = 0
        for (m in letters.asReversed()) {
            if (m.at / 1000.0 < since - MARGIN_S) break
            val name = CoinSend.wire(m.mid)
            if (floor != null && (characters(m.text) <= floor || !isText(m.text) || m.file != null)) continue
            // a coin letter, a chess step and a row of the phone's own mint nothing (iOS oneEach); a transfer's telling letter is the payment's
            if (CoinLetter.parse(m.text) != null || ChessLetter.parse(m.text) != null || WallCard.of(m.text) != null) continue
            if (m.text.contains(CoinTx.LINK) || ownRow(m.text) || !CoinSend.wireName(name)) continue
            val born = Marks.birthMs(m.mid) ?: continue
            if (born / 1000.0 < since || CoinBook.holds(CoinEntry.EARN, name)) continue
            val c = CoinBook.mint(PiLevels.multiplier(CoinBook.balance), name, key)
            if (0 < c) { paid += c; names++ }
        }
        if (0 < names) {
            Log.d("Montana", "chat_coin earned=$names paid=$paid" + (if (key != null) " group" else ""))
            val ls = synchronized(listeners) { listeners.toList() }
            MainThread.post { ls.forEach { it(paid) } }
        }
        return paid
    }

    /** EVERY MINTING IS SEEN (iOS MTChatMint.minted and lastBatch, MTWalletCore.swift:178-183): the coins the newest letters minted, told
     *  to the open ribbon's «+N» (MTMintPop); on the screen's thread. */
    private val listeners = mutableListOf<(Long) -> Unit>()
    fun listen(l: (Long) -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: (Long) -> Unit) { synchronized(listeners) { listeners.remove(l) } }

    /** The characters a person sees, spaces included (iOS String.count: one emoji of many points is one). */
    private fun characters(s: String): Int {
        val b = android.icu.text.BreakIterator.getCharacterInstance()
        b.setText(s)
        var n = 0
        while (b.next() != android.icu.text.BreakIterator.DONE) n++
        return n
    }

    /** One walk at a time, off the screen's thread: the letters land and the chats change faster than a walk takes. */
    private val q = java.util.concurrent.Executors.newSingleThreadExecutor()
    /** A pair's chat as it stands (iOS mintLetter and the open chat's every change): its letters born since the coin came on. */
    fun pair(ref: String) = q.execute {
        if (Groups.isKey(ref) || ref.startsWith("arc:") || Book.secret(ref) == null) return@execute
        Book.chat(ref)?.msgs?.toList()?.let { runCatching { credit(it) }.onFailure { e -> Log.w("Montana", "chat_coin " + e.javaClass.simpleName) } }
    }
    /** A group's or a channel's feed while it is open (iOS groupMints): each letter past the floor, in its own chain. */
    fun group(key: String) = q.execute {
        if (!Groups.isKey(key)) return@execute
        Book.chat(key)?.msgs?.toList()?.let { runCatching { credit(it, floor = GROUP_FLOOR, key = key) } }
    }
    /** THE BOOK WAS HEARD (iOS MTCoinVault.gather, MTWalletCore.swift:1130-1136): every pair's letters that landed before it mint now. */
    fun sweepPairs() { for (ref in Book.refs()) pair(ref) }
}
