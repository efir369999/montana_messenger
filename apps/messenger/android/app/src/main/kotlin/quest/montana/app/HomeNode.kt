package quest.montana.app

import android.content.Context
import android.util.Log
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.cert.X509Certificate
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

// YOUR NODE (iOS MontanaHomeNode, the author's word 28.09: «your node is your backup of the whole phone»).
// A machine the person owns, named by its address alone. The node keeps the sealed container the engine writes
// (MontanaBackup), under the key the 24 words open, the words never in it. A node of one's own knows no account,
// so the phone names a shelf by a TOKEN only the words derive (HKDF of the entropy under one label, then one HMAC);
// the node checks sha256(token) against the shelf's name and stores nothing of anybody. The token rides only inside
// TLS to the person's own machine.
object MontanaHomeNode {
    private const val HOST = "mt.home.node"        // NOT-UI: the node's address, sealed under the device key
    private const val PIN = "mt.home.node.pin"     // NOT-UI: the digest of the certificate the node made for itself
    private const val ON = "mt.home.node.on"       // NOT-UI: the daily copies switch
    private val keyLabel = "mt-vault-owner-v1".toByteArray()   // NOT-UI: the derivation's own label
    private val tokenLabel = "mt-vault-token".toByteArray()    // NOT-UI: the token's own label
    const val TOKEN_HEADER = "X-Montana-Vault"
    const val NAME_HEADER = "X-Montana-Name"
    /** The door's own TLS port on a node put up by address (iOS MontanaNodeSetup.tlsPort). */
    const val TLS_PORT = 8463

    val host: String get() = DeviceVault.get(HOST)?.toString(Charsets.UTF_8) ?: ""
    fun setHost(h: String) {
        val clean = h.trim().lowercase().replace("https://", "").replace("/", "")   // NOT-UI: the address, bare
        if (clean.isEmpty()) DeviceVault.delete(HOST) else DeviceVault.set(HOST, clean.toByteArray())
        Log.i("Montana", "home_node host set=${if (clean.isEmpty()) 0 else 1}")
    }
    private const val LAST = "mt.home.node.at"   // NOT-UI: this device's own clock of its last copy to the node
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("mt.defaults", Context.MODE_PRIVATE)
    fun on(ctx: Context) = prefs(ctx).getBoolean(ON, false)
    fun setOn(ctx: Context, v: Boolean) { prefs(ctx).edit().putBoolean(ON, v).apply() }
    fun noteCopied(ctx: Context, at: java.util.Date) { prefs(ctx).edit().putLong(LAST, at.time).apply() }
    /** Due once a day, or when the node holds none of ours. */
    fun due(ctx: Context, holdsNone: Boolean) = holdsNone || System.currentTimeMillis() - prefs(ctx).getLong(LAST, 0) >= 86_400_000L
    /** «Forget this device»: the node's address leaves with the person. */
    fun forget(ctx: Context) { DeviceVault.delete(HOST); DeviceVault.delete(PIN); prefs(ctx).edit().remove(ON).remove(LAST).apply() }
    /** The digest of the node's own certificate (a node put up by address); empty for a named node. */
    val pin: String get() = DeviceVault.get(PIN)?.toString(Charsets.UTF_8) ?: ""

    /** A pinned node is spoken to straight, on the door's own TLS port; a named one through its front, under /pushwake. */
    fun base(h: String): String? = when {
        h.isEmpty() -> null
        pin.isEmpty() -> "https://$h/pushwake"
        else -> "https://$h:$TLS_PORT"
    }

    // ── the shelf's name ──
    fun vaultKey(entropy: ByteArray): ByteArray = Hkdf.sha256(entropy, ByteArray(0), keyLabel)
    fun token(k: ByteArray): ByteArray = Hkdf.hmac(k, tokenLabel)
    fun shelf(token: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(token))

    /** This seed's token, or null without a seed. */
    fun tokenHex(): String? {
        val m = MontanaSeed.mnemonic ?: return null
        val e = MtBindings.nativeMnemonicToEntropy(m)?.takeIf { it.size == 32 } ?: return null
        val k = vaultKey(e)
        e.fill(0)
        return hex(token(k)).also { k.fill(0) }
    }

    /** THE FROZEN VECTORS (iOS MontanaHomeNode.keyKAT, computed outside this code on the counting bytes 0x00..0x1f). */
    fun keyKAT(): Boolean {
        val counting = ByteArray(32) { it.toByte() }
        val k = vaultKey(counting)
        val t = token(k)
        return hex(k) == "aa75b0afc0c9b1b4e31a8fecf371ee72866865e7a77cf61f9f1f0ad457652097"
            && hex(t) == "0695b3db38b3c8525f8d8b7a270ae0bc5504c2d0d58634a937e52c2b9f7d2d28"
            && shelf(t) == "125ff41ffac97cae3ce9ba4ab20ae5586587f5c8960fee4055f6aaa8c219b49a"
    }
}

