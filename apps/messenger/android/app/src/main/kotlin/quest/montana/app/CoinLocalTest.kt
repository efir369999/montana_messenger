package quest.montana.app

import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

// THE COIN CHAINS WALKED ON THIS PHONE ALONE (the owner's task 17.10.2026: «подготовь полностью локальный тест операций GENESIS,
// MINT, SEND и RECV с проверкой подписей, балансов и невозможности повторного зачисления»). Two chain nodes stand here, in memory,
// by the rules COIN-TX-V3 states for the nodes (sections 2, 3, 5): a record is taken only when the core verifies it, on its key's own
// chain node, on top of that chain's head, and when the chain's fold holds; a RECV claims its SEND at the SEND's node, once, within the
// SEND's day; a REFUND only after it, on the sender's chain, of a SEND nobody took. The clients are CoinClient -- the very code the phone
// lays and reads the network with -- over throwaway keys, a pipe of the test's own and books of their own: nothing touches the network,
// the person's coin key or the person's book. Beside them two vault nodes in memory and VaultClient, the code the seed's book rides the
// nodes with (CoinVault), over throwaway seeds. Run by `am start -S … --ez coinLocalTest true` on a test build; the diary says each step.

/** A book in memory: the balance, and every move by its name, as the phone's book keeps them (CoinBook). */
class MemoryLedger(start: Long = 0) : CoinLedger {
    private val moves = HashMap<String, Long>()
    override var balance: Long = start
        private set
    fun credit(coins: Long) { balance += coins }
    override fun send(coins: Long, peer: String, ref: String): Boolean {
        if (coins <= 0 || balance < coins || moves.containsKey("send:$ref")) return false
        moves["send:$ref"] = coins; balance -= coins; return true
    }
    override fun receive(coins: Long, peer: String, ref: String): Boolean {
        if (coins <= 0 || moves.containsKey("receive:$ref")) return false
        moves["receive:$ref"] = coins; balance += coins; return true
    }
    override fun retake(coins: Long, peer: String, ref: String): Boolean {
        if (coins <= 0 || moves.containsKey("send:$ref")) return false
        moves["send:$ref"] = coins; balance -= coins; return true
    }
    override fun holds(kind: String, ref: String) = moves.containsKey("$kind:$ref")
}
class MemoryMemo : CoinMemo {
    private val peers = HashMap<String, String>()
    private var open = JSONArray()
    private val pending = LinkedHashMap<String, ByteArray>()
    override fun peerFrom(conv: String) = peers[conv]
    override fun notePeerFrom(conv: String, from: String) { peers[conv] = from }
    override fun openSends() = JSONArray(open.toString())
    override fun keepOpen(a: JSONArray) { open = JSONArray(a.toString()) }
    override fun keepPending(id: String, rec: ByteArray) { pending[id] = rec }
    override fun dropPending(id: String) { pending.remove(id) }
    override fun pendings() = pending.values.toList()
}

/**
 * ONE CHAIN NODE IN MEMORY (COIN-TX-V3 sections 2, 3, 5): its own chains, a replica of its sibling's SENDs, the claim of every SEND of
 * its chains, and the doors the client knocks at -- /tx-head, /tx-get, /tx-put, /tx-settle, /tx-pair -- and the sibling's /tx-claim.
 */
class CoinLocalNode(val name: String, private val clock: () -> Long) {
    lateinit var sibling: CoinLocalNode
    class Held(val bytes: ByteArray, val r: CoinTx.Record, val at: Long, val seq: Long)
    private val byId = HashMap<String, Held>()
    private val log = ArrayList<Held>()
    private val states = HashMap<String, CoinRules.St>()
    private val sends = HashMap<String, CoinRules.SendInfo>()        // the SENDs of this node's chains
    private val claims = HashMap<String, Pair<String, String>>()     // a SEND's fate: «recv» and the receiver's from, or «refund»
    private val settled = HashSet<String>()                         // SENDs a RECV or a REFUND on this node's chains settled
    private var seq = 0L
    fun records(): List<Held> = synchronized(this) { log.toList() }
    fun state(from: String): CoinRules.St? = synchronized(this) { states[from] }
    private fun ok(o: JSONObject) = CoinTx.Answer(200, o, false)
    private fun no(code: Int, word: String) = CoinTx.Answer(code, JSONObject().put("error", word), false)
    private fun sendOf(id: String): CoinRules.SendInfo? = sends[id] ?: synchronized(sibling) { sibling.sends[id] }

