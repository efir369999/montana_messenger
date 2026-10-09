package quest.montana.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.ToneGenerator
import android.media.RingtoneManager
import android.os.Build
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.widget.LinearLayout
import org.json.JSONArray
import org.json.JSONObject
import org.webrtc.IceCandidate
import java.security.SecureRandom
import java.util.Date
import java.util.Locale

/**
 * THE CALL MACHINE, ITS FIRST HALF (iOS MontanaCall; the map is docs/calls.md). A call of the iPhone is heard here — by its
 * ring letter in the box (RG) or by its words on the node's lane — and rings as the system's call (iOS CallKit; here the
 * call's own notification). The caller is told «ringing», a decline is told «call-end», a call that ends unanswered leaves its
 * row, and the caller's «missed» letter (MC) lays the row of a call this phone never saw. «Answer» hands the offer to the
 * voice (CallLine) and the call stands as the system's ongoing call (CallService) until either side ends it.
 */
object Calls {
    const val LIFE_MS = 90_000L   // iOS callLifeS: the ring, the age of an offer, the life of a call letter — one number
    const val EXTRA_REF = "montana.call.ref"
    const val EXTRA_ANSWER = "montana.call.answer"
    private const val CHANNEL = "calls"
    private const val NOTE = 0x4d43   // one incoming call stands on the screen at a time
    private const val SEEDS = "callSeeds"   // seed -> {st, at}: «alive» rang here, «dead» is over (iOS MontanaMissedCall's book, burySeed)

    private class Ring(val ref: String, val seed: String, val video: Boolean, val out: Boolean = false,
                       val startedAt: Long = System.currentTimeMillis()) {   // iOS startedAt: this call's own birth by this device's clock (the critic's youngerThanOurs, 24.09, build 1500771e4d2b)
        var rejoins = 0   // runs that went back into this call and died before its new connection stood (iOS HeldCall.rejoins)
        var offer: String? = null   // incoming: the caller's description, kept for the answer; outgoing: ours, said until it rings
        var answered = false   // incoming: this person answered; outgoing: the far phone did
        var line = false   // the voice was handed its offer
        var ringing = false   // outgoing: the far phone said «call-ringing»
        var refused = false   // the system would not stand this call as its own (iOS callkit-refused/callkit-reset, builds 7492b6b28754/3811dfa0a06f): its own miss rides silent
        var answeredAt = 0L   // iOS answeredAt: the answering hand -- the callee's tap, the caller's received answer
        // THE RING'S LEDGER (iOS 608-611, the author's word 13.09: our part is concrete, the rest is the far side's, and the
        // diary says whose): knocks made, knocks a door rang a phone with, the seconds of the first and the last of those,
        // whether every door said «nobody», whether the second bell rang
        var knockN = 0; var knockOk = 0; var firstOkS = -1; var lastOkS = -1; var nobody = false; var bell = false
    }
    private var tone: ToneGenerator? = null
    private val gate = Any()
    private var ring: Ring? = null

    /** iOS callEpoch: the call's name on every word is its seed's first sixteen letters. */
    fun epochOf(seed: String) = seed.take(16)

    // ── what the iPhone says ──

    /** iOS ChatStore ringMark: a call letter raises the incoming call; its age and the graveyard cut the stale; no row. */
    fun ringLetter(ref: String, json: String) {
        val o = runCatching { JSONObject(json) }.getOrNull() ?: return
        val t = (o.optDouble("t", 0.0) * 1000).toLong()
        if (t > 0 && NodeClock.now() - t > LIFE_MS) return log("ring letter stale")   // the age by the node's clock on both ends (iOS 3996, K-11)
        if (t > 0) log("ring letter age=" + (NodeClock.now() - t) + " ms")   // how long the call took to reach this phone
        incoming(ref, o.optString("s"), o.optBoolean("v"), o.optString("n"), null, t)
    }

