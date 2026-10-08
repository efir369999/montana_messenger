import Foundation

// SSOT mesh address book ([I-10]/[C-1]) — the ONE place that binds a peer's three names and its
// reachable endpoints. Every discovery source writes here and every route reads here:
//
//   reference of a person  ←→  overlay_addr (§3.3, 32 B)  ←→  endpoints (ip:port, freshness, source)
//
// Sources: signed BLE announce (§10), direct-channel registration (§5.3), signed DHT record (§9.2),
// montana://p2p link (§9.5), and the observed address a peer reports back (§5.4).
// SSOT-CONSOLIDATE: replaces the former "p2pLearnedEndpoints" store in MontanaP2PNode (imported on
// first load) — endpoints must not live in two places, or the two copies drift.

// The dimension diversity is measured in. A node identity here is a keypair and costs nothing, so
// spreading peers across identities protects nobody — an attacker mints them by the thousand. What
// still costs money is where a machine sits on the internet, and that is what the selection
// counts: pick a network block at random, then a host inside it, so an attacker holding a whole
// block gets one voice rather than hundreds. Local endpoints are exempt — the neighbours on your own
// Wi-Fi share one block by nature and are not an eclipse vector.
enum MontanaNetGroup {
    static func of(_ ip: String) -> String {
        let bare = ip.split(separator: "%").first.map(String.init) ?? ip
        if bare.contains(":") {                                   // IPv6 -> /48
            let parts = bare.lowercased().split(separator: ":", omittingEmptySubsequences: false)
            return "v6:" + parts.prefix(3).joined(separator: ":")
        }
        let o = bare.split(separator: ".")                        // IPv4 -> /24
        return o.count == 4 ? "v4:" + o.prefix(3).joined(separator: ".") : "v4:" + bare
    }
    static func isDiverse(_ ip: String) -> Bool { MontanaTransport.isGlobalIP(ip) }
}

struct MontanaMeshEndpoint: Equatable {
    let ip: String
    let port: UInt16
    var at: TimeInterval          // unix seconds when last confirmed
    var source: String            // "ble" | "bonjour" | "dht" | "link" | "wire"
    var fails: Int = 0            // consecutive dial failures
    var nextTry: TimeInterval = 0 // not offered as a route before this moment

    var hostPort: String { ip.contains(":") ? "[\(ip)]:\(port)" : "\(ip):\(port)" }
    var group: String { MontanaNetGroup.of(ip) }
    var dueNow: Bool { nextTry <= Date().timeIntervalSince1970 }
    var isGlobal: Bool { MontanaTransport.isGlobalIP(ip) }
    static func == (l: MontanaMeshEndpoint, r: MontanaMeshEndpoint) -> Bool { l.ip == r.ip && l.port == r.port }
}


// SSOT for this node's OWN endpoints (spec s.3 §4.7). One rule governs publication: an address is
// published only after an inbound connection has actually ARRIVED on it. An address that looks
// routable and answers nothing is worse than none — correspondents dial it until it times out, and
// the route plan treats the peer as directly reachable, so the working path through a transit peer
// is never chosen. Proof is per local address, never a flag on the node: a connection accepted on
// this device's Wi-Fi address proves THAT address and says nothing about any other.
//
// Address family is irrelevant by construction. Whichever address works proves itself and gets
// published; whichever does not is never published. Nothing here needs to know what a particular
// carrier or ISP does — it observes whether anyone arrived.
enum MontanaSelfEndpoint {
    static let proofWindow: TimeInterval = 1800      // §4.7 PROOF_WINDOW
    private static let key = "mt.self.proven"
    private static let lock = NSLock()

