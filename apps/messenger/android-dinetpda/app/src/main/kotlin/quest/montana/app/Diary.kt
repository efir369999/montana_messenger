package quest.montana.app

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest

/**
 * THE DIARY RIDES TO THE NODE (iOS MontanaLog + MontanaDiagShip, stage 8-N, the author's decision 23.08; fork atoms 1340): every
 * line this app writes under «Montana» lands in Montana/Diagnostics/telemetry.log as it lies on an iPhone — the moment, then
 * the words with every address collapsed to its family and every name to a salted tag (iOS MontanaLog.hide 108-206) — and the
 * shipper carries the file to the doors' /diag-put under a random diagnostic id (iOS 3722-3833). Nothing in it names anyone:
 * no letter's words, no correspondent's name, no address; the salt never leaves the phone.
 */
object Diary {
    private const val FILE = "telemetry.log"
    private const val ROTATE = 512 * 1024L          // iOS Channel.telemetry.rotateAtBytes
    private const val KEEP = 6                      // iOS MontanaLog.keep: finished generations wait for the shipper
    private const val CHUNK = 262_144               // iOS shipRange: a quarter of a megabyte a request
    private const val PER_PASS = 32                 // iOS perPass: up to 8 MB of catching up per pass
    /** A birth millisecond in the diary, written as the letter born then is named there (iOS MontanaP2PTrace.shortMs,
     *  MontanaP2PTelemetry.swift 47-51 at 2155, 23.09): its last eight digits -- the whole thirteen are hidden by the
     *  diary as an address, and a reader could not match "upto=a:ec589d" with any letter. */
    fun shortMs(ms: Long): String = ms.toString().takeLast(8)
    private var dir: File? = null
    private var started = false
    @Volatile private var app: Context? = null

    /** Once a process: the reader of this process's own lines and the shipper (the app or its ear, whichever stands first). */
    @Synchronized fun start(c: Context) {
        if (started) return
        started = true
        dir = File(c.filesDir, "Montana/Diagnostics").apply { mkdirs() }
        val app = c.applicationContext
        this.app = app
        Thread({ listen() }, "diary").apply { isDaemon = true; start() }
        Thread({ ship(app) }, "diary-ship").apply { isDaemon = true; start() }
    }

