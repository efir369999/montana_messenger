package quest.montana.app

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

// ─────────────── the VPN wall's servers (iOS MontanaVPN.swift: MontanaVPNConfig, MontanaVPNParse, MontanaXrayConfig,
// MontanaVPNSubscription's body readers, MontanaVPNClash, MontanaVPNFile, MontanaVPNIntake) ───────────────

/** Every protocol the engine speaks, and one kind for what it does not (iOS MontanaVPNConfig.Proto). */
enum class VpnProto(val raw: String) {
    VLESS("vless"), VMESS("vmess"), TROJAN("trojan"), SHADOWSOCKS("shadowsocks"), HYSTERIA2("hysteria2"), WIREGUARD("wireguard"),
    SOCKS("socks"), UNSUPPORTED("unsupported");
    /** The engine's own name for the protocol in its config. */
    val engineName: String get() = if (this == HYSTERIA2) "hysteria" else raw
    companion object {
        /** A record a later build sealed may name a protocol this build does not know: that row reads as unspoken, the rest stay. */
        fun of(s: String): VpnProto = values().firstOrNull { it.raw == s } ?: UNSUPPORTED
    }
}

/**
 * A SERVER OF THE VPN WALL (iOS MontanaVPNConfig, MontanaVPN.swift:17-98): the link's every field the engine honours, the post-
 * quantum words of a link among them (the VLESS encryption, REALITY's mldsa65Verify), and a row that came as a whole engine
 * config keeps that config (engineOutbound). Kept in the iPhone's own JSON -- its Codable keys, a nil left out -- so the list
 * reads alike on both phones.
 */
class VpnConfig(var proto: VpnProto) {
    var uid: String? = null
    var name = ""; var host = ""; var port = 443; var uuidOrPassword = ""
    var network = "tcp"; var security = "none"; var flow = ""; var sni = ""; var fingerprint = ""
    var publicKey = ""; var shortId = ""; var method = ""
    var path: String? = null; var hostHeader: String? = null; var mode: String? = null; var extra: String? = null
    var serviceName: String? = null; var spiderX: String? = null; var subscription: String? = null
    var encryption: String? = null; var pqv: String? = null; var alpn: String? = null; var allowInsecure: Boolean? = null
    var pinSHA256: String? = null; var headerType: String? = null; var seed: String? = null; var authority: String? = null
    var multiMode: Boolean? = null; var obfsPassword: String? = null; var up: String? = null; var down: String? = null
    var mport: String? = null; var presharedKey: String? = null; var localIPs: String? = null; var reserved: String? = null
    var mtu: Int? = null; var user: String? = null; var scheme: String? = null; var raw: String? = null; var reason: String? = null
    var engineOutbound: String? = null

    /** The row's identity (iOS id): its own uid, else five of its fields. */
    val id: String get() = uid ?: "${proto.raw}:$host:$port:$uuidOrPassword:$name"

    fun copy(): VpnConfig = of(json())!!

    fun json(): JSONObject = JSONObject().apply {
        uid?.let { put("uid", it) }
        put("proto", proto.raw); put("name", name); put("host", host); put("port", port); put("uuidOrPassword", uuidOrPassword)
        put("network", network); put("security", security); put("flow", flow); put("sni", sni); put("fingerprint", fingerprint)
        put("publicKey", publicKey); put("shortId", shortId); put("method", method)
        fun opt(k: String, v: Any?) { if (v != null) put(k, v) }
        opt("path", path); opt("hostHeader", hostHeader); opt("mode", mode); opt("extra", extra); opt("serviceName", serviceName)
        opt("spiderX", spiderX); opt("subscription", subscription); opt("encryption", encryption); opt("pqv", pqv); opt("alpn", alpn)
        opt("allowInsecure", allowInsecure); opt("pinSHA256", pinSHA256); opt("headerType", headerType); opt("seed", seed)
        opt("authority", authority); opt("multiMode", multiMode); opt("obfsPassword", obfsPassword); opt("up", up); opt("down", down)
        opt("mport", mport); opt("presharedKey", presharedKey); opt("localIPs", localIPs); opt("reserved", reserved); opt("mtu", mtu)
        opt("user", user); opt("scheme", scheme); opt("raw", raw); opt("reason", reason); opt("engineOutbound", engineOutbound)
    }

    companion object {
        fun empty(p: VpnProto) = VpnConfig(p)
        /** One stored row; a row this build cannot read is left out alone (iOS decodeRows, the critic's P-9). */
        fun of(o: JSONObject): VpnConfig? = runCatching {
            val c = VpnConfig(VpnProto.of(o.getString("proto")))
            fun s(k: String): String? = if (o.has(k) && !o.isNull(k)) o.getString(k) else null
            fun b(k: String): Boolean? = if (o.has(k) && !o.isNull(k)) o.getBoolean(k) else null
            c.uid = s("uid"); c.name = o.getString("name"); c.host = o.getString("host"); c.port = o.getInt("port")
            c.uuidOrPassword = o.getString("uuidOrPassword"); c.network = o.getString("network"); c.security = o.getString("security")
            c.flow = o.getString("flow"); c.sni = o.getString("sni"); c.fingerprint = o.getString("fingerprint")
            c.publicKey = o.getString("publicKey"); c.shortId = o.getString("shortId"); c.method = o.getString("method")
            c.path = s("path"); c.hostHeader = s("hostHeader"); c.mode = s("mode"); c.extra = s("extra"); c.serviceName = s("serviceName")
            c.spiderX = s("spiderX"); c.subscription = s("subscription"); c.encryption = s("encryption"); c.pqv = s("pqv"); c.alpn = s("alpn")
            c.allowInsecure = b("allowInsecure"); c.pinSHA256 = s("pinSHA256"); c.headerType = s("headerType"); c.seed = s("seed")
            c.authority = s("authority"); c.multiMode = b("multiMode"); c.obfsPassword = s("obfsPassword"); c.up = s("up"); c.down = s("down")
            c.mport = s("mport"); c.presharedKey = s("presharedKey"); c.localIPs = s("localIPs"); c.reserved = s("reserved")
            c.mtu = if (o.has("mtu") && !o.isNull("mtu")) o.getInt("mtu") else null
            c.user = s("user"); c.scheme = s("scheme"); c.raw = s("raw"); c.reason = s("reason"); c.engineOutbound = s("engineOutbound")
            c
        }.getOrNull()
    }
}

/** The small words every reader here shares: the link's percent-encoding as the iPhone reads it, base64, UTF-8. */
object VpnText {
    /** Swift's removingPercentEncoding: %XX as UTF-8, «+» left as it is; a broken sequence answers none. */
    fun unpct(s: String): String? {
        if (!s.contains('%')) return s
        val out = java.io.ByteArrayOutputStream()
        var i = 0
        while (i < s.length) {
            val ch = s[i]
            if (ch == '%') {
                if (i + 2 >= s.length) return null
                val hi = Character.digit(s[i + 1], 16); val lo = Character.digit(s[i + 2], 16)
                if (hi < 0 || lo < 0) return null
                out.write(hi * 16 + lo); i += 3
            } else { out.write(ch.toString().toByteArray(Charsets.UTF_8)); i++ }
        }
        return utf8(out.toByteArray())
    }
    /** Swift's addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed minus «&=#?»). */
    fun pct(s: String): String {
        val keep = "-._~!$'()*+,;:@/" // the query-allowed set without & = # ?
        val sb = StringBuilder()
        for (b in s.toByteArray(Charsets.UTF_8)) {
            val c = b.toInt() and 0xff
            if ((c in 'a'.code..'z'.code) || (c in 'A'.code..'Z'.code) || (c in '0'.code..'9'.code) || keep.indexOf(c.toChar()) >= 0) sb.append(c.toChar())
            else sb.append('%').append(String.format("%02X", c))
        }
        return sb.toString()
    }
    /** URL-safe letters to the standard ones and the padding the length wants (iOS pad). */
    fun pad(s: String): String { var t = s.replace('-', '+').replace('_', '/'); while (t.length % 4 != 0) t += "="; return t }
    fun unb64(s: String): ByteArray? = runCatching { Base64.decode(pad(s), Base64.DEFAULT) }.getOrNull()?.takeIf { it.isNotEmpty() || s.isEmpty() }
    /** The bytes as UTF-8, or none when they are not (Swift's String(data:encoding:.utf8)). */
    fun utf8(b: ByteArray): String? = runCatching {
        Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(b)).toString()
    }.getOrNull()
    fun b64utf8(s: String): String? = unb64(s)?.let { utf8(it) }
    fun port(v: Any?): Int = when (v) { is Int -> v.takeIf { it in 0..65535 } ?: 0; is Long -> v.toInt().takeIf { it in 0..65535 } ?: 0
        is String -> v.toIntOrNull()?.takeIf { it in 0..65535 } ?: 0; else -> 0 }
    fun portOf(s: String): Int? = s.toIntOrNull()?.takeIf { it in 0..65535 && s.all { c -> c.isDigit() } }
}

/** THE LINKS (iOS MontanaVPNParse, MontanaVPN.swift:100-353 and 934-1022): one share link to its server, and back. */
object VpnParse {
    /** The schemes the wild writes that the engine does not speak: each kept as a row that says so. */
    val unspoken = setOf("tuic", "tuic5", "anytls", "ssh", "naive+https", "naive+quic", "snell", "ssr", "hysteria", "hy",
        "mieru", "juicity", "shadowtls")

