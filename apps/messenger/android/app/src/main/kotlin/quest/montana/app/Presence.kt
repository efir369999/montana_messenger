package quest.montana.app

import android.content.Context
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.zip.Deflater
import java.util.zip.Inflater

// ─────────────────────────── the live lane and the presence ladder (iOS MontanaWakePush signal lane, E2E beacons, ChatStore ladder) ───────────────────────────

/**
 * THE SIGNAL LANE (iOS MontanaWakePush.postSignal / fetchSignals, epoch «chat»): a word that lives an instant — typing, «in
 * my chat», «in the app» — never takes a place in the letters' queue. It is sealed under the pipe's key of the minute as a
 * letter is, as peer‖0‖epoch‖0‖deflate(text), and posted to the doors' /signal under the conversation's daily label; the
 * other side holds a long question on /signal-fetch and hears it the millisecond it lands. A bare «box» on the lane says the
 * box holds a letter of ours — it is fetched at once.
 */
object Signal {
    fun deflate(b: ByteArray): ByteArray {
        val d = Deflater(Deflater.DEFAULT_COMPRESSION, true)   // raw DEFLATE, as Apple's .zlib writes it (no header)
        d.setInput(b); d.finish()
        val out = ByteArrayOutputStream(); val buf = ByteArray(512)
        while (!d.finished()) out.write(buf, 0, d.deflate(buf))
        d.end(); return out.toByteArray()
    }
    private fun inflate(b: ByteArray): ByteArray? = runCatching {
        val i = Inflater(true); i.setInput(b)
        val out = ByteArrayOutputStream(); val buf = ByteArray(512)
        var guard = 0
        while (!i.finished() && guard++ < 1000) { val n = i.inflate(buf); if (n == 0 && (i.needsInput() || i.needsDictionary())) break; out.write(buf, 0, n) }
        i.end(); out.toByteArray()
    }.getOrNull()

    /** One word on the lane, at the door the other side asks (iOS postSignal): per-node stores do not talk to each other. */
    fun post(ref: String, text: String) = postWord(ref, "chat", text.toByteArray())

    /** A word of any epoch (iOS postSignal 3000-3054): «chat» for the live words, a call's own epoch for its words (Calls). */
    fun postWord(ref: String, epoch: String, payload: ByteArray) {
        val twin = MontanaSeed.twin ?: return
        val secret = Book.secret(ref) ?: return
        Thread {
            val body = twin.toByteArray() + byteArrayOf(0) + epoch.toByteArray() + byteArrayOf(0) + deflate(payload)
            val sealed = Wire.seal(Wire.bodyKey(secret, Wire.minute()), body) ?: return@Thread
            val cw = Wire.convW(secret, Wire.day())
            val req = JSONObject().put("conv", cw).put("from_id", Wire.subId(cw, twin)).put("env", Base64.encodeToString(sealed, Base64.NO_WRAP))
            // THE PEER NAMED THE DOORS THEY ASK — the word goes to the conversation's door and nowhere else; a peer who has not (an old
            // build, a fresh chat before its first beacon) gets it on every living door, and whichever it asks, the word is there
            // (iOS postSignal 3008-3013)
            val doors = (if (peerDoors(ref) != null) listOf(signalDoor(ref)) else Doors.ordered("signal").filter { doorAlive(it) }).filter { it.isNotEmpty() }.toMutableList()
            // A CALL KNOCKS EVERY DOOR (iOS 3014-3021, 15.13): a door dead a minute ago is the very door the path may carry again now
            if (epoch != "chat" || Calls.busy() || doors.isEmpty()) for (b in callDoors()) if (b !in doors) doors.add(b)
            if (doors.isEmpty()) { Log.d("Montana", "sig_tx SKIP no-door"); return@Thread }
            for (door in doors) {
                // ONE LANE PER DOOR (iOS 3031-3053): the word waits its turn; a chat word of this conversation replaces the one still waiting
                onSignalLane(door, if (epoch == "chat") ref else null) {
                    try {
                        // a chat word that waited past its door's death does not dial it; a call's word knocks every door (iOS 3033-3037)
                        if (epoch == "chat" && !doorAlive(door) && !Calls.busy()) return@onSignalLane
                        val (code, _) = onLane { Wire.post(door, "/signal", req, 8000, it) }
                        if (code == 200) doorAnswered(door) else if (code != CUT) doorFailed(door, code)
                    } finally { leaveSignalLane(door) }
                }
            }
        }.start()
    }

    /**
     * THE SIGNAL LANE OF A DOOR IS ONE LANE (iOS 2954-2995, 29.09; T1 23:31:45Z on 1988: twenty-five posts in flight the moment a tunnel
     * came up, 912 goroutines and 40 MB in 2.4 s, the extension killed): a door takes two words at a time; the rest wait in the order they
     * were said, a newer chat word of a conversation replacing the older one still waiting, and beyond sixteen the oldest chat word gives
     * way. Under the lock only the two tables move; the word itself runs after it.
     */
    private const val LANE_WIDTH = 2
    private const val LANE_DEPTH = 16
    private val laneBusy = HashMap<String, Int>()
    private val laneQueue = HashMap<String, ArrayDeque<Pair<String?, () -> Unit>>>()