    // ── the line as it lies on disk (iOS MontanaLog.write 235-252, hide 159-206) ──
    private val ROW = Regex("^\\s*(\\d+)\\.(\\d+)\\s+\\d+\\s+\\d+\\s+([A-Z])\\s+(\\S+)\\s*:\\s?(.*)")
    private val iso = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }

    /** This process's own lines, as the platform keeps them: the app reads its own without any permission. */
    private fun listen() {
        val pid = android.os.Process.myPid().toString()
        while (true) {
            runCatching {
                val p = ProcessBuilder("logcat", "-v", "threadtime", "-v", "epoch", "--pid=" + pid, "-s", "Montana:V", "AndroidRuntime:E")
                    .redirectErrorStream(true).start()
                p.inputStream.bufferedReader().forEachLine { row -> write(row) }
            }
            Thread.sleep(5000)
        }
    }

    @Synchronized private fun write(row: String) {
        val d = dir ?: return
        val m = ROW.find(row) ?: return
        val ms = m.groupValues[1].toLong() * 1000 + m.groupValues[2].padEnd(3, '0').take(3).toLong()
        val words = (if (m.groupValues[4] == "AndroidRuntime") "CRASH " else "") + m.groupValues[5]
        if (!d.isDirectory) d.mkdirs()   // «Forget this device» takes the folder with the person; the diary goes on in a new one
        val f = File(d, FILE)
        runCatching { f.appendText(iso.format(java.util.Date(ms)) + hide(" " + words) + "\n") }
        // THE TRACE OF A CALL IS NOT ROTATED UNDER THE CALL (iOS MontanaLog.holdRotation, atom 319c1ca96b0a): four rings at most
        if (f.length() >= ROTATE && !(Calls.busy() && f.length() < 4 * ROTATE)) rotate(d, f)
        if (m.groupValues[3] == "E" || m.groupValues[4] == "AndroidRuntime" || isFailure(m.groupValues[5])) failure()
    }

    /**
     * WHAT COUNTS AS AN ERROR — A CLOSED LIST (iOS MontanaP2PTrace.isFailure 72-118, atom bdee948c8ba1): a letter refused, dead of age
     * or red; a call that did not assemble or ring; a door that refused or went dead; a store that failed; any 5xx of a node and any
     * code=-1; a retry demanded anywhere — the author's classes (16.09: «a send failure, a demanded retry, a call error, a network or
     * connection error must fly to the diary at once»). Not an error: 404, and the shipment itself.
     */
    private val FAILURES = setOf("enqueue_drop", "send_refused", "send_failed", "send_red", "dial_failed", "sig_door", "handshake_timeout",
        "node_shut", "path_down", "call_refused", "ring_dead", "ring_unreached", "ring_expired", "notify_failed", "media_store_fail",
        "rx_media_dead", "of_relay_drop", "cam_denied", "cam_fail")
    private fun isFailure(words: String): Boolean {
        val w = words.removePrefix("call line: ").removePrefix("call: ")
        val event = w.substringBefore(' ')
        val kv = w.substringAfter(' ', "")
        if (event.startsWith("diag")) return false
        if (event in FAILURES) return true
        return when (event) {
            "call_ice", "ice" -> "failed" in kv.lowercase() || "disconnected" in kv.lowercase()
            "sig_tx" -> "FAIL" in kv
            "box_fetch" -> "refused" in kv
            "blob_get" -> "unreachable" in kv
            else -> "code=5" in kv || "code=-1" in kv || "retry" in event || "retry" in kv
        }
    }

    /**
     * AN ERROR SHIPS AT ONCE (iOS shipOnFailure 3892-3907): errors come in bursts and one report is enough — five seconds fold
     * them; a store every door refuses is not told of its own death at every breath.
     */
    @Volatile private var lastFailureShip = 0L
    @Volatile private var refused = 0
    private fun failure() {
        val now = System.currentTimeMillis()
        if (now - lastFailureShip <= 5000 || refused > 0) return
        lastFailureShip = now
        val c = app ?: return
        Thread({ runCatching { if (Calls.talking() == null) pass(c) } }, "diary-failure").apply { isDaemon = true; start() }
    }

    private fun gen(d: File, g: Int) = File(d, FILE + (if (g == 0) ".prev" else ".prev." + g))
    /** The finished file moves up one place; only when every place is taken is the oldest lost — and the loss is a line. */
    private fun rotate(d: File, f: File) {
        val oldest = gen(d, KEEP)
        val lost = if (oldest.exists()) oldest.length() else -1L
        if (lost >= 0) oldest.delete()
        for (g in KEEP - 1 downTo 0) gen(d, g).takeIf { it.exists() }?.renameTo(gen(d, g + 1))
        f.renameTo(gen(d, 0))
        if (lost >= 0) runCatching { File(d, FILE).appendText(iso.format(java.util.Date()) + " DIARY dropped " + FILE + " generation=" + KEEP + " bytes=" + lost + " -- rotated out before it was shipped\n") }
    }

    private val HEX = Regex("[0-9a-f]{10,}")
    private val IP4 = Regex("\\b\\d{1,3}(?:\\.\\d{1,3}){3}\\b")
    private val IP6 = Regex("[0-9a-fA-F:]{3,}")
    private val tags = HashMap<String, String>()
    /** iOS MontanaLog.hide: an address leaves only its family, a name its salted tag; numbers stay numbers. */
    fun hide(line: String): String {
        var out = line
        if (out.contains(':')) out = IP6.replace(out) { m ->
            val run = m.value
            val address = run.count { it == ':' } >= 2 && run.any { it != ':' } && (run.contains("::") || run.lowercase().any { it in "abcdef" })
            if (address) "[ip6]" else run
        }
        if (out.contains('.')) out = IP4.replace(out, "[ip4]")
        return HEX.replace(out) { m -> "a:" + tag(m.value) }
    }
    private fun tag(token: String): String = synchronized(tags) {
        tags[token] ?: run {
            val h = MessageDigest.getInstance("SHA-256").digest((salt() + token).toByteArray(Charsets.UTF_8))
            val t = h.take(3).joinToString("") { "%02x".format(it) }
            if (tags.size == 4096) tags.clear()   // a day's worth of names, then a fresh page
            tags[token] = t
            t
        }
    }
    @Volatile private var saltCache: String? = null
    private fun salt(): String {
        saltCache?.let { return it }
        val held = DeviceVault.get("diagSalt")?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() }
        val s = held ?: (java.util.UUID.randomUUID().toString().uppercase() + java.util.UUID.randomUUID().toString().uppercase()).also {
            DeviceVault.set("diagSalt", it.toByteArray(Charsets.UTF_8))
        }
        saltCache = s
        return s
    }

    /**
     * THE DIARY LEAVES THE PHONE ONLY BY THE PERSON'S YES (iOS MontanaDiagConsent, MontanaWakePush 3732-3751; App Review 5.1.1(ii),
     * 08.10): the switch stands in Privacy. Every Android build is one anyone may install, so it is born off, as the iPhone's builds
     * from TestFlight and the App Store are; off, the diary's id leaves, so a later yes starts a diary nobody can join to the one
     * before. The diary is still written here — only nothing of it leaves.
     */
    private const val CONSENT = "diagShare"
    val consented get() = Prefs.bool(CONSENT, false)
    fun setConsent(v: Boolean) {
        Prefs.setBool(CONSENT, v)
        if (!v) Prefs.remove("diagId")
    }

    // ── the shipper (iOS MontanaDiagShip 3722-3833, shipOnce 4032-4100) ──
    private val dg: String get() = Prefs.str("diagId", "").ifEmpty { java.util.UUID.randomUUID().toString().uppercase().also { Prefs.setStr("diagId", it) } }

    private fun ship(c: Context) {
        Thread.sleep(60_000)   // a minute, so a launch is never shared
        while (true) {
            // the voice outranks the journal
            if (Calls.talking() == null) runCatching { pass(c) }
            Thread.sleep(pause())
        }
    }

    /**
     * THE PAUSE (iOS pauseNs 3853-3858, liveSleepNs and idleSleepNs 3842-3843): ten minutes while a person looks, a quarter hour once
     * they do not. With the stores off, a fixed rhythm knocked on dead doors for as long as the app stood open (iOS measured 03.09
     * 20:10): each refusal by every door doubles the looking pause, up to the quarter hour; one journal that lands resets it.
     */
    private fun pause(): Long {
        if (!Presence.shown) return 900_000L
        return minOf(900_000L, 600_000L shl minOf(refused, 5))
    }

    /** The finished generations first, the oldest first, each forgotten once it landed whole; then the live file. */
    @Synchronized private fun pass(c: Context) {
        if (!consented) return   // the one road out asks the person's yes first (iOS MontanaDiagShip.put)
        val d = dir ?: return
        try { shipAll(c, d) } finally { tellTail(d) }
    }
    /**
     * THE SHIPPER'S LEDGER GOES INTO THE TELEMETRY (iOS shipOnce 4097-4103, 25.09): what the diary could not say about its own hole --
     * its words lay in the hole. The unsent tail in steps of 64 KB, with the standing refusal if any; said when it
     * changes, so a day that never caught up is read the next morning.
     */
    private var lastTail: String? = null
    private fun tellTail(d: File) {
        val wm = Prefs.str("diagWm", "0").toLongOrNull() ?: 0L
        val born = Prefs.str("diagGen", "")
        var pending = 0L
        val files = (KEEP downTo 0).map { gen(d, it) } + File(d, FILE)
        for (f in files) if (f.exists()) pending += if (birth(f) == born) maxOf(0L, f.length() - wm) else f.length()
        val words = FILE + "=" + pending / 65_536 * 64 + "KB" + (if (0 < refused) " refused=" + refused else "")
        if (words == lastTail) return
        lastTail = words
        android.util.Log.d("Montana", "diag_tail " + words)
    }
    private fun shipAll(c: Context, d: File) {
        var wm = Prefs.str("diagWm", "0").toLongOrNull() ?: 0L
        var born = Prefs.str("diagGen", "")
        fun keep() { Prefs.setStr("diagWm", wm.toString()); Prefs.setStr("diagGen", born) }
        for (g in KEEP downTo 0) {
            val f = gen(d, g).takeIf { it.exists() } ?: continue
            val b = birth(f)
            if (b != born) { wm = 0; born = b; keep() }
            val (at, done) = shipRange(c, f, wm)
            wm = at; keep()
            if (!done) return
            f.delete(); wm = 0; born = ""; keep()
        }
        val live = File(d, FILE).takeIf { it.exists() } ?: return
        val b = birth(live)
        if (b != born) { wm = 0; born = b; keep() }
        wm = shipRange(c, live, wm).first; keep()
    }
    /** The file's birth is its first line's moment: a rename keeps it, a fresh file has its own. */
    private fun birth(f: File): String = runCatching { f.bufferedReader().use { it.readLine() ?: "" }.take(24) }.getOrDefault("")

    /** Where the reading stopped, and whether the file was read to its end with every chunk landed. */
    private fun shipRange(c: Context, f: File, from: Long): Pair<Long, Boolean> {
        val size = f.length()
        if (size <= from) return from to true
        var at = from
        var sent = 0
        RandomAccessFile(f, "r").use { raf ->
            raf.seek(from)
            while (sent < PER_PASS) {
                val buf = ByteArray(CHUNK)
                val n = raf.read(buf)
                if (n <= 0) return at to true
                // half a line at a chunk's edge is not a line: it waits for the next chunk
                val last = buf.lastIndexOf('\n'.code.toByte()).takeIf { it < n } ?: -1
                if (last < 0) return at to false
                val lines = String(buf, 0, last + 1, Charsets.UTF_8).split('\n').filter { it.isNotEmpty() }
                if (lines.isNotEmpty() && !put(c, lines)) return at to false
                at += last + 1
                raf.seek(at)
                sent++
                Thread.sleep(250)   // a breath between chunks, so the radio is shared
            }
        }
        return at to (f.length() <= at)
    }

    /** The ONE door outward: every door that answers, the first to take it ends the walk. */
    private fun put(c: Context, lines: List<String>): Boolean {
        val version = runCatching { c.packageManager.getPackageInfo(c.packageName, 0).longVersionCode.toString() }.getOrDefault("?")
        val dev = JSONObject().put("model", Build.MANUFACTURER + " " + Build.MODEL).put("ios", "Android " + Build.VERSION.RELEASE)
            .put("build", version).put("tz", java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 1000)
            .put("lang", java.util.Locale.getDefault().language.take(2)).put("skew_ms", NodeClock.skewMs)
        val body = JSONObject().put("dg", dg).put("file", "tele").put("dev", dev).put("lines", JSONArray(lines))
        val bytes = body.toString().length
        for (door in Signal.writeOrder("diag")) {   // the elected door first (iOS MontanaDiagShip.put over bases(for: "diag"))
            // THE DEADLINE GROWS WITH THE BODY BY THE CARGO ROAD'S ONE RULE (iOS MontanaWakePush 3772-3775, MTNodeWire.cargoTimeoutS 306)
            val (code, _) = Wire.post(door, "/diag-put", body, Wire.cargoTimeoutMs(bytes))
            if (code == 200) { Signal.doorAnswered(door); refused = 0; return true }
            Signal.doorFailed(door, code)
        }
        refused++
        return false
    }
}