    /** The words of a call on the node's lane (iOS handleMeshCallSignal, handleSignal): its birth, and the end of a ring here. */
    fun hear(ref: String, epoch: String, payload: ByteArray) {
        val words = runCatching { JSONArray(String(payload, Charsets.UTF_8)) }.getOrNull() ?: return
        for (k in 0 until words.length()) {
            val w = words.optJSONObject(k) ?: continue
            // EVERY CALL WORD OF THEIRS IS PRESENCE (iOS handleSignal 2026-2036, notePeerSeen 1243-1245): stamped now, whatever it
            // says; only the invitation of a call already ended here proves nothing
            if (!(w.optString("ctrl") == "call" && seedState(w.optString("s")) == "dead")) Presence.noteSeen(ref, System.currentTimeMillis(), "call")
            // WHAT THE FAR BUILD CAN DO IS LEARNED FROM EVERY WORD OF THE CALL IN HAND (iOS learnPeerCaps 922-932)
            w.optJSONObject("caps")?.let { CallLine.learnCaps(ref, w.optString("e").ifEmpty { epoch }, it) }
            when (val ctrl = w.optString("ctrl")) {
                "call" -> if (w.optString("rsn") == "rejoin") rejoinHeard(ref, w) else {
                    val ts = w.optLong("ts")
                    if (ts > 0 && NodeClock.now() - ts > LIFE_MS) { log("call word stale"); continue }   // by the node's clock (iOS 2195, K-11)
                    if (ts > 0) log("call word age=" + (NodeClock.now() - ts) + " ms")
                    incoming(ref, w.optString("s"), w.optBoolean("video"), w.optString("n"), w.optJSONObject("sdp")?.optString("sdp"), ts)
                }
                "call-end", "call-gone" -> {
                    // «call-gone» names its call in «s» (iOS 24.09); every other word in «e», else by the lane's own epoch
                    val named = if (ctrl == "call-gone") epochOf(w.optString("s")) else w.optString("e").ifEmpty { epoch }
                    synchronized(gate) { ring?.takeIf { it.ref == ref && epochOf(it.seed) == named } }?.let { end(it, ctrl) }
                }
                // the far phone's words to a call of ours (iOS handleSignalBody «call-ringing» 2321, «call-answer» 2332)
                "call-ringing" -> outOf(ref, w, epoch)?.let { ringingHere(it) }
                "call-answer" -> {
                    val sdp = w.optJSONObject("sdp")?.optString("sdp")?.ifEmpty { null }
                    // the answer to a rejoin offer of this run, whichever side it first was (iOS 3641-3655)
                    val e = w.optString("e").ifEmpty { epoch }
                    if (sdp != null && CallLine.rejoiningFor(ref, e)) { CallLine.answered(ref, e, sdp); continue }
                    val r = outOf(ref, w, epoch)
                    if (r != null && sdp != null) {
                        synchronized(gate) { if (!r.answered) r.answeredAt = System.currentTimeMillis(); r.answered = true }
                        ringingHere(r)
                        tone(false)
                        CallLine.answered(ref, epochOf(r.seed), sdp)
                    }
                }
                "call-hold", "call-resume" -> CallLine.peerHeld(ref, w.optString("e").ifEmpty { epoch }, ctrl == "call-hold")
                // the picture and the descriptions in the middle of the call (iOS 2391-2543): the line owns them
                "call-video-ask", "call-video-ok", "call-video-no", "call-video-end", "call-restart", "call-restart-answer",
                "call-screen-on", "call-screen-off" -> CallLine.heard(ref, w.optString("e").ifEmpty { epoch }, ctrl, w)
                // the caller's candidates (iOS 2368): one in «candidate», an old build's batch in «candidates»
                "call-ice" -> {
                    val cs = ArrayList<IceCandidate>()
                    fun take(o: JSONObject?) {
                        val sdp = o?.optString("candidate")?.ifEmpty { null } ?: return
                        cs.add(IceCandidate(o.optString("sdpMid"), o.optInt("sdpMLineIndex"), sdp))
                    }
                    take(w.optJSONObject("candidate"))
                    w.optJSONArray("candidates")?.let { a -> for (j in 0 until a.length()) take(a.optJSONObject(j)) }
                    if (cs.isNotEmpty()) CallLine.remoteIce(ref, w.optString("e").ifEmpty { epoch }, cs)
                }
                else -> {}   // the frame key (SFrame) and the run that comes back into its call: not in this build
            }
        }
    }

    /**
     * THE BIRTH OF AN INCOMING CALL (iOS handleSignalBody «call»): a dead seed is nobody, the same seed is the same call, and
     * a seedless word is an offer for the call in hand, never a birth.
     */
    private fun incoming(ref: String, seed: String, video: Boolean, name: String, offer: String?, ts: Long = 0L) {
        if (PeerSafety.isBlocked(ref)) return log("blocked caller")   // a blocked person's call is not assembled (iOS 15.09)
        if (seed.isEmpty()) {
            synchronized(gate) { ring?.takeIf { it.ref == ref && it.offer == null }?.offer = offer }
            synchronized(gate) { ring?.takeIf { it.ref == ref } }?.let { voice(it) }   // an answer that waited for its offer
            return
        }
        val fresh = synchronized(gate) {
            if (seedState(seed) == "dead") return log("dead seed")
            val r0 = ring
            if (r0 != null && r0.seed != seed) {
                // A NEW SEED OF THE SAME PERSON OF AN ESTABLISHED CALL SUPERSEDES IT (iOS MontanaCall.swift handleSignalBody,
                // 24.09, build 4543d66a9265): their phone came back without our call — iOS ends an app whose person changes a
                // privacy switch in Settings — and called anew. A call only ringing, or of another person, is left alone, simply
                // busy; an established one ends here without a farewell (end(..., silent = true)): a call-end keyed by the peer
                // would end the NEW call that superseded it.
                // YOUNGER THAN OURS (iOS MontanaCall.swift handleSignalBody, the critic 24.09, build 1500771e4d2b): a delayed
                // invitation of a call the peer placed BEFORE ours must not end a living call — only a word younger than our
                // call's own birth may supersede it; a word with no moment at all is trusted only once our own line is lost.
                // our call's birth read on the node's clock (iOS 2170-2175: startedAt + skew), the clock the word's moment is said by
                val youngerThanOurs = if (ts > 0) ts > r0.startedAt + (NodeClock.now() - System.currentTimeMillis()) else CallLine.lost
                if (r0.ref == ref && r0.answered && youngerThanOurs) end(r0, "superseded", silent = true)
                else {
                    // THE REFUSAL NAMES THE CALL IT REFUSES (iOS MontanaCall.swift:2277-2280, build 2d2005d61c14): a
                    // call-end without the refused call's own epoch read as STALE at the caller there, who then heard
                    // ringing to the caller's own ninety-second timeout instead of a prompt decline.
                    // the same person only (iOS same_peer=1): another person's call is iOS's second line, which this phone has not
                    if (r0.ref == ref) say(ref, seed, "call-end")
                    return log("busy: another call rings")
                }
            }
            val r = ring
            if (r != null) { if (r.offer == null) r.offer = offer; false }
            else { ring = Ring(ref, seed, video).also { it.offer = offer }; true }
        }
        say(ref, seed, "call-ringing")   // the caller hears that it rings here (iOS 2218), for the birth and for each copy
        if (!fresh) { synchronized(gate) { ring?.takeIf { it.seed == seed } }?.let { voice(it) }; return }
        noteSeed(seed, "alive")
        Signal.cutForCall()   // iOS MontanaCall.setState 4405-4412 «born» (atom cf9b083f5567): the ring stands, so the fresh question is the call's short one
        CallSound.yieldToCall()   // the call holds the sound from its birth (iOS 4413)
        if (name.isNotBlank() && name.length <= 64 && Book.admitState(ref, "name", 0L)) Book.edit(ref) { it.name = name.trim() }   // iOS onCallerNamed; undated, never over a dated word
        Signal.hold(ref, "call")
        CallLine.updateProximity()   // a call in any state holds the sensor while its sound stands at the ear (iOS 4401)
        show(ref, video)
        CallScreen.ring(ref)   // the app in front rings on its own screen too (iOS incomingScreen)
        MainThread.later(LIFE_MS) { synchronized(gate) { ring?.takeIf { it.seed == seed && !it.answered } }?.let { end(it, "timeout") } }
        log("ring video=" + video)
    }