    private fun onSignalLane(door: String, key: String?, run: () -> Unit) {
        synchronized(laneBusy) {
            if ((laneBusy[door] ?: 0) >= LANE_WIDTH) {
                val q = laneQueue.getOrPut(door) { ArrayDeque() }
                if (key != null) q.removeAll { it.first == key }
                if (q.size >= LANE_DEPTH) { val i = q.indexOfFirst { it.first != null }; if (i >= 0) q.removeAt(i) }
                q.addLast(key to run)
                return
            }
            laneBusy[door] = (laneBusy[door] ?: 0) + 1
        }
        Thread { run() }.start()
    }

    private fun leaveSignalLane(door: String) {
        val next = synchronized(laneBusy) {
            laneBusy[door] = maxOf(0, (laneBusy[door] ?: 1) - 1)
            val q = laneQueue[door]
            if (q != null && q.isNotEmpty()) { laneBusy[door] = (laneBusy[door] ?: 0) + 1; q.removeFirst().second } else null
        }
        next?.let { Thread { it() }.start() }
    }

    // ── the doors' life (iOS WakePush baseFailed 318-346, signalDoorAnswered 451-459, the path change 516-528) ──
    private val doorFails = HashMap<String, Int>()
    private val deathStreak = HashMap<String, Int>()
    private val deadUntil = HashMap<String, Long>()
    /** No answer, or the door's own failure: two in a row and it rests a minute, then two, four, eight at most. A refusal is an answer. */
    fun doorFailed(door: String, code: Int) {
        if (code != -1 && code < 500) { doorAnswered(door, proved = false); return }
        val now = System.currentTimeMillis()
        var wasChosen = false
        val rest = synchronized(deadUntil) {
            if ((deadUntil[door] ?: 0L) > now) return
            val n = (doorFails[door] ?: 0) + 1
            doorFails[door] = n
            if (n < 2) return
            doorFails[door] = 0
            val streak = minOf((deathStreak[door] ?: 0) + 1, 4)
            deathStreak[door] = streak
            wasChosen = chosen == door
            if (wasChosen) chosen = null
            (60_000L shl (streak - 1)).also { deadUntil[door] = now + it }
        }
        Log.d("Montana", "sig_door dead " + host(door) + " code=" + code + " — not asked for " + rest / 1000 + "s")
        // the elected door is left only past its death, and the next live one is elected at the next write (iOS baseFailed 347-350)
        if (elected() == door) {
            elected = null
            Prefs.remove(ELECTED)
            Log.d("Montana", "door_elected " + host(door) + " died — the next live door is elected")
        }
        // THE STANDING QUESTION LEAVES A DEAD DOOR NOW (iOS baseFailed 351-354): the lane is cut and re-elected the same instant
        if (wasChosen) cut("door " + host(door) + " dead — the standing question leaves it")
    }
    fun doorAnswered(door: String, proved: Boolean = true) {
        val revived = synchronized(deadUntil) {
            val was = deathStreak.containsKey(door) || deadUntil.containsKey(door)
            doorFails.remove(door); deathStreak.remove(door); deadUntil.remove(door)
            if (proved) proof[host(door)] = System.currentTimeMillis()
            was
        }
        if (revived) {
            Log.d("Montana", "sig_door alive " + host(door))
            Wire.forgetGone()   // a door that was silent answers: what it holds is new knowledge (iOS door_alive, forgetGoneChunks)
            // A DOOR THAT ANSWERS AFTER SILENCE DRAINS THE QUEUE AT ONCE (iOS 1672): the letters that waited for it leave now
            if (draining.compareAndSet(false, true)) Thread { try { Post.flush() } finally { draining.set(false) } }.start()
        }
    }
    private val draining = java.util.concurrent.atomic.AtomicBoolean(false)
    /** Alive for me (iOS doorAlive 468-474): not silent in the last round of the doors, not resting dead by my own two silences. */
    fun doorAlive(door: String) = !Doors.silent(door) && synchronized(deadUntil) { (deadUntil[door] ?: 0L) <= System.currentTimeMillis() }
    /** PROOF OF A DOOR (iOS doorProof): the moment it last answered me with 200 since the path changed — keyed by host. */
    private val proof = HashMap<String, Long>()
    /**
     * THE PROVEN DOORS FIRST (iOS MontanaWakePush 484, measured 13.09 15:20: the first knock stood five seconds on a door that had
     * never answered on this network while three others had answered a second before): proof is what the app already knows — the
     * freshest first, an unproven door after them, a resting one last; with no proof at all, the network's own order.
     */
    fun byProof(doors: List<String>): List<String> = synchronized(deadUntil) {
        val now = System.currentTimeMillis()
        doors.sortedWith(compareBy({ if (now < (deadUntil[it] ?: 0L)) 2 else if (proof.containsKey(host(it))) 0 else 1 }, { -(proof[host(it)] ?: 0L) }))
    }
    private fun host(door: String) = android.net.Uri.parse(door).host ?: door
    /** The doors alive for me, in the network's order — what I name to the peer with every word (iOS signalDoors 500-503). */
    fun aliveHosts(): List<String> = Doors.ordered("signal").filter { doorAlive(it) }.map { host(it) }
    fun proveDoor(door: String) { synchronized(deadUntil) { proof[host(door)] = System.currentTimeMillis() } }

    // ═══ THE ELECTED DOOR (iOS 1638, the author's word; MontanaWakePush 281-316) ═══
    // The phone elects ONE live node and works with it: every write starts at the elected door and walks on only past its death; a
    // read that looks for what another phone wrote — the box, the chunks — sweeps every store, since that phone elected its own.
    // iOS also sets it first in the order of the signal doors (orderedBases); that order stays the network's here — two phones that
    // elected different doors would otherwise ask their conversation's door at two places (the finding for iOS, HANDOVER 08.10 11:2x).
    private const val ELECTED = "mt.door.elected"
    @Volatile private var elected: String? = null
    fun elected(): String? = elected ?: Prefs.str(ELECTED, "").ifEmpty { null }?.also { elected = it }

