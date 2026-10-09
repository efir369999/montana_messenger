package quest.montana.app

import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// ─────────────────────────── the network's own doors (iOS MontanaNodes.learn/list, MontanaWakePush.verifyBases/orderedBases) ───────────────────────────

/**
 * THE NETWORK NAMES ITS OWN DOORS (iOS MontanaNodes 150-160, MontanaWakePush 137-146): the list a door hands out (/doors)
 * supersedes the doors shipped in the app — a new door reaches every install as data, never as a rebuild. What a door can, it
 * says itself (/health, iOS MTNodeWire.health 205-214): a door that holds a capability is a path for it, a door asked and silent
 * is known silent. Both ends of a conversation walk this one list in its own order, so their signal lanes meet at one door
 * (iOS orderedBases 188-208; measured 04.09: three rules on two sides, and the two never shared one).
 */
object Doors {
    private const val LEARNED = "mt.nodes.learned"
    private val ALL_CAPS = setOf("box", "blob", "signal", "turn", "diag", "stun", "notify")   // a door that names nothing can everything (iOS allCaps 43)
    private val caps = HashMap<String, Set<String>>()
    private val silent = HashSet<String>()
    private var verifiedAt = 0L
    private val verifying = java.util.concurrent.atomic.AtomicBoolean(false)

    /** The hosts of a list, in its order: «host», «host:port», «[v6]:port», «wss://host/path»; commas and spaces part them, a comment goes by the line (iOS parse 185-228). */
    fun parse(raw: String): List<String> {
        val out = ArrayList<String>()
        for (line in raw.split('\n')) {
            val t = line.trim()
            if (t.isEmpty() || t.startsWith("#")) continue
            for (piece in t.split(',', ' ')) {
                var s = piece.trim()
                if (s.isEmpty() || s.startsWith("#")) continue
                if (s.lowercase().startsWith("wss://")) s = s.drop(6).substringBefore('/')
                if (s.startsWith("[") && ']' !in s) continue
                val host = when {
                    s.startsWith("[") -> s.substringAfter('[').substringBefore(']')
                    s.count { it == ':' } == 1 && s.substringAfter(':').toIntOrNull() != null -> s.substringBefore(':')
                    else -> s
                }
                if (host.isNotEmpty() && host !in out) out.add(host)
            }
        }
        return out
    }

    /** The network's list once learned, else the doors shipped in the app (iOS list 230-240: the learned list over the shipped one). */
    private fun hosts(): List<String> = parse(Prefs.str(LEARNED, "")).ifEmpty { MontanaCard.doors.mapNotNull { android.net.Uri.parse(it).host } }
    private fun base(host: String) = "https://" + host + "/pushwake"
    private fun host(door: String) = android.net.Uri.parse(door).host ?: door

    /**
     * THE DOORS OF A CAPABILITY, in the network's order (iOS orderedBases 192-208): the doors that said they hold it. Once the map
     * knows the doors and none of them holds it, nobody — a capability asked by name is never guessed; before any door has
     * answered, every door not known silent.
     */
    fun ordered(cap: String): List<String> {
        if (System.currentTimeMillis() - verifiedAt > 600_000L) verifyLater()
        val all = hosts().map { base(it) }
        val (known, mute) = synchronized(caps) { HashMap(caps) to HashSet(silent) }
        val good = all.filter { known[it]?.contains(cap) == true }
        if (good.isNotEmpty()) return good
        if (known.isNotEmpty()) return emptyList()
        return all.filter { it !in mute }.ifEmpty { all }
    }

    /** A door of the list (iOS MontanaNodes.Node 38-52): a bare one, or one behind a delivery network with the web socket's path. */
    class Door(val host: String, val port: Int, val path: String?) {
        val label: String get() = Channels.labelOf(host, port, path != null)
    }