/** RFC 5869 HKDF-SHA-256 and HMAC-SHA-256 on the platform's own javax.crypto (iOS: CryptoKit). */
object Hkdf {
    fun hmac(key: ByteArray, data: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(key.takeIf { it.isNotEmpty() } ?: ByteArray(32), "HmacSHA256")); doFinal(data) }

    /** Extract then expand to 32 bytes; an empty salt keys the extract with zeros, as the RFC says. */
    fun sha256(ikm: ByteArray, salt: ByteArray, info: ByteArray): ByteArray {
        val prk = hmac(salt, ikm)
        return hmac(prk, info + byteArrayOf(1)).also { prk.fill(0) }
    }
}

fun hex(b: ByteArray): String = b.joinToString("") { "%02x".format(it) }

/**
 * WHAT THE NODE ANSWERS, AND THIS PHONE'S OWN WORK ON THE WAY TO IT (iOS HomeNodeWatch). The bar reads two shares:
 * the bytes come (this phone's own count), then the frames filed.
 */
object HomeNodeWatch {
    /** What the node said last (iOS HomeNodeWatch.State): its own word, never this phone's guess. */
    sealed class State {
        object Unknown : State()
        object NoHost : State()
        object Asking : State()
        class None(val free: Long) : State()
        class Held(val name: String, val date: java.util.Date, val bytes: Long, val free: Long) : State()
        class Refused(val code: String) : State()
        class Silent(val code: String) : State()
    }
    @Volatile var state: State = State.Unknown; private set
    /** What the node names it can do (/health). */
    @Volatile var caps: List<String> = emptyList(); private set
    @Volatile var sealing: Double? = null; private set
    @Volatile var sending: Double? = null; private set
    @Volatile var fetching: Double? = null; private set
    @Volatile var restoring: Double? = null; private set
    @Volatile private var busy = false
    /** Told on every move of a share; the page that shows the bar sets it. */
    @Volatile var onChange: (() -> Unit)? = null
    private fun said() { onChange?.invoke() }

    private fun open(path: String, token: String?): HttpURLConnection? {
        val b = MontanaHomeNode.base(MontanaHomeNode.host) ?: return null
        val c = URL(b + path).openConnection() as HttpURLConnection
        if (token != null) c.setRequestProperty(MontanaHomeNode.TOKEN_HEADER, token)
        c.connectTimeout = 15_000
        c.readTimeout = 60_000
        if (c is HttpsURLConnection) NodeTrust.apply(c)
        return c
    }

    private fun code(e: Exception) = e.javaClass.simpleName
    private fun json(c: HttpURLConnection): org.json.JSONObject? = runCatching {
        org.json.JSONObject((if (c.responseCode < 400) c.inputStream else c.errorStream).bufferedReader().readText())
    }.getOrNull()

    /** The node's word, asked afresh: what it can do, and what it holds of ours. Runs on a worker thread. */
    fun ask() {
        if (MontanaHomeNode.host.isEmpty()) { state = State.NoHost; return said() }
        val tok = MontanaHomeNode.tokenHex() ?: run { state = State.NoHost; return said() }
        if (state is State.Asking) return
        state = State.Asking; said()
        runCatching {
            val h = open("/health", null)!!
            if (h.responseCode == 200) json(h)?.optJSONObject("caps")?.let { j ->
                caps = j.keys().asSequence().filter { j.optBoolean(it) }.sorted().toList()
            }
            h.disconnect()
        }
        state = try {
            val c = open("/vault-have", tok)!!
            val code = c.responseCode
            val j = if (code == 200) json(c) else null
            c.disconnect()
            if (j == null) {
                Log.i("Montana", "home_node have refused code=$code")
                State.Refused(code.toString())
            } else {
                val free = j.optLong("free")
                val top = j.optJSONArray("held")?.optJSONObject(0)
                Log.i("Montana", "home_node holds n=${j.optJSONArray("held")?.length() ?: 0} free=$free")
                if (top != null && top.has("name")) {
                    val n = top.getString("name")
                    State.Held(n, MontanaBackup.born(n) ?: java.util.Date(top.optLong("at") * 1000), top.optLong("bytes"), free)
                } else State.None(free)
            }
        } catch (e: Exception) {
            Log.i("Montana", "home_node no answer ${code(e)}")
            State.Silent(code(e))
        }
        said()
    }