    /** The doors of a write (iOS electedFirst 294-297 over the capability's doors, base 300-316): the elected first, elected now if none stands. */
    fun writeOrder(cap: String): List<String> {
        val all = Doors.ordered(cap)
        val e = elected()
        if (e != null && e in all) return listOf(e) + all.filter { it != e }
        val pick = all.firstOrNull { doorAlive(it) } ?: all.firstOrNull() ?: return all
        elected = pick
        Prefs.setStr(ELECTED, pick)
        Log.d("Montana", "door_elected " + host(pick))
        return listOf(pick) + all.filter { it != pick }
    }

    // ═══ ONE DOOR FOR SIGNALS (iOS 410-445, 15.2) ═══
    // Measured 04.09 22:40-23:00: each draft word went to three doors, the question walked a fourth rule — the two sides never shared
    // one. The lane has one decision point: elected by the network's order among the doors holding the signal, kept while it answers.
    private var chosen: String? = null
    fun signalDoor(): String {
        val order = Doors.ordered("signal")
        var fresh: String? = null
        val pick = synchronized(deadUntil) {
            val now = System.currentTimeMillis()
            val all = order.filter { (deadUntil[it] ?: 0L) <= now }
            val c = chosen
            if (c != null && c in all) c else (all.firstOrNull() ?: order.firstOrNull())?.also { chosen = it; fresh = it } ?: ""
        }
        fresh?.let { Log.d("Montana", "sig_door elected " + host(it)) }
        return pick
    }

    // ── where the peer listens (iOS notePeerDoor/peerDoors 554-573) ──
    private val peerBook = HashMap<String, Pair<List<String>, Long>>()
    /** The doors alive for the peer, in their order, named in their word — the draft's «d», the beacon's «@» tail. */
    fun notePeerDoor(ref: String, named: String) {
        val hs = named.lowercase().split(',').filter { h -> h.isNotEmpty() && h.length <= 64 && h.all { it.isLetterOrDigit() || it == '.' || it == '-' } }
        if (hs.isEmpty() || hs.size > 16) return
        val old = synchronized(peerBook) { peerBook.put(ref, hs to System.currentTimeMillis())?.first }
        if (old != hs) Log.d("Montana", "sig_door peer listens at " + hs.joinToString(","))
    }
    /** What they named, while it is fresh — three beats of twenty seconds; else null, and a word knocks every living door. */
    fun peerDoors(ref: String): List<String>? = synchronized(peerBook) { peerBook[ref]?.takeIf { System.currentTimeMillis() - it.second < 60_000L }?.first }
    /**
     * THE DOOR OF A CONVERSATION (iOS signalDoor(for:) 505-518) — one rule both sides compute alike: the first door, in the network's
     * own order, alive for me and named alive by the peer. Measured 05.09: one phone under its tunnel could not reach the first
     * door, the other on cellular could not reach the second — each posted into the other's hole. No common door yet — mine.
     */
    fun signalDoor(ref: String): String {
        val mine = signalDoor()
        val theirs = peerDoors(ref) ?: return mine
        return Doors.ordered("signal").firstOrNull { doorAlive(it) && host(it) in theirs } ?: mine
    }
    /** THE DOORS OF A CALL (iOS callDoors 475-492): alive and proven first, alive after them, the doors resting dead last. */
    fun callDoors(): List<String> {
        val all = Doors.ordered("signal")
        val alive = all.filter { doorAlive(it) }
        val proven = synchronized(deadUntil) { proof.keys.toSet() }
        return alive.filter { host(it) in proven } + alive.filter { host(it) !in proven } + all.filter { it !in alive }
    }

    // ── the lanes (iOS sigSessions and postLane: networkPathChanged 520-537, cutStandingQuestion 538-551) ──
    private const val CUT = -2
    private val asking = HashSet<java.net.HttpURLConnection>()   // the long questions in flight (iOS sigSessions)
    private val laneGen = java.util.concurrent.atomic.AtomicInteger()
    private val posting = HashSet<java.net.HttpURLConnection>()   // the words in flight (iOS postLane)
    private val postGen = java.util.concurrent.atomic.AtomicInteger()
    /** A post on the lane: cut by a path change, it leaves again at once on the fresh path — and the cut teaches nothing of the door. */
    private fun onLane(ask: (MutableSet<java.net.HttpURLConnection>) -> Pair<Int, String?>): Pair<Int, String?> {
        repeat(2) {
            val gen = postGen.get()
            val got = ask(posting)
            if (gen == postGen.get()) return got
        }
        return CUT to null
    }
    /**
     * THE STANDING QUESTION IS CUT (iOS cutStandingQuestion 538-551) — one move for two facts: the network path changed, the lane's
     * door died. Every question in flight fails this instant, and each conversation asks again at once, at its door as it stands now.
     * The words in flight are cut by a path change only (iOS networkPathChanged 529-537 swaps the post lane): a word on its way to
     * a door that just died is that door's own answer to wait for.
     */
    private fun cut(why: String, posts: Boolean = false) {
        laneGen.incrementAndGet()
        if (posts) postGen.incrementAndGet()
        val held = synchronized(asking) { asking.toList().also { asking.clear() } } + if (posts) synchronized(posting) { posting.toList().also { posting.clear() } } else emptyList()
        Thread { for (c in held) runCatching { c.disconnect() } }.start()
        Log.d("Montana", "sig_lane " + why + " — asking again now")
    }

