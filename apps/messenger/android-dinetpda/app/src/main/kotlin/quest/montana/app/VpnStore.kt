package quest.montana.app

import android.os.Build
import android.util.Log
import montanaxray.Montanaxray
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.text.Collator
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

// ─────────────── the VPN wall's store (iOS MontanaVPN.swift: MontanaVPNStore, MontanaVPNPlan(s), MontanaVPNSubscription's road,
// MontanaVPNSelection, MontanaVPNDelayBook, MontanaEngineDelay, MontanaVPNDelay, MontanaVPNLoadLine, MontanaVPNFreshener, MTVPNWall,
// MTVPNPay; MontanaNetworkView.swift: MontanaVPNPingLine; MontanaVPNTunnel.swift: MontanaVPNDead) ───────────────

/** The page hears the VPN by one word (iOS: the objects the page observes): a write of the list, a load, a measurement, the tunnel. */
object VpnBus {
    private val heard = CopyOnWriteArrayList<() -> Unit>()
    fun listen(f: () -> Unit) { heard.addIfAbsent(f) }
    fun unlisten(f: () -> Unit) { heard.remove(f) }
    fun say() = MainThread.post { heard.forEach { it() } }
}

/** One line of the VPN in the diary under its word (iOS MontanaTrace.mark("vpn_ui" | "vpn_sub", ...)): no link, no address. */
fun vpnMark(kind: String, detail: String) { Log.i("Montana", "$kind $detail") }
/** A plan named in the diary by a tag of its link, never by the link: the link is the plan's secret (iOS MontanaLog.label). */
fun vpnPlanLabel(url: String): String =
    "plan:" + MessageDigest.getInstance("SHA-256").digest(url.toByteArray()).take(4).joinToString("") { "%02x".format(it) }
private fun nowSeconds(): Double = System.currentTimeMillis() / 1000.0

/**
 * THE SERVERS (iOS MontanaVPNStore, MontanaVPN.swift:501-588 and 1936-2009): sealed under the device key (DeviceVault), read once per
 * process and held, and every row has an identity of its own -- a plan may name one machine twice, and two rows of one identity were
 * drawn as one and chosen together (22.09). A row of a plan the person no longer holds stays sealed and out of sight.
 */
object VpnStore {
    private const val KEY = "mt.vpn.servers"
    private val lock = Any()
    private var held: List<VpnConfig>? = null

    fun load(): MutableList<VpnConfig> { val plans = VpnPlans.ownedUrls(); return stored().filter { isOwned(it, plans) }.toMutableList() }
    private fun isOwned(row: VpnConfig, plans: Set<String>): Boolean = row.subscription?.let { it in plans } ?: true
    fun isRetired(id: String): Boolean { val plans = VpnPlans.ownedUrls(); return stored().any { it.id == id && !isOwned(it, plans) } }
    private fun stored(): List<VpnConfig> {
        synchronized(lock) { held?.let { return it } }
        val l = DeviceVault.get(KEY)?.let { decodeRows(it) } ?: mutableListOf()
        var changed = false
        val seen = HashSet<String>()
        for (row in l) {
            val u = row.uid ?: ""
            if (u.isEmpty() || u in seen) { row.uid = newId(); changed = true }
            seen.add(row.uid ?: "")
        }
        synchronized(lock) { held = l }
        if (changed) writeSealed(l)   // the repair is written once, never from the reading path again
        return l
    }
    /** An identity as the iPhone writes one (UUID().uuidString). */
    fun newId(): String = UUID.randomUUID().toString().uppercase(Locale.ROOT)
    /** THE LIST IS READ ROW BY ROW (iOS decodeRows, the critic's P-9): one row this build cannot read stays out, never the whole list. */
    fun decodeRows(d: ByteArray): MutableList<VpnConfig> {
        val rows = runCatching { JSONArray(String(d, Charsets.UTF_8)) }.getOrNull() ?: return mutableListOf()
        return (0 until rows.length()).mapNotNull { i -> rows.optJSONObject(i)?.let { VpnConfig.of(it) } }.toMutableList()
    }
    /** The sealed store read before anybody asks, off the main thread (iOS warm). */
    fun warm() {
        synchronized(lock) { if (held != null) return }
        Thread({ load(); VpnPlans.load() }, "mt-vpn-warm").start()
    }
    private fun writeSealed(list: List<VpnConfig>) {
        val a = JSONArray()
        list.forEach { a.put(it.json()) }
        DeviceVault.set(KEY, a.toString().toByteArray(Charsets.UTF_8))
    }
    @Synchronized fun save(list: List<VpnConfig>) {
        val plans = VpnPlans.ownedUrls()
        val own = list.filter { isOwned(it, plans) }
        val retained = stored().filter { old -> !isOwned(old, plans) && own.none { it.id == old.id } }
        val all = own + retained
        synchronized(lock) { held = all }
        writeSealed(all)
        VpnBus.say()
    }
    fun forgetHeld() { synchronized(lock) { held = null } }