    // ── what this phone says ──

    /**
     * «Decline» on a ring, «Hang up» on a call, and every rule that ends one (iOS CXEndCallAction, endByRule): the caller is
     * told «call-end». A declined call stays a missed one; an answered one leaves its length.
     */
    fun hangUp(why: String = "declined") {
        val r = synchronized(gate) { ring } ?: return
        say(r.ref, r.seed, "call-end")
        end(r, why)
    }

    /** THE SYSTEM'S REFUSAL ENDS THE BIRTH EVERYWHERE (iOS startCall's CXStartCallAction completion, MontanaCall.swift
     * 1817-1824, providerDidReset 4707-4716, build 7492b6b28754): a call whose own foreground service this phone could
     * not stand ends here and now — the far phone told before the teardown, not left ringing to its own ninety-second
     * wall over a call this phone no longer holds. */
    private fun refused(r: Ring, why: String) {
        if (synchronized(gate) { ring !== r }) return
        r.refused = true
        hangUp(why)
    }

    /** «Answer» (iOS acceptCall): the ring stops, the call stands as the system's, and the voice takes the offer. */
    fun answer() {
        val r = synchronized(gate) { ring?.takeIf { !it.out }?.also { if (!it.answered) it.answeredAt = System.currentTimeMillis(); it.answered = true } } ?: return
        hide()
        CallService.start(Book.ctx, r.ref) { refused(r, "service-refused") }
        voice(r)
        // iOS 2639-2647: an offer still on its way is waited for fifteen seconds, then the call honestly ends
        MainThread.later(15_000) { if (synchronized(gate) { ring === r && !r.line }) hangUp("offer-missing") }
    }

    /** The call in hand — answered and not yet ended — by its person; null when none (the call's screen asks it). */
    fun held(): String? = synchronized(gate) { ring?.takeIf { it.answered || it.out }?.ref }

    /** The person on the line with me now — the call answered on both ends (iOS stateSnapshot «connected» with peerSnapshot). */
    fun talking(): String? = synchronized(gate) { ring?.takeIf { it.answered }?.ref }

    /** A call stands in any state — ringing, dialling, talking (iOS stateSnapshot other than «idle»): its words knock every door. */
    fun busy(): Boolean = synchronized(gate) { ring != null }
    /** The correspondent of the call in hand, in any state (iOS MontanaCall.peerSnapshot): while it stands the radio is theirs. */
    fun peer(): String? = synchronized(gate) { ring?.ref }

    /** The ring in hand is a video call's (its letter's «v», its word's «video»): its screen and its questions say so. */
    fun ringVideo(): Boolean = synchronized(gate) { ring?.video == true }

    /** The words of a call of ours before the far phone answers — «Calling…», then «Ringing…» (iOS statusText 6470); null after. */
    fun stage(): Int? = synchronized(gate) { ring?.takeIf { it.out && !it.answered }?.let { if (it.ringing) R.string.call_ringing else R.string.call_calling } }

    // ── the call out (iOS startCall 1736-1919) ──