    /** iOS MontanaNodes.parse 185-228: a comment goes by the line; «wss://name/path» is a door behind a delivery network on 443; the port defaults to the direct one. */
    private fun doors(raw: String): List<Door> {
        val out = ArrayList<Door>()
        for (line in raw.split('\n')) {
            val t = line.trim()
            if (t.isEmpty() || t.startsWith("#")) continue
            for (piece in t.split(',', ' ')) {
                var w = piece.trim()
                if (w.isEmpty() || w.startsWith("#")) continue
                var host = w
                var port = Channels.PORT
                var path: String? = null
                if (w.lowercase().startsWith("wss://")) {
                    val body = w.drop(6)
                    val hostPart = body.substringBefore('/')
                    if (hostPart.isEmpty()) continue
                    path = if (body.contains('/')) "/" + body.substringAfter('/') else "/"
                    port = 443; w = hostPart; host = hostPart
                }
                if (w.startsWith("[")) {
                    val close = w.indexOf(']')
                    if (close < 0) continue
                    host = w.substring(1, close)
                    val rest = w.substring(close + 1)
                    if (rest.startsWith(":")) rest.drop(1).toIntOrNull()?.takeIf { it in 1..65535 }?.let { port = it }
                } else if (w.count { it == ':' } == 1) {
                    w.substringAfterLast(':').toIntOrNull()?.takeIf { it in 1..65535 }?.let { host = w.substringBeforeLast(':'); port = it }
                }
                if (host.isEmpty()) continue
                val d = Door(host, port, path)
                if (out.none { it.label == d.label }) out.add(d)
            }
        }
        return out
    }

    private const val SHIPPED = "api.montana.quest:443\nmontana.xxx:443\nwss://door.montana.quest/ws"   // iOS nodes.txt, line for line

    /** iOS MontanaNodes.list 230-240: the network's list once learned, else the shipped one; a machine is not its own node. */
    fun list(): List<Door> {
        val own = Channels.candidates().toSet()
        return doors(Prefs.str(LEARNED, "")).ifEmpty { doors(SHIPPED) }.filter { it.host !in own }
    }

    // THE MACHINES BEHIND THE DOORS (iOS MontanaNodes 162-183, the network's word 15.22): which doors are one machine — the page
    // groups by that word always, the handshake only colours the state. Absent in an older node's answer.
    private const val MACHINES = "mt.nodes.machines"
    fun machines(): List<Pair<String, Set<String>>> = runCatching {
        val arr = org.json.JSONArray(Prefs.str(MACHINES, "[]"))
        (0 until arr.length()).mapNotNull { i ->
            val m = arr.optJSONObject(i) ?: return@mapNotNull null
            val id = m.optString("id")
            val ds = m.optJSONArray("doors") ?: return@mapNotNull null
            if (id.isEmpty()) null else id to doors((0 until ds.length()).joinToString("\n") { ds.optString(it) }).map { it.label }.toSet()
        }
    }.getOrDefault(emptyList())

    // THE DOOR BOOK (iOS MontanaNodes.book 70-89): which door led to WHICH machine and in how long — an identity behind a door is
    // learned only by a handshake through it, so the first probing is unavoidable while a second must not happen.
    private const val BOOK = "mt.doorbook"
    fun book(): Map<String, Pair<String, Int>> = runCatching {
        val o = JSONObject(Prefs.str(BOOK, "{}"))
        o.keys().asSequence().mapNotNull { k ->
            val parts = o.optString(k).split(':')
            val ms = parts.getOrNull(1)?.toIntOrNull()
            if (parts.size == 2 && parts[0].isNotEmpty() && ms != null) k to (parts[0] to ms) else null
        }.toMap()
    }.getOrDefault(emptyMap())

    @Synchronized fun remember(door: String, overlay: String, ms: Int) {
        if (door.isEmpty()) return
        val o = runCatching { JSONObject(Prefs.str(BOOK, "{}")) }.getOrDefault(JSONObject())
        o.put(door, overlay + ":" + ms)
        Prefs.setStr(BOOK, o.toString())
    }

    /** Asked in the last round and did not answer (iOS silentDoors): not alive for the lane. */
    fun silent(door: String) = synchronized(caps) { door in silent }

    private fun verifyLater() {
        if (verifying.compareAndSet(false, true)) Thread { try { verify(0) } finally { verifying.set(false) } }.start()
    }