    fun parse(raw: String): VpnConfig? {
        val s = raw.trim()
        val sep = s.indexOf("://").takeIf { it >= 0 } ?: return null
        val scheme = s.substring(0, sep).lowercase()
        val rest = s.substring(sep + 3)
        return when (scheme) {
            "vless" -> parseVless(rest)
            "trojan" -> parseTrojan(rest)
            "vmess" -> parseVmess(rest)
            "ss" -> parseSS(rest)
            "hysteria2", "hy2" -> parseHysteria2(rest)
            "wireguard", "wg" -> parseWireGuard(rest)
            "socks", "socks5" -> parseSocks(rest)
            else -> if (scheme in unspoken) unsupported(s, scheme, "protocol") else null
        }
    }

    /** The row for a link the engine cannot speak: kept whole, its host and name read for the list. */
    fun unsupported(link: String, scheme: String, reason: String): VpnConfig {
        val c = VpnConfig.empty(VpnProto.UNSUPPORTED)
        c.scheme = scheme; c.raw = link; c.reason = reason; c.uuidOrPassword = link
        val body = link.indexOf("://").let { if (it >= 0) link.substring(it + 3) else link }
        val sp = splitURL(body, userRequired = false)
        if (sp != null) { c.host = sp.host; c.port = sp.port; c.name = sp.frag }
        else body.indexOf('#').takeIf { it >= 0 }?.let { c.name = VpnText.unpct(body.substring(it + 1)) ?: "" }
        if (c.name.isEmpty()) c.name = if (c.host.isEmpty()) scheme else c.host
        return c
    }

    /** What a body's lines became: the servers and the lines that were no server link (iOS Report). */
    class Report(val servers: MutableList<VpnConfig> = ArrayList(), var dropped: Int = 0) {
        val unsupported: Map<String, Int> get() = servers.filter { it.proto == VpnProto.UNSUPPORTED }.groupingBy { it.scheme ?: "?" }.eachCount()
        val unsupportedWord: String get() = unsupported.toSortedMap().entries.joinToString(",") { "${it.key}:${it.value}" }
    }
    fun parseMany(raw: String): List<VpnConfig> = report(raw).servers
    fun report(raw: String): Report {
        var text = raw.trim()
        if (!text.contains("://")) VpnText.b64utf8(text)?.let { text = it }
        val r = Report()
        for (line in text.split('\n', '\r', '\u0085', ' ', ' ')) {
            val l = line.trim()
            if (!l.contains("://") || l.startsWith("#") || l.startsWith("//")) continue
            val c = parse(l)
            if (c != null) r.servers.add(c) else r.dropped++
        }
        return r
    }

    private fun flag(v: String?): Boolean? { val t = v?.lowercase() ?: return null; if (t.isEmpty()) return null; return t == "1" || t == "true" || t == "yes" }

    private fun parseVless(s: String): VpnConfig? {
        val u = splitURL(s) ?: return null
        val c = VpnConfig.empty(VpnProto.VLESS)
        c.uuidOrPassword = u.user; c.host = u.host; c.port = u.port; c.name = u.frag.ifEmpty { u.host }
        c.flow = u.query["flow"] ?: ""
        u.query["encryption"]?.let { if (it.isNotEmpty() && it != "none") c.encryption = it }
        stream(c, u.query)
        return if (c.host.isEmpty() || c.uuidOrPassword.isEmpty()) null else c
    }

    /** The stream layer's query keys every scheme shares (the Xray share-link form). */
    private fun stream(c: VpnConfig, q: Map<String, String>) {
        q["type"]?.takeIf { it.isNotEmpty() }?.let { c.network = it }
        q["security"]?.takeIf { it.isNotEmpty() }?.let { c.security = it }
        c.sni = q["sni"] ?: q["host"] ?: c.sni
        c.fingerprint = q["fp"] ?: c.fingerprint
        c.publicKey = q["pbk"] ?: c.publicKey
        c.shortId = q["sid"] ?: c.shortId
        c.path = q["path"]; c.hostHeader = q["host"]; c.extra = q["extra"]
        c.serviceName = q["serviceName"]; c.spiderX = q["spx"]
        c.pqv = q["pqv"]; c.alpn = q["alpn"]; c.seed = q["seed"]; c.authority = q["authority"]
        c.allowInsecure = flag(q["allowInsecure"] ?: q["insecure"])
        q["headerType"]?.let { if (it.isNotEmpty() && it != "none") c.headerType = it }
        if (c.network == "grpc") c.multiMode = if (q["mode"] == "multi") true else null else c.mode = q["mode"]
    }

    private fun parseTrojan(s: String): VpnConfig? {
        val u = splitURL(s) ?: return null
        val c = VpnConfig.empty(VpnProto.TROJAN)
        c.uuidOrPassword = u.user; c.host = u.host; c.port = u.port; c.name = u.frag.ifEmpty { u.host }
        c.security = "tls"; c.flow = u.query["flow"] ?: ""
        stream(c, u.query)
        return if (c.host.isEmpty()) null else c
    }

    private fun parseVmess(b64: String): VpnConfig? {
        val j = VpnText.b64utf8(b64)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
        fun str(k: String): String? = when (val v = j.opt(k)) { is String -> v.ifEmpty { null }; is Int -> v.toString(); is Long -> v.toString(); else -> null }
        val c = VpnConfig.empty(VpnProto.VMESS)
        c.host = str("add") ?: ""
        c.port = VpnText.portOf(str("port") ?: "") ?: 443
        c.uuidOrPassword = str("id") ?: ""
        c.name = str("ps") ?: c.host
        c.network = str("net") ?: "tcp"
        val tls = (str("tls") ?: "").lowercase()
        c.security = if (tls.isEmpty() || tls == "none") "none" else tls
        c.sni = str("sni") ?: str("host") ?: ""
        c.fingerprint = str("fp") ?: ""; c.alpn = str("alpn")
        c.publicKey = str("pbk") ?: ""; c.shortId = str("sid") ?: ""; c.spiderX = str("spx")
        c.method = str("scy") ?: ""
        c.allowInsecure = flag(str("allowInsecure") ?: str("insecure"))
        c.path = str("path"); c.hostHeader = str("host")
        if (c.network == "grpc") { c.serviceName = str("path"); c.multiMode = if (str("mode") == "multi") true else null }
        if (c.network == "kcp") c.seed = str("path")
        if (c.network == "xhttp") c.mode = str("mode")
        str("type")?.let { if (it != "none" && (c.network == "tcp" || c.network == "kcp")) c.headerType = it }
        return if (c.host.isEmpty() || c.uuidOrPassword.isEmpty()) null else c
    }

    /** ss://base64(method:password)@host:port, ss://method:password@host:port (SIP002, the 2022 ciphers), or ss://base64(all). */
    private fun parseSS(rest: String): VpnConfig? {
        var body = rest; var name = ""
        body.indexOf('#').takeIf { it >= 0 }?.let { name = VpnText.unpct(body.substring(it + 1)) ?: ""; body = body.substring(0, it) }
        var q: Map<String, String> = emptyMap()
        body.indexOf('?').takeIf { it >= 0 }?.let { q = query(body.substring(it + 1)); body = body.substring(0, it) }
        var method = ""; var password = ""; var host = ""; var portS = ""
        val at = body.lastIndexOf('@')
        if (at >= 0) {
            val creds = body.substring(0, at)
            var dec = VpnText.b64utf8(creds) ?: ""
            if (!dec.contains(':')) dec = VpnText.unpct(creds) ?: creds
            dec.indexOf(':').takeIf { it >= 0 }?.let { method = dec.substring(0, it); password = dec.substring(it + 1) }
            val hp = body.substring(at + 1)
            hp.lastIndexOf(':').takeIf { it >= 0 }?.let { host = hp.substring(0, it); portS = hp.substring(it + 1) }
        } else VpnText.b64utf8(body)?.let { dec ->
            val a = dec.lastIndexOf('@'); val colon = dec.indexOf(':')
            if (a >= 0 && colon >= 0 && colon < a) {
                method = dec.substring(0, colon); password = dec.substring(colon + 1, a)
                val hp = dec.substring(a + 1)
                hp.lastIndexOf(':').takeIf { it >= 0 }?.let { host = hp.substring(0, it); portS = hp.substring(it + 1) }
            }
        }
        val c = VpnConfig.empty(VpnProto.SHADOWSOCKS)
        c.host = host; c.port = VpnText.portOf(portS) ?: 443; c.uuidOrPassword = password; c.method = method
        c.name = name.ifEmpty { host }
        stream(c, q)
        if (c.host.isEmpty()) return null
        // a SIP003 plugin is not in the engine: the row says so instead of failing at the dial
        if (!q["plugin"].isNullOrEmpty()) return unsupported("ss://$rest", "ss+plugin", "plugin")
        return c
    }

    private fun parseHysteria2(s: String): VpnConfig? {
        val u = splitURL(s, userRequired = false) ?: return null
        val c = VpnConfig.empty(VpnProto.HYSTERIA2)
        c.uuidOrPassword = VpnText.unpct(u.user) ?: u.user
        c.host = u.host; c.port = u.port; c.name = u.frag.ifEmpty { u.host }
        c.network = "hysteria"; c.security = "tls"
        c.sni = u.query["sni"] ?: u.query["peer"] ?: ""
        c.alpn = u.query["alpn"]
        c.allowInsecure = flag(u.query["insecure"] ?: u.query["allowInsecure"])
        c.pinSHA256 = u.query["pinSHA256"]
        if ((u.query["obfs"] ?: "").lowercase() == "salamander") u.query["obfs-password"]?.takeIf { it.isNotEmpty() }?.let { c.obfsPassword = it }
        c.mport = u.query["mport"]; c.up = u.query["up"] ?: u.query["upmbps"]; c.down = u.query["down"] ?: u.query["downmbps"]
        return if (c.host.isEmpty()) null else c
    }