    /**
     * THE CALL OUT: a fresh seed names it; the far phone is knocked at once and every five seconds by the call's wake (WakePush
     * wakeVoip: the platform's own call on an iPhone, its app open or not) until it says «ringing»; the offer rides the lane as
     * «call» every two seconds, six times at most, and a wake carries it too; the third knock without «ringing» sends the ring
     * letter loud (E2E.ringBell). Ninety seconds unanswered end it, and the far phone is left its «missed» letter.
     */
    fun dial(ref: String, video: Boolean = false): Boolean {
        if (PeerSafety.isBlocked(ref) || Book.secret(ref) == null) return false
        // UNDER THE PERMITTED-LIST FILTER A CALL HAS NO ROAD (iOS startCall 1755-1763): the doors may stand on a permitted cascade,
        // the media cannot -- the relay and the reflector are ours and stand on no list; the far phone is not rung for nothing
        if (NetProbe.filtersCalls) {
            log("call_refused filtered — this network passes permitted destinations only")
            Log.d("Montana", "E2E-CALL refused why=whitelist dir=out")
            CallScreen.tellNoRoad(filtered = true)
            return false
        }
        val seed = Base64.encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) }, Base64.NO_WRAP)
        val r = synchronized(gate) {
            if (ring != null) return false.also { log("busy: a call is in hand") }
            Ring(ref, seed, video, out = true).also { ring = it }
        }
        noteSeed(seed, "alive")
        Signal.cutForCall()   // iOS MontanaCall.setState 4405-4412 «born» (atom cf9b083f5567): the ring stands, so the fresh question is the call's short one
        CallSound.yieldToCall()
        Signal.hold(ref, "call")
        CallLine.updateProximity()
        CallService.start(Book.ctx, ref) { refused(r, "service-refused") }
        MainThread.later(1200) { pipsOn(r) }   // the searching pips until the far phone's own word «ringing» (iOS 1855, 4548-4556)
        Thread { knock(r) }.start()
        // one ring letter per call, its name the call's (iOS E2E 1162-1166): the road of a phone the wake does not reach
        Post.send(ref, "ring-" + epochOf(seed), Marks.RING + ringWords(r, loud = false))
        CallLine.dial(ref, seed, video) { sdp ->
            synchronized(gate) { r.offer = sdp }
            MainThread.post { offerOut(r, 0) }
            Thread { wake(r, sdp) }.start()
        }
        MainThread.later(LIFE_MS) { if (synchronized(gate) { ring === r && !r.answered }) hangUp("no-answer") }
        log("dial")
        return true
    }

    private fun ringWords(r: Ring, loud: Boolean) = JSONObject().put("v", r.video).put("s", r.seed).put("n", Prefs.userName.trim())
        .put("t", NodeClock.now() / 1000.0).apply { if (loud) put("b", 1) }.toString()

    /** The knock goes on for the whole ring (iOS 1800-1840): every five seconds until «ringing», an answer or the end. */
    private fun knock(r: Ring) {
        var n = 0
        while (synchronized(gate) { ring === r && !r.ringing && !r.answered }) {
            // EVERY DOOR SAID «NO RECIPIENTS» (iOS 1810-1815): the far phone never registered for calls — knocking on cannot change it
            val got = wake(r, null)
            if (got == NOBODY) { r.nobody = true; log("ring_nobody"); break }
            r.knockN++
            if (got == RUNG) {
                val sec = ((System.currentTimeMillis() - r.startedAt) / 1000).toInt()
                r.knockOk++
                if (r.firstOkS < 0) r.firstOkS = sec
                r.lastOkS = sec
            }
            n++
            // THE SECOND BELL (iOS 1825-1833): a door rang the far phone, ten seconds passed, no «ringing» — the ring letter goes
            // out loud by the message road, once per call; a bell rung sooner lands on a phone already ringing
            if (n >= 3 && r.knockOk > 0 && !r.bell && synchronized(gate) { ring === r && !r.ringing }) {
                r.bell = true
                Post.send(r.ref, "ringb-" + epochOf(r.seed), Marks.RING + ringWords(r, loud = true))
            }
            // four knocks, nobody rung, nobody ringing: the phone is asleep or out of reach — the diary says so (iOS 1834-1839)
            if (n == 4 && r.knockOk == 0 && synchronized(gate) { ring === r && !r.ringing }) log("ring_unreached")
            Thread.sleep(5000)
        }
    }

    /**
     * THE CALL'S WAKE (iOS WakePush.wakeVoip 3400-3483): «ring»‖0‖my address‖0‖deflate({o, v, s, n, g, av, rj}) sealed under the
     * pipe as a lane word is, posted to the doors' /wake-voip one by one until a door rang a phone. This build reads no answer off
     * the wake road and does not rejoin: «av» and «rj» say so. An offer too big for the platform's push rides the lane alone.
     * RUNG when a door rang a phone; NOBODY when every door said 404 — no recipients (iOS 3536-3553); else 0.
     */
    private fun wake(r: Ring, offer: String?): Int {
        // A BIRTH THAT NO LONGER HOLDS THE MACHINE WAKES NOBODY (iOS startCall's callGen guards, MontanaCall.swift
        // 1742-1884, build 7492b6b28754): a call ended here — superseded, declined, hung up, refused by the system —
        // must not wake the far phone, or offer it again, once its own birth is buried.
        if (synchronized(gate) { ring !== r }) return 0
        val twin = MontanaSeed.twin ?: return 0
        val secret = Book.secret(r.ref) ?: return 0
        fun sealed(o: String): String? {
            val words = JSONObject().put("o", o).put("v", r.video).put("s", r.seed).put("n", Prefs.userName.trim()).put("g", "")
                .put("av", false).put("rj", false)
            val body = "ring".toByteArray() + byteArrayOf(0) + twin.toByteArray() + byteArrayOf(0) + Signal.deflate(words.toString().toByteArray())
            return Wire.seal(Wire.bodyKey(secret, Wire.minute()), body)?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
        }
        val env = sealed(offer ?: "")?.takeIf { it.length <= 4600 } ?: sealed("") ?: return 0
        val cw = Wire.convW(secret, Wire.day())
        val req = JSONObject().put("conv", cw).put("from_id", Wire.subId(cw, twin)).put("env", env)
        var saw404 = false
        var sawOther = false
        for (door in Signal.byProof(MontanaCard.doors)) {   // the doors that answered on this path first (iOS 484)
            val (code, text) = Wire.post(door, "/wake-voip", req, 8000)
            val o = text?.let { runCatching { JSONObject(it) }.getOrNull() }
            val sent = o?.optInt("sent", o.optInt("woken", -1)) ?: -1
            log("wake code=" + code + " sent=" + sent + " offer=" + (offer != null))
            if (code == 200 && sent > 0) return RUNG
            if (code == 404) saw404 = true else sawOther = true
        }
        return if (saw404 && !sawOther) NOBODY else 0
    }
    private const val RUNG = 1
    private const val NOBODY = 2

    /** The offer on the lane every two seconds until the far phone rings or answers, six times at most (iOS 1895-1918). */
    private fun offerOut(r: Ring, n: Int) {
        val sdp = synchronized(gate) { if (ring !== r || r.ringing || r.answered) null else r.offer } ?: return
        val w = JSONObject().put("t", "cal").put("ctrl", "call").put("ts", NodeClock.now()).put("e", epochOf(r.seed))
            .put("sdp", JSONObject().put("type", "offer").put("sdp", sdp)).put("video", r.video).put("caps", CallLine.caps())
            .put("n", Prefs.userName.trim()).put("s", r.seed)
        Signal.postWord(r.ref, epochOf(r.seed), JSONArray().put(w).toString().toByteArray())
        if (n < 6) MainThread.later(2000) { offerOut(r, n + 1) }
    }

    private fun outOf(ref: String, w: JSONObject, epoch: String): Ring? {
        val e = w.optString("e").ifEmpty { epoch }
        return synchronized(gate) { ring?.takeIf { it.out && it.ref == ref && epochOf(it.seed) == e } }
    }

    /** The far phone rings (iOS 2321): the knock and the offer stop, the held candidates leave, the ringback sounds here. */
    private fun ringingHere(r: Ring) {
        val first = synchronized(gate) { (!r.ringing).also { r.ringing = true } }
        if (!first) return
        CallLine.release(r.ref, epochOf(r.seed))
        if (!r.answered) tone(true)
        log("far phone rings")
    }

    /** The ringback (iOS startRingback): the platform's own tone on the call's stream, while the far phone rings. */
    private fun tone(on: Boolean) = MainThread.post {
        pips?.let { runCatching { it.stop(); it.release() } }
        pips = null
        tone?.let { runCatching { it.stopTone(); it.release() } }
        tone = null
        if (on && synchronized(gate) { ring?.let { it.out && !it.answered } == true })
            tone = runCatching { ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80).also { it.startTone(ToneGenerator.TONE_SUP_RINGTONE) } }.getOrNull()
    }

    /**
     * THE SEARCHING TONE (iOS startDialTone 4542-4569, reconnectFile 4616-4630): from the dial until the far phone's own word
     * «ringing» — two low pips every three seconds, the carrier's sound of waiting. The ringback waits for that word, so no ear
     * hears «it rings» while the offer still looks for a door; tone() ends both.
     */
    private var pips: android.media.AudioTrack? = null
    private fun pipsOn(r: Ring) {
        if (pips != null || !synchronized(gate) { ring === r && r.out && !r.ringing && !r.answered }) return
        val pcm = searchPips()
        pips = runCatching {
            android.media.AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .setAudioFormat(android.media.AudioFormat.Builder().setEncoding(android.media.AudioFormat.ENCODING_PCM_16BIT).setSampleRate(8000)
                    .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(android.media.AudioTrack.MODE_STATIC).setBufferSizeInBytes(pcm.size * 2).build()
                .also { t -> t.write(pcm, 0, pcm.size); t.setLoopPoints(0, pcm.size, -1); t.setVolume(0.6f); t.play() }
        }.getOrNull()
        log("call_tone search")
    }
    /** Two pips of 120 ms at 380 Hz, 100 ms apart, soft-edged over 10 ms, then silence to three seconds — the iPhone's samples. */
    fun searchPips(): ShortArray {
        val sr = 8000
        val out = ShortArray(3 * sr)
        val len = sr * 120 / 1000
        for (pip in 0 until 2) {
            val start = pip * (sr * 220 / 1000)
            for (i in 0 until len) {
                val v = Math.sin(2.0 * Math.PI * 380.0 * i / sr)
                val edge = minOf(1.0, minOf(i.toDouble(), (len - i).toDouble()) / (sr / 100))
                out[start + i] = (v * edge * 6000).toInt().toShort()
            }
        }
        return out
    }

    /** The offer goes to the voice once — when the call is answered and its offer is here, in whichever order they came. */
    private fun voice(r: Ring) {
        val offer = synchronized(gate) { if (r.line || !r.answered) null else r.offer?.also { r.line = true } } ?: return
        CallLine.answer(r.ref, r.seed, offer)
    }

    private fun say(ref: String, seed: String, ctrl: String) {
        val w = JSONObject().put("t", "cal").put("ctrl", ctrl).put("ts", NodeClock.now()).put("e", epochOf(seed))
        Signal.postWord(ref, epochOf(seed), JSONArray().put(w).toString().toByteArray())
    }

    private fun end(r: Ring, why: String, silent: Boolean = false) {
        synchronized(gate) { if (ring !== r) return; ring = null }
        noteSeed(r.seed, "dead", engaged = r.answered || r.out)
        tone(false)
        val spoken = CallLine.stop(r.seed)
        val dur = spoken.dur
        story(r, why, spoken)
        holdOnDisk()   // the call ended: its record goes (iOS 3508-3510)
        CallService.stop()
        CallScreen.hide()
        Signal.release(r.ref, "call")
        hide()
        // THE SUPERSEDED CALL LEAVES NO ROW AND NO FAREWELL (iOS call_superseded, 24.09, build 4543d66a9265): it never
        // reached the person, so no row of its own is written, and a call-end keyed by the peer would end the NEW call.
        if (!silent) {
            // iOS: «missed» means the person never reacted — an answer whose call did not connect is «Connection failed»
            row(r.ref, r.video, incoming = !r.out, dur = dur, missed = !r.answered)
            // a call of ours nobody took leaves the far phone its «missed» letter (iOS missedCallMark); one of theirs, the banner here
            // LOUD ONLY FOR A PHONE THAT NEVER RANG (iOS MontanaCall 5722, 13.09: the author's three notifications for one call): a phone
            // that said «ringing» has shown its person the call and written its own missed row — the letter still rides, silent
            // A BIRTH THE SYSTEM REFUSED RIDES SILENT TOO (iOS build 3811dfa0a06f: refused = endReason.hasPrefix("callkit-"),
            // "silent: rang || refused"): this phone never truly held the call either, so a loud «missed call» for it is
            // one notification too many.
            if (r.out) { if (!r.answered) Post.send(r.ref, Marks.mintMid(), Marks.MISSED + JSONObject().put("v", r.video).put("s", r.seed), quiet = r.ringing || r.refused) }
            else if (!r.answered && why != "declined") Notify.letter(r.ref, rowText(r.video, true, 0, true))   // iOS postMissedCallBanner
        }
        log("end " + why + (if (silent) " silent" else ""))
    }

    /**
     * THE PEER CAME BACK INTO THIS CALL (iOS handleSignalBody «call» rsn rejoin 2108-2132, handleSignal 2026-2035): the same seed,
     * a new connection, no ring; the dead connection is replaced in place by the line. A rejoin of a call that ended here is
     * told so at once -- the run that came back would otherwise wait out its window over «Reconnecting…» for a call nobody holds.
     */
    private fun rejoinHeard(ref: String, w: JSONObject) {
        val seed = w.optString("s")
        val sdp = w.optJSONObject("sdp")?.optString("sdp")?.ifEmpty { null } ?: return
        if (seed.isEmpty()) return
        if (seedState(seed) == "dead") {
            log("call_rejoin rx of a call that ended here — call-end")
            Signal.postWord(ref, epochOf(seed), JSONArray().put(JSONObject().put("t", "cal").put("ctrl", "call-end").put("ts", NodeClock.now())
                .put("e", epochOf(seed))).toString().toByteArray())
            return
        }
        val r = synchronized(gate) { ring?.takeIf { it.ref == ref && it.seed == seed && it.answered } }
        if (r == null) return log("call_rejoin rx for no call held here — buried")
        CallLine.rebuildForRejoin(ref, epochOf(seed), sdp, w.optJSONObject("caps"))
    }

    // ═══ THE CALL ON DISK (iOS HeldCall 751-772, holdOnDisk 3505-3521, rejoinHeldCall 3533-3587; atoms dc1b54275bf6,
    // 85e52e1b67b9, c0e89e93b0f9): the living call stands on disk from its connection to its end, sealed by the device's key --
    // the peer, the seed, video or voice, the side, since when, whether the peer rebuilds, the last moment it was known alive
    // (every five seconds), how many runs already went back into it. The next run finds it and goes back into the call. ═══
    private const val HELD = "mt.call.held"
    @Volatile private var heldAt = 0L
    private var launchRead = false
    private var launchHeld: JSONObject? = null

    /** The record the previous run left, read once, before this run writes its own (iOS init 787-797). */
    private fun launchRecord(): JSONObject? = synchronized(gate) {
        if (!launchRead) {
            launchRead = true
            launchHeld = DeviceVault.get(HELD)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() }
            launchHeld?.let { h ->
                log("call_lost epoch=" + h.optString("seed").take(8) + " connected=" + (if (h.optLong("connectedAt") > 0L) 1 else 0) +
                    " rebuilds=" + (if (h.optBoolean("rebuilds")) 1 else 0) + " tries=" + h.optInt("rejoins") +
                    " age_s=" + (System.currentTimeMillis() - h.optLong("alive")) / 1000 + " — the previous run died holding it")
            }
        }
        launchHeld
    }

    /** The call in hand written down: forced at its connection and when the peer's caps say «rejoin», else every five seconds. */
    fun holdOnDisk(force: Boolean = false) {
        launchRecord()
        val r = synchronized(gate) { ring?.takeIf { it.answered || it.out } }
        val at = CallLine.connectedAt
        if (r == null) {
            // a held call waiting for its person is not wiped by an end elsewhere: only its judgement removes it (iOS 3508-3512)
            if (synchronized(gate) { launchHeld == null } && heldAt != 0L) DeviceVault.delete(HELD)
            heldAt = 0L
            return
        }
        val now = System.currentTimeMillis()
        if (at == 0L || (!force && now - heldAt < 5000)) return
        heldAt = now
        val o = JSONObject().put("peer", r.ref).put("seed", r.seed).put("video", CallLine.video || r.video).put("initiator", r.out)
            .put("startedAt", r.startedAt).put("connectedAt", at).put("rebuilds", CallLine.peerRebuilds).put("alive", now).put("rejoins", r.rejoins)
        DeviceVault.set(HELD, o.toString().toByteArray(Charsets.UTF_8))
    }
    /** A rejoin that stood is no fall: the next run goes back in (iOS 5076, 24.09 23:20). */
    fun rejoinStood() { synchronized(gate) { ring?.rejoins = 0 } }

    /**
     * THE RUN GOES BACK INTO THE CALL ITS PROCESS HELD (iOS rejoinHeldCall 3533-3587): asked when the app faces the person; only a
     * call that stood connected, with a peer that rebuilds in place, whose last known moment lies inside the call's window, and
     * that no run went back into twice. Not yet: the person has not come back to the screen, or the peer's pipe is not open.
     */
    fun rejoinHeldCall(act: MainActivity, attempt: Int = 0) {
        val h = launchRecord() ?: return
        val age = System.currentTimeMillis() - h.optLong("alive")
        val ok = 0L < h.optLong("connectedAt") && h.optBoolean("rebuilds") && h.optInt("rejoins") < 2 && age < LIFE_MS && synchronized(gate) { ring == null }
        if (!ok) return judged(h, "not tried connected=" + (if (0L < h.optLong("connectedAt")) 1 else 0) + " rebuilds=" + (if (h.optBoolean("rebuilds")) 1 else 0) +
            " tries=" + h.optInt("rejoins") + " age_s=" + age / 1000)
        val ref = h.optString("peer"); val seed = h.optString("seed")
        if (Book.secret(ref) == null || CallScreen.front !== act) {
            if (attempt < 40) MainThread.later(250) { rejoinHeldCall(act, attempt + 1) } else judged(h, "not tried — the person or the pipe never came")
            return
        }
        synchronized(gate) { launchHeld = null }
        val video = h.optBoolean("video"); val out = h.optBoolean("initiator")
        val r = Ring(ref, seed, video, out, h.optLong("startedAt")).also {
            it.answered = true; it.ringing = true; it.line = true; it.rejoins = h.optInt("rejoins") + 1; it.answeredAt = h.optLong("connectedAt")
        }
        synchronized(gate) { ring = r }
        noteSeed(seed, "alive")
        log("call_rejoin tx age_s=" + age / 1000 + " video=" + (if (video) 1 else 0) + " waited_ms=" + attempt * 250 + " epoch=" + epochOf(seed).take(8))
        Signal.hold(ref, "call")
        CallService.start(Book.ctx, ref) { refused(r, "service-refused") }
        CallLine.rejoin(ref, seed, video, out, h.optLong("connectedAt"), h.optLong("alive") + LIFE_MS)
        CallScreen.show(act, ref)
        CallLine.updateProximity()
    }
    private fun judged(h: JSONObject, why: String) {
        synchronized(gate) { launchHeld = null }
        log("call_rejoin " + why)
        // the call this phone held and will not go back into is over here: «call-gone» answers its asks now (iOS lostEpoch)
        noteSeed(h.optString("seed"), "dead", engaged = true)
        if (synchronized(gate) { ring == null }) DeviceVault.delete(HELD)
    }

    /**
     * ONE LINE PER CALL, AND ITS END IN THE DAY-LONG JOURNAL (iOS 3021-3064; atoms 41d0cac99d59, d3fcc97a4974, 2c0ff001b031):
     * how long the setup took and the road alone (from the answering hand), whether it rang, the line's own story, why it
     * ended and through which door -- a hand (the reason read from the call's state, iOS handReason 2875-2879), a rule, or the
     * far side -- and the ring's ledger with the one word of whose side a miss is on (iOS faultSide 612-622).
     */
    private fun story(r: Ring, why: String, sp: CallLine.Spoken) {
        val connected = sp.connectedAt > 0L
        val reason = when (why) {
            "declined" -> if (!r.out && !r.answered) "declined" else if (!connected) (if (r.out && !r.ringing) "cancelled-unrung" else "cancelled") else "hung-up"
            "call-end" -> "peer-ended"
            "call-gone" -> "peer-gone"
            "no-answer" -> "timeout"
            else -> why
        }
        val door = when (why) { "declined" -> "hand"; "call-end", "call-gone", "superseded" -> "-"; else -> "rule:" + why }
        val setup = if (connected) sp.connectedAt - r.startedAt else -1L
        val connect = if (connected && r.answeredAt > 0L) sp.connectedAt - r.answeredAt else -1L
        val ringS = if (r.answeredAt > 0L) (r.answeredAt - r.startedAt) / 1000 else -1L
        val side = when {
            connected -> "talk"
            !r.out -> if (r.answered) "net" else "hand"
            r.answeredAt > 0L -> "net"   // the far hand answered, the road failed
            r.ringing -> "callee"   // it rang there, nobody picked up
            r.nobody -> "ours-registration"   // every door: no recipients for them
            r.knockOk > 0 -> "apple"   // a door rang the far phone, no word «ringing» came
            r.knockN > 0 -> "ours-road"   // not one door rang a single phone
            else -> "ours"
        }
        val dir = if (r.out) "out" else "in"
        val v = if (sp.video || (sp.connectedAt == 0L && r.video)) 1 else 0   // iOS isVideo: what the call was at its end
        val ledger = "knocks=" + r.knockN + "/" + r.knockOk + " first_ok_s=" + r.firstOkS
        Log.d("Montana", "call_summary dir=" + dir + " video=" + v + " setup_ms=" + setup + " connect_ms=" + connect + " ring_s=" + ringS +
            " rang=" + (if (r.ringing) 1 else 0) + " " + sp.summary.ifEmpty { "talk_s=0" } + " end=" + reason + " " + ledger + " last_ok_s=" + r.lastOkS +
            " bell=" + (if (r.bell) 1 else 0) + " side=" + side)
        Log.d("Montana", "E2E-CALL end dir=" + dir + " video=" + v + " talk_s=" + sp.dur + " end=" + reason + " door=" + door +
            " rang=" + (if (r.ringing) 1 else 0) + " " + ledger + " bell=" + (if (r.bell) 1 else 0) + " " + sp.end.ifEmpty { "paths=-" } +
            " probe=" + NetProbe.verdictWord + " side=" + side)
    }

    /**
     * The caller's «missed» letter (iOS DeliveryEngine missedCallMark): a call this phone saw, alive or dead, has its row
     * already; any other becomes a missed row here. The receipt is the letter's place's own.
     */
    fun missedLetter(ref: String, json: String) {
        if (PeerSafety.isBlocked(ref)) return
        val o = runCatching { JSONObject(json) }.getOrNull() ?: JSONObject()
        val seed = o.optString("s")
        if (seed.isNotEmpty() && seedState(seed) != null) return log("missed letter of a call seen here")
        noteSeed(seed, "dead")
        val video = o.optBoolean("v")
        row(ref, video, incoming = true, dur = 0, missed = true)
        Notify.letter(ref, rowText(video, true, 0, true))
    }

    // ── the call's row (iOS appendCallLog, callMark) ──

    class Info(val video: Boolean, val incoming: Boolean, val dur: Int, val missed: Boolean)

    fun info(text: String): Info? {
        if (!text.startsWith(Marks.CALL)) return null
        val o = runCatching { JSONObject(text.removePrefix(Marks.CALL)) }.getOrNull() ?: return null
        return Info(o.optBoolean("v"), o.optBoolean("inc"), o.optInt("dur"), o.optBoolean("miss"))
    }

    private fun rowText(video: Boolean, incoming: Boolean, dur: Int, missed: Boolean) =
        Marks.CALL + JSONObject().put("v", video).put("inc", incoming).put("dur", dur).put("miss", missed).toString()

    /** Each phone lays its own row of a call; the same call told twice within its life lands once (iOS «one row per call»). */
    fun row(ref: String, video: Boolean, incoming: Boolean, dur: Int, missed: Boolean) {
        val now = System.currentTimeMillis()
        Book.edit(ref) { c ->
            val last = c.msgs.lastOrNull()
            val li = last?.let { info(it.text) }
            if (last != null && li != null && li.video == video && li.incoming == incoming && li.missed == missed && now - last.at < LIFE_MS) return@edit
            c.msgs.add(Msg(Marks.mintMid(), rowText(video, incoming, dur, missed), !incoming, now, state = if (incoming) 2 else 3))
            c.msgs.sortBy { it.at }
        }
    }

    /** iOS ChatStore.listPreview for a call: the glyph and the call's word. */
    fun words(c: Context, i: Info): String = (if (i.video) "📹 " else "📞 ") + c.getString(when {
        i.missed -> if (i.incoming) R.string.call_missed else R.string.call_unanswered
        i.video -> R.string.call_video
        else -> R.string.call_voice
    })

    /** iOS MessageBubble.callBubble: the glyph, red when missed; the kind; under it the arrow, how it went and the moment. */
    fun body(c: Context, m: Msg, into: LinearLayout) {
        val i = info(m.text) ?: return
        val ink = BubbleStyle.text(m.mine)
        val accent = if (i.missed) SysColor.red else ink
        val how = when {
            i.missed -> c.getString(if (i.incoming) R.string.call_missed_short else R.string.call_no_answer)
            i.dur > 0 -> String.format(Locale.ROOT, "%d:%02d", i.dur / 60, i.dur % 60)
            else -> c.getString(R.string.call_failed)
        }
        val time = android.text.format.DateFormat.getTimeFormat(c).format(Date(m.at))
        into.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            addView(c.icon(if (i.video) R.drawable.ic_peer_video else R.drawable.ic_peer_phone, accent, 18), lp(dp(18), dp(18)).apply { marginEnd = dp(10) })
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(c.getString(if (i.video) R.string.call_video else R.string.call_voice), 15f, ink, bold = true), lp(WRAP, WRAP))
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    addView(c.icon(if (i.incoming) R.drawable.ic_call_received else R.drawable.ic_call_made, accent, 10), lp(dp(10), dp(10)).apply { marginEnd = dp(4) })
                    addView(c.text(how + " · " + time, 12f, BubbleStyle.time(m.mine)), lp(WRAP, WRAP))
                }, lp(WRAP, WRAP).apply { topMargin = dp(2) })
            }, lp(WRAP, WRAP))
        }, lp(WRAP, WRAP))
    }

    // ── the ring on the screen (iOS: CallKit's incoming call; here the call's own notification) ──

    private fun show(ref: String, video: Boolean) {
        val c = Book.ctx
        val nm = c.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(NotificationChannel(CHANNEL, c.getString(R.string.app_calls), NotificationManager.IMPORTANCE_HIGH).apply {
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 1000, 1000)
        })
        val name = Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        fun page(answer: Boolean) = PendingIntent.getActivity(c, if (answer) 2 else 1,
            Intent(c, MainActivity::class.java).putExtra(EXTRA_REF, ref).putExtra(EXTRA_ANSWER, answer)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        val decline = PendingIntent.getBroadcast(c, 3, Intent(c, CallDecline::class.java), flags)
        val b = Notification.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(name)   // USER-DATA: the caller's name
            .setContentText(c.getString(if (video) R.string.call_video else R.string.call_voice))
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setContentIntent(page(false))
            .setFullScreenIntent(page(false), true)
        if (Build.VERSION.SDK_INT >= 31) {
            val face = Book.shownFace(ref).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }?.let { Icon.createWithBitmap(it) }
            val who = Person.Builder().setName(name).setIcon(face).setImportant(true).build()
            b.setStyle(Notification.CallStyle.forIncomingCall(who, decline, page(true)).setIsVideo(video))
        } else {
            b.addAction(Notification.Action.Builder(null as Icon?, c.getString(R.string.call_decline), decline).build())
            b.addAction(Notification.Action.Builder(null as Icon?, c.getString(R.string.call_accept), page(true)).build())
        }
        val n = b.build()
        n.flags = n.flags or Notification.FLAG_INSISTENT   // the ringtone rings on until the call is answered or gone
        runCatching { nm.notify(NOTE, n) }.onFailure { log("notify: " + it.message) }
    }

    private fun hide() { Book.ctx.getSystemService(NotificationManager::class.java)?.cancel(NOTE) }

    // ── the seeds this phone has seen (iOS MontanaMissedCall's book, MontanaCall's graveyard), kept the letter queue's week ──

    private fun seeds(): JSONObject = runCatching { JSONObject(Prefs.str(SEEDS, "{}")) }.getOrNull() ?: JSONObject()
    private fun seedState(seed: String): String? = seeds().optJSONObject(seed)?.optString("st")?.ifEmpty { null }
    // ENGAGED, NOT MERELY RUNG (iOS MontanaCall.lostEpoch, the critic 24.09, build 1500771e4d2b, K1): a second device of the
    // same person can be rung by the same seed and never take the call — its own «dead» must not let it speak for a call its
    // twin still holds. Engaged says whether THIS device answered or dialled; answerGone below honours only an engaged «dead».
    private fun noteSeed(seed: String, st: String, engaged: Boolean = false) {
        if (seed.isEmpty()) return
        synchronized(gate) {
            val o = seeds(); val now = System.currentTimeMillis()
            o.put(seed, JSONObject().put("st", st).put("at", now).put("en", engaged))
            o.keys().asSequence().toList().filter { now - (o.optJSONObject(it)?.optLong("at") ?: 0L) > 7 * 86_400_000L }.forEach { o.remove(it) }
            Prefs.setStr(SEEDS, o.toString())
        }
    }

    private val goneSaid = HashSet<String>()

    /** THE FAR PHONE'S FRESH CHECKS FOR A CALL WE LOST ARE ANSWERED (iOS MontanaWakePush.swift answerGone, 24.09, build
     * 4543d66a9265, fixed again in 2b921f39a583): without this word the far phone stood «reconnecting» to its own thirty-second
     * deadline over a call nobody here held any more. Answered once per epoch, and only an epoch this phone's own graveyard says
     * it once held and ended — a call still in hand, or an epoch never seen here, says nothing (a candidate may precede a birth
     * and must stay buried). Called from CallLine.heard on a restart ask with no line to answer it. */
    fun answerGone(ref: String, epoch: String) {
        if (epoch.isEmpty()) return
        synchronized(gate) {
            if (ring?.let { epochOf(it.seed) == epoch } == true) return   // a call still in hand is not gone
            if (!goneSaid.add(epoch)) return
        }
        val dead = seeds().let { o -> o.keys().asSequence().any {
            epochOf(it) == epoch && o.optJSONObject(it)?.optString("st") == "dead" && o.optJSONObject(it)?.optBoolean("en") == true } }
        if (!dead) return
        val w = JSONObject().put("t", "cal").put("ctrl", "call-gone").put("ts", NodeClock.now()).put("e", epoch).put("s", epoch)
        Signal.postWord(ref, epoch, JSONArray().put(w).toString().toByteArray())
        log("call-gone tx epoch=" + epoch)
    }

    private fun log(s: String) { Log.d("Montana", "call: " + s) }
}

/** The ring's «Decline» and the call's «Hang up» (Calls, CallService): the system hands the press here. */
class CallDecline : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) { Thread { Calls.hangUp() }.start() }
}