    /** THE HAND-ADD HAS ONE OWNER (iOS add, 29.09): every row that comes by hand joins here with an identity of its own; a row the list
     *  holds already (the same machine, port and secret) is not taken twice. Answers how many joined. */
    @Synchronized fun add(fresh: List<VpnConfig>): Int {
        if (fresh.isEmpty()) return 0
        val list = load()
        var joined = 0
        for (f in fresh) {
            if (list.any { it.host == f.host && it.port == f.port && it.uuidOrPassword == f.uuidOrPassword }) continue
            if ((f.uid ?: "").isEmpty()) f.uid = newId()
            list.add(f); joined++
        }
        if (0 < joined) save(list)
        return joined
    }
    fun addFromLink(raw: String): Int = add(VpnParse.parseMany(raw))
    @Synchronized fun remove(at: Int) { val l = load(); if (at !in l.indices) return; l.removeAt(at); save(l) }
    @Synchronized fun rename(at: Int, to: String) { val l = load(); if (at !in l.indices) return; l[at] = l[at].copy().also { it.name = to }; save(l) }
    /** A new order of the whole list, written in one step (the page's pin and its sort by ping). */
    @Synchronized fun reorder(order: (MutableList<VpnConfig>) -> Unit) { val l = load(); order(l); save(l) }

    private val loadLine = Any()
    /**
     * EVERY SERVER OF ONE PLAN (iOS addFromSubscription): what this link gave last time is replaced by what it gives now, a server it
     * held keeps its identity (so the choice survives), a server added by hand is never touched; a failed load keeps the servers and
     * writes its reason on the plan. EVERY LOAD STANDS IN ONE LINE (iOS MontanaVPNLoadLine): two loads writing at once would lose the
     * server added by hand between them. Blocking: off the main thread.
     */
    fun addFromSubscription(url: String, onAttempt: ((Int) -> Unit)? = null): Int = synchronized(loadLine) { addFromSubscriptionNow(url, onAttempt) }
    private fun addFromSubscriptionNow(key: String, onAttempt: ((Int) -> Unit)?): Int {
        if (VpnWallToken.isWallKey(key) || VpnPay.isPlan(key)) return 0
        val fetched = try { VpnSubscription.fetch(key, onAttempt) } catch (e: VpnSubscription.FetchError) {
            val p = VpnPlans.load().firstOrNull { it.url == key }
            if (p != null) { p.lastError = e.label; VpnPlans.upsert(p) }
            else VpnPlans.upsert(VpnPlan(key).also { it.lastError = e.label })
            throw e
        }
        synchronized(this) {
            val list = load()
            val old = list.filter { it.subscription == key }
            list.removeAll { it.subscription == key }
            // a plan may name one machine twice under two names (an "auto" beside its country): both stay, as the plan lists them;
            // only a server held from elsewhere is not taken a second time. An identity from the last load goes to one row at most.
            val others = ArrayList(list)
            val pool = ArrayList(old)
            for (f in fetched.servers) {
                if (others.any { it.host == f.host && it.port == f.port && it.uuidOrPassword == f.uuidOrPassword }) continue
                val same = pool.indexOfFirst { it.host == f.host && it.port == f.port && it.uuidOrPassword == f.uuidOrPassword && it.name == f.name }
                    .takeIf { 0 <= it } ?: pool.indexOfFirst { it.host == f.host && it.port == f.port && it.uuidOrPassword == f.uuidOrPassword }
                f.uid = if (0 <= same) pool.removeAt(same).uid ?: newId() else newId()
                list.add(f)
            }
            val prev = VpnPlans.load().firstOrNull { it.url == key }
            val ui = fetched.userinfo
            val unspoken = VpnParse.Report(fetched.servers.filter { it.proto == VpnProto.UNSUPPORTED }.toMutableList())
            VpnPlans.upsert(VpnPlan(key, if (fetched.title.isEmpty()) prev?.title ?: "" else fetched.title, nowSeconds(), fetched.servers.size).also { p ->
                p.upload = ui["upload"]; p.download = ui["download"]; p.total = ui["total"]; p.expire = ui["expire"]?.toDouble()
                p.lastError = null
                p.unsupported = if (unspoken.servers.isEmpty()) null else unspoken.servers.size
                p.unsupportedKinds = if (unspoken.servers.isEmpty()) null else unspoken.unsupportedWord
                p.updateInterval = fetched.updateHours ?: prev?.updateInterval
                p.folded = prev?.folded; p.pinnedAt = prev?.pinnedAt; p.wallOf = null   // a load renews what the panel says, not the person's arrangement
            })
            save(list)
        }
        return fetched.servers.size
    }

    fun subscriptions(): List<String> {
        val seen = VpnPlans.load().map { it.url }.toMutableList()
        for (c in load()) { val s = c.subscription; if (s != null && s !in seen) seen.add(s) }
        return seen.filter { !VpnWallToken.isWallKey(it) && !VpnPay.isPlan(it) }
    }
    /** Every plan again; a plan whose server is silent keeps what it had. Blocking. */
    fun refreshSubscriptions(onAttempt: ((Int) -> Unit)? = null): Int {
        var n = 0
        for (u in subscriptions()) n += runCatching { addFromSubscription(u, onAttempt) }.getOrDefault(0)
        return n
    }
    /** The plan and every server it brought leave together; a server pasted by hand stays. */
    @Synchronized fun removeSubscription(url: String) {
        save(load().filter { it.subscription != url })
        VpnPlans.remove(url)
    }
}

/** One plan and what it said the last time it answered (iOS MontanaVPNPlan, MontanaVPN.swift:1792-1813), sealed beside the servers. */
class VpnPlan(var url: String, var title: String = "", var updatedAt: Double = 0.0, var count: Int = 0) {
    var upload: Long? = null; var download: Long? = null
    var total: Long? = null        // 0 or absent -- unlimited
    var expire: Double? = null     // unix seconds; 0 or absent -- no end
    var lastError: String? = null  // the label of the last failed load; nil once a load succeeds
    var unsupported: Int? = null   // rows of the last load the engine cannot speak
    var unsupportedKinds: String? = null
    var updateInterval: Int? = null
    var folded: Boolean? = null    // the person's own arrangement of the page, sealed with the plan (24.09)
    var pinnedAt: Double? = null
    var wallOf: String? = null
    val id: String get() = url
    val host: String get() = runCatching { URI(url).host }.getOrNull() ?: url
    val shownTitle: String get() = title.ifEmpty { host }

