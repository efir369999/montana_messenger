package quest.montana.app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.util.Log
import java.net.Inet4Address
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * BEING FINDABLE ON THE LOCAL NETWORK (iOS MontanaP2PNode.meshDiscoverable 164-198, MontanaBonjour — MontanaP2P 178-367 — and
 * startPeerScan 657-710). One switch, the person's own and off at birth (the author's word 27.08): while it is off this phone
 * announces itself nowhere. On, it offers «_montana._udp» under a name drawn for this launch, its record carrying the direct port
 * and nothing else — not a name, not a reference, not a conversation; and every twenty seconds it listens for the others. The
 * Montana nodes of this network are everyone who answered with a port: who they are the announcement does not say and must not —
 * the channel finds out, and a letter under its pipe's tag is opened by its holder alone.
 */
object Mesh {
    const val KEY = "mt.mesh.discoverable"   // iOS UserDefaults «mt.mesh.discoverable»
    private const val TYPE = "_montana._udp"   // iOS MontanaBonjour.type
    @Volatile private var app: Context? = null
    @Volatile private var nodes: List<Pair<String, Int>> = emptyList()
    @Volatile private var lastKey = ""
    private var published: NsdManager.RegistrationListener? = null
    @Volatile private var name = ""
    @Volatile private var started = false

    val discoverable: Boolean get() = Prefs.bool(KEY, false)

    /** The nodes of this local network, address and direct port (iOS MontanaP2PNode.lanNodes). */
    fun lanNodes(): List<Pair<String, Int>> = nodes

    /** Once, for the app's whole life, beside the channels (iOS autoStart, startLocalMeshIfAccepted 298-312). */
    fun start(c: Context) {
        if (started) return
        started = true
        app = c.applicationContext
        if (discoverable && Channels.listening) advertise()
        // iOS startPeerScan: the first scan at 0.2 s, then every twenty; a scan of a phone that is not findable does nothing
        Thread { Thread.sleep(200); while (true) { runCatching { scan() }; Thread.sleep(20_000) } }.start()
    }

    /** The direct port stands: the offer names it now (iOS refreshTXT 274-281 — the record follows its bytes). */
    fun portUp() { if (started && discoverable) advertise() }

    /**
     * The switch (iOS meshDiscoverable.set, applyDiscoverability 180-198): what it governs is whether this phone OFFERS itself —
     * its announcement on the local network; the channels it holds and the letters it carries stand regardless.
     */
    fun setDiscoverable(on: Boolean) {
        Prefs.setBool(KEY, on)
        if (on) advertise() else stopAdvertising()
        Log.d("Montana", "discoverable on=" + (if (on) 1 else 0))
    }

    private fun nsd(): NsdManager? = app?.getSystemService(NsdManager::class.java)

    /** The offer (iOS advertise 217-232, txt 252-266): «mt-» and four bytes the core draws; «d» — the direct port, once it stands. */
    @Synchronized private fun advertise() {
        val m = nsd() ?: return
        stopAdvertising()
        val me = "mt-" + (MtBindings.nativeRandom(4)?.let { Wire.hex(it) } ?: "00000000")
        name = me
        val info = NsdServiceInfo().apply {
            serviceName = me
            serviceType = TYPE
            port = Channels.PORT
            // a record naming port zero invites the neighbours to knock at nothing (iOS 253-259)
            if (Channels.listening) setAttribute("d", Channels.PORT.toString())
        }
        val l = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(i: NsdServiceInfo) { Log.d("Montana", "lan_offer port=" + Channels.PORT + " d=" + (if (Channels.listening) 1 else 0)) }
            override fun onRegistrationFailed(i: NsdServiceInfo, code: Int) { Log.d("Montana", "lan_offer_failed code=" + code) }
            override fun onServiceUnregistered(i: NsdServiceInfo) {}
            override fun onUnregistrationFailed(i: NsdServiceInfo, code: Int) {}
        }
        if (runCatching { m.registerService(info, NsdManager.PROTOCOL_DNS_SD, l) }.isSuccess) published = l
    }

    /** iOS stopAdvertising 203-207: the phone keeps listening and keeps every channel — it only stops saying it is here. */
    @Synchronized private fun stopAdvertising() {
        val l = published ?: return
        published = null
        runCatching { nsd()?.unregisterService(l) }
    }

    /**
     * One scan (iOS startPeerScan 665-693, browse 294-310): 0.9 s of listening, each answer resolved — IPv4 only, as iOS ipPort
     * 354-366 — my own address and a loopback left out; a route is an answer with a direct port. A road that appeared where there
     * was none is said once.
     */
    private fun scan() {
        if (!discoverable) return
        val m = nsd() ?: return
        val found = java.util.Collections.synchronizedList(ArrayList<NsdServiceInfo>())
        val l = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(i: NsdServiceInfo) { found.add(i) }
            override fun onServiceLost(i: NsdServiceInfo) {}
            override fun onDiscoveryStarted(t: String) {}
            override fun onDiscoveryStopped(t: String) {}
            override fun onStartDiscoveryFailed(t: String, code: Int) { Log.d("Montana", "lan_browse_failed code=" + code) }
            override fun onStopDiscoveryFailed(t: String, code: Int) {}
        }
        if (runCatching { m.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, l) }.isFailure) return
        Thread.sleep(900)   // iOS browseMDNS(timeoutMs: 900)
        runCatching { m.stopServiceDiscovery(l) }
        val own = Channels.candidates().filter { !it.contains(':') }.toSet()
        val routes = LinkedHashSet<Pair<String, Int>>()
        // iOS resolves each answer with four seconds inside its window; Android resolves one at a time, so four seconds are the round's
        val until = System.currentTimeMillis() + 4000
        for (s in found.toList().distinctBy { it.serviceName }) {
            if (s.serviceName == name) continue
            val left = until - System.currentTimeMillis()
            if (left <= 0) break
            val r = resolve(m, s, left) ?: continue
            val d = r.attributes["d"]?.let { String(it) }?.toIntOrNull() ?: 0
            for (ip in v4(r)) if (ip !in own && !ip.startsWith("127.") && d in 1..65535) routes.add(ip to d)
        }
        val list = routes.sortedBy { it.first + ":" + it.second }
        val had = nodes.isNotEmpty()
        nodes = list
        if (list.isNotEmpty() && !had) Log.d("Montana", "lan_routes n=" + list.size)
        val key = list.joinToString(",") { it.first + ":" + it.second }
        if (key != lastKey) { lastKey = key; Log.d("Montana", "lan_nodes n=" + list.size) }
    }

    @Suppress("DEPRECATION")
    private fun resolve(m: NsdManager, s: NsdServiceInfo, waitMs: Long): NsdServiceInfo? {
        val done = CountDownLatch(1)
        var out: NsdServiceInfo? = null
        val l = object : NsdManager.ResolveListener {
            override fun onServiceResolved(i: NsdServiceInfo) { out = i; done.countDown() }
            override fun onResolveFailed(i: NsdServiceInfo, code: Int) { done.countDown() }
        }
        if (runCatching { m.resolveService(s, l) }.isFailure) return null
        if (!done.await(waitMs, TimeUnit.MILLISECONDS) && Build.VERSION.SDK_INT >= 34) runCatching { m.stopServiceResolution(l) }
        return out
    }

    @Suppress("DEPRECATION")
    private fun v4(i: NsdServiceInfo): List<String> {
        val all = if (Build.VERSION.SDK_INT >= 34) i.hostAddresses else listOfNotNull(i.host)
        return all.filterIsInstance<Inet4Address>().mapNotNull { it.hostAddress }
    }
}