    private var pathWatched = false
    /** THE NETWORK PATH CHANGED (iOS 516-528): dead on one path says nothing of another — every door is forgiven at once. */
    fun watchPath(c: Context) {
        if (pathWatched) return
        pathWatched = true
        val cm = c.getSystemService(android.net.ConnectivityManager::class.java) ?: return
        runCatching {
            cm.registerDefaultNetworkCallback(object : android.net.ConnectivityManager.NetworkCallback() {
                // THE DOORS ARE JUDGED AGAIN ONCE, ON THE FIRST SATISFIED PATH AFTER THE NETWORK CHANGED (iOS 1989, MontanaNetWitness):
                // not on the change itself — a path lost and found again inside a second judged every door twice for nothing
                override fun onAvailable(n: android.net.Network) {
                    val sig = n.toString()
                    if (sig == judgedOn) return
                    judgedOn = sig
                    forgive("path available")
                }
                override fun onLost(n: android.net.Network) = cut("path lost — the questions on its socket are cut", posts = true)
            })
        }
    }
    @Volatile private var judgedOn: String? = null
    private fun forgive(why: String) {
        synchronized(deadUntil) { deadUntil.clear(); doorFails.clear(); deathStreak.clear(); proof.clear(); chosen = null }   // proof on one path says nothing of another
        Wire.forgetGone()   // a new path may reach a store the old one could not
        cut(why + " — every door forgiven, every lane cut", posts = true)   // the questions in flight stood on the old path's socket (iOS 520-537)
    }

    /**
     * The words that landed for `ref`: opened by the minute (this one and its neighbours), unpacked, handed on by their epoch —
     * «chat» to the presence, any other to the call it names; «box» hints fetch the box.
     */
    private fun open(ref: String, envs: org.json.JSONArray) {
        val secret = Book.secret(ref) ?: return
        for (k in 0 until envs.length()) {
            val e = envs.optString(k)
            if (e == "box") { Thread { Post.fetch() }.start(); continue }
            val sealed = runCatching { Base64.decode(e, Base64.DEFAULT) }.getOrNull() ?: continue
            val w0 = Wire.minute()
            val plain = listOf(w0, w0 - 1, w0 + 1).firstNotNullOfOrNull { w -> Wire.open(Wire.bodyKey(secret, w), sealed) } ?: continue
            Meeting.firstDone(ref)   // a word under the pipe proves the other side holds it, on this road too (iOS 1961)
            val a = plain.indexOf(0); if (a < 0) continue
            val b = (a + 1 until plain.size).firstOrNull { plain[it] == 0.toByte() } ?: continue
            val epoch = String(plain, a + 1, b - a - 1, Charsets.UTF_8)
            val words = inflate(plain.copyOfRange(b + 1, plain.size))?.takeIf { it.isNotEmpty() } ?: continue
            if (epoch == "chat") Presence.hear(ref, String(words, Charsets.UTF_8)) else Calls.hear(ref, epoch, words)
        }
    }

    /**
     * THE LAST WORD OF EVERY PEER, IN ONE QUESTION (iOS sweepPresence, WakePush 3180-3269; the author's word 11.09: «T2 does not see
     * that T1 was online until the chat is opened»): the lane hands over a minute of words, the node keeps each side's last sealed word
     * for the box's term (/signal-last), and this asks for all of them at once — at the app's return and on the coin. A swept word is a
     * stamp, never a live word (Presence.stamp). It opens by the node's own moment (Wire.openBoxed): iOS opens it by the minute of the
     * question, so there a word older than two minutes never opens (HANDOVER, session 7).
     */
    fun sweep() {
        val twin = MontanaSeed.twin ?: return
        val q = ArrayList<JSONObject>()
        val chatOf = HashMap<String, String>()
        val w0 = Wire.day()
        for (ref in Book.refs()) {
            val secret = Book.secret(ref) ?: continue
            for (w in (w0 - 1)..w0) {
                val cw = Wire.convW(secret, w)
                chatOf[cw] = ref
                q.add(JSONObject().put("conv", cw).put("from_id", Wire.subId(cw, twin)))
            }
        }
        if (q.isEmpty()) return
        val best = HashMap<String, Pair<String, Long>>()   // per conversation, the newest word across the doors (env, the node's second)
        var doors = 0
        for (door in Doors.ordered("signal").filter { doorAlive(it) }) {
            for (start in q.indices step 128) {
                val part = org.json.JSONArray(q.subList(start, minOf(start + 128, q.size)))
                val (code, text) = Wire.post(door, "/signal-last", JSONObject().put("q", part), 6000)
                // a door that does not know the question answers 404 and is skipped (iOS [P2P-COMPAT])
                val rows = (if (code == 200 && text != null) runCatching { JSONObject(text).optJSONArray("last") }.getOrNull() else null) ?: continue
                doors++
                for (i in 0 until rows.length()) {
                    val r = rows.optJSONObject(i) ?: continue
                    val chat = chatOf[r.optString("conv")] ?: continue
                    val env = r.optString("env"); val at = r.optLong("at")
                    if (env.isNotEmpty() && (best[chat]?.second ?: 0L) < at) best[chat] = env to at
                }
            }
        }
        var words = 0
        for ((chat, w) in best) {
            val secret = Book.secret(chat) ?: continue
            val sealed = runCatching { Base64.decode(w.first, Base64.DEFAULT) }.getOrNull() ?: continue
            val plain = Wire.openBoxed(sealed, secret, w.second) ?: continue
            val a = plain.indexOf(0); if (a < 0) continue
            val b = (a + 1 until plain.size).firstOrNull { plain[it] == 0.toByte() } ?: continue
            if (String(plain, a + 1, b - a - 1, Charsets.UTF_8) != "chat") continue
            val text = inflate(plain.copyOfRange(b + 1, plain.size))?.takeIf { it.isNotEmpty() } ?: continue
            Presence.stamp(chat, String(text, Charsets.UTF_8), w.second * 1000)
            words++
        }
        Log.d("Montana", "presence_sweep convs=" + chatOf.size / 2 + " doors=" + doors + " words=" + words)
    }