    fun json(): JSONObject = JSONObject().apply {
        put("url", url); put("title", title); put("updatedAt", updatedAt); put("count", count)
        fun opt(k: String, v: Any?) { if (v != null) put(k, v) }
        opt("upload", upload); opt("download", download); opt("total", total); opt("expire", expire); opt("lastError", lastError)
        opt("unsupported", unsupported); opt("unsupportedKinds", unsupportedKinds); opt("updateInterval", updateInterval)
        opt("folded", folded); opt("pinnedAt", pinnedAt); opt("wallOf", wallOf)
    }
    companion object {
        fun of(o: JSONObject): VpnPlan? = runCatching {
            fun has(k: String) = o.has(k) && !o.isNull(k)
            VpnPlan(o.getString("url"), o.getString("title"), o.getDouble("updatedAt"), o.getInt("count")).apply {
                if (has("upload")) upload = o.getLong("upload"); if (has("download")) download = o.getLong("download")
                if (has("total")) total = o.getLong("total"); if (has("expire")) expire = o.getDouble("expire")
                if (has("lastError")) lastError = o.getString("lastError"); if (has("unsupported")) unsupported = o.getInt("unsupported")
                if (has("unsupportedKinds")) unsupportedKinds = o.getString("unsupportedKinds")
                if (has("updateInterval")) updateInterval = o.getInt("updateInterval")
                if (has("folded")) folded = o.getBoolean("folded"); if (has("pinnedAt")) pinnedAt = o.getDouble("pinnedAt")
                if (has("wallOf")) wallOf = o.getString("wallOf")
            }
        }.getOrNull()
    }
}

/** THE PLANS (iOS MontanaVPNPlans, MontanaVPN.swift:1815-1920): held in memory, read from the sealed store once; only a plan the
 *  person entered is active -- the received and the coin-provisioned plans of older builds stay sealed. */
object VpnPlans {
    private const val KEY = "mt.vpn.plans"
    private val lock = Any()
    private var held: List<VpnPlan>? = null
    fun isOwned(plan: VpnPlan): Boolean {
        if (plan.wallOf != null) return false
        val u = runCatching { URI(plan.url) }.getOrNull() ?: return false
        if (u.host == null) return false
        val scheme = u.scheme?.lowercase(Locale.ROOT)
        return scheme == "https" || scheme == "http"
    }
    fun owns(url: String): Boolean = load().any { it.url == url }
    fun ownedUrls(): Set<String> = load().mapTo(HashSet()) { it.url }
    fun load(): MutableList<VpnPlan> = stored().filter(::isOwned).toMutableList()
    private fun stored(): List<VpnPlan> {
        synchronized(lock) { held?.let { return it } }
        val l = DeviceVault.get(KEY)?.let { d ->
            runCatching { JSONArray(String(d, Charsets.UTF_8)) }.getOrNull()?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it)?.let(VpnPlan::of) } }
        } ?: emptyList()
        synchronized(lock) { held = l }
        return l
    }
    @Synchronized fun save(list: List<VpnPlan>) {
        val own = list.filter(::isOwned)
        val retained = stored().filter { old -> !isOwned(old) && own.none { it.url == old.url } }
        val all = own + retained
        synchronized(lock) { held = all }
        val a = JSONArray()
        all.forEach { a.put(it.json()) }
        DeviceVault.set(KEY, a.toString().toByteArray(Charsets.UTF_8))
        VpnBus.say()
    }
    fun forgetHeld() { synchronized(lock) { held = null } }
    @Synchronized fun upsert(p: VpnPlan) {
        val l = load()
        val i = l.indexOfFirst { it.url == p.url }
        if (0 <= i) l[i] = p else l.add(p)
        save(l)
    }
    @Synchronized fun remove(url: String) = save(load().filter { it.url != url })

    /** THE ORDER OF THE PAGE, NAMED ONCE (iOS ordered, [C-1]): the pinned first, the newest pin highest, then the rest by name; a
     *  correspondent's wall after the person's own, in the chats' order. */
    fun ordered(wallRank: Map<String, Int> = emptyMap()): List<VpnPlan> = ordered(load(), wallRank)
    fun ordered(plans: List<VpnPlan>, wallRank: Map<String, Int>): List<VpnPlan> {
        val names = Collator.getInstance(Locale.getDefault()).apply { strength = Collator.SECONDARY }   // iOS localizedCaseInsensitiveCompare
        fun rank(p: VpnPlan): Triple<Int, Int, Int> {
            val conv = p.wallOf ?: return Triple(0, if (p.pinnedAt == null) 1 else 0, 0)
            return Triple(1, wallRank[conv] ?: Int.MAX_VALUE, if (VpnWallToken.isWallKey(p.url)) 1 else 0)
        }
        return plans.sortedWith { a, b ->
            val ra = rank(a); val rb = rank(b)
            if (ra != rb) compareValuesBy(ra, rb, { it.first }, { it.second }, { it.third })
            else {
                val x = a.pinnedAt; val y = b.pinnedAt
                when {
                    x != null && y != null -> y.compareTo(x)
                    x != null -> -1
                    y != null -> 1
                    else -> names.compare(a.shownTitle, b.shownTitle)
                }
            }
        }
    }
    fun setFolded(url: String, folded: Boolean) {
        val p = load().firstOrNull { it.url == url } ?: return
        p.folded = if (folded) true else null
        upsert(p)
    }
    fun setPinned(url: String, pinned: Boolean) {
        val p = load().firstOrNull { it.url == url } ?: return
        p.pinnedAt = if (pinned) nowSeconds() else null
        upsert(p)
    }
    /** THE HAND-ADDED SECTION WEARS A PIN TOO (iOS manualPinKey, 24.09), kept in the settings: a moment with no link in it. */
    const val MANUAL_PIN_KEY = "mt.vpn.manualPin"
    val manualPinnedAt: Double? get() = Prefs.str(MANUAL_PIN_KEY, "").toDoubleOrNull()?.takeIf { 0 < it }
    fun setManualPinned(pinned: Boolean) { if (pinned) Prefs.setStr(MANUAL_PIN_KEY, nowSeconds().toString()) else Prefs.remove(MANUAL_PIN_KEY) }
    /** The hand-added section's fold outlives the page as a plan's does (iOS manualFoldKey, 24.09). */
    const val MANUAL_FOLD_KEY = "mt.vpn.manualFolded"
    val manualFolded: Boolean get() = Prefs.bool(MANUAL_FOLD_KEY, false)
    fun setManualFolded(folded: Boolean) { if (folded) Prefs.setBool(MANUAL_FOLD_KEY, true) else Prefs.remove(MANUAL_FOLD_KEY) }
    /** Where the hand-added section stands among the ordered plans (iOS manualSlot): pinned, among the pins by its moment; unpinned,
     *  after the person's own plans and above every wall. */
    fun manualSlot(plans: List<VpnPlan>, pinnedAt: Double?): Int {
        val own = plans.indexOfFirst { it.wallOf != null }.takeIf { 0 <= it } ?: plans.size
        val at = pinnedAt ?: return own
        return plans.take(own).indexOfFirst { (it.pinnedAt ?: 0.0) < at }.takeIf { 0 <= it } ?: own
    }
}