    fun ask(path: String, body: JSONObject): CoinTx.Answer = synchronized(this) {
        when (path) {
            "/tx-head" -> {
                val s = states[body.optString("from")] ?: CoinRules.St()
                ok(JSONObject().put("head", s.head).put("height", s.height).put("birth", s.birth.toString()).put("mint_end", s.mintEnd.toString())
                    .put("proven", s.proven.toString()).put("declared", s.declared.toString()).put("v3", if (s.v3) 1 else 0).put("now", clock())
                    .put("minted", s.minted.toString()))
            }
            "/tx-get" -> byId[body.optString("id")]?.let { ok(JSONObject().put("rec", Base64.encodeToString(it.bytes, Base64.NO_WRAP))) } ?: no(404, "no record")
            "/tx-settle" -> {
                val c = claims[body.optString("send")]
                ok(JSONObject().put("state", c?.first ?: "open").put("by", c?.second ?: ""))
            }
            "/tx-pair" -> {
                val tags = body.optJSONArray("tags")?.let { a -> (0 until a.length()).map { a.optString(it) }.toSet() } ?: emptySet()
                val since = body.optLong("since", 0)
                val txs = JSONArray()
                for (h in log) if (h.seq > since && Wire.hex(h.r.pair) in tags) txs.put(JSONObject().put("id", h.r.id).put("rec", Base64.encodeToString(h.bytes, Base64.NO_WRAP)))
                ok(JSONObject().put("txs", txs).put("last", seq))
            }
            "/tx-put" -> put(body)
            "/tx-claim" -> claim(body)
            else -> no(404, "no such door")
        }
    }

    /** A record laid at this node's door: the core's signature, the chain's node, the head, the fold, a RECV's claim and a REFUND's day. */
    private fun put(body: JSONObject): CoinTx.Answer {
        val bytes = runCatching { Base64.decode(body.optString("rec"), Base64.DEFAULT) }.getOrNull() ?: return no(400, "no record")
        val r = CoinTx.read(bytes) ?: return no(400, "bad record")   // the core verifies the signature and the shape
        if (r.version != 3) return no(400, "retired")
        if (CoinTx.chainNode(r.from) != name) return no(403, "not this key's chain node")
        val s = states[r.from] ?: CoinRules.St()
        if (r.prev != s.head) return CoinTx.Answer(409, JSONObject().put("error", "not on the head").put("head", s.head), false)
        val at = maxOf(clock(), s.lastAt)
        val kind = CoinRules.Kind.of(r.kind)
        val all = HashMap<String, CoinRules.SendInfo>(sends).apply { putAll(synchronized(sibling) { sibling.sends }) }
        val done = HashSet<String>(settled).apply { addAll(synchronized(sibling) { sibling.settled }) }
        val (next, wait) = CoinRules.step(s, r.rule(), at, all, done)
        if (wait) return no(409, "no such send")
        if (next == null) return no(409, when (kind) {
            CoinRules.Kind.SEND -> "overspend"; CoinRules.Kind.MINT -> "allowance"; CoinRules.Kind.GENESIS -> "genesis"; else -> "settled"
        })
        // A SEND HAS ONE FATE, SET ONCE AT ITS OWN CHAIN NODE (section 5): a RECV claims it there within its day, a REFUND after it
        if (kind == CoinRules.Kind.RECV) {
            val S = all[r.ref] ?: return no(409, "no such send")
            val authority = CoinTx.chainNode(S.from)
            val claimed = if (authority == name) claimHere(r.ref, "recv", r.from, S) else synchronized(sibling) { sibling.claimHere(r.ref, "recv", r.from, S) }
            if (!claimed) return no(409, "settled")
        }
        if (kind == CoinRules.Kind.REFUND) {
            val S = sends[r.ref] ?: return no(409, "settled")
            if (!claimHere(r.ref, "refund", r.from, S)) return no(409, "settled")
        }
        seq++
        val h = Held(bytes, r, at, seq)
        byId[r.id] = h; log.add(h); states[r.from] = next
        if (kind == CoinRules.Kind.SEND) sends[r.id] = CoinRules.SendInfo(r.from, r.coins, at, r.to, r.a)
        if (kind == CoinRules.Kind.RECV || kind == CoinRules.Kind.REFUND) settled.add(r.ref)
        return ok(JSONObject().put("id", r.id))
    }
    /** The authority's one clock decides (section 5): a RECV in time wins once, by its key; a REFUND only after the day, of an untaken SEND. */
    fun claimHere(send: String, state: String, by: String, S: CoinRules.SendInfo): Boolean {
        val c = claims[send]
        if (c != null) return c.first == "recv" && state == "recv" && c.second == by   // the same receiver laid again on a moved head
        val now = clock()
        if (state == "recv" && S.at + 86_400 <= now) return false
        if (state == "refund" && (now < S.at + 86_400 || S.from != by)) return false
        claims[send] = state to by
        return true
    }
    private fun claim(body: JSONObject): CoinTx.Answer {
        val bytes = runCatching { Base64.decode(body.optString("rec"), Base64.DEFAULT) }.getOrNull() ?: return no(400, "no record")
        val r = CoinTx.read(bytes) ?: return no(400, "bad record")
        val S = sends[r.ref] ?: return no(409, "no such send")
        return if (claimHere(r.ref, "recv", r.from, S)) ok(JSONObject().put("ok", true)) else no(409, "settled")
    }
}

