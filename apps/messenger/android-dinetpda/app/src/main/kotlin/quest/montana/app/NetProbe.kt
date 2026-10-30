package quest.montana.app

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * THE MODE OF THE NETWORK IS MEASURED, NEVER GUESSED (iOS MontanaNetProbe, MontanaWakePush.swift 4108-4318; atoms
 * c0b52069608a, b3f67ba312fd, 1d49288c2894). «The node does not work» meant four different things -- our own door down, no
 * network at all, the operator's tunnel dropped, or the country's permitted list on -- and all four wrote one word. So the
 * diary names the mode itself: one beacon the public accounts of the list name as permitted, one nobody claims is
 * permitted yet answers on any ordinary line; their pair of answers reads the mode, headers only, a number nobody asked
 * before against every cache. The door round asks it when a door was silent (at most once a minute) and on its own every
 * hour; three agreeing rounds before a word is believed; the line's verdict under the list (NetLine) moves only on a
 * round no tunnel carried, and every road that asks reads that verdict and nothing else -- the call's refusal before a
 * far phone is rung for nothing.
 */
object NetProbe {
    private val permitted = listOf("https://max.ru/robots.txt" to "text", "https://mail.ru/robots.txt" to "text",
        "https://ya.ru/favicon.ico" to "image", "https://vk.com/robots.txt" to "text", "https://www.gosuslugi.ru/robots.txt" to "text")
    private val ordinary = listOf("https://detectportal.firefox.com/success.txt" to "text", "https://www.gstatic.com/generate_204" to "any",
        "https://captive.apple.com/hotspot-detect.html" to "text", "https://example.com/" to "text", "https://duckduckgo.com/robots.txt" to "text")
    private const val ROT = "mt.probe.rot"
    private const val MODE = "mt.probe.mode"
    private const val CONF = "mt.probe.conf"
    private const val AT = "mt.probe.at"
    private const val LINE = "mt.probe.line"
    private const val SAID_MODE = "mt.probe.saidMode"
    private const val SAID_AT = "mt.probe.saidAt"

    /** ONE TABLE OF FAILURE CLASSES (iOS failClass 4142-4157): which no-answer, never «unreachable». */
    fun failClass(e: Throwable): String {
        val w = (e.javaClass.simpleName + " " + (e.message ?: "")).lowercase()
        return when {
            "bad record" in w || "record mac" in w -> "tls-reset"
            e is javax.net.ssl.SSLHandshakeException || "handshake" in w -> "handshake"
            e is java.net.UnknownHostException -> "name"
            e is java.net.SocketTimeoutException || "timed out" in w || "timeout" in w -> "timeout"
            e is java.net.ConnectException || "refused" in w -> "refused"
            "unreachable" in w || "network is down" in w -> "net-down"
            "reset" in w || "abort" in w -> "reset"
            "closed" in w || "broken pipe" in w -> "peer-closed"
            else -> "other"
        }
    }

    private class Shot(val host: String, val code: Int, val cls: String, val ms: Long, val ok: Boolean)

    /** A PERMITTED PAGE BEHIND A GATE IS NOT AN OPEN LINE (iOS ask 4161-4189): the kind of the answer is checked beside its code. */
    private fun ask(t: Pair<String, String>): Shot {
        val host = runCatching { URL(t.first).host }.getOrDefault("-")
        val began = System.currentTimeMillis()
        return try {
            val u = URL(t.first + (if ('?' in t.first) "&" else "?") + "mt=" + (java.security.SecureRandom().nextInt() ushr 1))
            val c = u.openConnection() as HttpURLConnection
            c.requestMethod = "HEAD"; c.connectTimeout = 4000; c.readTimeout = 4000; c.useCaches = false; c.instanceFollowRedirects = true
            val code = c.responseCode
            val kind = (c.contentType ?: "").lowercase()
            c.disconnect()
            val kindOk = t.second == "any" || t.second in kind
            val ok = (code == 200 || code == 204) && kindOk
            Shot(host, code, if (ok) "-" else if (kindOk) "code" else "gate", System.currentTimeMillis() - began, ok)
        } catch (e: Exception) { Shot(host, 0, failClass(e), System.currentTimeMillis() - began, false) }
    }