/**
 * THE PLAN'S PANEL, AND NOTHING OF OURS (iOS MontanaVPNSubscription, MontanaVPN.swift:1034-1157; SERVER-DEBT-ACK there): the person
 * pastes the link their provider gave them and this is the road that reads it -- no Montana server on it, no identifier of a person,
 * only the shape that panel's protocol asks for. The link lies in the sealed store on the device.
 */
object VpnSubscription {
    private const val DEVICE_KEY = "mt.vpn.hwid"
    const val ATTEMPTS = 4

    /** A plan's link (iOS isSubscriptionURL): http or https; the fragment names the profile for a human and the server never sees it. */
    fun isSubscriptionURL(s: String): String? {
        val raw = s.trim()
        val low = raw.lowercase(Locale.ROOT)
        if (!low.startsWith("https://") && !low.startsWith("http://")) return null
        val bare = raw.substringBefore('#')
        return bare.takeIf { runCatching { URI(it) }.isSuccess }
    }
    fun deviceId(): String {
        DeviceVault.get(DEVICE_KEY)?.let { String(it, Charsets.UTF_8) }?.takeIf { it.isNotEmpty() }?.let { return it }
        val fresh = UUID.randomUUID().toString().lowercase(Locale.ROOT)
        DeviceVault.set(DEVICE_KEY, fresh.toByteArray(Charsets.UTF_8))
        return fresh
    }

    /** The words the page shows for a failure (iOS FetchError.label): the code when the panel answered, the class when it did not. */
    sealed class FetchError(val label: String) : Exception(label) {
        class Status(val code: Int) : FetchError("HTTP $code")
        class Network : FetchError("network")
        class Empty : FetchError("empty")
        class Form(val form: String) : FetchError("body: $form")
    }
    class Fetched(val servers: List<VpnConfig>, val title: String, val userinfo: Map<String, Long>, val updateHours: Int?,
                  val form: String, val dropped: Int)
    private class Reply(val code: Int, val headers: Map<String?, List<String>>, val body: ByteArray) {
        fun header(name: String): String? = headers.entries.firstOrNull { it.key?.equals(name, ignoreCase = true) == true }?.value?.firstOrNull()
    }

    /** ONE ATTEMPT IS NOT AN ANSWER (iOS fetch, 22.09: the panel behind the author's link answered 502 to three requests of eight): a
     *  5xx or a network fault is asked again after a breath, a 4xx is the panel's word and stands. Blocking. */
    fun fetch(url: String, onAttempt: ((Int) -> Unit)? = null): Fetched {
        var last: FetchError = FetchError.Network()
        for (attempt in 1..ATTEMPTS) {
            onAttempt?.invoke(attempt)
            try {
                val r = get(url)
                if (r.code in 200..299) {
                    val read = VpnBody.body(r.body)
                    val list = read.servers.onEach { it.subscription = url }
                    val title = headerText(r, "profile-title")
                    val info = userinfo(headerText(r, "subscription-userinfo"))
                    val unspoken = VpnParse.Report(list.toMutableList()).unsupportedWord
                    vpnMark("vpn_sub", "plan=${vpnPlanLabel(url)} try=$attempt status=${r.code} bytes=${r.body.size} form=${read.form} servers=${list.size} unsupported=${unspoken.ifEmpty { "-" }} dropped=${read.dropped}")
                    if (list.isEmpty()) throw if (read.form in setOf("links", "base64", "engine-json", "sing-box", "clash")) FetchError.Empty() else FetchError.Form(read.form)
                    return Fetched(list, title, info, headerText(r, "profile-update-interval").toIntOrNull(), read.form, read.dropped)
                }
                vpnMark("vpn_sub", "plan=${vpnPlanLabel(url)} try=$attempt status=${r.code} bytes=${r.body.size}")
                last = FetchError.Status(r.code)
                if (r.code < 500) throw last
            } catch (e: FetchError) {
                if (e is FetchError.Status && 500 <= e.code) last = e else throw e
            } catch (e: Exception) {
                vpnMark("vpn_sub", "plan=${vpnPlanLabel(url)} try=$attempt err=${e.javaClass.simpleName}")
                last = FetchError.Network()
            }
            if (attempt < ATTEMPTS) Thread.sleep(1500)
        }
        throw last
    }