    private fun parseWireGuard(s: String): VpnConfig? {
        val u = splitURL(s) ?: return null
        val c = VpnConfig.empty(VpnProto.WIREGUARD)
        c.uuidOrPassword = VpnText.unpct(u.user) ?: u.user
        c.host = u.host; c.port = u.port; c.name = u.frag.ifEmpty { u.host }
        c.network = "udp"; c.security = "none"
        c.publicKey = u.query["publickey"] ?: u.query["pk"] ?: u.query["peer"] ?: ""
        c.presharedKey = u.query["presharedkey"] ?: u.query["psk"]
        c.localIPs = u.query["address"] ?: u.query["ip"]
        c.reserved = u.query["reserved"]
        c.mtu = u.query["mtu"]?.toIntOrNull()
        return if (c.host.isEmpty() || c.uuidOrPassword.isEmpty() || c.publicKey.isEmpty()) null else c
    }

    private fun parseSocks(s: String): VpnConfig? {
        val u = splitURL(s, userRequired = false) ?: return null
        val c = VpnConfig.empty(VpnProto.SOCKS)
        c.host = u.host; c.port = u.port; c.name = u.frag.ifEmpty { u.host }
        c.network = "tcp"; c.security = "none"
        var dec = if (u.user.contains(':')) VpnText.unpct(u.user) ?: u.user else VpnText.b64utf8(u.user) ?: ""
        if (!dec.contains(':')) dec = ""
        dec.indexOf(':').takeIf { it >= 0 }?.let { c.user = dec.substring(0, it); c.uuidOrPassword = dec.substring(it + 1) }
        return if (c.host.isEmpty()) null else c
    }

    fun query(s: String): Map<String, String> {
        val m = HashMap<String, String>()
        for (kv in s.split('&')) {
            val i = kv.indexOf('=')
            if (i > 0) { val v = kv.substring(i + 1); m[kv.substring(0, i)] = VpnText.unpct(v) ?: v }
        }
        return m
    }

    class Url(val user: String, val host: String, val port: Int, val query: Map<String, String>, val frag: String)
    /** userinfo@host:port?query#fragment (iOS splitURL): the userinfo required unless said otherwise, a path dropped, 443 by default. */
    fun splitURL(s: String, userRequired: Boolean = true): Url? {
        var rest = s; var frag = ""
        rest.indexOf('#').takeIf { it >= 0 }?.let { frag = VpnText.unpct(rest.substring(it + 1)) ?: ""; rest = rest.substring(0, it) }
        var q: Map<String, String> = emptyMap()
        rest.indexOf('?').takeIf { it >= 0 }?.let { q = query(rest.substring(it + 1)); rest = rest.substring(0, it) }
        var user = ""
        val at = rest.lastIndexOf('@')
        if (at >= 0) { user = rest.substring(0, at); rest = rest.substring(at + 1) } else if (userRequired) return null
        rest.indexOf('/').takeIf { it >= 0 }?.let { rest = rest.substring(0, it) }
        var host = rest; var port = 443
        val colon = rest.lastIndexOf(':')
        if (!rest.endsWith("]") && colon >= 0 && !rest.substring(colon + 1).contains(':')) {
            host = rest.substring(0, colon)
            port = VpnText.portOf(rest.substring(colon + 1)) ?: return null
        }
        if (host.isEmpty()) return null
        return Url(user, host, port, q, frag)
    }

    /** The server back to its share link (iOS serialize): the same words the link came with. */
    fun serialize(c: VpnConfig): String {
        fun e(s: String) = VpnText.pct(s)
        val frag = if (c.name.isEmpty()) "" else "#" + e(c.name)
        return when (c.proto) {
            VpnProto.VLESS -> {
                val q = mutableListOf("type=${c.network}", "security=${c.security}")
                if (c.flow.isNotEmpty()) q.add("flow=${c.flow}")
                c.encryption?.takeIf { it.isNotEmpty() }?.let { q.add("encryption=${e(it)}") }
                q += wrapperQuery(c) + transportQuery(c)
                "vless://${c.uuidOrPassword}@${c.host}:${c.port}?${q.joinToString("&")}$frag"
            }
            VpnProto.TROJAN -> {
                val q = mutableListOf("type=${c.network}", "security=${c.security}")
                if (c.flow.isNotEmpty()) q.add("flow=${c.flow}")
                q += wrapperQuery(c) + transportQuery(c)
                "trojan://${c.uuidOrPassword}@${c.host}:${c.port}?${q.joinToString("&")}$frag"
            }
            VpnProto.VMESS -> {
                val path = (when (c.network) { "grpc" -> c.serviceName; "kcp" -> c.seed; else -> c.path }) ?: ""
                val j = JSONObject().put("v", "2").put("ps", c.name).put("add", c.host).put("port", c.port.toString())
                    .put("id", c.uuidOrPassword).put("net", c.network).put("type", c.headerType ?: "none")
                    .put("tls", if (c.security == "none") "" else c.security).put("sni", c.sni).put("host", c.hostHeader ?: "")
                    .put("path", path).put("aid", "0").put("scy", c.method.ifEmpty { "auto" }).put("fp", c.fingerprint)
                c.alpn?.takeIf { it.isNotEmpty() }?.let { j.put("alpn", it) }
                if (c.publicKey.isNotEmpty()) { j.put("pbk", c.publicKey); j.put("sid", c.shortId) }
                c.mode?.takeIf { it.isNotEmpty() }?.let { j.put("mode", it) }
                "vmess://" + Base64.encodeToString(j.toString().toByteArray(), Base64.NO_WRAP)
            }
            VpnProto.SHADOWSOCKS -> {
                val creds = Base64.encodeToString("${c.method}:${c.uuidOrPassword}".toByteArray(), Base64.NO_WRAP)
                val q = wrapperQuery(c) + transportQuery(c)
                val tail = if (c.network == "tcp" && q.isEmpty()) "" else "?" + (listOf("type=${c.network}", "security=${c.security}") + q).joinToString("&")
                "ss://$creds@${c.host}:${c.port}$tail$frag"
            }
            VpnProto.HYSTERIA2 -> {
                val q = ArrayList<String>()
                if (c.sni.isNotEmpty()) q.add("sni=${e(c.sni)}")
                if (c.allowInsecure == true) q.add("insecure=1")
                c.obfsPassword?.takeIf { it.isNotEmpty() }?.let { q.add("obfs=salamander"); q.add("obfs-password=${e(it)}") }
                c.pinSHA256?.takeIf { it.isNotEmpty() }?.let { q.add("pinSHA256=${e(it)}") }
                c.mport?.takeIf { it.isNotEmpty() }?.let { q.add("mport=${e(it)}") }
                c.up?.takeIf { it.isNotEmpty() }?.let { q.add("up=${e(it)}") }
                c.down?.takeIf { it.isNotEmpty() }?.let { q.add("down=${e(it)}") }
                c.alpn?.takeIf { it.isNotEmpty() }?.let { q.add("alpn=${e(it)}") }
                "hysteria2://${e(c.uuidOrPassword)}@${c.host}:${c.port}?${q.joinToString("&")}$frag"
            }
            VpnProto.WIREGUARD -> {
                val q = mutableListOf("publickey=${e(c.publicKey)}")
                c.localIPs?.takeIf { it.isNotEmpty() }?.let { q.add("address=${e(it)}") }
                c.reserved?.takeIf { it.isNotEmpty() }?.let { q.add("reserved=${e(it)}") }
                c.mtu?.let { q.add("mtu=$it") }
                c.presharedKey?.takeIf { it.isNotEmpty() }?.let { q.add("presharedkey=${e(it)}") }
                "wireguard://${e(c.uuidOrPassword)}@${c.host}:${c.port}?${q.joinToString("&")}$frag"
            }
            VpnProto.SOCKS -> {
                val user = c.user ?: ""
                val creds = if (user.isEmpty()) "" else Base64.encodeToString("$user:${c.uuidOrPassword}".toByteArray(), Base64.NO_WRAP) + "@"
                "socks://$creds${c.host}:${c.port}$frag"
            }
            VpnProto.UNSUPPORTED -> c.raw ?: ""
        }
    }
    private fun wrapperQuery(c: VpnConfig): List<String> {
        fun e(s: String) = VpnText.pct(s)
        val q = ArrayList<String>()
        if (c.sni.isNotEmpty()) q.add("sni=${e(c.sni)}")
        if (c.fingerprint.isNotEmpty()) q.add("fp=${c.fingerprint}")
        if (c.publicKey.isNotEmpty()) q.add("pbk=${e(c.publicKey)}")
        if (c.shortId.isNotEmpty()) q.add("sid=${c.shortId}")
        c.pqv?.takeIf { it.isNotEmpty() }?.let { q.add("pqv=${e(it)}") }
        c.alpn?.takeIf { it.isNotEmpty() }?.let { q.add("alpn=${e(it)}") }
        if (c.allowInsecure == true) q.add("allowInsecure=1")
        c.pinSHA256?.takeIf { it.isNotEmpty() }?.let { q.add("pinSHA256=${e(it)}") }
        return q
    }
    private fun transportQuery(c: VpnConfig): List<String> {
        fun e(s: String) = VpnText.pct(s)
        val q = ArrayList<String>()
        c.path?.takeIf { it.isNotEmpty() }?.let { q.add("path=${e(it)}") }
        c.hostHeader?.takeIf { it.isNotEmpty() }?.let { q.add("host=${e(it)}") }
        c.mode?.takeIf { it.isNotEmpty() }?.let { q.add("mode=$it") }
        if (c.multiMode == true) q.add("mode=multi")
        c.extra?.takeIf { it.isNotEmpty() }?.let { q.add("extra=${e(it)}") }
        c.serviceName?.takeIf { it.isNotEmpty() }?.let { q.add("serviceName=${e(it)}") }
        c.authority?.takeIf { it.isNotEmpty() }?.let { q.add("authority=${e(it)}") }
        c.spiderX?.takeIf { it.isNotEmpty() }?.let { q.add("spx=${e(it)}") }
        c.headerType?.takeIf { it.isNotEmpty() }?.let { q.add("headerType=$it") }
        c.seed?.takeIf { it.isNotEmpty() }?.let { q.add("seed=${e(it)}") }
        return q
    }
}