    /** THE ONE OWNER OF «THIS LINE PASSES PERMITTED DESTINATIONS ONLY» (iOS 4195-4209). */
    val line: NetLine get() = runCatching { NetLine.of(JSONObject(Prefs.str(LINE, "{}"))) }.getOrDefault(NetLine())
    val underWhitelist: Boolean get() = line.holds(System.currentTimeMillis() / 1000.0)
    /** A call has no road under the list unless a tunnel carries this app past the filter. */
    val filtersCalls: Boolean get() = underWhitelist && !tunnelPresent()
    /** The mode and its confidence in one word for a summary line: «open/3», «whitelist/1», «-/0». */
    val verdictWord: String get() = Prefs.str(MODE, "-").ifEmpty { "-" } + "/" + (Prefs.str(CONF, "0").toIntOrNull() ?: 0)

    /** A tunnel stands: the system names a VPN among the networks (iOS MontanaNetWitness.tunnelPresent). */
    fun tunnelPresent(): Boolean = runCatching {
        val cm = Book.ctx.getSystemService(ConnectivityManager::class.java)
        @Suppress("DEPRECATION") cm.allNetworks.any { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }
    }.getOrDefault(false)

    /** WHAT CARRIED THE ROUND, IN THREE WORDS (iOS shortIfs 4211-4223): the radio and how many tunnels stood. */
    private fun shortIfs(): String = runCatching {
        val cm = Book.ctx.getSystemService(ConnectivityManager::class.java)
        @Suppress("DEPRECATION") val caps = cm.allNetworks.mapNotNull { cm.getNetworkCapabilities(it) }
        val carried = listOfNotNull("cell".takeIf { caps.any { it.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } },
            "wifi".takeIf { caps.any { it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } })
        val tunnels = caps.count { it.hasTransport(NetworkCapabilities.TRANSPORT_VPN) }
        (if (carried.isEmpty()) "none" else carried.joinToString("+")) + (if (tunnels > 0) "/tun" + tunnels else "")
    }.getOrDefault("none")

    private fun stamp(): Double = Prefs.str(AT, "0").toDoubleOrNull() ?: 0.0
    /** The probe's own clock (iOS 4225-4239): the hour is the baseline, the minute the ceiling on the answer to a silent door. */
    fun hourPassed() = System.currentTimeMillis() / 1000.0 - stamp() > 3600
    fun minutePassed() = System.currentTimeMillis() / 1000.0 - stamp() > 60