    /** The request the panels' protocol asks for (iOS request): who asks, and this device's own random identity for their device limit. */
    private fun get(url: String): Reply {
        var target = URL(url)
        val ver = runCatching { Book.ctx.packageManager.getPackageInfo(Book.ctx.packageName, 0).versionName }.getOrNull()?.substringBefore(' ') ?: "1"
        val headers = linkedMapOf("User-Agent" to "Montana/$ver (Android)", "Accept" to "*/*", "x-hwid" to deviceId(), "x-device-os" to "Android",
            "x-ver-os" to Build.VERSION.RELEASE, "x-device-model" to Build.MODEL)
        repeat(6) {
            // THE PLATFORM'S TRANSPORT RULE, AS THE IPHONE'S (iOS App Transport Security): plain http is refused for a public name and
            // never applied to an address, an unqualified name or a .local one -- the self-hosted panels at http://address:port/sub
            val r = if (target.protocol == "http" && atsExempt(target.host)) plainGet(target, headers) else {
                val c = (target.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 30_000; readTimeout = 30_000; instanceFollowRedirects = false
                    for ((k, v) in headers) setRequestProperty(k, v)
                }
                try {
                    val code = c.responseCode
                    val body = if (code in 300..399) ByteArray(0) else (if (400 <= code) c.errorStream else c.inputStream)?.use { it.readBytes() } ?: ByteArray(0)
                    Reply(code, c.headerFields, body)
                } finally { c.disconnect() }
            }
            // the platform's session follows a redirect, between schemes too (iOS URLSession)
            val to = if (r.code in 300..399 && r.code != 304) r.header("Location") else null
            if (to != null) { target = URL(target, to); return@repeat }
            return r
        }
        throw java.io.IOException("too many redirects")
    }
    private fun atsExempt(host: String): Boolean {
        val h = host.trim('[', ']').lowercase(Locale.ROOT)
        val address = Regex("^[0-9.]+$").matches(h) || h.contains(':')
        return address || !h.contains('.') || h.endsWith(".local")
    }
    /** One plain HTTP/1.1 GET on a socket, for the addresses the transport rule leaves alone: the status, the headers, the body
     *  (by its length, its chunks, or to the close). */
    private fun plainGet(u: URL, headers: Map<String, String>): Reply {
        java.net.Socket().use { s ->
            val port = if (u.port < 0) 80 else u.port
            s.connect(java.net.InetSocketAddress(u.host.trim('[', ']'), port), 30_000)
            s.soTimeout = 30_000
            val path = (u.path.ifEmpty { "/" }) + (u.query?.let { "?$it" } ?: "")
            val req = StringBuilder("GET $path HTTP/1.1\r\nHost: ${u.host}${if (u.port < 0) "" else ":" + u.port}\r\n")
            for ((k, v) in headers) req.append(k).append(": ").append(v).append("\r\n")
            req.append("Connection: close\r\n\r\n")
            s.getOutputStream().apply { write(req.toString().toByteArray(Charsets.UTF_8)); flush() }
            val input = java.io.BufferedInputStream(s.getInputStream())
            fun line(): String {
                val b = java.io.ByteArrayOutputStream()
                while (true) { val ch = input.read(); if (ch < 0 || ch == '\n'.code) break; if (ch != '\r'.code) b.write(ch) }
                return String(b.toByteArray(), Charsets.ISO_8859_1)
            }
            val status = line().split(' ').getOrNull(1)?.toIntOrNull() ?: throw java.io.IOException("no status")
            val got = LinkedHashMap<String?, MutableList<String>>()
            while (true) {
                val l = line()
                if (l.isEmpty()) break
                val i = l.indexOf(':')
                if (0 < i) got.getOrPut(l.substring(0, i).trim()) { ArrayList() }.add(l.substring(i + 1).trim())
            }
            fun h(n: String) = got.entries.firstOrNull { it.key.equals(n, ignoreCase = true) }?.value?.firstOrNull()
            val body = java.io.ByteArrayOutputStream()
            when {
                h("Transfer-Encoding")?.contains("chunked", ignoreCase = true) == true -> while (true) {
                    val size = line().substringBefore(';').trim().toIntOrNull(16) ?: break
                    if (size == 0) break
                    val buf = ByteArray(size); var off = 0
                    while (off < size) { val n = input.read(buf, off, size - off); if (n < 0) break; off += n }
                    body.write(buf, 0, off); line()
                }
                h("Content-Length") != null -> {
                    val want = h("Content-Length")!!.toLongOrNull() ?: 0L
                    val buf = ByteArray(16384); var left = want
                    while (0 < left) { val n = input.read(buf, 0, minOf(buf.size.toLong(), left).toInt()); if (n < 0) break; body.write(buf, 0, n); left -= n }
                }
                else -> body.write(input.readBytes())
            }
            return Reply(status, got, body.toByteArray())
        }
    }