object CoinLocalTest {
    private class Check(val name: String, val ok: Boolean, val said: String)

    fun run(): String {
        if (!CoinTx.agrees) return "coin_local refused: the canon's vectors do not hold".also { Log.w("Montana", it) }
        val checks = ArrayList<Check>()
        fun check(name: String, ok: Boolean, said: String = "") { checks.add(Check(name, ok, said)); Log.d("Montana", "coin_local " + (if (ok) "ok   " else "FAIL ") + name + if (said.isEmpty()) "" else " -- $said") }

        var t = 1_792_000_000L   // the nodes' second: before the v2 cut, so a GENESIS may announce a book
        val clock = { t }
        val quest = CoinLocalNode("montana.quest", clock); val xxx = CoinLocalNode("montana.xxx", clock)
        quest.sibling = xxx; xxx.sibling = quest
        val nodes = mapOf(quest.name to quest, xxx.name to xxx)
        // A ROAD THAT LOSES ITS ANSWERS ON ASK (section 11: «if one is down, its keys' records wait»): the node takes the record, the
        // phone hears nothing back -- a put's answer and the reads after it lost while `lose` is up
        var loseFromPut = 0   // armed: the next put is taken and its answer lost, and this many reads after it lost too
        var loseGets = 0
        val door = CoinDoor { node, path, body ->
            val n = nodes[node] ?: return@CoinDoor CoinTx.Answer(-1, null, true)
            if (0 < loseFromPut && path == "/tx-put") { n.ask(path, body); loseGets = loseFromPut - 1; loseFromPut = 0; return@CoinDoor CoinTx.Answer(-1, null, false) }
            if (0 < loseGets && path == "/tx-get") { loseGets--; return@CoinDoor CoinTx.Answer(-1, null, false) }
            n.ask(path, body)
        }

        // throwaway keys, never a person's: S and R on different chain nodes, so a RECV claims its SEND across the two
        fun key(label: String) = CoinTx.hands(Wire.sha(label.toByteArray()))
        val S = key("montana android local coin test S") ?: return "coin_local refused: no key"
        var i = 0
        var R = key("montana android local coin test R 0") ?: return "coin_local refused: no key"
        while (CoinTx.chainNode(R.from) == CoinTx.chainNode(S.from)) { i++; R = key("montana android local coin test R $i") ?: return "coin_local refused: no key" }
        val X = key("montana android local coin test X") ?: return "coin_local refused: no key"
        val pipe = "local:pipe"
        val secret = Wire.sha("montana android local coin test pipe".toByteArray())
        val bookS = MemoryLedger(1000); val bookR = MemoryLedger(0); val bookX = MemoryLedger(0)
        val memoS = MemoryMemo().apply { notePeerFrom(pipe, R.from) }; val memoR = MemoryMemo().apply { notePeerFrom(pipe, S.from) }
        fun client(h: CoinTx.Hands, book: CoinLedger, memo: CoinMemo) = CoinClient(door, book, memo, { h }, { c -> if (c == pipe) secret else null }, { listOf(pipe) }, { true }, clock)
        fun sent(r: CoinClient.Send3) = (r as? CoinClient.Send3.Sent)?.id
        val cs = client(S, bookS, memoS); val cr = client(R, bookR, memoR); val cx = client(X, bookX, MemoryMemo())
        fun st(h: CoinTx.Hands) = cs.chain3(h.from)
        fun raw(h: CoinTx.Hands, rec: ByteArray?) = rec?.let { nodes[CoinTx.chainNode(h.from)]?.ask("/tx-put", JSONObject().put("rec", Base64.encodeToString(it, Base64.NO_WRAP))) }
        check("keys on two chain nodes", CoinTx.chainNode(S.from) != CoinTx.chainNode(R.from), "S at " + CoinTx.chainNode(S.from) + ", R at " + CoinTx.chainNode(R.from))

        // 1. GENESIS: the book's balance before the chain opened, announced as declared; R and X open by a GENESIS of 0
        val g = cs.reconcile(force = true)
        check("S GENESIS announces the book", g != null && g.v3 && g.declared == 1000L && g.proven == 0L && g.height == 1, "declared=${g?.declared} proven=${g?.proven}")
        val gr = cr.reconcile(force = true); cx.reconcile(force = true)
        check("R GENESIS of 0", gr != null && gr.v3 && gr.declared == 0L && gr.proven == 0L && gr.height == 1)

        // 2. MINT: what the book holds above the chain, within the time the interval allows
        bookS.credit(500)
        t += 400
        val m = cs.reconcile(force = true)
        val room = CoinRules.timeA(m?.mintEnd?.minus(m.birth) ?: 0)
        check("S MINT proves the book's surplus within its time", m != null && m.proven == minOf(500L, room) && m.height == 2 && m.minted == m.proven,
            "proven=${m?.proven} allowance=$room")

        // 3. SEND: proven spent first, the rest declared; the commitment hides R until R opens it
        val id1 = sent(cs.send3(1200, pipe))
        val afterSend = st(S)
        val wantDec = maxOf(0L, 1200 - (m?.proven ?: 0))
        check("S SEND 1200 laid", id1 != null && afterSend != null && afterSend.height == 3, "id=" + id1?.take(12))
        check("S chain after the SEND", afterSend != null && afterSend.proven + afterSend.declared == 1500L - 1200L && afterSend.declared == 1000L - wantDec,
            "proven=${afterSend?.proven} declared=${afterSend?.declared}")
        check("S book after the SEND", bookS.balance == 300L, "book=${bookS.balance}")

        // 4. RECV: R's scan finds the SEND by the pair's tag, opens the blind for its own key and claims it at S's node
        val sr = cr.scanPairs("local")
        val afterRecv = st(R)
        check("R scan credits the SEND once", sr != null && sr.credited == 1 && bookR.balance == 1200L, "credited=${sr?.credited} book=${bookR.balance}")
        check("R chain after the RECV", afterRecv != null && afterRecv.proven == 1200L - wantDec && afterRecv.declared == wantDec && afterRecv.height == 2,
            "proven=${afterRecv?.proven} declared=${afterRecv?.declared}")
        val fate = nodes[CoinTx.chainNode(S.from)]?.ask("/tx-settle", JSONObject().put("send", id1))
        check("S's node names R the SEND's taker", fate?.obj?.optString("state") == "recv" && fate.obj.optString("by") == R.from)

        // 5. NO SECOND CREDIT: the scan again, a second RECV record, the book's own name
        val sr2 = cr.scanPairs("local again")
        check("R scan again credits nothing", sr2 != null && sr2.credited == 0 && bookR.balance == 1200L, "credited=${sr2?.credited} book=${bookR.balance}")
        val sendRec = id1?.let { quest.records().plus(xxx.records()).firstOrNull { h -> h.r.id == it } }?.r
        val blind1 = sendRec?.let { CoinRules.blind(secret, it.nonce) }
        val second = blind1?.let { b -> st(R)?.let { s -> CoinTx.build3(CoinRules.Kind.RECV, 1200, s.head, CoinTx.fresh(), to = b, ref = id1, a = sendRec.a, hands = R) } }
        val a2 = raw(R, second)
        check("a second RECV of the same SEND is refused", a2 != null && a2.code == 409, "code=${a2?.code} word=${a2?.obj?.optString("error")}")
        check("the book takes a name once", !bookR.receive(1200, pipe, CoinTx.REF_PREFIX + id1) && bookR.balance == 1200L)

        // 6. OVERSPEND: the client refuses before it signs, and the node refuses a record that tries
        val over = cs.send3(1000, pipe)
        check("S cannot send above its chain", over is CoinClient.Send3.NotApplicable && bookS.balance == 300L, (over as? CoinClient.Send3.NotApplicable)?.why ?: "")
        val s3 = st(S)
        val forged = s3?.let { CoinTx.build3(CoinRules.Kind.SEND, 1000, it.head, CoinTx.fresh(), CoinTx.pairTag(secret), CoinRules.commitment(CoinRules.bytes(R.from)!!, ByteArray(32)), a = 1000, hands = S) }
        val a3 = raw(S, forged)
        check("the node refuses an overspend", a3?.code == 409 && a3.obj?.optString("error") == "overspend", "code=${a3?.code} word=${a3?.obj?.optString("error")}")

        // 7. A SIGNATURE THAT DOES NOT HOLD, A MINT ABOVE TIME, A SECOND GENESIS, A RECORD OFF ITS NODE
        val s4 = st(S)
        val good = s4?.let { CoinTx.build3(CoinRules.Kind.SEND, 10, it.head, CoinTx.fresh(), CoinTx.pairTag(secret), CoinRules.commitment(CoinRules.bytes(R.from)!!, ByteArray(32)), a = 10, hands = S) }
        val torn = good?.copyOf()?.also { it[it.size - 7] = (it[it.size - 7].toInt() xor 0x5a).toByte() }
        val a4 = raw(S, torn)
        check("the node refuses a forged signature", a4?.code == 400, "code=${a4?.code} word=${a4?.obj?.optString("error")}")
        val s5 = st(S)
        val greedy = s5?.let { CoinTx.build3(CoinRules.Kind.MINT, CoinRules.timeA(10_000), it.head, CoinTx.fresh(), a = it.mintEnd, b = t - 1, hands = S) }
        val a5 = raw(S, greedy)
        check("the node refuses a MINT above its time", a5?.code == 409 && a5.obj?.optString("error") == "allowance", "code=${a5?.code} word=${a5?.obj?.optString("error")}")
        val again = st(R)?.let { CoinTx.build3(CoinRules.Kind.GENESIS, 0, it.head, CoinTx.fresh(), hands = R) }
        val a6 = raw(R, again)
        check("the node refuses a second GENESIS", a6?.code == 409 && a6.obj?.optString("error") == "genesis", "code=${a6?.code} word=${a6?.obj?.optString("error")}")
        val off = nodes.values.first { it.name != CoinTx.chainNode(R.from) }.ask("/tx-put", JSONObject().put("rec", Base64.encodeToString(again ?: ByteArray(0), Base64.NO_WRAP)))
        check("a record laid at the other node is refused", off.code == 403, "code=${off.code}")
        val replay = sendRec?.let { nodes[CoinTx.chainNode(S.from)]?.ask("/tx-put", JSONObject().put("rec", Base64.encodeToString(quest.records().plus(xxx.records()).first { h -> h.r.id == id1 }.bytes, Base64.NO_WRAP))) }
        check("a record laid again is refused", replay?.code == 409, "code=${replay?.code} word=${replay?.obj?.optString("error")}")

        // 8. A RECEIVER THE SEND DOES NOT NAME: X opens nothing with its own key
        val id2 = sent(cs.send3(100, pipe))
        val sendRec2 = id2?.let { quest.records().plus(xxx.records()).firstOrNull { h -> h.r.id == it } }?.r
        val wrong = sendRec2?.let { s -> st(X)?.let { c -> CoinTx.build3(CoinRules.Kind.RECV, 100, c.head, CoinTx.fresh(), to = CoinRules.blind(secret, s.nonce), ref = id2, a = s.a, hands = X) } }
        val a7 = raw(X, wrong)
        check("a RECV by a key the SEND does not name is refused", a7?.code == 409, "code=${a7?.code} word=${a7?.obj?.optString("error")}")

        // 9. REFUND: not before the day; after it the coins come home, and the late RECV finds the SEND settled
        cs.refundDue()
        check("no REFUND before the day", nodes[CoinTx.chainNode(S.from)]?.ask("/tx-settle", JSONObject().put("send", id2))?.obj?.optString("state") == "open" && bookS.balance == 200L,
            "book=${bookS.balance}")
        t += 86_460
        cs.refundDue()
        val refunded = nodes[CoinTx.chainNode(S.from)]?.ask("/tx-settle", JSONObject().put("send", id2))?.obj?.optString("state")
        check("the REFUND after the day brings the coins home", refunded == "refund" && bookS.balance == 300L, "state=$refunded book=${bookS.balance}")
        val late = cr.scanPairs("local late")
        check("a RECV after the REFUND credits nothing", late != null && late.credited == 0 && bookR.balance == 1200L, "credited=${late?.credited} book=${bookR.balance}")

        // 10. AN ANSWER LOST ON THE ROAD: the node took the SEND and the phone heard nothing -- the record waits on the disk and the coins
        // stay its own; at the next launch its node's word decides it once. The record stands on the chain as its head, so its put again
        // is a 409 -- iOS reads that as «behind» and gives the coins back; this side asks the node for the record first and finds it left
        val beforePending = bookS.balance
        loseFromPut = 2   // the put's answer and the one read after it
        val p = cs.send3(50, pipe)
        check("a SEND whose answer was lost waits, its coins held once", p == CoinClient.Send3.Pending && bookS.balance == beforePending - 50 && memoS.pendings().size == 1,
            "result=" + p.javaClass.simpleName + " book=${bookS.balance} waiting=${memoS.pendings().size}")
        cs.settle()
        check("the next launch finds it left: no coins given back twice", bookS.balance == beforePending - 50 && memoS.pendings().isEmpty(),
            "book=${bookS.balance} waiting=${memoS.pendings().size}")
        val ps = cr.scanPairs("local pending")
        check("its receiver takes it once", ps != null && ps.credited == 1 && bookR.balance == 1250L, "credited=${ps?.credited} book=${bookR.balance}")

        // 11. THE GENESIS WAITS FOR THE SEED'S BOOK: a key whose vault has not answered lays nothing; once it has, its GENESIS announces the
        // book gathered -- laid from the phone's share alone, the book of the seed's other devices could never be announced
        val Y = key("montana android local coin test Y") ?: return "coin_local refused: no key"
        var yHeard = false
        val bookY = MemoryLedger(40)
        val cy = CoinClient(door, bookY, MemoryMemo(), { Y }, { null }, { emptyList() }, { true }, clock, bookHeard = { yHeard })
        val w0 = cy.reconcile(force = true)
        check("no GENESIS before the vault answered", w0 != null && !w0.v3 && w0.height == 0, "v3=${w0?.v3} height=${w0?.height}")
        yHeard = true
        val w1 = cy.reconcile(force = true)
        check("the GENESIS once it answered announces the gathered book", w1 != null && w1.v3 && w1.declared == 40L && w1.height == 1,
            "declared=${w1?.declared} height=${w1?.height}")
        // ...and for the person's own yes (the owner's word 17.10.2026: a warning before the first irreversible record)
        val W = key("montana android local coin test W") ?: return "coin_local refused: no key"
        var yes = false
        val cw = CoinClient(door, MemoryLedger(25), MemoryMemo(), { W }, { null }, { emptyList() }, { true }, clock, genesisAllowed = { yes })
        val wa = cw.reconcile(force = true)
        check("no GENESIS before the person's yes", wa != null && !wa.v3 && wa.height == 0, "v3=${wa?.v3} height=${wa?.height}")
        yes = true
        val wb = cw.reconcile(force = true)
        check("the GENESIS after the person's yes", wb != null && wb.v3 && wb.declared == 25L && wb.height == 1, "declared=${wb?.declared}")

        // ONE GENESIS A KEY: two devices of the same words; the second, shown a head from before the first one's GENESIS, lays none
        val Z = key("montana android local coin test Z") ?: return "coin_local refused: no key"
        CoinClient(door, MemoryLedger(30), MemoryMemo(), { Z }, { null }, { emptyList() }, { true }, clock).reconcile(force = true)
        var stale = 1
        val staleDoor = CoinDoor { node, path, body ->
            if (0 < stale && path == "/tx-head") {
                stale--
                return@CoinDoor CoinTx.Answer(200, JSONObject().put("head", CoinRules.ZERO).put("height", 0).put("v3", 0).put("now", t), false)
            }
            door.ask(node, path, body)
        }
        val zs = CoinClient(staleDoor, MemoryLedger(50), MemoryMemo(), { Z }, { null }, { emptyList() }, { true }, clock).reconcile(force = true)
        val zGenesis = (quest.records() + xxx.records()).count { it.r.from == Z.from && it.r.kind == CoinRules.Kind.GENESIS.code }
        check("one GENESIS a key across two devices of the words", zGenesis == 1 && zs != null && zs.v3 && zs.declared == 30L && zs.height == 1,
            "genesis=$zGenesis declared=${zs?.declared} height=${zs?.height}")

        // 12. THE BOOK RIDES THE SEED: the vault's own walk against two nodes in memory
        vault { name, ok, said -> check(name, ok, said) }

        // 13. THE FOLD OF EVERY RECORD THE NODES TOOK EQUALS EVERY NODE'S WORD, AND EVERY BOOK EQUALS ITS CHAIN
        val all = quest.records().map { it to quest.name } + xxx.records().map { it to xxx.name }
        val st0 = HashMap<String, CoinRules.St>(); val sendsAll = HashMap<String, CoinRules.SendInfo>(); val settledAll = HashSet<String>()
        var progress = true
        val byPrev = all.groupBy { it.first.r.from }.mapValues { (_, l) -> l.associateBy { it.first.r.prev } }
        while (progress) {
            progress = false
            for ((from, chain) in byPrev) {
                var s = st0[from] ?: CoinRules.St()
                while (true) {
                    val h = chain[s.head]?.first ?: break
                    val (n, w) = CoinRules.step(s, h.r.rule(), h.at, sendsAll, settledAll)
                    if (w || n == null) break
                    if (h.r.kind == CoinRules.Kind.SEND.code) sendsAll[h.r.id] = CoinRules.SendInfo(from, h.r.coins, h.at, h.r.to, h.r.a)
                    if (h.r.kind == CoinRules.Kind.RECV.code || h.r.kind == CoinRules.Kind.REFUND.code) settledAll.add(h.r.ref)
                    s = n; progress = true
                }
                st0[from] = s
            }
        }
        val agree = listOf(S, R, X).all { h -> val n = nodes[CoinTx.chainNode(h.from)]?.state(h.from); st0[h.from] == n }
        check("an independent fold of every record equals each node's state", agree)
        val fs = st0[S.from]; val fr = st0[R.from]
        check("each book equals its chain", fs != null && fr != null && bookS.balance == fs.proven + fs.declared && bookR.balance == fr.proven + fr.declared,
            "S book=${bookS.balance} chain=${fs?.let { it.proven + it.declared }}, R book=${bookR.balance} chain=${fr?.let { it.proven + it.declared }}")
        check("every record the nodes hold verifies by the core", all.all { CoinTx.read(it.first.bytes)?.id == it.first.r.id }, "records=${all.size}")

        val failed = checks.count { !it.ok }
        val line = "coin_local " + (if (failed == 0) "all hold" else "FAILED $failed") + " ${checks.size - failed}/${checks.size} records=${all.size}"
        Log.d("Montana", line)
        return line
    }