    private val holders = HashMap<String, MutableSet<String>>()
    private val running = HashMap<String, Int>()

    /** THE LANE OF ONE CONVERSATION stands while anyone holds it — the open chat, a call ringing — one long question, at its door. */
    fun hold(ref: String, why: String) {
        val start = synchronized(holders) {
            holders.getOrPut(ref) { mutableSetOf() }.add(why)
            ((running[ref] ?: 0) == 0).also { if (it) running[ref] = 1 }
        }
        if (start) listen(ref)
    }

    fun release(ref: String, why: String) {
        synchronized(holders) { holders[ref]?.let { it.remove(why); if (it.isEmpty()) holders.remove(ref) } }
    }

    /**
     * THE APP'S EAR (what the platform's call push — PushKit — gives the iPhone, this phone keeps for itself on our own doors, with
     * no third party): while the app stands — in front, or closed under its EarService — the lane of every conversation is held, so a call's first word rings here
     * the millisecond it lands — as an iPhone's ring does — not at the box's next round. The doors read a held lane as «this
     * phone is here» and keep the bell of a letter silent: the person is here, its screen is receiving it.
     */
    fun ear(on: Boolean) {
        for (ref in Book.refs()) if (on && !PeerSafety.isBlocked(ref)) hold(ref, "ear") else release(ref, "ear")
    }

    /**
     * THE LONG QUESTION (iOS fetchSignals 3270-3321): the conversation's door asked with a wait of twelve seconds — the doors' gate
     * cuts at fifteen — and asked again the moment it answers, while the lane is held.
     */
    private fun listen(ref: String) {
        Thread {
            var fails = 0
            while (true) {
                val twin = MontanaSeed.twin
                val secret = Book.secret(ref)
                val go = synchronized(holders) {
                    val ok = twin != null && secret != null && !holders[ref].isNullOrEmpty()
                    if (!ok) running[ref] = (running[ref] ?: 1) - 1
                    ok
                }
                if (!go || twin == null || secret == null) return@Thread
                // ONE QUESTION, AT THE CONVERSATION'S DOOR (iOS fetchSignals 3276-3277): the first door alive for both, or mine
                val door = signalDoor(ref)
                if (door.isEmpty()) { Thread.sleep(2000); continue }
                val gen = laneGen.get()
                val cw = Wire.convW(secret, Wire.day())
                // WHILE A CALL IS BUILT THE QUESTIONS ARE SHORT (iOS fetchSignals 3286-3299): a silently dead one costs six seconds, not
                // thirty — three while it rings or connects, ten in a joined call, twelve at rest (the doors' nginx holds fifteen)
                val wait = if (Calls.busy() && CallLine.connectedAt == 0L) 3 else if (CallLine.connectedAt > 0L) 10 else 12
                val (code, text) = Wire.post(door, "/signal-fetch", JSONObject().put("conv", cw).put("from_id", Wire.subId(cw, twin)).put("wait", wait), (wait + 3) * 1000, asking)
                // CUT BY OUR OWN HAND (iOS 3304-3307, 3317): the fresh lane asks now, and a question we cut says nothing of the door
                if (gen != laneGen.get()) { fails = 0; continue }
                EarService.awake()   // the answer woke the phone: it stays up for the word and the next question (the app closed)
                if (code != 200 || text == null) { doorFailed(door, code); fails++; Thread.sleep(minOf(10_000L, 1000L * fails)); continue }
                doorAnswered(door)
                fails = 0
                runCatching { JSONObject(text).optJSONArray("envs") }.getOrNull()?.let { envs -> if (envs.length() > 0) open(ref, envs) }
            }
        }.start()
    }
}

/**
 * THE PRESENCE LADDER (iOS ChatStore presenceWord): «typing…» lives five seconds, «in chat» and «online» one life of 45 —
 * two beats of the 20-second heartbeat and a margin; a departure word ends it at once; a word older than its life is history
 * and lights nothing (the lane hands over a minute of words when a chat opens). When no live word stands, the stamp: «last
 * seen…» — exact when both share it, the coarse class when either hides.
 */
object Presence {
    const val TYPING = "​​TY:"
    const val WATCH = "​​WA:"   // «1» my chat with you is on my screen, «0» left it
    const val APP = "​​AP:"     // «1» the app is on my screen, «0» left it; «0B» — gone for good
    private const val TYPING_LIFE = 5_000L
    private const val WORD_LIFE = 45_000L
    const val BEAT = 20_000L
    private const val CLOCK_SLACK = 2_000L   // iOS clockSlackS: two clocks and the node's whole second may differ by this much