/** THE ENGINE'S CONFIG (iOS MontanaXrayConfig, MontanaVPN.swift:357-498, and the extension's fullConfigString). */
object XrayConfig {
    /** A comma-separated word of a link as the list the engine takes. */
    fun list(s: String?): List<String> = (s ?: "").split(',').map { it.trim() }.filter { it.isNotEmpty() }

    fun outbound(c: VpnConfig): JSONObject {
        servedOutbound(c)?.let { return it }
        val endpoint = if (c.host.startsWith("[") && c.host.endsWith("]")) c.host.substring(1, c.host.length - 1) else c.host
        when (c.proto) {
            VpnProto.UNSUPPORTED -> return JSONObject().put("protocol", "blackhole").put("tag", "proxy")
            VpnProto.WIREGUARD -> {
                val peer = JSONObject().put("publicKey", c.publicKey).put("endpoint", "${c.host}:${c.port}")
                c.presharedKey?.takeIf { it.isNotEmpty() }?.let { peer.put("preSharedKey", it) }
                val ips = list(c.localIPs)
                val settings = JSONObject().put("secretKey", c.uuidOrPassword).put("peers", JSONArray().put(peer))
                    .put("address", JSONArray(if (ips.isEmpty()) listOf("10.0.0.2/32") else ips))
                c.mtu?.takeIf { it > 0 }?.let { settings.put("mtu", it) }
                val reserved = list(c.reserved).mapNotNull { it.toIntOrNull() }
                if (reserved.isNotEmpty()) settings.put("reserved", JSONArray(reserved))
                return JSONObject().put("protocol", "wireguard").put("settings", settings).put("tag", "proxy")
            }
            else -> {}
        }
        val stream = JSONObject().put("network", c.network).put("security", c.security)
        if (c.security == "reality") {
            val rs = JSONObject().put("serverName", c.sni).put("fingerprint", c.fingerprint).put("publicKey", c.publicKey)
                .put("shortId", c.shortId).put("show", false)
            c.spiderX?.takeIf { it.isNotEmpty() }?.let { rs.put("spiderX", it) }
            c.pqv?.takeIf { it.isNotEmpty() }?.let { rs.put("mldsa65Verify", it) }
            stream.put("realitySettings", rs)
        } else if (c.security == "tls") {
            val ts = JSONObject().put("serverName", c.sni).put("fingerprint", c.fingerprint)
            val alpn = list(c.alpn)
            if (alpn.isNotEmpty()) ts.put("alpn", JSONArray(alpn))
            // the link's allowInsecure is never written: the engine removed it; its road is the pinned hash
            c.pinSHA256?.takeIf { it.isNotEmpty() }?.let { ts.put("pinnedPeerCertSha256", it) }
            stream.put("tlsSettings", ts)
        }
        when (c.network) {
            "tcp", "raw" -> if (c.headerType == "http") {
                val request = JSONObject().put("path", JSONArray().put(c.path ?: "/"))
                val hostWord = c.hostHeader ?: c.sni
                if (hostWord.isNotEmpty()) request.put("headers", JSONObject().put("Host", JSONArray(list(hostWord))))
                stream.put("tcpSettings", JSONObject().put("header", JSONObject().put("type", "http").put("request", request)))
            }
            "kcp", "mkcp" -> {
                val k = JSONObject()
                c.seed?.takeIf { it.isNotEmpty() }?.let { k.put("seed", it) }
                c.headerType?.takeIf { it.isNotEmpty() }?.let { k.put("header", JSONObject().put("type", it)) }
                stream.put("kcpSettings", k)
            }
            "ws" -> { val w = JSONObject().put("path", c.path ?: "/"); c.hostHeader?.takeIf { it.isNotEmpty() }?.let { w.put("host", it) }; stream.put("wsSettings", w) }
            "httpupgrade" -> { val h = JSONObject().put("path", c.path ?: "/"); c.hostHeader?.takeIf { it.isNotEmpty() }?.let { h.put("host", it) }; stream.put("httpupgradeSettings", h) }
            "xhttp", "splithttp" -> {
                val x = JSONObject().put("path", c.path ?: "/").put("mode", c.mode ?: "auto")
                c.hostHeader?.takeIf { it.isNotEmpty() }?.let { x.put("host", it) }
                c.extra?.let { e -> runCatching { JSONObject(e) }.getOrNull()?.let { x.put("extra", it) } }
                stream.put("xhttpSettings", x)
            }
            "grpc" -> {
                val g = JSONObject().put("serviceName", c.serviceName ?: "")
                c.authority?.takeIf { it.isNotEmpty() }?.let { g.put("authority", it) }
                if (c.multiMode == true) g.put("multiMode", true)
                stream.put("grpcSettings", g)
            }
            "hysteria" -> {
                stream.put("hysteriaSettings", JSONObject().put("version", 2).put("auth", c.uuidOrPassword))
                val mask = JSONObject()
                c.obfsPassword?.takeIf { it.isNotEmpty() }?.let { mask.put("udp", JSONArray().put(JSONObject().put("type", "salamander").put("settings", JSONObject().put("password", it)))) }
                val quic = JSONObject()
                c.up?.toIntOrNull()?.takeIf { it > 0 }?.let { quic.put("brutalUp", "$it mbps") }
                c.down?.toIntOrNull()?.takeIf { it > 0 }?.let { quic.put("brutalDown", "$it mbps") }
                c.mport?.takeIf { it.isNotEmpty() }?.let { quic.put("udpHop", JSONObject().put("ports", it)) }
                if (quic.length() > 0) mask.put("quicParams", quic)
                if (mask.length() > 0) stream.put("finalmask", mask)
            }
        }
        val settings: JSONObject = when (c.proto) {
            VpnProto.VLESS -> {
                val enc = c.encryption ?: ""
                val user = JSONObject().put("id", c.uuidOrPassword).put("encryption", enc.ifEmpty { "none" })
                if (c.flow.isNotEmpty()) user.put("flow", c.flow)
                JSONObject().put("vnext", JSONArray().put(JSONObject().put("address", endpoint).put("port", c.port).put("users", JSONArray().put(user))))
            }
            VpnProto.VMESS -> JSONObject().put("vnext", JSONArray().put(JSONObject().put("address", endpoint).put("port", c.port)
                .put("users", JSONArray().put(JSONObject().put("id", c.uuidOrPassword).put("security", c.method.ifEmpty { "auto" })))))
            VpnProto.TROJAN -> JSONObject().put("servers", JSONArray().put(JSONObject().put("address", endpoint).put("port", c.port).put("password", c.uuidOrPassword)))
            VpnProto.SHADOWSOCKS -> JSONObject().put("servers", JSONArray().put(JSONObject().put("address", endpoint).put("port", c.port)
                .put("password", c.uuidOrPassword).put("method", c.method)))
            VpnProto.HYSTERIA2 -> JSONObject().put("version", 2).put("address", endpoint).put("port", c.port)
            VpnProto.SOCKS -> {
                val server = JSONObject().put("address", endpoint).put("port", c.port)
                c.user?.takeIf { it.isNotEmpty() }?.let { server.put("users", JSONArray().put(JSONObject().put("user", it).put("pass", c.uuidOrPassword))) }
                JSONObject().put("servers", JSONArray().put(server))
            }
            VpnProto.WIREGUARD, VpnProto.UNSUPPORTED -> JSONObject()
        }
        return JSONObject().put("protocol", c.proto.engineName).put("settings", settings).put("streamSettings", stream).put("tag", "proxy")
    }

    /** The outbound a JSON plan served, as it is: our tag, and the one TLS key the engine refuses taken away (iOS servedOutbound). */
    fun servedOutbound(c: VpnConfig): JSONObject? {
        if (c.proto == VpnProto.UNSUPPORTED) return null
        val ob = c.engineOutbound?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
        if (ob.optString("protocol") != c.proto.engineName) return null
        ob.put("tag", "proxy")
        ob.optJSONObject("streamSettings")?.optJSONObject("tlsSettings")?.remove("allowInsecure")
        return ob
    }