    /**
     * THE VAULT'S WALK (iOS MTCoinVault.gather): two devices of one seed with books of their own, two nodes with two rows each. What one lays
     * the other gathers once by the names; nothing is laid twice; other words open nothing; a move under a restored name joins no book; past
     * FOLD pieces the whole book is laid anew and only the pieces read go; a row refused as full is laid whole next; a change of person in
     * the middle writes nothing. Throwaway seeds, never a person's: nothing touches the network or the person's book.
     */
    private fun vault(check: (String, Boolean, String) -> Unit) {
        check("the vault's frozen vectors hold (iOS keys, the reference LZFSE, RFC 8439)", CoinVault.agrees, "")
        val a = VaultLocalNode(); val b = VaultLocalNode()
        val nodes = mapOf("vault-a.local" to a, "vault-b.local" to b)
        val doors = listOf("https://vault-a.local/pushwake", "https://vault-b.local/pushwake")
        var bump: MemoryVaultBook? = null   // armed: the next question moves this book's person
        val door = VaultDoor { d, path, body, _ ->
            bump?.let { it.generation++; bump = null }
            nodes[android.net.Uri.parse(d).host]?.post(path, body) ?: (-1 to null)
        }
        val seed = Wire.sha("montana android local vault test seed".toByteArray())
        val other = Wire.sha("montana android local vault test other seed".toByteArray())
        fun client(book: VaultBook, s: ByteArray = seed) = VaultClient(door, book, { doors }, { s.copyOf() })
        fun e(k: String, c: Long, ref: String) = CoinEntry(k, c, ref, at = 1_760_000_000.0)
        val k = CoinVault.keys(seed.copyOf())
        val common = Wire.hex(k.token)
        val ownA = Wire.hex(CoinVault.nodeToken(seed.copyOf(), "vault-a.local"))
        val ownB = Wire.hex(CoinVault.nodeToken(seed.copyOf(), "vault-b.local"))

        val bookX = MemoryVaultBook().apply { take(e("earn", 100, "tap:w1")); take(e("earn", 50, "tap:w2")); take(e("send", 30, "tx:aa")) }
        val bookY = MemoryVaultBook().apply { take(e("earn", 7, "tap:w9")) }
        val x = client(bookX); val y = client(bookY)
        check("a vault not asked is not heard", !x.heard, "")
        val gx = x.gather("local x")
        check("X lays its book on both rows of both nodes", gx != null && x.heard && gx.answered == 4 && gx.laid == 12 && a.size(common) == 1 && a.size(ownA) == 1
            && b.size(common) == 1 && b.size(ownB) == 1, "answered=${gx?.answered} laid=${gx?.laid}")
        val gy = y.gather("local y")
        check("Y of the same words gathers X's moves once by their names, lays its own alone", gy != null && gy.joined == 3 && bookY.balance == 127L && gy.laid == 4,
            "joined=${gy?.joined} book=${bookY.balance} laid=${gy?.laid}")
        val gx2 = x.gather("local x again")
        check("X takes Y's move and lays nothing", gx2 != null && gx2.joined == 1 && gx2.laid == 0 && bookX.balance == bookY.balance && bookX.all().size == 4,
            "joined=${gx2?.joined} laid=${gx2?.laid} X=${bookX.balance} Y=${bookY.balance}")
        val gx3 = x.gather("local x thrice")
        check("a gather again moves nothing and fetches nothing it opened", gx3 != null && gx3.joined == 0 && gx3.laid == 0 && gx3.got == 0, "got=${gx3?.got}")

        // other words: a piece of this seed laid in their row opens to nothing
        val zCommon = Wire.hex(CoinVault.keys(other.copyOf()).token)
        a.blobs(common).firstOrNull()?.let { a.plant(zCommon, it) }
        val bookZ = MemoryVaultBook()
        val gz = client(bookZ, other).gather("local other words")
        check("other words open none of the seed's pieces", gz != null && gz.got == 0 && bookZ.all().isEmpty() && a.size(zCommon) == 1, "got=${gz?.got}")

        // a move under a restored name rides no book; the wire name beside it joins
        a.plant(common, CoinVault.seal(listOf(e("receive", 999, "mid:arc:feed"), e("receive", 5, "given:t1-AAAA"), e("receive", 4, "arc:beef"),
            e("receive", 3, "mid:t1760000000000-3B1F2D4C-0A1B-4C2D-8E3F-405162738495")), k.seal)!!)
        val gr = y.gather("local restored names")
        check("moves under restored names are passed, the wire name joins", gr != null && gr.joined == 1 && bookY.balance == 130L, "joined=${gr?.joined} book=${bookY.balance}")

        // past FOLD pieces the whole book is laid as one; the pieces read go with it, a piece that would not open stays
        repeat(CoinVault.FOLD) { i -> b.plant(ownB, CoinVault.seal(listOf(e("earn", 1, "tap:fold$i")), k.seal)!!) }
        b.plant(ownB, ByteArray(64) { 7 })
        val before = b.size(ownB)
        val gf = y.gather("local fold")
        check("past FOLD pieces the whole book is laid as one, the broken piece kept", gf != null && 1 <= gf.whole && b.size(ownB) == 2,
            "pieces before=$before after=${b.size(ownB)} whole=${gf?.whole}")
        check("the fold's moves joined once", bookY.balance == 130L + CoinVault.FOLD, "book=${bookY.balance}")

        // a row refused as full is laid whole at the next gather
        a.cap = a.size(ownA)
        bookY.take(e("earn", 11, "tap:w10"))
        val g413 = y.gather("local full")
        a.cap = Int.MAX_VALUE
        val gw = y.gather("local after full")
        check("a row refused as full is laid whole next", g413 != null && gw != null && 1 <= gw.whole && a.size(ownA) == 1, "whole=${gw?.whole} pieces=${a.size(ownA)}")
        val gx4 = x.gather("local x at the end")
        check("both devices hold one book", gx4 != null && bookX.balance == bookY.balance && bookX.all().map { it.id }.toSet() == bookY.all().map { it.id }.toSet(),
            "X=${bookX.balance} Y=${bookY.balance}")

        // the person changed while the gather waited: nothing is written
        bookY.take(e("earn", 13, "tap:w11"))
        val sizes = listOf(a.size(common), a.size(ownA), b.size(common), b.size(ownB))
        bump = bookY
        val gm = y.gather("local moved")
        check("a gather across a change of person writes nothing", gm == null && sizes == listOf(a.size(common), a.size(ownA), b.size(common), b.size(ownB)), "")
    }
}

