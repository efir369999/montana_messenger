package quest.montana.app

import android.content.Context
import android.graphics.Color
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import org.json.JSONObject

/**
 * THE LIVE DRAFT (iOS E2E.sendDraftWord / handleMeshDraft, LiveDraftBubble): the words in my field appear on their screen as
 * I type them — a grey bubble at the feed's foot with the caret where I hold it — and theirs on mine. The word is
 * «⁣mtdraft:» + base64 {t, c, n[, rm][, ck]}: the text, the caret, the moment it was said (strictly growing), the letter it
 * answers, «ck» for a checkpoint of a closing chat. It rides the signal lane (at most four a second, the ending always);
 * an empty text is the ending. «Live chat» in Privacy (liveTypingEnabled) silences my words and hides theirs.
 */
object LiveDraft {
    const val MARK = "⁣mtdraft:"
    class Draft(val text: String, val caret: Int, val replyMid: String)

    private val said = HashMap<String, String>()        // the last text of mine standing on their screen
    private val sentAt = HashMap<String, Long>()
    private val pending = HashMap<String, Runnable>()
    private val heardAt = HashMap<String, Long>()       // the moment of the newest word of theirs shown
    private val shown = HashMap<String, Draft>()
    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private val on get() = Prefs.bool("liveTypingEnabled", true)
    private val h = android.os.Handler(android.os.Looper.getMainLooper())
    private var lastStamp = 0L
    /** The moment a word was said, strictly growing (iOS draftStamp): two words in one millisecond keep their order. */
    // ONE COUNTER FOR EVERY WORD THIS PHONE SAYS, BY THE NODE'S CLOCK (iOS draftStamp, E2E 1013): the draft's «n» and the presence «T» in one row
    private fun stamp(): Long = Presence.saidMs()

    // ── what I say ──
    /** «d» — the doors alive for me, in the one builder of the word (iOS sendDraftWord 474-475): the peer picks the first we share. */
    private fun doors(body: JSONObject) = body.apply { Signal.aliveHosts().joinToString(",").takeIf { it.isNotEmpty() }?.let { put("d", it) } }
    /** The field as it stands; an empty text ends the draft (and is always said, whatever the switch). */
    fun say(ref: String, text: String, caret: Int = -1, replyMid: String = "", checkpoint: Boolean = false) {
        val ending = text.isEmpty()
        if (!ending && !on) return
        if (PeerSafety.isBlocked(ref)) return
        if (!checkpoint && said[ref] == text) return        // the wire already says exactly this
        if (ending && said[ref] == null) return              // nothing of mine stands there
        said[ref] = text
        pending.remove(ref)?.let { h.removeCallbacks(it) }
        val now = System.currentTimeMillis()
        val due = 250 - (now - (sentAt[ref] ?: 0))
        val speak = Runnable {
            sentAt[ref] = System.currentTimeMillis(); pending.remove(ref)
            val body = doors(JSONObject().put("t", text).put("c", caret).put("n", stamp()))
            if (replyMid.isNotEmpty()) body.put("rm", replyMid)
            if (checkpoint) body.put("ck", 1)
            Signal.post(ref, MARK + Base64.encodeToString(body.toString().toByteArray(), Base64.NO_WRAP))
            if (ending) said.remove(ref)
        }
        // four a second fit the node's window; the ending is never held back
        if (ending || due <= 0) speak.run() else { pending[ref] = speak; h.postDelayed(speak, due) }
    }