    /** The row's whole engine config, keys sorted, as the plan panels serve it (iOS shareJSON, «Copy JSON»). */
    fun shareJSON(c: VpnConfig): String? {
        if (c.proto == VpnProto.UNSUPPORTED) return null
        val full = JSONObject().put("remarks", c.name).put("outbounds", JSONArray().put(outbound(c)).put(JSONObject().put("protocol", "freedom").put("tag", "direct")))
        return pretty(full, 0)
    }
    /** Sorted keys, two spaces a level, «key : value» as the iPhone's JSONSerialization pretty-prints. */
    private fun pretty(v: Any?, depth: Int): String {
        val pad = "  ".repeat(depth + 1); val end = "  ".repeat(depth)
        return when (v) {
            is JSONObject -> if (v.length() == 0) "{\n\n$end}" else v.keys().asSequence().sorted().joinToString(",\n", "{\n", "\n$end}") { k ->
                pad + JSONObject.quote(k) + " : " + pretty(v.opt(k), depth + 1) }
            is JSONArray -> if (v.length() == 0) "[\n\n$end]" else (0 until v.length()).joinToString(",\n", "[\n", "\n$end]") { pad + pretty(v.opt(it), depth + 1) }
            is String -> JSONObject.quote(v)
            null, JSONObject.NULL -> "null"
            else -> v.toString()
        }
    }

    /** One server as a config the engine can run for a measurement: the outbound and nothing else (iOS probeConfig). */
    fun probeConfig(c: VpnConfig): String = JSONObject().put("log", JSONObject().put("loglevel", "warning"))
        .put("outbounds", JSONArray().put(outbound(c)).put(JSONObject().put("protocol", "freedom").put("tag", "direct"))).toString()

    /**
     * THE TUNNEL'S WHOLE CONFIG (iOS PacketTunnelProvider.fullConfigString): the local SOCKS inbound the pump feeds, the chosen
     * outbound and the direct one, private and loopback destinations out directly, everything else through the server; a
     * connection policy of small buffers and short idle limits that keeps a burst of flows survivable.
     */
    fun tunnel(outbound: JSONObject, socksPort: Int): String {
        val level = JSONObject().put("handshake", 4).put("connIdle", 30).put("uplinkOnly", 1).put("downlinkOnly", 1).put("bufferSize", 4)
        val private = JSONArray(listOf("127.0.0.0/8", "::1/128", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16",
            "224.0.0.0/4", "fe80::/10", "fc00::/7", "ff00::/8"))
        return JSONObject()
            .put("log", JSONObject().put("loglevel", "warning"))
            .put("policy", JSONObject().put("levels", JSONObject().put("0", level)))
            .put("inbounds", JSONArray().put(JSONObject().put("tag", "socks-in").put("listen", "127.0.0.1").put("port", socksPort)
                .put("protocol", "socks").put("settings", JSONObject().put("udp", true).put("auth", "noauth"))))
            .put("outbounds", JSONArray().put(outbound).put(JSONObject().put("protocol", "freedom").put("tag", "direct")))
            .put("routing", JSONObject().put("rules", JSONArray()
                .put(JSONObject().put("type", "field").put("outboundTag", "direct").put("ip", private))
                .put(JSONObject().put("type", "field").put("outboundTag", "proxy").put("network", "tcp,udp"))))
            .toString()
    }
}

/**
 * A PLAN'S BODY, IN ANY OF ITS FORMS (iOS MontanaVPNSubscription.body and its readers, MontanaVPN.swift:1159-1392): share links,
 * a base64 blob of them, the JSON array of whole engine configs, the sing-box JSON, the Clash YAML, and the profile files -- each
 * read by its shape, never by its extension.
 */
object VpnBody {
    class Body(val servers: MutableList<VpnConfig> = ArrayList(), var dropped: Int = 0, var form: String = "")

    fun body(data: ByteArray, name: String = ""): Body {
        val text = VpnText.utf8(data) ?: return Body(form = "binary")
        val s = text.trim()
        val b = Body()
        if (s.startsWith("[") || s.startsWith("{")) {
            val j = runCatching { if (s.startsWith("[")) JSONArray(s) else JSONObject(s) }.getOrNull()
            if (j != null) {
                if (j is JSONObject) {
                    val outs = j.optJSONArray("outbounds")
                    if (outs != null && (0 until outs.length()).any { outs.optJSONObject(it)?.let { o -> o.has("type") && !o.has("protocol") } == true }) {
                        b.form = "sing-box"
                        (0 until outs.length()).mapNotNull { outs.optJSONObject(it)?.let { o -> fromSingBox(o) } }.forEach { b.servers.add(it) }
                        return b
                    }
                }
                val configs = if (j is JSONArray) (0 until j.length()).mapNotNull { j.optJSONObject(it) } else listOf(j as JSONObject)
                b.form = "engine-json"
                configs.mapNotNull { fromEngineConfig(it, name) }.forEach { b.servers.add(it) }
                b.dropped = configs.size - b.servers.size
                return b
            }
        }
        if (VpnFile.looksLikeProfile(s)) { b.form = "profile"; return b }   // the iPhone's own VPN profile: an Apple property list, no server for this engine
        if (s.startsWith("<")) { b.form = "html"; return b }
        if (VpnClash.looksLike(s)) { b.form = "clash"; b.servers.addAll(VpnClash.servers(s)); return b }
        if (VpnFile.looksLikeWireGuard(s)) { b.form = "wireguard"; VpnFile.wireGuard(s, name)?.let { b.servers.add(it) }; return b }
        if (VpnFile.looksLikeHysteria(s)) { b.form = "hysteria"; VpnFile.hysteria(s, name)?.let { b.servers.add(it) }; return b }
        if (VpnFile.looksLikeOpenVPN(s)) { b.form = "openvpn"; b.servers.add(VpnFile.openVPN(text, name)); return b }
        val r = VpnParse.report(s)
        b.form = if (s.contains("://")) "links" else "base64"; b.servers.addAll(r.servers); b.dropped = r.dropped
        return b
    }

    private val speak = mapOf("vless" to VpnProto.VLESS, "vmess" to VpnProto.VMESS, "trojan" to VpnProto.TROJAN, "shadowsocks" to VpnProto.SHADOWSOCKS,
        "hysteria" to VpnProto.HYSTERIA2, "wireguard" to VpnProto.WIREGUARD, "socks" to VpnProto.SOCKS)