    // Every address this node holds on a real interface. Loopback is nobody's route, our own tunnel
    // carries nothing for the mesh, link-local does not leave the link — none are candidates.
    static func candidates() -> [String] {
        var out: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return out }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0, let sa = cur.pointee.ifa_addr else { continue }
            let fam = sa.pointee.sa_family
            guard fam == UInt8(AF_INET) || fam == UInt8(AF_INET6) else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            guard !name.hasPrefix("utun"), !name.hasPrefix("lo") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host).split(separator: "%").first.map(String.init) ?? ""
            guard !ip.isEmpty, publishable(ip), !out.contains(ip) else { continue }
            out.append(ip)
        }
        return out
    }

    static func publishable(_ ip: String) -> Bool {
        let low = ip.lowercased()
        return !(low.hasPrefix("fe80") || low == "::1" || low.hasPrefix("169.254.") || low == "127.0.0.1")
    }

    static func hasIPv4() -> Bool { candidates().contains { !$0.contains(":") } }

    // An inbound connection landed on this exact local address: it is reachable from wherever that
    // peer sits, and that is the only evidence §4.7 accepts.
    private static func provenMap() -> [String: Double] {
        guard let d = MontanaLocalVault.getDecrypted(key),
              let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: Double] else { return [:] }
        return m
    }

    static func markProven(_ raw: String) {
        let ip = raw.split(separator: "%").first.map(String.init) ?? raw
        guard !ip.isEmpty, publishable(ip) else { return }
        lock.lock()   // LOCK-OK: the book in memory and its vault record change as one step
        var m = provenMap()
        let fresh = m[ip] == nil
        m[ip] = Date().timeIntervalSince1970
        if let d = try? JSONSerialization.data(withJSONObject: m) { MontanaLocalVault.setEncrypted(key, d) }
        lock.unlock()
        if fresh { MontanaP2PTrace.mark("addr_proven", "ip=\(ip)") }
    }

    // Proven inside the window AND still held by an interface: an address that proved itself
    // yesterday and is gone from the interface today is not an address any more.
    static func proven() -> [String] {
        lock.lock()
        let m = provenMap()
        lock.unlock()
        let cutoff = Date().timeIntervalSince1970 - proofWindow
        let live = Set(candidates())
        return m.filter { $0.value > cutoff && live.contains($0.key) }
                .sorted { $0.value > $1.value }
                .map { $0.key }
    }

    // Wire form (§4.7): IPv6 always bracketed, so one string names host and port unambiguously.
    static func hostPort(_ ip: String, _ port: UInt16) -> String {
        ip.contains(":") ? "[\(ip)]:\(port)" : "\(ip):\(port)"
    }
    static func kind(_ ip: String) -> MontanaEndpoint.Kind { ip.contains(":") ? .directV6 : .directV4 }
}

final class MontanaOverlayBook {
    static let shared = MontanaOverlayBook()

    struct Entry {
        var ref: String = ""
        var overlay: Data? = nil          // 32 B §3.3
        var authPub: Data? = nil          // 1952 B ML-DSA-65 (lets us verify this peer's signed records)
        var endpoints: [MontanaMeshEndpoint] = []
        /// Overlays of nodes that hold a live channel to this peer. A device on a cellular network has
        /// no address anyone can dial; what it has is a node it is already connected to, and that is
        /// the address that means something — reach it there.
        var via: [Data] = []
        var viaAt: TimeInterval = 0
        /// The reference an entry gives at acquaintance, so a sender tells two machines of ONE owner
        /// from two owners. It stands on the secret the two of them share, so one owner hands two
        /// senders references that do not join, and holding one creates nothing persistent.
        var ownerRef: Data? = nil
    }

    private let lock = NSLock()
    private var byRef: [String: Entry] = [:]
    private var refByOverlay: [Data: String] = [:]
    private static let key = "mt.mesh.book"
    private static let legacyKey = "p2pLearnedEndpoints"
    private static let ttl: TimeInterval = 7 * 86_400

    private init() { load() }

    // ── binding identity ──
    func bind(ref: String, overlay: Data, authPub: Data? = nil) {
        guard !ref.isEmpty, overlay.count == 32 else { return }
        lock.lock()
        var e = byRef[ref] ?? Entry(ref: ref)
        e.ref = ref
        e.overlay = overlay
        if let a = authPub, a.count == 1952 { e.authPub = a }
        // The owner link is given by THE ENTRY POINT ITSELF at an introduction, and by nobody on its
        // behalf. Here stood a computation of it with MY owner secret -- and that exactly cancelled what
        // the value exists for: two machines of one owner give me two different shared secrets, hence
        // two different links, hence one owner counts as two, and the bound on owner distinctness
        // protects nothing. An empty link is honester than a computed one: the unknown counts as nothing.
        byRef[ref] = e
        refByOverlay[overlay] = ref
        lock.unlock()
        save()
    }

    // An address the owner deliberately took in — scanned, followed as a link, typed into contacts —
    // is known even before any way of reaching it is. Recognition on a local network works by matching
    // the rotating label against endpoints this device knows, so an address missing from here is
    // invisible no matter how close the peer stands.
    func note(ref: String) {
        guard !ref.isEmpty else { return }
        lock.lock()
        let fresh = byRef[ref] == nil
        if fresh { byRef[ref] = Entry(ref: ref) }
        lock.unlock()
        if fresh { save() }
    }