    /** "base64:..." or plain, as the panels write a header (iOS headerText). COMPAT-LOCAL: a panel's word read here, never one between
     *  Montana builds. */
    private fun headerText(r: Reply, name: String): String {
        val raw = r.header(name)?.trim().orEmpty()
        if (raw.isEmpty()) return ""
        if (raw.lowercase(Locale.ROOT).startsWith("base64:")) VpnText.b64utf8(raw.substring(7))?.let { return it }
        return raw
    }
    /** "upload=0; download=40333815636; total=0; expire=1820218794" (iOS userinfo). */
    fun userinfo(s: String): Map<String, Long> {
        val out = HashMap<String, Long>()
        for (part in s.split(';')) {
            val kv = part.split("=", limit = 2).map { it.trim() }
            if (kv.size == 2) kv[1].toLongOrNull()?.let { out[kv[0]] = it }
        }
        return out
    }
}

/** THE SERVER THE TUNNEL STANDS ON (iOS MontanaVPNSelection, MontanaVPN.swift:762-791): one writer of the choice. */
object VpnSelection {
    const val KEY = "mt.vpn.sel"
    /** THE PERSON'S LAST HAND ON THE VPN (iOS handKey, 30.09): nothing automatic raises another row within the dead rows' ten minutes. */
    const val HAND_KEY = "mt.vpn.hand"
    val handAt: Double get() = Prefs.str(HAND_KEY, "0").toDoubleOrNull() ?: 0.0
    fun noteHand() = Prefs.setStr(HAND_KEY, nowSeconds().toString())
    /** THE CHOICE IS SPOKEN, NOT ONLY WRITTEN (iOS adopt, 25.09): the tunnel's owner publishes it and the page draws it. */
    fun adopt(id: String) { Prefs.setStr(KEY, id); VpnTunnel.noteSelection(id) }
    /** On the main thread. */
    fun select(act: MainActivity?, cfg: VpnConfig, why: String) {
        if (cfg.proto == VpnProto.UNSUPPORTED) {   // the row says what it is; nothing is installed from it (29.09)
            vpnMark("vpn_ui", "select refused row=${cfg.id.take(8)} scheme=${cfg.scheme ?: "?"} -- the engine cannot speak it")
            return
        }
        adopt(cfg.id)
        if (why == "hand") { VpnDead.clear(cfg.id); noteHand() }   // the person's finger outranks the dead mark (25.09)
        val on = VpnTunnel.isOn
        vpnMark("vpn_ui", "select row=${cfg.id.take(8)} net=${cfg.network} sec=${cfg.security} by=$why restart=$on")
        if (on) VpnTunnel.restart(act, cfg)
    }
}

/** THE DEAD ROWS (iOS MontanaVPNDead, MontanaVPNTunnel.swift:838-854): a server the tunnel judged dead is raised by nothing automatic
 *  for ten minutes; a finger on the row clears its mark. */
object VpnDead {
    private const val KEY = "mt.vpn.dead"
    const val COOLDOWN = 600.0
    private fun table(): MutableMap<String, Double> {
        val o = runCatching { JSONObject(Prefs.str(KEY, "{}")) }.getOrNull() ?: return HashMap()
        return o.keys().asSequence().associateWith { o.optDouble(it, 0.0) }.toMutableMap()
    }
    private fun keep(t: Map<String, Double>) = Prefs.setStr(KEY, JSONObject(t).toString())
    fun mark(id: String) {
        val now = nowSeconds()
        val t = table().filterValues { now < it }.toMutableMap()
        t[id] = now + COOLDOWN
        keep(t)
    }
    fun clear(id: String) { val t = table(); t.remove(id); keep(t) }
    fun isDead(id: String): Boolean = (table()[id] ?: 0.0) > nowSeconds()
}

/** THE BOOK OF DELAYS (iOS MontanaVPNDelayBook, MontanaVPN.swift:797-829): what every server last answered and when; the row draws
 *  the last number always, dimmed past half an hour. This device's own word about this hour, kept under its own key. */
object VpnDelayBook {
    const val KEY = "mt.vpn.delays"
    const val STALE = 1800.0
    class Entry(val ms: Int?, val err: String?, val at: Double) { val age: Double get() = maxOf(0.0, nowSeconds() - at) }
    private val entries = HashMap<String, Entry>()
    private var read = false
    private fun read() {
        if (read) return
        read = true
        // the stored form is {id: [ms, at]}, ms -1 for an answer of no number; the error's word is not kept across runs
        val o = runCatching { JSONObject(Prefs.str(KEY, "{}")) }.getOrNull() ?: return
        for (id in o.keys()) {
            val v = o.optJSONArray(id) ?: continue
            if (v.length() != 2) continue
            val ms = v.optDouble(0, -1.0)
            entries[id] = Entry(if (ms < 0) null else ms.toInt(), if (ms < 0) "no answer" else null, v.optDouble(1, 0.0))
        }
    }
    @Synchronized fun entry(id: String): Entry? { read(); return entries[id] }
    @Synchronized fun record(id: String, ms: Int?, err: String?) { read(); entries[id] = Entry(ms, if (ms == null) err ?: "no answer" else null, nowSeconds()) }
    /** Kept once per batch, never per row, and only for servers the list still holds. */
    fun persist() {
        val known = VpnStore.load().map { it.id }.toSet()
        val o = JSONObject()
        synchronized(this) { read(); for ((id, e) in entries) if (id in known) o.put(id, JSONArray().put((e.ms ?: -1).toDouble()).put(e.at)) }
        Prefs.setStr(KEY, o.toString())
    }
    @Synchronized fun stalest(list: List<VpnConfig>): VpnConfig? {
        read()
        return list.filter { it.proto != VpnProto.UNSUPPORTED }.minByOrNull { entries[it.id]?.at ?: 0.0 }
    }
}