    private fun JSONObject.s(k: String): String? = (opt(k) as? String)
    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).mapNotNull { optJSONObject(it) }
    private fun JSONArray.strings(): List<String> = (0 until length()).mapNotNull { opt(it) as? String }

    /** One whole engine config to the server it dials (iOS fromEngineConfig): the outbound tagged «proxy», else the first we speak. */
    fun fromEngineConfig(c: JSONObject, fallback: String = ""): VpnConfig? {
        val outs = c.optJSONArray("outbounds")?.objects() ?: emptyList()
        val ob = outs.firstOrNull { it.s("tag") == "proxy" && speak[it.s("protocol") ?: ""] != null }
            ?: outs.firstOrNull { speak[it.s("protocol") ?: ""] != null } ?: return null
        val proto = speak[ob.s("protocol") ?: ""] ?: return null
        val settings = ob.optJSONObject("settings") ?: return null
        val cfg = VpnConfig.empty(proto)
        cfg.name = c.s("remarks") ?: ""
        if (cfg.name.isEmpty()) cfg.name = fallback
        cfg.engineOutbound = sorted(ob).toString()
        when (proto) {
            VpnProto.VLESS, VpnProto.VMESS -> {
                val v = settings.optJSONArray("vnext")?.optJSONObject(0) ?: return null
                val u = v.optJSONArray("users")?.optJSONObject(0) ?: return null
                cfg.host = v.s("address") ?: ""; cfg.port = VpnText.port(v.opt("port"))
                cfg.uuidOrPassword = u.s("id") ?: ""; cfg.flow = u.s("flow") ?: ""
                if (proto == VpnProto.VLESS) u.s("encryption")?.let { if (it.isNotEmpty() && it != "none") cfg.encryption = it }
                if (proto == VpnProto.VMESS) u.s("security")?.let { if (it != "auto") cfg.method = it }
            }
            VpnProto.TROJAN, VpnProto.SHADOWSOCKS -> {
                val v = settings.optJSONArray("servers")?.optJSONObject(0) ?: return null
                cfg.host = v.s("address") ?: ""; cfg.port = VpnText.port(v.opt("port"))
                cfg.uuidOrPassword = v.s("password") ?: ""; cfg.method = v.s("method") ?: ""
            }
            VpnProto.SOCKS -> {
                val v = settings.optJSONArray("servers")?.optJSONObject(0) ?: return null
                cfg.host = v.s("address") ?: ""; cfg.port = VpnText.port(v.opt("port"))
                v.optJSONArray("users")?.optJSONObject(0)?.let { cfg.user = it.s("user"); cfg.uuidOrPassword = it.s("pass") ?: "" }
            }
            VpnProto.HYSTERIA2 -> { cfg.host = settings.s("address") ?: ""; cfg.port = VpnText.port(settings.opt("port")) }
            VpnProto.WIREGUARD -> {
                cfg.uuidOrPassword = settings.s("secretKey") ?: ""
                cfg.localIPs = settings.optJSONArray("address")?.strings()?.joinToString(",")
                (settings.opt("mtu") as? Int)?.takeIf { it > 0 }?.let { cfg.mtu = it }
                settings.optJSONArray("reserved")?.let { r -> cfg.reserved = (0 until r.length()).mapNotNull { r.opt(it) as? Int }.joinToString(",") }
                settings.optJSONArray("peers")?.optJSONObject(0)?.let { peer ->
                    cfg.publicKey = peer.s("publicKey") ?: ""; cfg.presharedKey = peer.s("preSharedKey")
                    val ep = peer.s("endpoint") ?: ""
                    ep.lastIndexOf(':').takeIf { it >= 0 }?.let { cfg.host = ep.substring(0, it); cfg.port = VpnText.portOf(ep.substring(it + 1)) ?: 0 }
                }
                cfg.network = "udp"
                if (cfg.name.isEmpty()) cfg.name = cfg.host
                return if (cfg.host.isEmpty() || cfg.port == 0 || cfg.uuidOrPassword.isEmpty() || cfg.publicKey.isEmpty()) null else cfg
            }
            VpnProto.UNSUPPORTED -> return null
        }
        val ss = ob.optJSONObject("streamSettings") ?: JSONObject()
        cfg.network = ss.s("network") ?: if (proto == VpnProto.HYSTERIA2) "hysteria" else "tcp"
        cfg.security = ss.s("security") ?: if (proto == VpnProto.HYSTERIA2) "tls" else "none"
        if (cfg.network == "splithttp") cfg.network = "xhttp"
        if (cfg.network == "raw") cfg.network = "tcp"
        if (cfg.network == "mkcp") cfg.network = "kcp"
        val rs = ss.optJSONObject("realitySettings"); val ts = ss.optJSONObject("tlsSettings")
        if (rs != null) {
            cfg.sni = rs.s("serverName") ?: ""; cfg.fingerprint = rs.s("fingerprint") ?: ""; cfg.publicKey = rs.s("publicKey") ?: ""
            cfg.shortId = rs.s("shortId") ?: ""; cfg.spiderX = rs.s("spiderX"); cfg.pqv = rs.s("mldsa65Verify")
        } else if (ts != null) {
            cfg.sni = ts.s("serverName") ?: ""; cfg.fingerprint = ts.s("fingerprint") ?: ""
            cfg.alpn = ts.optJSONArray("alpn")?.strings()?.joinToString(",")
            if (ts.opt("allowInsecure") == true) cfg.allowInsecure = true
            cfg.pinSHA256 = ts.s("pinnedPeerCertSha256")
        }
        val x = ss.optJSONObject("xhttpSettings") ?: ss.optJSONObject("splithttpSettings")
        val w = ss.optJSONObject("wsSettings"); val h = ss.optJSONObject("httpupgradeSettings"); val g = ss.optJSONObject("grpcSettings")
        val k = ss.optJSONObject("kcpSettings"); val t = ss.optJSONObject("tcpSettings") ?: ss.optJSONObject("rawSettings")
        when {
            x != null -> { cfg.path = x.s("path"); cfg.hostHeader = x.s("host"); cfg.mode = x.s("mode"); x.opt("extra")?.let { if (it is JSONObject || it is JSONArray) cfg.extra = it.toString() } }
            w != null -> { cfg.path = w.s("path"); cfg.hostHeader = w.s("host") ?: w.optJSONObject("headers")?.s("Host") }
            h != null -> { cfg.path = h.s("path"); cfg.hostHeader = h.s("host") }
            g != null -> { cfg.serviceName = g.s("serviceName"); cfg.authority = g.s("authority"); if (g.opt("multiMode") == true) cfg.multiMode = true }
            k != null -> { cfg.seed = k.s("seed"); cfg.headerType = k.optJSONObject("header")?.s("type") }
            t != null -> t.optJSONObject("header")?.takeIf { it.s("type") == "http" }?.let { hd ->
                cfg.headerType = "http"
                val req = hd.optJSONObject("request")
                cfg.path = req?.optJSONArray("path")?.strings()?.firstOrNull()
                cfg.hostHeader = req?.optJSONObject("headers")?.optJSONArray("Host")?.strings()?.firstOrNull()
            }
        }
        ss.optJSONObject("hysteriaSettings")?.let { cfg.uuidOrPassword = it.s("auth") ?: "" }
        ss.optJSONObject("finalmask")?.let { fm ->
            fm.optJSONArray("udp")?.objects()?.filter { it.s("type") == "salamander" }?.forEach { cfg.obfsPassword = it.optJSONObject("settings")?.s("password") }
            fm.optJSONObject("quicParams")?.let { qp ->
                cfg.up = mbps(qp.opt("brutalUp")); cfg.down = mbps(qp.opt("brutalDown"))
                qp.optJSONObject("udpHop")?.let { hop -> cfg.mport = hop.s("ports") ?: (hop.opt("ports") as? Int)?.toString() }
            }
        }
        if (cfg.name.isEmpty()) cfg.name = cfg.host
        return if (cfg.host.isEmpty() || cfg.port == 0 || (proto != VpnProto.SOCKS && cfg.uuidOrPassword.isEmpty())) null else cfg
    }

    /** A JSON object with its keys sorted, every level (iOS JSONSerialization .sortedKeys). */
    private fun sorted(v: Any?): Any? = when (v) {
        is JSONObject -> { val o = JSONObject(java.util.TreeMap<String, Any?>()); v.keys().asSequence().sorted().forEach { o.put(it, sorted(v.opt(it))) }; o }
        is JSONArray -> JSONArray().also { a -> (0 until v.length()).forEach { a.put(sorted(v.opt(it))) } }
        else -> v
    }

    /** The engine's Bandwidth word («100 mbps», «1 gbps», a bare number of bps) to the link's mbps number. */
    fun mbps(v: Any?): String? {
        if (v is Int) return if (v < 1_000_000) null else (v / 1_000_000).toString()
        if (v is Long) return if (v < 1_000_000) null else (v / 1_000_000).toString()
        val s = (v as? String)?.lowercase()?.trim()?.ifEmpty { null } ?: return null
        val digits = s.takeWhile { it.isDigit() || it == '.' }
        val n = digits.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        return when (s.substring(digits.length).trim()) {
            "g", "gb", "gbps" -> (n * 1000).toInt().toString()
            "k", "kb", "kbps" -> if (n < 1000) null else (n / 1000).toInt().toString()
            "", "b", "bps" -> if (n < 1_000_000) null else (n / 1_000_000).toInt().toString()
            else -> n.toInt().toString()
        }
    }

    /** One outbound of a sing-box config to ours (iOS fromSingBox); a type the engine lacks keeps a row that says so. */
    fun fromSingBox(o: JSONObject): VpnConfig? {
        val type = (o.s("type") ?: "").lowercase()
        val name = o.s("tag") ?: ""
        val known = mapOf("vless" to VpnProto.VLESS, "vmess" to VpnProto.VMESS, "trojan" to VpnProto.TROJAN, "shadowsocks" to VpnProto.SHADOWSOCKS,
            "hysteria2" to VpnProto.HYSTERIA2, "wireguard" to VpnProto.WIREGUARD, "socks" to VpnProto.SOCKS)
        val proto = known[type]
        if (proto == null) {
            if (type in setOf("selector", "urltest", "direct", "block", "dns", "")) return null
            val u = VpnConfig.empty(VpnProto.UNSUPPORTED)
            u.scheme = type; u.reason = "protocol"; u.name = name.ifEmpty { type }
            u.host = o.s("server") ?: ""; u.port = VpnText.port(o.opt("server_port"))
            u.uuidOrPassword = "$type:${u.host}:${u.port}:$name"; u.raw = o.toString()
            return u
        }
        val c = VpnConfig.empty(proto)
        c.name = name; c.host = o.s("server") ?: ""; c.port = VpnText.port(o.opt("server_port"))
        fun unsupportedAs(scheme: String, reason: String): VpnConfig { val u = c.copy(); u.proto = VpnProto.UNSUPPORTED; u.scheme = scheme; u.reason = reason; return u }
        when (proto) {
            VpnProto.VLESS -> { c.uuidOrPassword = o.s("uuid") ?: ""; c.flow = o.s("flow") ?: "" }
            VpnProto.VMESS -> { c.uuidOrPassword = o.s("uuid") ?: ""; o.s("security")?.let { if (it != "auto") c.method = it } }
            VpnProto.TROJAN -> c.uuidOrPassword = o.s("password") ?: ""
            VpnProto.SHADOWSOCKS -> {
                c.uuidOrPassword = o.s("password") ?: ""; c.method = o.s("method") ?: ""
                if (!o.s("plugin").isNullOrEmpty()) return unsupportedAs("ss+plugin", "plugin")
            }
            VpnProto.HYSTERIA2 -> {
                c.uuidOrPassword = o.s("password") ?: ""; c.network = "hysteria"; c.security = "tls"
                o.optJSONObject("obfs")?.takeIf { it.s("type") == "salamander" }?.let { c.obfsPassword = it.s("password") }
                (o.opt("up_mbps") as? Int)?.takeIf { it > 0 }?.let { c.up = it.toString() }
                (o.opt("down_mbps") as? Int)?.takeIf { it > 0 }?.let { c.down = it.toString() }
                o.optJSONArray("server_ports")?.strings()?.takeIf { it.isNotEmpty() }?.let { c.mport = it.joinToString(",").replace(':', '-') }
            }
            VpnProto.WIREGUARD -> {
                c.uuidOrPassword = o.s("private_key") ?: ""; c.publicKey = o.s("peer_public_key") ?: ""; c.presharedKey = o.s("pre_shared_key")
                c.localIPs = o.optJSONArray("local_address")?.strings()?.joinToString(",")
                o.optJSONArray("reserved")?.let { r -> c.reserved = (0 until r.length()).mapNotNull { r.opt(it) as? Int }.joinToString(",") }
                (o.opt("mtu") as? Int)?.takeIf { it > 0 }?.let { c.mtu = it }
                c.network = "udp"
            }
            VpnProto.SOCKS -> { c.user = o.s("username"); c.uuidOrPassword = o.s("password") ?: "" }
            VpnProto.UNSUPPORTED -> return null
        }
        o.optJSONObject("tls")?.takeIf { it.opt("enabled") == true && proto != VpnProto.WIREGUARD }?.let { t ->
            c.security = "tls"; c.sni = t.s("server_name") ?: ""
            if (t.opt("insecure") == true) c.allowInsecure = true
            c.alpn = t.optJSONArray("alpn")?.strings()?.joinToString(",")
            c.fingerprint = t.optJSONObject("utls")?.s("fingerprint") ?: ""
            t.optJSONObject("reality")?.takeIf { it.opt("enabled") == true }?.let { r -> c.security = "reality"; c.publicKey = r.s("public_key") ?: ""; c.shortId = r.s("short_id") ?: "" }
        }
        val tr = o.optJSONObject("transport")
        if (tr != null && proto != VpnProto.HYSTERIA2 && proto != VpnProto.WIREGUARD) when ((tr.s("type") ?: "").lowercase()) {
            "ws" -> { c.network = "ws"; c.path = tr.s("path"); c.hostHeader = tr.optJSONObject("headers")?.s("Host") }
            "grpc" -> { c.network = "grpc"; c.serviceName = tr.s("service_name") }
            "httpupgrade" -> { c.network = "httpupgrade"; c.path = tr.s("path"); c.hostHeader = tr.s("host") }
            "http" -> return unsupportedAs("$type+h2", "transport")   // sing-box's h2, which the engine removed for xhttp
        }
        if (c.name.isEmpty()) c.name = c.host
        return if (c.host.isEmpty() || c.port == 0 || (proto != VpnProto.SOCKS && c.uuidOrPassword.isEmpty())) null else c
    }
}