    // ── the daily links (iOS sendLinkWord, askLinkWord) ──
    private val linkSaidAt = HashMap<String, Long>()
    /**
     * OUR DAILY LINK TO A CORRESPONDENT (iOS sendLinkWord), so they can introduce us to a friend the way they share their own
     * code: said when a chat is opened, at most once a correspondence per six hours (the link lives a day), and at their ask at
     * once. It rides the draft word with the words of mine already standing there — an empty text would end a draft.
     */
    fun sayLink(ref: String, force: Boolean = false) {
        if (PeerSafety.isBlocked(ref) || Book.secret(ref) == null) return
        if (!force && System.currentTimeMillis() - (linkSaidAt[ref] ?: 0L) < 6 * 3600_000L) return
        val (link, born) = MontanaCard.currentShortWithBorn(Book.ctx) ?: return
        linkSaidAt[ref] = System.currentTimeMillis()
        val body = doors(JSONObject().put("t", said[ref] ?: "").put("c", -1).put("n", stamp()).put("rl", link).put("rb", born))
        Signal.post(ref, MARK + Base64.encodeToString(body.toString().toByteArray(), Base64.NO_WRAP))
    }
    /** «Hand me your link» (iOS askLinkWord, share contact): a peer of this build answers with its link at once. */
    fun askLink(ref: String) {
        if (Book.secret(ref) == null) return
        val body = doors(JSONObject().put("t", said[ref] ?: "").put("c", -1).put("n", stamp()).put("rq", 1))
        Signal.post(ref, MARK + Base64.encodeToString(body.toString().toByteArray(), Base64.NO_WRAP))
    }
    /**
     * THE DAILY LINK, PRELOADED (iOS E2E.sendLinkIfNeeded, MontanaE2E.swift:1467-1478; the author's word 15.09: share contact
     * must not wait): my current short link rides to a correspondent as a silent durable letter — the draft word's shape, by
     * the queue, not the live lanes (iOS sendDraftWord durable, 478-482) — once per link per peer; the receiver keeps it a day.
     */
    fun sayLinkIfNeeded(ref: String) {
        if (PeerSafety.isBlocked(ref) || Book.secret(ref) == null) return
        val (link, born) = MontanaCard.currentShortWithBorn(Book.ctx) ?: return
        val key = "linkSent." + ref
        if (Prefs.str(key, "") == link) return
        Prefs.setStr(key, link)
        val body = doors(JSONObject().put("t", said[ref] ?: "").put("c", -1).put("n", stamp()).put("rl", link).put("rb", born))
        Post.send(ref, Marks.mintMid(), MARK + Base64.encodeToString(body.toString().toByteArray(), Base64.NO_WRAP), quiet = true)
        android.util.Log.d("Montana", "link_tx durable to=" + ref.take(10))
    }
    /** Every correspondent gets the current link — launch, foreground, rotation; nothing if they have it (iOS sendLinkToAll 1479-1482). */
    fun sayLinkToAll() { for (ref in Book.refs()) sayLinkIfNeeded(ref) }

    // ── what I hear ──
    /** A draft word of theirs off the lane. true — a keystroke said now (it lights «typing…»). */
    fun hear(ref: String, word: String): Boolean {
        val j = runCatching { JSONObject(String(Base64.decode(word.removePrefix(MARK), Base64.DEFAULT), Charsets.UTF_8)) }.getOrNull() ?: return false
        j.optString("d").takeIf { it.isNotEmpty() }?.let { Signal.notePeerDoor(ref, it) }   // the doors they ask (iOS handleMeshDraft 1032)
        val n = j.optLong("n", 0)
        if (n > 0) { if (n <= (heardAt[ref] ?: 0)) return false; heardAt[ref] = n }   // an older word is an echo of the road
        // THEIR DAILY LINK, handed to us to hand on (iOS MTPeerLinks.note); their ask for mine is answered at once (iOS rq)
        j.optString("rl").takeIf { Meeting.invite(it) != null }?.let { PeerLinks.note(ref, it, j.optDouble("rb", System.currentTimeMillis() / 1000.0)) }
        if (j.optInt("rq") == 1) MainThread.post { sayLink(ref, force = true) }
        val state = j.has("rl") || j.has("rq") || j.has("ab") || j.has("al")   // a word of state, never a keystroke (iOS draftStateKeys)
        if (!on) return false
        val text = j.optString("t")
        // WORDS THAT ALREADY BECAME A LETTER ARE NOT A DRAFT (iOS draft_ghost): a word equal to a letter of theirs just landed
        val landed = text.isNotEmpty() && Book.chat(SamePair.root(ref))?.msgs?.takeLast(5)?.any { !it.mine && it.text == text } == true
        if (text.isEmpty() || landed) shown.remove(ref) else shown[ref] = Draft(text, j.optInt("c", -1), j.optString("rm"))
        changed()
        val fresh = n == 0L || NodeClock.now() - n <= 7_000   // the draft's «n» is the node's already (iOS 1087: nodeNow - n <= typingWordLife)
        return text.isNotEmpty() && !landed && !j.has("ck") && !state && fresh
    }
    fun of(ref: String): Draft? = shown[ref]
}