    /** A door's own word on what it can (iOS MTNodeWire.health 205-214): null — silent; a door that names nothing can everything. */
    private fun health(door: String): Set<String>? = try {
        val conn = URL(door + "/health").openConnection() as HttpURLConnection
        conn.connectTimeout = 6000; conn.readTimeout = 6000
        val code = conn.responseCode
        val text = if (code == 200) conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) } else null
        conn.disconnect()
        text?.let { t ->
            val c = JSONObject(t).optJSONObject("caps")
            c?.keys()?.asSequence()?.filter { c.optBoolean(it) }?.toSet() ?: ALL_CAPS
        }
    } catch (_: Exception) { null }

    /**
     * ONE ROUND OF THE DOORS (iOS verifyBases 91-186): every door's /health at once, merged into what is known (a door silent now
     * keeps what it said before, its silence written down); the network's list from the first door that answered; a door learned
     * this round is asked at once, not in ten minutes (iOS 166-175).
     */
    private fun verify(pass: Int) {
        val before = hosts().toSet()
        val doors = hosts().map { base(it) }
        val found = java.util.concurrent.ConcurrentHashMap<String, Set<String>>()
        val asked = doors.map { d -> Thread { health(d)?.let { found[d] = it } }.also { it.start() } }
        for (a in asked) a.join(12_500)
        synchronized(caps) {
            for (d in doors) { val held = found[d]; if (held != null) { caps[d] = held; silent.remove(d) } else silent.add(d) }
            verifiedAt = System.currentTimeMillis()
        }
        for (d in found.keys) Signal.proveDoor(d)   // the round's answer is proof for the call's walk (iOS 115)
        Log.d("Montana", "accel_paths ok=" + doors.filter { found[it] != null }.joinToString(",") { host(it) + "[" + found[it].orEmpty().sorted().joinToString("|") + "]" } + " of=" + doors.size)
        // THE MODE OF THE NETWORK (iOS MontanaWakePush 172-181, atoms c0b52069608a, b3f67ba312fd): a silent door is a question --
        // the mode is measured then, at most once a minute -- and the round runs once an hour on its own, so a verdict has open
        // lines to stand against
        val mute = doors.filter { found[it] == null }.map { host(it) }
        val alive = doors.filter { found[it] != null }.map { host(it) }
        if ((mute.isNotEmpty() && NetProbe.minutePassed()) || NetProbe.hourPassed()) runCatching { NetProbe.round(mute, alive) }
        val first = doors.firstOrNull { found[it] != null } ?: return
        val named = try {
            val conn = URL(first + "/doors").openConnection() as HttpURLConnection
            conn.connectTimeout = 8000; conn.readTimeout = 8000
            val t = if (conn.responseCode == 200) conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) } else null
            conn.disconnect()
            // the answer counts when it names doors (iOS MontanaWakePush.swift:145: !doors.isEmpty): the machines and the barred ride it
            t?.let { JSONObject(it).takeIf { j -> (j.optJSONArray("doors")?.length() ?: 0) > 0 } }
        } catch (_: Exception) { null }
        if (named != null) {
            val ds = named.getJSONArray("doors")
            val raw = (0 until ds.length()).map { ds.optString(it) }.filter { it.isNotEmpty() }.joinToString("\n")
            if (parse(raw).isNotEmpty() && raw != Prefs.str(LEARNED, "")) {
                Prefs.setStr(LEARNED, raw)
                Log.d("Montana", "doors_learned n=" + parse(raw).size)
            }
            // the network names its machines too (iOS MontanaWakePush 147-153): which doors are one node
            named.optJSONArray("nodes")?.let { nodes ->
                val keep = org.json.JSONArray()
                for (i in 0 until nodes.length()) {
                    val n = nodes.optJSONObject(i) ?: continue
                    if (n.optString("id").isNotEmpty() && n.optJSONArray("doors") != null) keep.put(JSONObject().put("id", n.optString("id")).put("doors", n.optJSONArray("doors")))
                }
                if (keep.toString() != Prefs.str(MACHINES, "")) { Prefs.setStr(MACHINES, keep.toString()); Log.d("Montana", "machines_learned n=" + keep.length()) }
            }
            // THE BARRED (iOS MontanaWakePush.swift:155-158, Guideline 1.2): the addresses the network's operators barred after a
            // report ride this same answer; every install refuses their letters on every road ([P2P-COMPAT]: an absent key changes nothing).
            named.optJSONArray("barred")?.let { arr -> PeerSafety.setBarred((0 until arr.length()).map { arr.optString(it) }) }
        }
        if (pass == 0 && !before.containsAll(hosts())) verify(1)
    }
}