    /**
     * A COPY TO THE NODE: sealed by the engine, sent whole, and held only on the node's echo of its digest.
     * Runs on the caller's worker thread; `done` answers there.
     */
    fun send(ctx: Context, done: (CopyResult) -> Unit) {
        val tok = MontanaHomeNode.tokenHex()
        if (busy || tok == null) return done(CopyResult.Refused(if (tok == null) Refusal.NoSeed else Refusal.Stopped))
        busy = true
        sealing = 0.0; said()
        var file: File? = null
        try {
            val made = MontanaBackup.create(ctx) { f -> sealing = f; said() }
            sealing = null; said()
            if (made !is CopyResult.Made) return done(made)
            val f = made.file.also { file = it }
            val digest = hex(MessageDigest.getInstance("SHA-256").let { md ->
                f.inputStream().use { i -> val b = ByteArray(1 shl 16); while (true) { val n = i.read(b); if (n < 0) break; md.update(b, 0, n) } }
                md.digest()
            })
            val c = open("/vault-put?name=${f.name}&sha256=$digest", tok) ?: return done(CopyResult.Refused(Refusal.Stopped))
            c.requestMethod = "PUT"
            c.doOutput = true
            c.setFixedLengthStreamingMode(f.length())
            c.setRequestProperty("content-type", "application/octet-stream")
            c.setRequestProperty("X-Montana-SHA256", digest)
            sending = 0.0; said()
            Log.i("Montana", "home_node put start name=${f.name} bytes=${f.length()}")
            val sentAll = java.util.concurrent.atomic.AtomicLong(0)
            // A FRONT THAT STOPS READING MUST NOT HOLD THE PHONE (29.09, diag.montana.quest: nginx refuses a body over
            // 1 MB with 413 and stops reading; the write then waits forever, the bar at 49%). No byte taken for a
            // minute → the connection is cut, and the node's own word is read if it gave one.
            val moved = java.util.concurrent.atomic.AtomicLong(System.currentTimeMillis())
            val watch = java.util.Timer(true).apply {
                schedule(object : java.util.TimerTask() {
                    override fun run() { if (System.currentTimeMillis() - moved.get() > 60_000) { c.disconnect(); cancel() } }
                }, 5_000, 5_000)
            }
            try { c.outputStream.use { out ->
                f.inputStream().use { inp ->
                    val b = ByteArray(1 shl 16)
                    var sent = 0L
                    var shown = -1
                    while (true) {
                        val n = inp.read(b); if (n < 0) break
                        out.write(b, 0, n); sent += n; sentAll.set(sent); moved.set(System.currentTimeMillis())
                        val pct = (sent * 100 / maxOf(1L, f.length())).toInt()
                        if (pct != shown) { shown = pct; sending = pct / 100.0; said() }
                    }
                }
            } } catch (e: java.io.IOException) {
                val said = runCatching { c.responseCode }.getOrDefault(-1)
                Log.i("Montana", "home_node put cut code=$said sent=${sentAll.get()} ${code(e)}: ${e.message?.take(80)}")
                // The node's own code when it gave one; else where the road stopped, in the person's own units.
                val where = if (said > 0) "put $said" else "put stalled at ${sentAll.get() / 1024} KB of ${f.length() / 1024} KB"
                return done(CopyResult.Refused(Refusal.CloudRefused(where)))
            } finally { watch.cancel() }
            val code = c.responseCode
            val j = json(c)
            c.disconnect()
            sending = null; said()
            if (code != 200 || j?.optString("sha256") != digest) {
                Log.i("Montana", "home_node put refused code=$code")
                return done(CopyResult.Refused(Refusal.CloudRefused("put $code ${j?.optString("error") ?: ""}".trim())))
            }
            MontanaHomeNode.noteCopied(ctx, MontanaBackup.born(f.name) ?: java.util.Date())
            Log.i("Montana", "home_node held bytes=${f.length()} (the node echoed the digest)")
            done(made)
        } catch (e: Exception) {
            Log.i("Montana", "home_node put no answer ${code(e)}")
            state = State.Silent(code(e))
            done(CopyResult.Refused(Refusal.CloudRefused("put ${code(e)}")))
        } finally {
            file?.delete()   // handed: the shelf copy leaves either way; the node's word decides what is held
            sealing = null; sending = null; busy = false; said()
        }
    }

    /**
     * THE DAILY ROAD (launch and the switch): the node is asked first; a copy is sealed and sent only when one is due --
     * the node holds none of ours, or this device's last copy is a day old -- and rides Wi-Fi alone.
     */
    /** Once per launch of the app, a little after the first screen stands (iOS tickSoon): a page drawn anew is not a launch. */
    @Volatile private var launched = false
    fun tickSoon(act: MainActivity) {
        if (launched) return
        launched = true
        act.onMainAfter(12_000) { act.background { tick(act, force = false) } }
    }