    // ── learning an endpoint (any source) ──
    func learn(ref: String, ip: String, port: UInt16, source: String) {
        guard !ref.isEmpty, !ip.isEmpty, port > 0, ip != "127.0.0.1" else { return }
        let now = Date().timeIntervalSince1970
        lock.lock()
        var e = byRef[ref] ?? Entry(ref: ref)
        e.ref = ref
        if let i = e.endpoints.firstIndex(where: { $0.ip == ip && $0.port == port }) {
            e.endpoints[i].at = now; e.endpoints[i].source = source
        } else {
            e.endpoints.append(MontanaMeshEndpoint(ip: ip, port: port, at: now, source: source))
        }
        e.endpoints = Self.prune(e.endpoints)
        byRef[ref] = e
        lock.unlock()
        save()
    }

    func learn(overlay: Data, ip: String, port: UInt16, source: String) {
        guard let w = ref(forOverlay: overlay) else { return }   // an unnamed peer stays unrouted by design
        learn(ref: w, ip: ip, port: port, source: source)
    }

    // An endpoint that refuses the connection is not an address any more. Two consecutive failures
    // retire it, so a port left over from the peer's previous launch cannot be dialled in a loop
    // while the peer is actually listening somewhere else. A success resets the count.
    // A failure delays an address instead of forgetting it, growing each time and spread by a random
    // factor so a whole set never retries in lockstep (30 seconds, doubling, shifted by the number of
    // live connections, capped at eight hours). An address is never lost: a peer that
    // moves back onto it is reachable again the moment the delay passes.
    private static let backoffBase: TimeInterval = 30
    private static let backoffCap: TimeInterval = 8 * 3600
    @discardableResult
    func fail(ref: String, ip: String, port: UInt16) -> Bool {
        let now = Date().timeIntervalSince1970
        lock.lock()
        guard var e = byRef[ref], let i = e.endpoints.firstIndex(where: { $0.ip == ip && $0.port == port }) else {
            lock.unlock(); return false
        }
        e.endpoints[i].fails += 1
        let n = min(e.endpoints[i].fails, 10)
        let spread = Double.random(in: 0.5...1.5)   // LOCAL-RANDOM-OK: spread of a retry, so a crowd does not knock in step; not a quantity of the protocol
        e.endpoints[i].nextTry = now + min(Self.backoffCap, Self.backoffBase * pow(2, Double(n)) * spread)
        let delayed = e.endpoints[i].nextTry - now
        byRef[ref] = e
        lock.unlock()
        save()
        MontanaP2PTrace.mark("endpoint_backoff", "peer=\(String(ref.prefix(10))) \(ip):\(port) for=\(Int(delayed))s")
        return true
    }

    func succeeded(ref: String, ip: String, port: UInt16) {
        lock.lock()
        if var e = byRef[ref], let i = e.endpoints.firstIndex(where: { $0.ip == ip && $0.port == port }) {
            e.endpoints[i].fails = 0; e.endpoints[i].nextTry = 0
            byRef[ref] = e
        }
        lock.unlock()
    }