/** THE ENGINE'S OWN MEASUREMENT (iOS MontanaEngineDelay, MontanaVPN.swift:609-694): the server dialled for real, its protocol spoken, a
 *  204-endpoint fetched through it; several servers through one engine instance, `width` at a time, the answers in their order. */
object VpnEngineDelay {
    /** The engine's batch answer -- [{"ms":71},{"ms":-1,"err":"..."}] -- as rows; a batch that failed whole fails every row. */
    fun answers(text: String, count: Int, error: String?): List<Pair<Int?, String?>> {
        val rows = (if (error == null) runCatching { JSONArray(text) }.getOrNull()?.takeIf { it.length() == count } else null)
            ?: return List(count) { null to classified(error ?: "no answer") }
        return (0 until count).map { i ->
            val row = rows.optJSONObject(i)
            val ms = row?.optInt("ms", -1) ?: -1
            if (0 <= ms) ms to null else null to classified(row?.optString("err")?.ifEmpty { null } ?: "no answer")
        }
    }
    /** The engine's own words to a short honest one (iOS reason). */
    fun reason(word: String): String {
        val d = word.lowercase(Locale.ROOT)
        return when {
            "deadline" in d || "timeout" in d -> "timeout"
            "refused" in d -> "refused"
            "reset" in d -> "reset"
            d == "eof" || d.endsWith(": eof") || "closed" in d -> "closed"
            "no such host" in d || "dns" in d -> "DNS error"
            "reality" in d || "tls" in d || "certificate" in d -> "TLS error"
            "unreachable" in d || "network is down" in d -> "unreachable"
            else -> "connection error"
        }
    }
    /** THE ENGINE'S WORD RIDES BEHIND THE CLASS (iOS classified, 29.09): every host and address scrubbed, the spaces closed. */
    fun classified(raw: String): String { val word = scrub(raw); val kind = reason(raw); return if (word.isEmpty()) kind else "$kind·$word" }
    fun scrub(raw: String): String {
        var t = raw.replace(Regex("""\[[0-9A-Fa-f:.]+\](:\d+)?"""), "[ip6]")
        t = t.replace(Regex("""[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d+)?"""), "[host]")
        return t.replace(" ", "_").take(90)
    }
}

/** THE DELAY OF A SERVER (iOS MontanaVPNDelay, MontanaVPN.swift:696-760). Under a standing tunnel the engine's sockets are protected
 *  (MontanaVpnService), so a measurement leaves the phone through its own network and our tunnel is not inside the number. */
object VpnDelay {
    /** How many servers one batch measures at once (the author's word 29.09: «ping six servers at once»). */
    const val WIDTH = 6
    /** Blocking: off the main thread. */
    fun measureMany(list: List<VpnConfig>, stun: String? = null): List<Pair<Int?, String?>> {
        if (list.isEmpty()) return emptyList()
        val outbounds = JSONArray()
        list.forEach { outbounds.put(XrayConfig.outbound(it)) }
        val json = outbounds.toString()
        return try {
            val text = if (stun != null) Montanaxray.measureUDPMany(json, stun, WIDTH.toLong(), "", 0)
                       else Montanaxray.measureMany(json, "", WIDTH.toLong(), "", 0)
            VpnEngineDelay.answers(text, list.size, null)
        } catch (e: Throwable) {
            VpnEngineDelay.answers("", list.size, e.message ?: "no answer")
        }
    }
}

/**
 * THE PING LINE, SIX AT A TIME (iOS MontanaVPNPingLine, MontanaNetworkView.swift:1054-1130): only the person's finger on a section's
 * gauge asks it; the line walks the list in batches behind the page, every answer lands in the book of delays as it comes, and the rows
 * in flight wear a spinner beside their last number. A measurement reports a condition; it never chooses a server.
 */
object VpnPingLine {
    @Volatile var inFlight: Set<String> = emptySet(); private set
    private val waiting = ArrayList<Pair<String, VpnConfig>>()
    private val queued = HashSet<String>()
    private var running = false
    private var done = 0
    private var total = 0
    private var began = 0L
    private val answered = ArrayList<Int>()
    private var failed = 0

    @Synchronized fun ask(list: List<VpnConfig>) {
        var fresh = 0
        for (c in list) if (c.proto != VpnProto.UNSUPPORTED && queued.add(c.id)) { waiting.add(c.id to c); fresh++ }
        if (fresh == 0) return
        total += fresh
        vpnMark("vpn_ui", "ping line asked=$fresh waiting=${waiting.size} of=$total")
        if (running) return
        running = true
        began = System.currentTimeMillis(); answered.clear(); failed = 0
        Thread({ walk() }, "mt-vpn-ping").start()
    }