    /**
     * ONE TARGET FROM EACH GROUP PER ROUND, in turn (iOS round 4241-4303); a disagreement asks a second pair. True when this
     * round decided the line's verdict afresh.
     */
    @Synchronized fun round(mute: List<String>, alive: List<String>): Boolean {
        Prefs.setStr(AT, (System.currentTimeMillis() / 1000.0).toString())   // stamped before the beacons fly (iOS 4249-4252)
        val turn = (Prefs.str(ROT, "0").toIntOrNull() ?: 0)
        Prefs.setStr(ROT, (turn + 1).toString())
        val tunnelAtStart = tunnelPresent()
        var wl = ask(permitted[Math.floorMod(turn, permitted.size)])
        var nw = ask(ordinary[Math.floorMod(turn, ordinary.size)])
        var pairs = 1
        if (wl.ok != nw.ok) {
            val wl2 = ask(permitted[Math.floorMod(turn + 1, permitted.size)])
            val nw2 = ask(ordinary[Math.floorMod(turn + 1, ordinary.size)])
            if (wl2.ok) wl = wl2
            if (nw2.ok) nw = nw2
            pairs = 2
        }
        val mode = when {
            wl.ok && nw.ok -> "open"
            wl.ok -> "whitelist"
            nw.ok -> "unclear"
            wl.cls == "name" && nw.cls == "name" -> "name-blocked"
            else -> "no-net"
        }
        val same = Prefs.str(MODE, "") == mode
        val conf = if (same) minOf(3, (Prefs.str(CONF, "0").toIntOrNull() ?: 0) + 1) else 1
        Prefs.setStr(MODE, mode)
        Prefs.setStr(CONF, conf.toString())
        val tunnel = tunnelAtStart || tunnelPresent()
        val now = System.currentTimeMillis() / 1000.0
        val before = line
        val after = if (tunnel) before else before.step(mode, nw.ok, now)
        if (!tunnel) Prefs.setStr(LINE, after.json().toString())
        val held = after.holds(now)
        if (held != before.holds(now))
            Log.d("Montana", "net_line filtered=" + (if (held) 1 else 0) + " run=" + after.run + " wl=" + wl.host + ":" + wl.code + "/" + wl.cls + " nonwl=" + nw.host + ":" + nw.code + "/" + nw.cls)
        val up = alive.sorted().joinToString(","); val down = mute.sorted().joinToString(",")
        val body = "wl=" + wl.host + ":" + wl.code + "/" + wl.cls + "/" + wl.ms + "ms nonwl=" + nw.host + ":" + nw.code + "/" + nw.cls + "/" + nw.ms + "ms" +
            " doors_up=" + up.ifEmpty { "-" } + " doors_mute=" + down.ifEmpty { "-" } + " ifs=" + shortIfs() + " vpn=" + (if (tunnel) 1 else 0) +
            " mode=" + mode + " conf=" + conf + " pairs=" + pairs + " line=" + (if (held) "whitelist" else "-") + "/" + after.run
        // written when the mode changes, and otherwise at most once a quarter of an hour (iOS markChanged every: 900)
        val saidAt = Prefs.str(SAID_AT, "0").toDoubleOrNull() ?: 0.0
        if (Prefs.str(SAID_MODE, "") != mode || now - saidAt > 900) {
            Log.d("Montana", "net_probe " + body)
            Prefs.setStr(SAID_MODE, mode); Prefs.setStr(SAID_AT, now.toString())
        }
        return !tunnel && (if (after.filtered) mode == "whitelist" else nw.ok)
    }
}

/**
 * THE LINE UNDER THE PERMITTED LIST, WITH HYSTERESIS (iOS MTNetLine, MontanaWakePush.swift 4320-4348): three agreeing rounds
 * enter the verdict; it is left only by two rounds in a row in which a destination nobody permits answered; a blink of the
 * radio neither enters nor leaves it; a verdict no round confirmed for six hours lapses.
 */
data class NetLine(val filtered: Boolean = false, val at: Double = 0.0, val run: Int = 0) {
    fun holds(now: Double) = filtered && now - at < LAPSE
    fun step(mode: String, ordinary: Boolean, now: Double): NetLine {
        var next = if (filtered && !holds(now)) NetLine() else this
        if (mode == "whitelist") {
            val run = minOf(ENTER, maxOf(0, next.run) + 1)
            val f = next.filtered || ENTER <= run
            next = NetLine(f, if (f) now else next.at, run)
        } else if (ordinary) {
            val run = maxOf(-LEAVE, minOf(0, next.run) - 1)
            next = NetLine(if (LEAVE <= -run) false else next.filtered, next.at, run)
        } else next = next.copy(run = 0)
        return next
    }
    fun json(): JSONObject = JSONObject().put("filtered", filtered).put("at", at).put("run", run)
    companion object {
        const val ENTER = 3
        const val LEAVE = 2
        const val LAPSE = 6 * 3600.0
        fun of(o: JSONObject) = NetLine(o.optBoolean("filtered"), o.optDouble("at", 0.0), o.optInt("run"))
    }
}