    fun tick(ctx: Context, force: Boolean) {
        val why = when { !MontanaHomeNode.on(ctx) -> "switch off"; MontanaHomeNode.host.isEmpty() -> "no address"; busy -> "busy"; else -> null }
        if (why != null) { Log.i("Montana", "home_node tick skipped: $why"); return }
        if (!force && !onWifi(ctx)) run { Log.i("Montana", "home_node tick skipped: not on Wi-Fi (${networkWord(ctx)})"); return }
        ask()
        val none = when (state) { is State.None -> true; is State.Held -> false; else -> return }
        if (!MontanaHomeNode.due(ctx, none)) run { Log.i("Montana", "home_node tick skipped: not due"); return }
        send(ctx) { ask() }
    }

    /**
     * THE NEWEST COPY THE NODE HOLDS comes back to the shelf and is laid into this device by the engine: it merges,
     * it never erases (MontanaBackup.restore). Runs on the caller's worker thread; `done` answers there.
     */
    fun takeBack(ctx: Context, done: (CopyResult) -> Unit) {
        val tok = MontanaHomeNode.tokenHex()
        if (busy || tok == null) return done(CopyResult.Refused(Refusal.Stopped))
        val shelf = MontanaBackup.shelf(ctx) ?: return done(CopyResult.Refused(Refusal.Stopped))
        val conn = open("/vault-get", tok) ?: return done(CopyResult.Refused(Refusal.Stopped))
        busy = true
        fetching = 0.0; said()
        val landing = File(shelf, java.util.UUID.randomUUID().toString() + ".part")   // NOT-UI: the unfinished name
        try {
            val code = conn.responseCode
            val name = conn.getHeaderField(MontanaHomeNode.NAME_HEADER)
            if (code != 200 || name == null || MontanaBackup.born(name) == null || !MontanaBackup.plainName(name)) {
                Log.i("Montana", "home_node get refused code=$code")
                return done(CopyResult.Refused(if (code == 404) Refusal.Empty else Refusal.CloudRefused("get $code")))
            }
            val total = conn.contentLengthLong
            var got = 0L
            conn.inputStream.use { inp ->
                landing.outputStream().use { out ->
                    val buf = ByteArray(1 shl 16)
                    var shown = -1
                    while (true) {
                        val n = inp.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        got += n
                        if (total > 0) {
                            val pct = (got * 100 / total).toInt()
                            if (pct != shown) { shown = pct; fetching = pct / 100.0; said() }
                        }
                    }
                }
            }
            val dst = File(shelf, name)
            dst.delete()
            if (!landing.renameTo(dst)) return done(CopyResult.Refused(Refusal.DiskRefused("move")))
            fetching = null; restoring = 0.0; said()
            Log.i("Montana", "home_node fetched $name")
            val r = MontanaBackup.restore(ctx, dst) { f -> restoring = f; said() }
            if (r is CopyResult.Taken) MontanaHomeNode.noteCopied(ctx, MontanaBackup.born(name) ?: java.util.Date())
            dst.delete()
            done(r)
        } catch (e: Exception) {
            val why = "get " + e.javaClass.simpleName
            Log.i("Montana", "home_node get no answer $why")
            done(CopyResult.Refused(if (e is java.io.IOException && e.message?.contains("ENOSPC") == true) Refusal.NoSpace else Refusal.CloudRefused(why)))
        } finally {
            landing.delete()
            conn.disconnect()
            fetching = null; restoring = null; busy = false; said()
        }
    }
}

/**
 * THE NODE'S CERTIFICATE, TRUSTED BY ITS DIGEST ALONE (iOS MTNodeTrust): a node put up by address has no name and no
 * authority; the digest the set-up brought back is the whole trust. Without a pin the platform's own judgement stands.
 */
private object NodeTrust {
    fun apply(c: HttpsURLConnection) {
        val pin = MontanaHomeNode.pin
        if (pin.isEmpty()) return
        val tm = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = throw java.security.cert.CertificateException()
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                val leaf = chain.firstOrNull() ?: throw java.security.cert.CertificateException("no chain")
                if (hex(MessageDigest.getInstance("SHA-256").digest(leaf.encoded)) != pin) throw java.security.cert.CertificateException("pin")
            }
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        c.sslSocketFactory = SSLContext.getInstance("TLS").apply { init(null, arrayOf(tm), null) }.socketFactory
        // The digest names the machine; its address carries no name a certificate could be issued to.
        c.hostnameVerifier = javax.net.ssl.HostnameVerifier { _, _ -> true }
    }
}