/**
 * THE DAILY LINKS OUR CORRESPONDENTS HANDED US (iOS MTPeerLinks): each with the moment it was born; a link is shown only while
 * its day runs, rather than hand a friend a code that answers «spent».
 */
object PeerLinks {
    private const val KEY = "peerRdvLinks"
    private fun all(): JSONObject = DeviceVault.get(KEY)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONObject()
    @Synchronized fun note(ref: String, link: String, born: Double) {
        DeviceVault.set(KEY, all().put(ref, JSONObject().put("l", link).put("b", born)).toString().toByteArray(Charsets.UTF_8))
        android.util.Log.d("Montana", "link_rx from=" + ref.take(10))
    }
    /** The link, while its day runs. */
    fun fresh(ref: String): String? = all().optJSONObject(ref)
        ?.takeIf { System.currentTimeMillis() / 1000.0 - it.optDouble("b", 0.0) < 24 * 3600 }?.optString("l")?.ifEmpty { null }
    /** The last link they handed, whatever its day: the face their card wears on the node outlives the card's day (iOS
     * MTPeerLinks.any, MontanaE2E.swift:61, atom 796a76a34ae0). */
    fun any(ref: String): String? = all().optJSONObject(ref)?.optString("l")?.ifEmpty { null }
    fun wipe() = DeviceVault.delete(KEY)
    /** The links and the moments they were born, for a copy (iOS MTPeerLinks, MontanaE2E.swift 46-57: two sealed maps by conversation, «peerRdvLinks» and «.b»). */
    fun carried(): Pair<Map<String, String>, Map<String, Double>> {
        val o = all()
        val links = HashMap<String, String>()
        val born = HashMap<String, Double>()
        for (r in o.keys()) o.optJSONObject(r)?.let { e -> e.optString("l").takeIf { it.isNotEmpty() }?.let { links[r] = it; born[r] = e.optDouble("b", 0.0) } }
        return links to born
    }
    /** A copy laid (iOS SeedScope.unionKeys 6311): a correspondent's link held here stands, the copy adds the others. */
    @Synchronized fun lay(links: Map<String, String>, born: Map<String, Double>) {
        val o = all()
        for ((r, l) in links) if (l.isNotEmpty() && !o.has(r)) o.put(r, JSONObject().put("l", l).put("b", born[r] ?: 0.0))
        DeviceVault.set(KEY, o.toString().toByteArray(Charsets.UTF_8))
    }
}

/**
 * THEIR WORDS AS THEY TYPE THEM (iOS LiveDraftBubble): the correspondent's side, a grey bubble without a tail, the caret
 * «│» exactly where they hold it; the quote of the letter they answer above the words.
 */
fun Context.liveDraftBubble(d: LiveDraft.Draft, chat: Chat?): View = FrameLayout(this).apply {
    val caret = if (d.caret < 0 || d.caret > d.text.length) d.text.length else d.caret
    addView(vstack(Gravity.NO_GRAVITY) {
        background = rounded(Color.rgb(33, 33, 33), 17, Color.argb(90, 255, 255, 255))   // iOS: grey 0.13 with a light rim, no tail
        setPadding(dp(13), dp(8), dp(13), dp(8))
        if (d.replyMid.isNotEmpty()) chat?.msgs?.find { it.mid == d.replyMid }?.let { q ->
            addView(hstack {
                addView(View(context).apply { setBackgroundColor(Color.WHITE) }, lp(dp(3), dp(16)).apply { marginEnd = dp(6) })
                addView(text(letterWords(context, q), 12f, Color.argb(180, 255, 255, 255)).apply { maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END })   // USER-DATA
            }, lp().apply { bottomMargin = dp(2) })
        }
        addView(text(d.text.substring(0, caret) + "│" + d.text.substring(caret), 17f, Color.WHITE).apply { maxWidth = dp(260) })   // USER-DATA: their draft
    }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.START))
}