    private val typingUntil = HashMap<String, Long>()
    private val inChatUntil = HashMap<String, Long>()
    private val onlineUntil = HashMap<String, Long>()
    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() {
        val ls = synchronized(listeners) { listeners.toList() }
        MainThread.post { ls.forEach { it() } }
    }

    val sharing get() = Prefs.bool("presenceSharing", true)
    /**
     * THE PERSON HIDES, AND SAYS SO ONCE (iOS MontanaPresencePrivacy.setSharing, E2E.presenceFarewell 849-855): one honest word
     * «0h» to everyone I speak presence to — an old reader takes the digit and the word dies, a new one reads the tail and coarsens
     * my stamp at once — then silence; shown again, «here» at once. Android went silent without the word: their phones kept my exact
     * moment and, for the word's life, «online».
     */
    fun setSharing(v: Boolean) {
        if (v == sharing) return
        Prefs.setBool("presenceSharing", v)
        if (v) Thread { sayApp(true) }.start()
        else Thread { for (ref in Book.refs()) if (SamePair.merged(ref) == null && !PeerSafety.isBlocked(ref)) Signal.post(ref, APP + "0h") }.start()
    }
    /** The moment a word was said, as iOS says it (E2E.saidTail): «T» + seconds + «.» + three digits of milliseconds. */
    fun saidTail(now: Long = System.currentTimeMillis()) = "T" + (now / 1000) + "." + (1000 + now % 1000).toString().drop(1)
    private val saidRe = Regex("T(\\d{9,11})\\.(\\d{3})")
    private fun said(payload: String): Long? = saidRe.find(payload)?.let { m -> m.groupValues[1].toLong() * 1000 + m.groupValues[2].toLong() }

    // ── what I say ──
    fun sayTyping(ref: String) { if (sharing) Signal.post(ref, TYPING + saidTail()) }
    fun sayChat(ref: String, open: Boolean) { if (sharing) Signal.post(ref, WATCH + (if (open) "1" else "0") + saidTail() + heldTail(ref) + doorTail()) }

    /** The tag a word names a thing by (iOS Announced.wireTag, MontanaDeliveryEngine 417-422): SHA-256's first four bytes, big-endian, in digits; none — «0». */
    fun wireTag(d: ByteArray?): String {
        if (d == null || d.isEmpty()) return "0"
        val h = java.security.MessageDigest.getInstance("SHA-256").digest(d)
        return (((h[0].toLong() and 0xff) shl 24) or ((h[1].toLong() and 0xff) shl 16) or ((h[2].toLong() and 0xff) shl 8) or (h[3].toLong() and 0xff)).toString()
    }
    private val heldFace = HashMap<String, Pair<Long, String>>()   // ref -> (the face file's moment, its tag): a file is new every update
    /**
     * WHAT I HOLD OF YOU, in every presence word (iOS heldTail, MontanaE2E 543-568; fork atom 1778): «F» + the tag of your face on my
     * screen, «N» + the tag of your name — digits only, after the moment, so every older reader reads nothing of it. The peer compares
     * with what it is and sends again what my screen holds stale.
     */
    private fun heldTail(ref: String): String {
        val f = Book.face(ref)
        val face = if (!f.exists()) "0" else synchronized(heldFace) {
            heldFace[ref]?.takeIf { it.first == f.lastModified() }?.second ?: wireTag(f.readBytes()).also { heldFace[ref] = f.lastModified() to it }
        }
        val n = Book.chat(ref)?.name.orEmpty()
        return "F" + face + "N" + wireTag(if (n.isEmpty()) null else n.toByteArray(Charsets.UTF_8))
    }
    /**
     * WHAT THEY HOLD OF ME, heard in their word (iOS heardHeld 629-667): their screen's tags of my face and my name against what I am —
     * a difference forgets the receipted mark and announces anew, at most once a minute a person. Android read nothing of it: an
     * iPhone that held an old face of this phone kept it for ever.
     */
    private val heldAskedAt = HashMap<String, Long>()
    private fun heardHeld(ref: String, payload: String) {
        fun digits(after: Char): String? {
            val i = payload.indexOf(after); if (i < 0) return null
            return payload.substring(i + 1).takeWhile { it.isDigit() }.ifEmpty { null }
        }
        val f = digits('F') ?: return
        val n = digits('N') ?: return
        val faceOff = f != wireTag(SelfFace.bytes(Book.ctx))
        val nameOff = n != wireTag(Prefs.userName.trim().takeIf { it.isNotEmpty() }?.toByteArray(Charsets.UTF_8))
        if (!faceOff && !nameOff) return
        val now = System.currentTimeMillis()
        synchronized(heldAskedAt) { if (now - (heldAskedAt[ref] ?: 0L) < 60_000L) return; heldAskedAt[ref] = now }
        Log.d("Montana", "held_differs face=" + (if (faceOff) 1 else 0) + " name=" + (if (nameOff) 1 else 0))
        Thread { Post.announceAgain(ref, faceOff, nameOff) }.start()
    }
    /** «@DOORS» — the doors alive for me, in the chat word's tail (iOS doorTail 685-691): UPPERCASE, so no old reader takes a host's «h» for hiding. */
    private fun doorTail() = Signal.aliveHosts().joinToString(",").let { if (it.isEmpty()) "" else "@" + it.uppercase() }
    fun sayApp(open: Boolean) {
        if (!sharing) return
        for (ref in Book.refs()) if (SamePair.merged(ref) == null && !PeerSafety.isBlocked(ref)) Signal.post(ref, APP + (if (open) "1" else "0") + saidTail() + heldTail(ref))
    }