/** THE CLASH BODY (iOS MontanaVPNClash, MontanaVPN.swift:1394-1611): `proxies:` and one map per server, read by a small reader of its shape. */
object VpnClash {
    private class Line(val indent: Int, val text: String)

    fun looksLike(s: String) = s.lines().any { it.startsWith("proxies:") }
    fun servers(s: String): List<VpnConfig> = items(s).mapNotNull { server(it) }

    fun items(s: String): List<Map<String, Any>> {
        val lines = s.lines().map { it.replace("\t", "  ") }
        val start = lines.indexOfFirst { it.startsWith("proxies:") }.takeIf { it >= 0 } ?: return emptyList()
        val out = ArrayList<Map<String, Any>>()
        val block = ArrayList<Line>(); var base = 0
        fun flush() { if (block.isNotEmpty()) { out.add(map(block.toList())); block.clear() } }
        for (line in lines.drop(start + 1)) {
            val t = line.trim()
            if (t.isEmpty() || t.startsWith("#")) continue
            val indent = line.takeWhile { it == ' ' }.length
            if (indent == 0) break
            if (t.startsWith("- ")) { flush(); base = indent + 2; block.add(Line(0, t.substring(2).trim())) }
            else if (block.isNotEmpty()) block.add(Line(maxOf(0, indent - base), t))
        }
        flush()
        return out
    }

    /** The whole document as one map (the Hysteria 2 client config). */
    fun document(s: String): Map<String, Any> = map(s.lines().map { it.replace("\t", "  ") }.mapNotNull { l ->
        val t = l.trim(); if (t.isEmpty() || t.startsWith("#")) null else Line(l.takeWhile { it == ' ' }.length, t) })

    private fun map(lines: List<Line>): Map<String, Any> {
        val m = LinkedHashMap<String, Any>()
        var i = 0
        while (i < lines.size) {
            val l = lines[i]
            if (l.text.startsWith("{")) { m.putAll(flowMap(l.text)); i++; continue }
            val colon = keyColon(l.text); if (colon == null) { i++; continue }
            val key = l.text.substring(0, colon).trim()
            val rest = l.text.substring(colon + 1).trim()
            var j = i + 1
            while (j < lines.size && l.indent < lines[j].indent) j++
            if (rest.isEmpty() && i + 1 < j) {
                val inner = lines.subList(i + 1, j)
                m[key] = if (inner.first().text.startsWith("- ")) inner.map { scalar(it.text.substring(2)) } else map(inner)
            } else m[key] = value(rest)
            i = j
        }
        return m
    }
    /** The colon that ends a key: the first one followed by a space or the end of the line. */
    private fun keyColon(t: String): Int? { for (i in t.indices) if (t[i] == ':' && (i + 1 == t.length || t[i + 1] == ' ')) return i; return null }
    private fun value(rest: String): Any = when {
        rest.startsWith("{") -> flowMap(rest)
        rest.startsWith("[") -> splitTop(rest.substring(1, if (rest.endsWith("]")) rest.length - 1 else rest.length)).map { scalar(it) }
        else -> scalar(rest)
    }
    private fun scalar(raw: String): Any {
        var t = raw.trim()
        if (t.length >= 2 && t.first() == t.last() && (t.first() == '"' || t.first() == '\'')) t = t.substring(1, t.length - 1)
        if (t == "true") return true
        if (t == "false") return false
        if (t.isNotEmpty() && t.all { it.isDigit() }) t.toIntOrNull()?.let { return it }
        return t
    }
    private fun flowMap(s: String): Map<String, Any> {
        val m = LinkedHashMap<String, Any>()
        for (part in splitTop(s.substring(1, if (s.endsWith("}")) s.length - 1 else s.length))) {
            val colon = keyColon(part) ?: continue
            m[part.substring(0, colon).trim()] = value(part.substring(colon + 1).trim())
        }
        return m
    }
    private fun splitTop(s: String): List<String> {
        val out = ArrayList<String>(); val cur = StringBuilder(); var depth = 0; var quote: Char? = null
        for (ch in s) {
            if (quote != null) { cur.append(ch); if (ch == quote) quote = null; continue }
            if (ch == '"' || ch == '\'') { quote = ch; cur.append(ch); continue }
            if (ch == '{' || ch == '[') depth++ else if (ch == '}' || ch == ']') depth--
            if (ch == ',' && depth == 0) { out.add(cur.toString()); cur.setLength(0); continue }
            cur.append(ch)
        }
        if (cur.toString().isNotBlank()) out.add(cur.toString())
        return out
    }