/** A book in memory as the vault sees it, by CoinBook.join's own rule: a move once by its name, never of no coins or under a restored name. */
class MemoryVaultBook : VaultBook {
    override var generation = 0
    private val moves = LinkedHashMap<String, CoinEntry>()
    val balance: Long get() = moves.values.sumOf { it.signed }
    fun take(e: CoinEntry) { moves[e.id] = e }
    override fun all(): List<CoinEntry> = moves.values.toList()
    override fun join(moves: List<CoinEntry>): Int {
        var n = 0
        for (e in moves) { if (e.c <= 0 || e.restoredName || e.id in this.moves) continue; this.moves[e.id] = e; n++ }
        return n
    }
}

/**
 * ONE VAULT NODE IN MEMORY (the doors iOS MTCoinVault asks): rows by token, pieces by the SHA-256 of their bytes. /vault-get answers the
 * pieces the phone has not opened and names all it keeps; /vault-put takes a piece and lets the pieces it names go, both at once -- or
 * refuses as full (413) when the row would pass its cap.
 */
class VaultLocalNode(var cap: Int = Int.MAX_VALUE) {
    private val rows = HashMap<String, LinkedHashMap<String, ByteArray>>()
    fun size(token: String) = synchronized(this) { rows[token]?.size ?: 0 }
    fun blobs(token: String): List<ByteArray> = synchronized(this) { rows[token]?.values?.toList().orEmpty() }
    fun plant(token: String, blob: ByteArray) { synchronized(this) { rows.getOrPut(token) { LinkedHashMap() }[Wire.hex(Wire.sha(blob))] = blob } }
    fun post(path: String, body: JSONObject): Pair<Int, JSONObject?> = synchronized(this) {
        val token = body.optString("token")
        if (token.length != 64) return 400 to JSONObject().put("error", "bad token")
        val row = rows.getOrPut(token) { LinkedHashMap() }
        when (path) {
            "/vault-get" -> {
                val have = body.optJSONArray("have")?.let { h -> (0 until h.length()).map { h.optString(it) }.toSet() }.orEmpty()
                val ps = JSONArray()
                for ((id, bytes) in row) if (id !in have) ps.put(JSONObject().put("piece", id).put("blob", Base64.encodeToString(bytes, Base64.NO_WRAP)))
                200 to JSONObject().put("held", JSONArray(row.keys.toList())).put("pieces", ps)
            }
            "/vault-put" -> {
                val bytes = runCatching { Base64.decode(body.optString("blob"), Base64.DEFAULT) }.getOrNull() ?: return 400 to null
                val gone = body.optJSONArray("replace")?.let { r -> (0 until r.length()).map { r.optString(it) }.filter { it in row } }.orEmpty()
                if (cap < row.size - gone.size + 1) return 413 to JSONObject().put("error", "full")
                val id = Wire.hex(Wire.sha(bytes))
                for (g in gone) if (g != id) row.remove(g)
                row[id] = bytes
                200 to JSONObject().put("piece", id)
            }
            else -> 404 to null
        }
    }
}