    /** A blocked person's live words leave with the block (iOS toggleBlocked 979: typing and watching removed). */
    fun drop(ref: String) {
        typingUntil.remove(ref); inChatUntil.remove(ref); onlineUntil.remove(ref)
        changed()
    }

    // ── what I hear ──
    /** A word of the lane from `ref` (iOS append's presence branches + liveWordMoves). */
    fun hear(ref: String, text: String) {
        if (PeerSafety.isBlocked(ref)) return   // a blocked person reaches nothing
        // THEIR LIVE DRAFT (iOS handleMeshDraft): its bubble, and «typing…» when it is a keystroke said now
        if (text.startsWith(LiveDraft.MARK)) { if (LiveDraft.hear(ref, text)) hear(ref, TYPING + saidTail()); return }
        val now = System.currentTimeMillis()
        val at = said(text)
        val age = at?.let { (now - it).coerceAtLeast(0) } ?: 0L
        when {
            text.startsWith(TYPING) -> {
                if (age > TYPING_LIFE + 2000) { noteSeen(ref, at); return }   // a keystroke a minute old is not typing now
                typingUntil[ref] = now + TYPING_LIFE - age
                inChatUntil[ref] = now + WORD_LIFE - age; onlineUntil[ref] = now + WORD_LIFE - age   // typing proves the chat is on their screen
                MainThread.later(TYPING_LIFE - age + 50) { changed() }
            }
            text.startsWith(WATCH) || text.startsWith(APP) -> {
                val chat = text.startsWith(WATCH)
                val payload = text.removePrefix(if (chat) WATCH else APP)
                // THE DOORS THEY ASK (iOS ChatStore 3910-3912, WakePush 3252): my words for them go there
                payload.indexOf('@').takeIf { it >= 0 }?.let { Signal.notePeerDoor(ref, payload.substring(it + 1)) }
                hides(ref, payload.drop(1).contains('h'), at ?: now)
                val open = payload.startsWith("1")
                if (age <= WORD_LIFE) Board.heardPresence(ref, payload)   // their wall's version (iOS heardHeld, wallHeard)
                if (age <= WORD_LIFE) heardHeld(ref, payload)   // only a word said now says what their screen holds
                if (age <= WORD_LIFE) {
                    if (open) {
                        if (chat) inChatUntil[ref] = now + WORD_LIFE - age
                        onlineUntil[ref] = now + WORD_LIFE - age
                        MainThread.later(WORD_LIFE - age + 50) { changed() }
                    } else {
                        inChatUntil.remove(ref); typingUntil.remove(ref)
                        if (!chat) onlineUntil.remove(ref)
                    }
                }
                if (!chat && payload.drop(1).startsWith("B")) gone(ref, at ?: now)
                else if (open) back(ref, at ?: now)
            }
            else -> return
        }
        noteSeen(ref, at ?: now)
        changed()
    }

    /** THE ONE WRITER OF THE STAMP (iOS noteSeen): a moment never later than now, never earlier than the one held. */
    fun noteSeen(ref: String, atMs: Long?) {
        val ts = minOf(atMs ?: return, System.currentTimeMillis())
        if (ts <= seenAt(ref)) return
        Prefs.setStr("seenAt.$ref", ts.toString())
        changed()
    }

    private fun seenAt(ref: String) = Prefs.str("seenAt.$ref", "0").toLongOrNull() ?: 0L

    /**
     * A SWEPT WORD IS A STAMP (iOS sweepPresence 3232-3264): history never lights «online» or «in chat» (13.09 15:15 — a «1» swept
     * twelve seconds after a phone locked lit «in chat» for a locked phone); it says when the peer was there, its hiding, its doors
     * and «gone». The word's own moment stands unless it runs ahead of the node's by more than the clocks' slack: a clock set ahead
     * said it, and the node's moment stands (iOS 24.09). A draft or a typing word is proof of the moment alone.
     */
    fun stamp(ref: String, text: String, nodeAt: Long) {
        if (PeerSafety.isBlocked(ref)) return
        val at = said(text)?.let { if (it - nodeAt > CLOCK_SLACK + 1000) nodeAt else it } ?: nodeAt
        val app = text.startsWith(APP)
        if (app || text.startsWith(WATCH)) {
            val payload = text.removePrefix(if (app) APP else WATCH)
            hides(ref, payload.drop(1).contains('h'), at)
            payload.indexOf('@').takeIf { it >= 0 }?.let { Signal.notePeerDoor(ref, payload.substring(it + 1)) }
            if (app && payload.drop(1).startsWith("B")) gone(ref, at) else if (app) back(ref, at)
        }
        noteSeen(ref, at)
        changed()
    }

    /** THE PEER'S HIDING, BY ITS MOMENT (iOS notePeerHides 322-329): an older word never undoes a newer one. */
    private fun hides(ref: String, h: Boolean, at: Long) {
        if (at < (Prefs.str("phideAt_$ref", "0").toLongOrNull() ?: 0L)) return
        Prefs.setStr("phideAt_$ref", at.toString())
        Prefs.setBool("phide_$ref", h)
    }
    /** «GONE FOR GOOD» AND ITS END, BY THEIR MOMENTS (iOS peerGone / peerBack 1720-1732): a word older than the farewell ends nothing. */
    private fun gone(ref: String, at: Long) {
        if (at < goneAt(ref)) return
        Prefs.setStr("peerGoneAt.$ref", at.toString())
        Prefs.setBool("peerGone.$ref", true)
        inChatUntil.remove(ref); typingUntil.remove(ref); onlineUntil.remove(ref)
    }
    private fun back(ref: String, at: Long) {
        if (!Prefs.bool("peerGone.$ref", false) || at <= goneAt(ref)) return
        Prefs.remove("peerGone.$ref"); Prefs.remove("peerGoneAt.$ref")
    }
    private fun goneAt(ref: String) = Prefs.str("peerGoneAt.$ref", "0").toLongOrNull() ?: 0L