    /** One Clash proxy map to a server, in the engine's words (iOS server). */
    @Suppress("UNCHECKED_CAST")
    fun server(m: Map<String, Any>): VpnConfig? {
        fun str(k: String): String? = when (val v = m[k]) { is String -> v.ifEmpty { null }; is Int -> v.toString(); else -> null }
        fun bool(k: String): Boolean? = when (val v = m[k]) { is Boolean -> v; is String -> if (v == "true") true else if (v == "false") false else null; else -> null }
        fun sub(k: String): Map<String, Any> = (m[k] as? Map<String, Any>) ?: emptyMap()
        val type = (str("type") ?: "").lowercase()
        val name = str("name") ?: ""
        val known = mapOf("vless" to VpnProto.VLESS, "vmess" to VpnProto.VMESS, "trojan" to VpnProto.TROJAN, "ss" to VpnProto.SHADOWSOCKS,
            "hysteria2" to VpnProto.HYSTERIA2, "wireguard" to VpnProto.WIREGUARD, "socks5" to VpnProto.SOCKS)
        val proto = known[type]
        if (proto == null) {
            if (type.isEmpty()) return null
            val u = VpnConfig.empty(VpnProto.UNSUPPORTED)
            u.scheme = type; u.reason = "protocol"; u.host = str("server") ?: ""; u.port = VpnText.portOf(str("port") ?: "") ?: 0
            u.name = name.ifEmpty { type }; u.uuidOrPassword = "$type:${u.host}:${u.port}:$name"
            return u
        }
        val c = VpnConfig.empty(proto)
        c.name = name; c.host = str("server") ?: ""; c.port = VpnText.portOf(str("port") ?: "") ?: 0
        c.sni = str("servername") ?: str("sni") ?: str("peer") ?: ""
        c.fingerprint = str("client-fingerprint") ?: ""
        c.alpn = (m["alpn"] as? List<Any>)?.mapNotNull { it as? String }?.joinToString(",")
        if (bool("skip-cert-verify") == true) c.allowInsecure = true
        fun unsupportedAs(scheme: String, reason: String): VpnConfig { val u = c.copy(); u.proto = VpnProto.UNSUPPORTED; u.scheme = scheme; u.reason = reason; return u }
        when (proto) {
            VpnProto.VLESS -> { c.uuidOrPassword = str("uuid") ?: ""; c.flow = str("flow") ?: ""; c.security = if (bool("tls") == true) "tls" else "none" }
            VpnProto.VMESS -> { c.uuidOrPassword = str("uuid") ?: ""; str("cipher")?.let { if (it != "auto") c.method = it }; c.security = if (bool("tls") == true) "tls" else "none" }
            VpnProto.TROJAN -> { c.uuidOrPassword = str("password") ?: ""; c.security = "tls" }
            VpnProto.SHADOWSOCKS -> { c.uuidOrPassword = str("password") ?: ""; c.method = str("cipher") ?: ""; if (str("plugin") != null) return unsupportedAs("ss+plugin", "plugin") }
            VpnProto.HYSTERIA2 -> {
                c.uuidOrPassword = str("password") ?: ""; c.network = "hysteria"; c.security = "tls"
                if ((str("obfs") ?: "") == "salamander") c.obfsPassword = str("obfs-password")
                c.up = mbpsWord(str("up")); c.down = mbpsWord(str("down")); c.mport = str("ports"); c.pinSHA256 = str("fingerprint")
            }
            VpnProto.WIREGUARD -> {
                c.uuidOrPassword = str("private-key") ?: ""; c.publicKey = str("public-key") ?: ""; c.presharedKey = str("pre-shared-key")
                c.localIPs = listOfNotNull(str("ip"), str("ipv6")).joinToString(",") { if (it.contains('/')) it else if (it.contains(':')) "$it/128" else "$it/32" }
                (m["reserved"] as? List<Any>)?.let { r -> c.reserved = r.mapNotNull { (it as? Int)?.toString() ?: (it as? String) }.joinToString(",") }
                c.mtu = str("mtu")?.toIntOrNull(); c.network = "udp"
            }
            VpnProto.SOCKS -> { c.user = str("username"); c.uuidOrPassword = str("password") ?: "" }
            VpnProto.UNSUPPORTED -> return null
        }
        (m["reality-opts"] as? Map<String, Any>)?.let { r ->
            c.security = "reality"; c.publicKey = (r["public-key"] as? String) ?: ""
            c.shortId = (r["short-id"] as? String) ?: ((r["short-id"] as? Int)?.toString() ?: "")
        }
        val network = (str("network") ?: "tcp").lowercase()
        if (proto != VpnProto.HYSTERIA2 && proto != VpnProto.WIREGUARD) when (network) {
            "ws" -> { c.network = "ws"; val w = sub("ws-opts"); c.path = w["path"] as? String
                c.hostHeader = (w["headers"] as? Map<String, Any>)?.entries?.firstOrNull { it.key.lowercase() == "host" }?.value as? String }
            "grpc" -> { c.network = "grpc"; c.serviceName = sub("grpc-opts")["grpc-service-name"] as? String }
            "h2", "http" -> return unsupportedAs("$type+$network", "transport")
        }
        if (c.name.isEmpty()) c.name = c.host
        return if (c.host.isEmpty() || c.port == 0 || (proto != VpnProto.SOCKS && c.uuidOrPassword.isEmpty())) null else c
    }
    /** Clash writes bandwidth as «100 Mbps» or a bare number of mbps. */
    fun mbpsWord(s: String?): String? { val n = s?.lowercase()?.takeWhile { it.isDigit() }?.toIntOrNull() ?: 0; return if (n > 0) n.toString() else null }
}

/** THE PROFILE FILES (iOS MontanaVPNFile, MontanaVPN.swift:1613-1749): a file read by its shape, never by its extension. */
object VpnFile {
    fun looksLikeWireGuard(s: String): Boolean { val low = s.lowercase(); return low.contains("[interface]") && low.contains("privatekey") }
    /** The first peer is the server; the interface's secret and the peer's key are the two the engine dials with. */
    fun wireGuard(s: String, name: String): VpnConfig? {
        val iface = HashMap<String, String>(); val peer = HashMap<String, String>()
        var section = ""; var peers = 0
        for (raw in s.lines()) {
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("#") || line.startsWith(";")) continue
            if (line.startsWith("[")) { section = line.lowercase(); if (section == "[peer]") peers++; continue }
            val eq = line.indexOf('=').takeIf { it >= 0 } ?: continue
            val k = line.substring(0, eq).trim().lowercase(); val v = line.substring(eq + 1).trim()
            if (section == "[interface]") iface[k] = v else if (section == "[peer]" && peers == 1) peer[k] = v
        }
        val c = VpnConfig.empty(VpnProto.WIREGUARD)
        c.network = "udp"; c.security = "none"
        c.uuidOrPassword = iface["privatekey"] ?: ""; c.publicKey = peer["publickey"] ?: ""; c.presharedKey = peer["presharedkey"]
        val ips = XrayConfig.list(iface["address"]); c.localIPs = if (ips.isEmpty()) null else ips.joinToString(",")
        c.mtu = iface["mtu"]?.toIntOrNull()
        val reserved = XrayConfig.list(peer["reserved"] ?: iface["reserved"]); c.reserved = if (reserved.isEmpty()) null else reserved.joinToString(",")
        val endpoint = peer["endpoint"] ?: ""
        val colon = endpoint.lastIndexOf(':')
        if (!endpoint.endsWith("]") && colon >= 0 && !endpoint.substring(colon + 1).contains(':')) {
            c.host = endpoint.substring(0, colon); c.port = VpnText.portOf(endpoint.substring(colon + 1)) ?: 0
        } else { c.host = endpoint; c.port = 51820 }
        c.name = name.ifEmpty { c.host }
        return if (c.host.isEmpty() || c.port == 0 || c.uuidOrPassword.isEmpty() || c.publicKey.isEmpty()) null else c
    }

    fun looksLikeHysteria(s: String): Boolean { var server = false; var auth = false
        for (l in s.lines()) { if (l.startsWith("server:")) server = true else if (l.startsWith("auth:")) auth = true }
        return server && auth }
    @Suppress("UNCHECKED_CAST")
    fun hysteria(s: String, name: String): VpnConfig? {
        val m = VpnClash.document(s)
        val server = (m["server"] as? String)?.ifEmpty { null } ?: return null
        val c = VpnConfig.empty(VpnProto.HYSTERIA2)
        c.network = "hysteria"; c.security = "tls"
        var host = server; var ports = ""
        val colon = server.lastIndexOf(':')
        if (!server.endsWith("]") && colon >= 0 && !server.substring(colon + 1).contains(':')) { host = server.substring(0, colon); ports = server.substring(colon + 1) }
        c.host = host
        val words = ports.split(',').map { it.trim() }
        val plain = words.firstOrNull { VpnText.portOf(it) != null }
        val leading = (words.firstOrNull() ?: "").takeWhile { it.isDigit() }
        c.port = plain?.let { VpnText.portOf(it) } ?: VpnText.portOf(leading) ?: 443
        val hopping = words.filter { it != plain && it.isNotEmpty() }
        if (hopping.isNotEmpty()) c.mport = hopping.joinToString(",")
        when (val a = m["auth"]) { is String -> c.uuidOrPassword = a; is Int -> c.uuidOrPassword = a.toString() }
        (m["tls"] as? Map<String, Any>)?.let { tls -> c.sni = (tls["sni"] as? String) ?: ""; if (tls["insecure"] == true) c.allowInsecure = true; c.pinSHA256 = tls["pinSHA256"] as? String }
        (m["obfs"] as? Map<String, Any>)?.takeIf { it["type"] == "salamander" }?.let { o -> c.obfsPassword = (o["salamander"] as? Map<String, Any>)?.get("password") as? String }
        (m["bandwidth"] as? Map<String, Any>)?.let { bw -> c.up = VpnBody.mbps(bw["up"]); c.down = VpnBody.mbps(bw["down"]) }
        c.name = name.ifEmpty { c.host }
        return if (c.host.isEmpty() || c.uuidOrPassword.isEmpty()) null else c
    }

    fun looksLikeOpenVPN(s: String): Boolean { var remote = false; var client = false
        for (l in s.lines()) { val t = l.trim(); if (t.startsWith("remote ")) remote = true
            if (t == "client" || t.startsWith("dev ") || t.startsWith("proto ") || t.startsWith("<ca>")) client = true }
        return remote && client }
    /** The row that says so; the profile itself is kept whole, so it can be copied on. */
    fun openVPN(s: String, name: String): VpnConfig {
        val c = VpnConfig.empty(VpnProto.UNSUPPORTED)
        c.scheme = "openvpn"; c.reason = "protocol"; c.raw = s; c.port = 1194
        for (l in s.lines()) {
            val words = l.trim().split(' ').filter { it.isNotEmpty() }
            if (words.firstOrNull() != "remote" || words.size < 2) continue
            c.host = words[1]; if (words.size > 2) VpnText.portOf(words[2])?.let { c.port = it }
            break
        }
        c.name = name.ifEmpty { c.host }
        c.uuidOrPassword = "openvpn:${c.host}:${c.port}:${c.name}"
        return c
    }

    /** The iPhone's own VPN profile, an Apple property list: named for what it is, never dialled by this engine. */
    fun looksLikeProfile(s: String) = s.startsWith("<?xml") && s.contains("com.apple.vpn.managed")
}

/** EVERY ROAD IN IS ONE ROAD (iOS MontanaVPNIntake): a plan's link is fetched, everything else read in place by the one body reader. */
object VpnIntake {
    sealed class Read { class Subscription(val url: String) : Read(); class Servers(val body: VpnBody.Body) : Read() }
    /** A file over this is no profile: the biggest honest one, an OpenVPN profile with its certificates, is a few kilobytes. */
    const val FILE_MAX = 1_048_576
    fun read(text: String, name: String = ""): Read =
        VpnSubscription.isSubscriptionURL(text)?.let { Read.Subscription(it) } ?: Read.Servers(VpnBody.body(text.toByteArray(), name))
}