    /// Learn where a peer is reachable THROUGH. Published in its signed record, so it is as
    /// authenticated as any endpoint and needs no trust in the node named.
    func learnVia(ref: String, nodes: [Data]) {
        guard !ref.isEmpty else { return }
        lock.lock()
        var e = byRef[ref] ?? Entry(ref: ref)
        e.ref = ref
        e.via = nodes.filter { $0.count == 32 }
        e.viaAt = Date().timeIntervalSince1970
        byRef[ref] = e
        lock.unlock()
    }
    func via(ref: String) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        guard let e = byRef[ref], Date().timeIntervalSince1970 - e.viaAt < 7200 else { return [] }
        return e.via
    }

    // ── reading ──
    // Dial order: freshest global endpoints first (reachable from any egress), then LAN-scoped.
    func endpoints(ref: String) -> [MontanaMeshEndpoint] {
        lock.lock(); defer { lock.unlock() }
        let eps = Self.prune(byRef[ref]?.endpoints ?? []).filter { $0.dueNow }
        return eps.sorted { a, b in a.isGlobal != b.isGlobal ? a.isGlobal : a.at > b.at }
    }
    func overlay(forRef w: String) -> Data? { lock.lock(); defer { lock.unlock() }; return byRef[w]?.overlay }
    func authPub(forRef w: String) -> Data? { lock.lock(); defer { lock.unlock() }; return byRef[w]?.authPub }
    func ref(forOverlay o: Data) -> String? { lock.lock(); defer { lock.unlock() }; return refByOverlay[o] }
    func allEntries() -> [Entry] { lock.lock(); defer { lock.unlock() }; return Array(byRef.values) }
    var count: Int { lock.lock(); defer { lock.unlock() }; return byRef.count }

    private static func prune(_ eps: [MontanaMeshEndpoint]) -> [MontanaMeshEndpoint] {
        let cutoff = Date().timeIntervalSince1970 - ttl
        return eps.filter { $0.at > cutoff }.sorted { $0.at > $1.at }.prefix(8).map { $0 }
    }

    // ── persistence (plain JSON in defaults; no secrets — public endpoints only) ──
    private func save() {
        lock.lock()
        let arr: [[String: Any]] = byRef.values.map { e in
            var m: [String: Any] = ["w": e.ref]
            if let o = e.overlay { m["o"] = o.map { String(format: "%02x", $0) }.joined() }
            if let a = e.authPub { m["p"] = a.base64EncodedString() }
            m["e"] = e.endpoints.map { ["i": $0.ip, "p": Int($0.port), "t": $0.at, "s": $0.source,
                                        "f": $0.fails, "n": $0.nextTry] }
            return m
        }
        lock.unlock()
        guard let d = try? JSONSerialization.data(withJSONObject: arr) else { return }
        // An address book is a graph: who with whom and where. It must not lie in the clear for a
        // minute: a backup, a debug dump and any access to the app settings read it whole. It is
        // written sealed with the device key, like correspondence.
        MontanaLocalVault.setEncrypted(Self.key, d)
    }

    private func load() {
        if let d = MontanaLocalVault.getDecrypted(Self.key),
           let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] {
            for m in arr {
                guard let w = m["w"] as? String, !w.isEmpty else { continue }
                var e = Entry(ref: w)
                if let oh = m["o"] as? String, let o = Self.hexData(oh), o.count == 32 {
                    e.overlay = o; refByOverlay[o] = w
                }
                if let p = m["p"] as? String, let a = Data(base64Encoded: p), a.count == 1952 { e.authPub = a }
                if let eps = m["e"] as? [[String: Any]] {
                    e.endpoints = eps.compactMap { x in
                        guard let i = x["i"] as? String, let p = x["p"] as? Int, let t = x["t"] as? Double,
                              let port = UInt16(exactly: p) else { return nil }
                        return MontanaMeshEndpoint(ip: i, port: port, at: t, source: (x["s"] as? String) ?? "?",
                                                   fails: (x["f"] as? Int) ?? 0, nextTry: (x["n"] as? Double) ?? 0)
                    }
                    e.endpoints = Self.prune(e.endpoints)
                }
                byRef[w] = e
            }
        }
        importLegacy()
    }

    // One-shot import of the former endpoint store, then it is retired (single source from here on).
    private func importLegacy() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.legacyKey) as? [String: String] ?? [:]
        guard !raw.isEmpty else { return }
        let cutoff = Date().timeIntervalSince1970 - Self.ttl
        for (ref, v) in raw {
            let f = v.split(separator: "|").map(String.init)
            guard f.count == 3, let port = UInt16(f[1]), let ts = Double(f[2]), ts > cutoff, !f[0].isEmpty else { continue }
            var e = byRef[ref] ?? Entry(ref: ref)
            e.ref = ref
            if !e.endpoints.contains(where: { $0.ip == f[0] && $0.port == port }) {
                e.endpoints.append(MontanaMeshEndpoint(ip: f[0], port: port, at: ts, source: "ble"))
            }
            byRef[ref] = e
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        save()
    }

    static func hexData(_ s: String) -> Data? {
        var out = Data(); var i = s.startIndex
        while let n = s.index(i, offsetBy: 2, limitedBy: s.endIndex) {
            guard let b = UInt8(s[i..<n], radix: 16) else { return nil }
            out.append(b); i = n
        }
        return out
    }
    static func hex(_ d: Data, _ n: Int = 4) -> String { d.prefix(n).map { String(format: "%02x", $0) }.joined() }
}