    /** THE MOMENT BEHIND THE LINE, as a number to sort by (iOS presenceStamp): a live word above every stamp, «gone» at the bottom. */
    fun stamp(ref: String): Long {
        val now = System.currentTimeMillis()
        if ((typingUntil[ref] ?: 0) > now) return now + 3
        if ((inChatUntil[ref] ?: 0) > now) return now + 2
        if ((onlineUntil[ref] ?: 0) > now) return now + 1
        if (Prefs.bool("peerGone.$ref", false)) return 1
        return seenAt(ref)
    }

    /** The one presence line (iOS presenceWord): the words and whether they are live (green). null — nothing is known. */
    fun word(c: Context, ref: String): Pair<String, Boolean>? {
        val now = System.currentTimeMillis()
        if ((typingUntil[ref] ?: 0) > now) return c.getString(R.string.pr_typing) to true
        if ((inChatUntil[ref] ?: 0) > now) return c.getString(R.string.pr_in_chat) to true
        // a person on the line with me is present for as long as the call stands (iOS presenceWord 15.7)
        if (Calls.talking() == ref) return c.getString(R.string.pr_on_call) to true
        if ((onlineUntil[ref] ?: 0) > now) return c.getString(R.string.pr_online) to true
        if (Prefs.bool("peerGone.$ref", false)) return c.getString(R.string.pr_seen_long_ago) to false
        val seen = seenAt(ref).takeIf { it > 0 } ?: return null
        val exact = sharing && !Prefs.bool("phide_$ref", false)
        return (if (exact) phrase(c, seen) else coarse(c, seen)) to false
    }
    /** iOS MontanaSeen.coarse: the class, never the minute. */
    private fun coarse(c: Context, ts: Long): String {
        val d = System.currentTimeMillis() - ts
        return c.getString(when {
            d < 3 * 86_400_000L -> R.string.pr_seen_recently
            d < 7 * 86_400_000L -> R.string.pr_seen_week
            d < 30 * 86_400_000L -> R.string.pr_seen_month
            else -> R.string.pr_seen_long_ago
        })
    }
    /** iOS MontanaSeen.phrase: minutes within the hour (never under one), «today at», «yesterday at», else the day. */
    private fun phrase(c: Context, ts: Long): String {
        val diff = System.currentTimeMillis() - ts
        if (diff < 3_600_000L) { val m = maxOf(1, (diff / 60_000L).toInt()); return c.resources.getQuantityString(R.plurals.pr_minutes, m, m) }
        val time = android.text.format.DateFormat.getTimeFormat(c).format(java.util.Date(ts))
        if (android.text.format.DateUtils.isToday(ts)) return c.getString(R.string.pr_today_at, time)
        if (android.text.format.DateUtils.isToday(ts + 86_400_000L)) return c.getString(R.string.pr_yesterday_at, time)
        return android.text.format.DateUtils.formatDateTime(c, ts, android.text.format.DateUtils.FORMAT_SHOW_DATE)
    }

    // ── the app's own beat (iOS appBeacon + the 20-second heartbeat) ──
    private var appOpen = false
    private val beat = object : Runnable {
        override fun run() { if (appOpen) { Thread { sayApp(true) }.start(); MainThread.later(BEAT, this) } }
    }
    /** The app stands on the person's screen (iOS: the scene is active). */
    val shown: Boolean get() = appOpen
    fun appShown() { if (appOpen) return; appOpen = true; MainThread.post { beat.run() } }
    fun appHidden() { if (!appOpen) return; appOpen = false; Thread { sayApp(false) }.start() }
    fun log(s: String) = Log.d("Montana", "presence: $s")

    /**
     * «The app is on my screen» follows the activity's own life (iOS: the scene's phase) — watched from here, so no other
     * file carries it: registered once, on the first pickup of the box (which runs only while the app stands).
     */
    private var watching = false
    fun watchApp(c: Context) {
        if (watching) return
        watching = true
        Signal.watchPath(c)
        Channels.start()   // the phone holds its nodes for the app's whole life (iOS MontanaNodes.open)
        Mesh.start(c)   // and, while the person lets it, is findable on the local network (iOS startLocalMeshIfAccepted)
        (c.applicationContext as android.app.Application).registerActivityLifecycleCallbacks(object : android.app.Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(a: android.app.Activity) = appShown()
            override fun onActivityPaused(a: android.app.Activity) = appHidden()
            override fun onActivityCreated(a: android.app.Activity, b: android.os.Bundle?) {}
            override fun onActivityStarted(a: android.app.Activity) {}
            override fun onActivityStopped(a: android.app.Activity) {}
            override fun onActivitySaveInstanceState(a: android.app.Activity, b: android.os.Bundle) {}
            override fun onActivityDestroyed(a: android.app.Activity) {}
        })
        // on the screen only when an activity really stands in front — a pickup from a background job must not say «online»;
        // the callbacks above say it when the activity resumes later
        val me = android.app.ActivityManager.RunningAppProcessInfo().also { android.app.ActivityManager.getMyMemoryState(it) }
        if (me.importance <= android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) appShown()
    }
}