    private fun walk() {
        while (true) {
            val batch = synchronized(this) {
                if (waiting.isEmpty()) {
                    vpnMark("vpn_ui", "ping all done n=$done ok=${answered.size} fail=$failed best=${answered.minOrNull() ?: 0} worst=${answered.maxOrNull() ?: 0} took=${System.currentTimeMillis() - began}")
                    running = false; done = 0; total = 0
                    return
                }
                val b = waiting.take(VpnDelay.WIDTH)
                repeat(b.size) { waiting.removeAt(0) }
                inFlight = b.map { it.first }.toSet()
                b
            }
            VpnBus.say()
            val t0 = System.currentTimeMillis()
            var results = VpnDelay.measureMany(batch.map { it.second })
            // «busy» is the engine's word about itself, never the servers' verdict: asked once more after a breath
            if (results.any { it.second == "busy" }) { Thread.sleep(1500); results = VpnDelay.measureMany(batch.map { it.second }) }
            val fault = results.size == batch.size && results.all { it.first == null && it.second in setOf("busy", "unreachable", "timeout", "connection error") }
            if (fault) vpnMark("vpn_ui", "ping batch indeterminate n=${batch.size}; kept last confirmed rows")
            synchronized(this) {
                batch.forEachIndexed { i, item ->
                    val r = results.getOrNull(i) ?: (null to "connection error")
                    queued.remove(item.first)
                    done++
                    if (!fault) {
                        if (r.first != null) answered.add(r.first!!) else failed++
                        VpnDelayBook.record(item.first, r.first, r.second)
                    }
                    vpnMark("vpn_ui", "ping row=${item.first.take(8)} net=${item.second.network} ms=${r.first ?: "-"} err=${r.second ?: "-"} step=$done/$total")
                }
                inFlight = emptySet()
            }
            VpnDelayBook.persist()
            vpnMark("vpn_ui", "ping batch n=${batch.size} took=${System.currentTimeMillis() - t0}")
            VpnBus.say()
        }
    }
}

/**
 * THE FRESHENER (iOS MontanaVPNFreshener, MontanaVPN.swift:846-905; the author's word 30.09: «once an hour it checks natively and slows
 * nothing, strictly in turn, one subscription, then a pause of 13 seconds, then the next; the top six by the person's own order»): alive
 * while the app stands on the screen -- once an hour, and at a return after more than an hour away, the first six plans of the page's
 * order are asked again; the rest wait for the hand (a plan's own update, the pull of the page). Nothing here measures a server.
 */
object VpnFreshener {
    const val BEAT = 3_600_000L
    const val TOP = 6
    const val PAUSE = 13_000L
    @Volatile var generation = 0; private set
    private var active = false
    @Volatile private var beating = false
    @Volatile private var pulling = false
    private var lastBeat = 0L
    private val clock = android.os.Handler(android.os.Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() { Thread({ hourBeat("hour") }, "mt-vpn-fresh").start(); clock.postDelayed(this, BEAT) }
    }
    private fun moved() { generation++; VpnBus.say() }
    /** On the main thread: the app came to the screen or left it (iOS appActive): the hour's beat stands only while it is there. */
    fun appActive(on: Boolean) {
        if (on == active) return
        active = on
        clock.removeCallbacks(tick)
        if (!on) return
        clock.postDelayed(tick, BEAT)
        if (BEAT <= System.currentTimeMillis() - lastBeat) Thread({ hourBeat("return") }, "mt-vpn-fresh").start()
    }
    /** The pull of the page, the person's own hand (iOS coinRefresh): every plan is loaded now, one after another. Blocking. */
    fun coinRefresh() {
        if (pulling) return
        pulling = true
        try {
            var refreshed = 0
            for (plan in VpnPlans.load()) {
                if (VpnWallToken.isWallKey(plan.url)) continue
                if (runCatching { VpnStore.addFromSubscription(plan.url) }.isSuccess) refreshed++
            }
            if (0 < refreshed) moved()
            vpnMark("vpn_ui", "fresh coin plans=$refreshed")
        } finally { pulling = false }
    }
    private fun hourBeat(reason: String) {
        if (beating) return
        beating = true
        try {
            lastBeat = System.currentTimeMillis()
            var asked = 0
            for (plan in VpnPlans.ordered().take(TOP)) {
                if (0 < asked) Thread.sleep(PAUSE)
                asked++
                if (runCatching { VpnStore.addFromSubscription(plan.url) }.isSuccess) moved()
            }
            vpnMark("vpn_ui", "fresh $reason plans=$asked of=${VpnPlans.load().size}")
        } finally { beating = false }
    }
}

/** THE RETIRED VPN-WALL TOKEN (iOS MTVPNWall, MontanaVPN.swift:2012-2020): still recognised for live older builds, never imported,
 *  fetched, answered or published (author, 13.10.2026). Its letters ride the wire's service mark (Pipes.isService) and never land. */
object VpnWallToken {
    const val MARK = "​​VW:"
    const val KEY_PREFIX = "montana://vpn-wall/"
    fun isWallKey(key: String?): Boolean = key?.startsWith(KEY_PREFIX) == true
}

/** The nodes' VPN of older builds (iOS MTVPNPay, MontanaNetworkView.swift:1494-1501): its names stay readable in the wallet; this app no
 *  longer provisions rows or charges coins for a tunnel. */
object VpnPay {
    const val REF_PREFIX = "vpnpay:"
    const val PLAN_KEY = "montana://vpn-pay"
    fun isPlan(url: String?): Boolean = url == PLAN_KEY
}
