import Foundation
import MontanaBindings
import Darwin
import Network
import Security
import CryptoKit

extension Notification.Name {
    /// A message delivered over the Wi-Fi mesh. userInfo: ["from": String, "text": String].
    static let montanaP2PIncoming = Notification.Name("montanaP2PIncoming")
    /// An outgoing mesh frame actually hit the wire. userInfo: ["address", "mid", "transport"] —
    /// refines the bubble glyph to the wire's real physical medium (same classifier as the receive side).
    static let montanaP2PSent = Notification.Name("montanaP2PSent")
    /// A mesh peer became reachable (new Bonjour discovery or BLE announce). userInfo: ["address"] —
    /// triggers the profile catch-up push (name/avatar), the serverless analog of the WS-connect broadcast.
    static let montanaP2PPeerUp = Notification.Name("montanaP2PPeerUp")
}

/// A P2P message in a Wi-Fi conversation (delivered directly). `peer` is the other
/// party's Montana address; `mine` marks outgoing.
struct P2PMsg: Identifiable, Hashable {
    let id = UUID()
    let peer: String
    let text: String
    let mine: Bool
    let at: String
}

struct MontanaPeer: Identifiable, Hashable {
    let name: String            // human name from the neighbor's Montana profile
    let endpoint: String            // ip:port on the LAN (postman)
    let neighborRef: String     // the neighbor's public Montana reference (from Bonjour TXT); "" if absent
    let directPort: UInt16      // persistent direct-channel listener port (Bonjour TXT "d"); 0 if absent
    var id: String { endpoint }
    var ip: String {
        if endpoint.hasPrefix("["), let end = endpoint.firstIndex(of: "]") {        // [ipv6]:port
            return String(endpoint[endpoint.index(after: endpoint.startIndex)..<end])
        }
        if endpoint.filter({ $0 == ":" }).count > 1 { return endpoint }             // raw ipv6 (no port)
        return endpoint.split(separator: ":").first.map(String.init) ?? endpoint    // ipv4:port
    }
}

// Rotating discovery label (spec s.3 §13 stage 5). What a device broadcasts on a shared network must
// mean nothing to a stranger: the human name and the reference used to go out in clear, so anyone
// on a café Wi-Fi could read who was in the room. The label is derived from the owner's own address and
// the current minute, so a contact — who already knows that address — recognises it by pre-computing
// the same value, while everyone else sees a number that changes every minute.
/// The label an announce carries on the local network.
///
/// It stands on the label of the twin correspondence — a value derived from the owner branch of a
/// seed, which leaves no device and which nobody outside can compute. What used to stand here was a
/// PUBLIC reference: anyone holding it computed every window of the label and recognised that
/// person on any network they walked into, while the rotation hid nothing from the only party it
/// mattered to hide from. Its shape and its window come from MTPipe — one composition, one window,
/// one tolerance for the whole tree.
/// How this device is recognised on a local network, and it is the SAME question the radio asks:
/// a tag of the current window standing on the secret two correspondents share.
///
/// What stood here was a tag of its own making — a hash of this device's standing reference under a
/// domain of its own («mt-local-tag»). It hid the reference from a passer-by, but only after that
/// reference had been handed to every neighbour in the clear by the radio, and it was a second
/// derivation of a quantity the set already defines. One quantity, one place: `mt-tag`.
enum MontanaLocalTag {
    static func window(_ at: Date = Date()) -> UInt64 { MTPipe.window(at) }

    /// Whose tag this is, if it is anybody's this device knows. One lookup in the index of the
    /// window — not a hash per correspondence per window, which is what it used to be.
    static func conv(forTag tag: String, at: Date = Date()) -> String? {
        guard let d = Data(montanaHex: tag) else { return nil }
        // A pipe tag names its correspondence; a point of first contact names the correspondence
        // still waiting at it. Both are «whose tag is this», and both are answered here.
        return MTPipeBook.match(d, at: at) ?? MTPipeBook.convAwaiting(firstContactTag: d, at: at)
    }
}

/// Montana mesh transport over the network FFI (mt_client_*).
/// Synchronous FFI calls — run on a background queue (block_on inside).
/// Delivery: connect(courier) → register(queue) → send/recv/ack.
final class MontanaP2P {
    private var postman: OpaquePointer?
    private var client: OpaquePointer?

    /// Local postman (LAN/backup role). Returns: port (0 = error).
    func startPostman(bind: String) -> UInt16 {
        var buf = [CChar](repeating: 0, count: 64)
        return bind.withCString { c in
            postman = mt_postman_start(c, &buf, 64)
            return postman != nil ? mt_postman_port(postman) : 0
        }
    }

    func stopPostman() {
        if let p = postman { mt_postman_stop(p); postman = nil }
    }

    /// ML-KEM pubkey of the local postman (for clients that deposit to us).
    func postmanKemPubkey() -> Data? {
        guard let p = postman else { return nil }
        var out = [UInt8](repeating: 0, count: 1184)
        let n = mt_postman_kem_pubkey(p, &out, 1184)
        return n == 1184 ? Data(out) : nil
    }

    /// Connect to the genesis postman-courier.
    func connect(endpoint: String) -> Bool {
        return endpoint.withCString { c in
            client = mt_client_connect(c)
            return client != nil
        }
    }

    func disconnect() {
        if let c = client { mt_client_free(c); client = nil }
    }

    /// Courier route on OWN postman: overlay -> physical addr. Self-host needs a route to itself
    /// (self.overlay -> 127.0.0.1:port) so the proxy-register lands on the local host and the queue registers.

    /// Register the queue DIRECTLY on the connected node (self-host: no courier, no self-connection).
    func registerDirect(queue: Data) -> Bool {
        guard let client else { return false }
        let q = [UInt8](queue)
        return q.withUnsafeBufferPointer { qp in
            mt_client_register_direct(client, qp.baseAddress, q.count) == 0
        }
    }

    /// Register a queue (recipient).
    func register(hostOverlay: Data, hostKem: Data, queue: Data) -> Bool {
        guard let client else { return false }
        let ho = [UInt8](hostOverlay), hk = [UInt8](hostKem), q = [UInt8](queue)
        return ho.withUnsafeBufferPointer { hoP in
            hk.withUnsafeBufferPointer { hkP in
                q.withUnsafeBufferPointer { qP in
                    mt_client_register(client, hoP.baseAddress, hkP.baseAddress, qP.baseAddress, q.count) == 0
                }
            }
        }
    }

    /// Send (sealed to host_kem, two-hop).
    func send(hostOverlay: Data, hostKem: Data, sendId: Data, sendSk: Data, msgId: Data, msg: Data) -> Bool {
        guard let client else { return false }
        let ho = [UInt8](hostOverlay), hk = [UInt8](hostKem), si = [UInt8](sendId)
        let sk = [UInt8](sendSk), mi = [UInt8](msgId), m = [UInt8](msg)
        return ho.withUnsafeBufferPointer { hoP in hk.withUnsafeBufferPointer { hkP in
            si.withUnsafeBufferPointer { siP in sk.withUnsafeBufferPointer { skP in
                mi.withUnsafeBufferPointer { miP in m.withUnsafeBufferPointer { mP in
                    mt_client_send(client, hoP.baseAddress, hkP.baseAddress, siP.baseAddress,
                                   skP.baseAddress, miP.baseAddress, mP.baseAddress, m.count) == 0
                }}}}}}
    }


    /// Acknowledge receipt — the host drops the buffer (drop-on-ack, authenticated by recv_key signature).
    func ack(hostOverlay: Data, hostKem: Data, recvId: Data, recvSk: Data) -> Bool {
        guard let client else { return false }
        let ho = [UInt8](hostOverlay), hk = [UInt8](hostKem), ri = [UInt8](recvId), rk = [UInt8](recvSk)
        return ho.withUnsafeBufferPointer { hoP in hk.withUnsafeBufferPointer { hkP in
            ri.withUnsafeBufferPointer { riP in rk.withUnsafeBufferPointer { rkP in
                mt_client_ack(client, hoP.baseAddress, hkP.baseAddress, riP.baseAddress, rkP.baseAddress) == 0
            }}}}
    }

    // MARK: auto-discovery via native Apple Bonjour (iOS Local Network privacy
    // blocks raw multicast Rust-mdns; NetService/NetServiceBrowser is the standard path).
    func advertiseMDNS(port: UInt16, directPort: UInt16) { MontanaBonjour.shared.advertise(port: port, directPort: directPort) }
    /// Offer these correspondences on the local network — the same knock the radio makes.
    func browseMDNS(timeoutMs: UInt32 = 3000) -> [MontanaPeer] {
        MontanaBonjour.shared.browse(timeout: Double(timeoutMs) / 1000.0)
    }

    deinit { disconnect(); stopPostman() }
}


// MARK: native Bonjour — advertise/browse via Apple NetService (works under iOS
// Local Network privacy; iOS silences raw multicast Rust-mdns without an access prompt).
final class MontanaBonjour: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = MontanaBonjour()
    private let type = "_montana._udp."
    private let domain = "local."
    private var published: NetService?
    private var resolving: [NetService] = []
    /// Set once by the app, which is where the device identity lives — this file also compiles into the
    /// notification extension, and reaching into the archive from here would not link there.
    /// A neighbour address and ALL conversations it answers for. Before, one was kept: parsing
    /// stopped at the first recognised mark, and if a neighbour announced several, an arbitrary one
    /// was remembered. The record then went into a dictionary keyed by conversation -- two
    /// neighbours answering for one erased each other (the list flickered), while a conversation a
    /// neighbour answered for by its second mark got no address at all, and a letter to it went over
    /// radio with live Wi-Fi. What is heard on the local network: the address and port of the direct
    ///
    /// Here stood the neighbour's list of conversations, and when the announcement stopped carrying
    /// them the list stayed empty -- while parsing was built FROM it. An empty list gave zero
    /// neighbours per neighbour: a node was heard, announced, would be dialled in a hundred
    private var found: [String: UInt16] = [:]   // ip:port -> direct channel port

    // The advertised service says nothing about its owner: the instance name is meaningless for this
    // launch, and TXT carries the rotating label plus the direct port. Contacts recognise the label;
    // a stranger on the same network learns only that some device speaks this protocol.
    /// Stop announcing. The node keeps listening and keeps every channel it holds — it simply stops
    /// telling the local network it is here.
    func stopAdvertising() {
        DispatchQueue.main.async { self.published?.stop(); self.published = nil }
    }

    /// The instance name is meaningless for this launch, and it is drawn by the core: it lives as
    /// long as the announce does, and a value longer than a frame is never taken from the phone.
    private static func instanceTag() -> String {
        var b = [UInt8](repeating: 0, count: 4)
        guard mt_random_fast(&b, 4) == 0 else { return "00000000" }
        return b.map { String(format: "%02x", $0) }.joined()
    }

    func advertise(port: UInt16, directPort: UInt16) {
        DispatchQueue.main.async {
            self.published?.stop()
            let svc = NetService(domain: self.domain, type: self.type,
                                 name: "mt-" + MontanaBonjour.instanceTag(),
                                 port: Int32(port))
            svc.delegate = self
            svc.setTXTRecord(NetService.data(fromTXTRecord: MontanaBonjour.txt(directPort)))
            svc.schedule(in: .main, forMode: .common)
            svc.publish()
            self.published = svc
            self.directPort = directPort
            self.lastTXT = ""
            self.startTXTFollow()
        }
    }

    /// What this device offers on a local network: a port to dial, and the tags of the pipes it has
    /// something to carry for. Nothing else — not a standing reference, not a name.
    ///
    /// A person's chosen name used to ride here, so everyone on every network this phone ever joined
    /// read who had walked in. A name reaches a correspondent over the channel the two of them
    /// hold, which is where it was always supposed to travel.
    private var directPort: UInt16 = 0
    /// The announcement carries NOTHING about conversations -- only the port to knock on.
    ///
    /// Conversation marks in the record were an error of class, not a detail: the record holds 255
    /// bytes, and everything that grows with the number of chats sooner or later falls out of it --
    /// silently. We paid for that all day: full labels did not fit, heads collided, parsing took the
    /// first that turned up, the ledger erased neighbour by neighbour. Neither of the two other
    /// implementations does this: one puts only its service identifier on the air, the other one
    ///
    /// So here is the same answer, and it is simpler than all the previous ones: a neighbour
    /// announces that it is a Montana node and which port to knock on. Who it is, the CHANNEL finds
    /// out -- it has neither a 255-byte bound nor an observer. An outsider now sees less than before:
    private static func txt(_ directPort: UInt16) -> [String: Data] {
        // A record naming port zero invites the neighbours to knock at nothing. It appeared because
        // the announcement can run before the listener has its port, and it made this device look
        // present on the local network while being unreachable there.
        guard directPort > 0 else {
            MontanaP2PTrace.mark("lan_offer_skipped", "the port is not up yet")
            return [:]
        }
        let txt: [String: Data] = ["d": Data(String(directPort).utf8)]
        // What this device actually PUTS on the air, split by where it came from. Without it a
        // silent record is indistinguishable from a device with nothing to say — and the two need
        // different answers. Counts only: a count says nothing about who anybody talks to.
        MontanaP2PTrace.mark("lan_offer", "port=\(directPort)")
        return txt
    }

    /// A label holds for one window and no longer. The record used to be rewritten only when the
    /// LIST of correspondences changed, so a device with a card outstanding published the point of
    /// one minute for as long as it stood there — and after that minute it was announcing a node
    /// that no longer existed. The bytes decide: the record is written when they differ.
    private var lastTXT: String = ""
    private var txtTimer: DispatchSourceTimer?
    func refreshTXT() {
        guard let svc = published else { return }
        let dict = MontanaBonjour.txt(directPort)
        let key = dict.map { "\($0.key)=\(String(data: $0.value, encoding: .utf8) ?? "")" }.sorted().joined(separator: ";")
        guard key != lastTXT else { return }
        lastTXT = key
        svc.setTXTRecord(NetService.data(fromTXTRecord: dict))
    }

    /// Follow the window while this device has anything to say. Cheap: every label of a window is
    /// computed once and cached by the book, so a tick that changes nothing writes nothing.
    private func startTXTFollow() {
        guard txtTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 5, repeating: 15)
        t.setEventHandler { [weak self] in self?.refreshTXT() }
        t.resume()
        txtTimer = t
    }

    func browse(timeout: TimeInterval) -> [MontanaPeer] {
        resolving = []
        found = [:]
        let browser = NetServiceBrowser()
        browser.includesPeerToPeer = false
        browser.delegate = self
        browser.schedule(in: .current, forMode: .common)
        browser.searchForServices(ofType: type, inDomain: domain)
        RunLoop.current.run(until: Date().addingTimeInterval(timeout))
        browser.stop()
        // One neighbour, one record. Whom it answers for the announcement does not say and must not;
        // a letter is sealed with the addressee queue key, so a neighbour it is not meant for cannot
        // open it -- it either carries it on or drops it. Every conversation has a path at once.
        return found.map { ep, dport in
            MontanaPeer(name: ep, endpoint: ep, neighborRef: "", directPort: dport)
        }.sorted { $0.endpoint < $1.endpoint }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        MontanaLog.event("P2P browse FOUND \(service.name)")
        service.delegate = self
        service.schedule(in: .current, forMode: .common)
        service.resolve(withTimeout: 4)
        resolving.append(service)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        MontanaLog.event("P2P browse DID-NOT-SEARCH err=\(errorDict) (likely Local Network permission denied)")
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let endpoints = sender.addresses else { return }
        var dport: UInt16 = 0
        if let txt = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txt)
            if let d = dict["d"], let s = String(data: d, encoding: .utf8), let p = UInt16(s) { dport = p }
        }
        for data in endpoints {
            if let ep = MontanaBonjour.ipPort(from: data) { found[ep] = dport }
        }
        MontanaLog.event("P2P resolved -> \(endpoints.compactMap { MontanaBonjour.ipPort(from: $0) }.joined(separator: ",")) d=\(dport)")
    }

    /// Whether we managed to announce ourselves on the local network. iOS gives no call that returns
    /// the system permission state -- but a refusal is visible: the announcement is not published.
    /// That is the only thing we know for certain, and it is what we show, not a flag of our own.
    private(set) var announceAccepted = false

    func netServiceDidPublish(_ sender: NetService) {
        announceAccepted = true
        MontanaLog.event("P2P advertise PUBLISHED \(sender.name):\(sender.port)")
    }
    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        announceAccepted = false
        MontanaLog.event("P2P advertise DID-NOT-PUBLISH \(sender.name) err=\(errorDict)")
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        MontanaLog.event("P2P resolve DID-NOT-RESOLVE \(sender.name) err=\(errorDict)")
    }

    static func ipPort(from data: Data) -> String? {
        return data.withUnsafeBytes { raw -> String? in
            guard let sa = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return nil }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var serv = [CChar](repeating: 0, count: Int(NI_MAXSERV))
            let r = getnameinfo(sa, socklen_t(data.count), &host, socklen_t(host.count),
                                &serv, socklen_t(serv.count), NI_NUMERICHOST | NI_NUMERICSERV)
            guard r == 0 else { return nil }
            let h = String(cString: host)
            if h.contains(":") { return nil }  // IPv4 only — node_hello parses ip:port
            return "\(h):\(String(cString: serv))"
        }
    }
}


// ════════════════════════════════════════════════════════════════════════════
// PERSISTENT DIRECT CHANNEL — instant delivery over the Wi-Fi LAN (one handshake per peer,
// no polling). One TCP connection per peer stays open and every signal (text,
// delete-for-everyone, receipts, edits) travels the moment it exists, device to device.
// Post-quantum secured: a fresh ML-KEM-768 key exchange on
// connect derives a per-session key; every frame is sealed (ChaCha20-Poly1305, mt_e2e_seal_blob).
// Wire per frame: 4-byte big-endian length prefix + body.
//   Acceptor (receiver): on ready sends frame(my_kem_pk 1184); reads frame(ct 1088) -> decaps ->
//     shared key; then reads sealed data frames -> open -> post .montanaP2PIncoming.
//   Initiator (sender): reads frame(peer_kem_pk); encaps -> (ct, shared key); sends frame(ct);
//     then pushes sealed data frames (from|mid|text).
// ════════════════════════════════════════════════════════════════════════════
final class MontanaP2PDirect {
    static let shared = MontanaP2PDirect()
    private let q = DispatchQueue(label: "montana.p2p.direct")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var myKemPk = [UInt8](repeating: 0, count: 1184)   // MT_MLKEM_PUBKEY_SIZE
    private var myKemSk = [UInt8](repeating: 0, count: 2400)   // MT_MLKEM_SECKEY_SIZE
    private var ident: MontanaOverlayKey?                 // §3.3 overlay identity for registration
    private var outbound: [String: OutConn] = [:]              // peer montana address -> sender connection
    private var inbound: [ObjectIdentifier: OutConn] = [:]     // strong ref to acceptor connections
    private var started = false
    private var portTries = 0
    private var useEphemeralPort = false
    private var keepaliveTimer: DispatchSourceTimer?
    // Lock-guarded snapshot of live channels (overlay -> peer coordinates). Read by the mesh services
    // from inside the dispatch itself, so it must never route through `q` (that would deadlock).
    private let idxLock = NSLock()
    /// ONE registry of the living -- a row per CHANNEL, because a channel is what exists. Both views
    /// are derived from it and neither is stored apart: "whom we hold" (identity) and "by which way"
    /// (door). Before, the ledger stood on the peer identity, and two doors to ONE node were written
    /// into one cell: the second erased the first, and a break of either killed the node record
    /// entirely -- the 24.08 measurement on T2 gave `node_open at=api...` and five milliseconds later
    /// `nodes=1(... relay=0)[]` with a live second channel, while dialling hammered an already open
    /// door in batches of `connect_ms=0`. The key is the channel itself: its break removes exactly
    /// its own row and nobody else's. The key is the channel's permanent identifier, not its address
    /// in memory: an address is reused, and a dead channel's row would fall to a live one.
    private var liveIndex: [UInt64: LiveChannel] = [:]
    private static let cidLock = NSLock()
    private static var cidNext: UInt64 = 1
    static func nextCid() -> UInt64 {
        cidLock.lock(); defer { cidLock.unlock() }
        cidNext &+= 1; return cidNext
    }

    struct LiveChannel {
        let overlay: Data
        let ref: String
        let ip: String
        let port: UInt16
        /// The whole door: name, port and the WIRE DRESS. A bare door and a door behind a delivery
        /// network on one name are different paths, and one key for both would bring erasure back in
        let pathKey: String
        /// Dialled by us at the door address -- this is a PATH. An incoming guest is not a path: its
        /// port is ephemeral and corresponds to no door.
        let door: Bool
        /// How long this door took to stand up. A measure of the path, not the node: one machine has doors of different speed.
        let ms: Int
    }

    /// Doors leading to an ALREADY HELD node slower than another: extra channels to one machine.
    /// Until they are collapsed, the phone opens itself twice to the same node and wastes the wire.
    static func foldedDoors(_ rows: [LiveChannel]) -> [LiveChannel] {
        var best: [Data: LiveChannel] = [:]
        for r in rows where r.door {
            if let b = best[r.overlay], (b.ms, b.pathKey) <= (r.ms, r.pathKey) { continue }
            best[r.overlay] = r
        }
        return rows.filter { $0.door && best[$0.overlay]?.pathKey != $0.pathKey }
    }

    /// Three pure rules over the rows -- the whole of the ledger. Kept apart so that they can be
    /// frozen by a test on invented rows, not only on a live network.
    static func doorsHeld(_ rows: [LiveChannel]) -> Set<String> {
        Set(rows.filter { $0.door }.map { $0.pathKey })
    }
    static func nodesHeld(_ rows: [LiveChannel], doors: Set<String>) -> Set<Data> {
        Set(rows.filter { $0.door && doors.contains($0.pathKey) }.map { $0.overlay })
    }
    static func peersHeld(_ rows: [LiveChannel]) -> [LiveChannel] {
        var byPeer: [Data: LiveChannel] = [:]
        for r in rows.sorted(by: { $0.pathKey < $1.pathKey }) where byPeer[r.overlay] == nil {
            byPeer[r.overlay] = r
        }
        return Array(byPeer.values)
    }
    // The race offers the same envelope for several endpoints. Once one of them is carrying it, the
    // others must not put a second copy on the very same channel — measured: a 236 KB avatar written
    // three times over one link. A repeat of the same message to the same peer within this window is
    // the race, not a retry; the delivery engine's real retries come minutes apart.
    private var recentSends: [String: Date] = [:]
    private static let raceWindow: TimeInterval = 5
    /// Identifiers of frames this device has ALREADY seen, and of those it wrote itself.
    /// Both sets live here, not in a connection: a frame arrives over one connection while it was
    /// sent over several, and filtering inside one connection did not see the repeat at all.
    private var seenFrames: Set<Data> = []
    private var originated: Set<Data> = []
    private static let frameMemory = 8192

    final class OutConn {
        /// The channel identifier for the whole of its life and not a second longer. The ledger row
        /// lives EXACTLY as long: it is removed both by a break and by the object's death -- because
        /// "the channel is gone" happens without a break handler too, while the handler holds the
        /// channel weakly and exits silently on a dead one. Six places in this file drop a connection;
        /// remembering them on every edit is discipline, while a lifetime is construction.
        let cid: UInt64 = MontanaP2PDirect.nextCid()
        /// The door dialled by this channel: name, port and wire dress, computed once.
        var doorKey = ""
        deinit { MontanaP2PDirect.shared.forget(cid) }
        let nw: MTWire
        var sendKey: [UInt8]?      // Noise_PQ session key, this side -> peer
        var recvKey: [UInt8]?      // Noise_PQ session key, peer -> this side
        var pending: [(Data, String)] = []   // (payload, mid) queued before the handshake completes
        var dialAt = Date()
        var sentAt: [String: Date] = [:]     // mid -> wire time, for the e2e ack round-trip
        var channelHash: [UInt8] = []        // Noise_PQ transcript hash (§5.0), binds the §5.1 proof
        var isDialer = true
        var peerIP = ""                      // remote IP — classifies internet vs Wi-Fi LAN
        var peerPort: UInt16 = 0             // remote port — for a bounded reconnect on a dropped channel
        var redials = 0                      // reconnect attempts for this channel (bounded, anti-storm)
        var peerRefStr = ""          // peer mt… reference — routes wire-medium refinement to the chat
        var myOverlayTag = Data()                  // my overlay_addr (§3.3)
        var peerOverlay: Data?               // peer overlay_addr, verified via registration (§5.3)
        /// The owner link THIS machine named at the introduction. It lives together with the
        /// introduction and is written nowhere: it is the introduction, not a record about the peer.
        var peerOwnerRef: Data?
        var ownerAsks = 0            // how many times the owner name was asked again on this channel
        var peerAuthPub: Data?
        var challengeNonce: Data?            // nonce I issued to the peer
        var myRegConfirmed = false           // peer returned RegisterResult 0x00 for my registration
        var peerRegConfirmed = false         // I verified the peer proof
        var flushed = false
        var ready: Bool { myRegConfirmed && peerRegConfirmed }
        var sentAtMsg: [Data: Date] = [:]    // OverlayFrame msg_id -> wire time
        var isService = false                // opened for a DHT/NAT RPC, not for a chat peer
        var lastUsed = Date()                // traffic on this channel — drives the idle close and the cap
        var netWaiters: [UInt8: [(id: UUID, cb: (Data?) -> Void)]] = [:]   // reply type -> FIFO of waiters
        var readyWaiters: [(OutConn?) -> Void] = []
        var closeWhy = ""                    // why WE closed it: every cancel of ours names itself (23.09)
        init(_ nw: MTWire) { self.nw = nw }
    }

    private var onReady: ((UInt16) -> Void)?
    func start(mnemonic: String, onReady: @escaping (UInt16) -> Void) {
        q.async {
            if self.started { if self.port > 0 { onReady(self.port) } else { self.onReady = onReady }; return }
            self.onReady = onReady
            self.ident = MontanaOverlayKey.device()
            var seed = [UInt8](repeating: 0, count: 64)   // MT_MLKEM_SEED_LEN — ephemeral (forward secrecy)
            // The seed of this node's ephemeral pair comes from the core: six sources folded, and a
            // refusal when fewer than three are alive.
            guard mt_random_fast(&seed, 64) == 0,
                  mt_mlkem_keypair_from_seed(seed, &self.myKemPk, &self.myKemSk) == 0 else {
                MontanaLog.event("P2P direct: keygen FAIL"); return
            }
            let l: NWListener
            let tcpOpts = NWProtocolTCP.Options()
            tcpOpts.enableKeepalive = true; tcpOpts.keepaliveIdle = 10; tcpOpts.keepaliveInterval = 5; tcpOpts.keepaliveCount = 2
            let params = NWParameters(tls: nil, tcp: tcpOpts)
            params.allowLocalEndpointReuse = true
            // The mesh never travels inside our own VPN. utun presents itself as `.other`, so barring
            // that interface type keeps every mesh socket on the physical network: neighbours are
            // reached directly, and the tunnel extension — which the system terminates over a few
            // megabytes — is not asked to carry traffic that was never meant for it.
            // IFACE-CHECKED: the listener accepts from wherever they come; an interface ban took
            // incoming away from the node exactly when the person switched on any tunnel.
            // A node's port is STABLE across launches. A random port meant every relaunch invalidated
            // every address the peers had published for us: they kept dialling a port nobody listened
            // on while we listened somewhere else (measured: a message stuck for 101s doing exactly
            // that). With a fixed port a published endpoint stays true, and the tunnel extension knows
            // where to listen while the app is dead.
            if self.useEphemeralPort, let any = try? NWListener(using: params) {
                l = any
            } else if let fixed = NWEndpoint.Port(rawValue: MontanaDirectPort.value),
               let bound = try? NWListener(using: params, on: fixed) {
                l = bound
            } else {
                // The port is taken — most likely by our own tunnel extension standing in for a dead
                // app. Ask it to step aside, then take the port back; only if that fails do we fall
                // back to an ephemeral one.
                MontanaDirectPort.requestRelease()
                Thread.sleep(forTimeInterval: 0.4)
                if let fixed = NWEndpoint.Port(rawValue: MontanaDirectPort.value),
                   let bound = try? NWListener(using: params, on: fixed) {
                    l = bound
                } else {
                    // The port is THE port: every install of this app, on every device, listens on the
                    // same number, and a published address means nothing if it is not that one. Rather
                    // than take a random port and advertise an address nobody can use, the node keeps
                    // asking for its own and stays out of the mesh until it has it.
                    MontanaLog.event("P2P direct: port \(MontanaDirectPort.value) busy — retrying")
                    MontanaP2PTrace.mark("port_busy", "port=\(MontanaDirectPort.value)")
                    self.healListener(mnemonic: mnemonic, retry: self.onReady, after: 3)
                    return
                }
            }
            l.newConnectionHandler = { [weak self] c in self?.acceptInbound(MTWire(c)) }
            l.stateUpdateHandler = { [weak self] st in
                guard let self else { return }
                switch st {
                case .ready:
                    guard let p = l.port?.rawValue, self.port != p else { return }
                    self.port = p; MontanaLog.event("P2P direct listener :\(p)")
                    MontanaP2PTrace.mark("direct_listener", "port=\(p)")
                    self.onReady?(p); self.onReady = nil
                case .waiting(let err), .failed(let err):
                    self.portTries += 1
                    // The port is held by somebody — normally our own tunnel extension standing in
                    // for a dead app. Silence here cost a whole test: a device with no listener
                    // cannot be a node, cannot accept anybody, and said nothing about it.
                    MontanaP2PTrace.mark("direct_listener_blocked", "err=\(err)")
                    MontanaLog.event("P2P direct listener blocked: \(err)")
                    l.cancel(); self.listener = nil; self.started = false; self.port = 0
                    MontanaDirectPort.requestRelease()
                    self.useEphemeralPort = self.portTries >= 3
                    self.healListener(mnemonic: mnemonic, retry: self.onReady, after: 2)
                case .cancelled:
                    // A node without a listener is not a node: it cannot be dialled and accepts nobody.
                    // Before, this state was swallowed whole: the 24.08 measurement on the seventeenth
                    // after a fast restart showed port=0 for half a minute straight and NOT ONE line
                    // about the reason -- the app kept silent about having gone deaf.
                    MontanaP2PTrace.mark("direct_listener_gone", "port=\(MontanaDirectPort.value)")
                    self.listener = nil; self.started = false; self.port = 0
                    self.healListener(mnemonic: mnemonic, retry: self.onReady, after: 2)
                default:
                    // There is no silence on the main path: every other state names itself, and the
                    // next trace will say a name instead of emptiness.
                    MontanaP2PTrace.mark("direct_listener_state", "st=\(st)")
                    return
                }
            }
            l.start(queue: self.q)
            self.listener = l
            self.started = true
            self.startKeepalive()
        }
    }

    /// ONE healing of the listener for all reasons ([I-10]): the port is taken, the listener was
    /// refused, the listener died. Before, every reason started its own deferred retry, and two
    /// retries arriving together raised TWO listeners -- in the 24.08 trace that shows as two
    /// direct_listener lines in a row. The retry is one, and a second call does not double it.
    private var healPending = false
    private func healListener(mnemonic: String, retry: ((UInt16) -> Void)?, after: Double) {
        guard !healPending else { return }
        healPending = true
        q.asyncAfter(deadline: .now() + after) { [weak self] in
            guard let self else { return }
            self.healPending = false
            // SILENT-OK: the listener is already up from another pass -- a retry loses nothing.
            guard self.listener == nil else { return }
            self.started = false
            self.start(mnemonic: mnemonic, onReady: retry ?? { _ in })
        }
    }

    // Keep each live outbound channel warm (every 8s) so it does not drop on idle and the first
    // message after a pause is instant. The frame ([0x02], no separators) is ignored by the receiver.
    private func startKeepalive() {
        guard keepaliveTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + 8, repeating: 8)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            for (_, oc) in self.outbound where oc.sendKey != nil {
                if let ka = MontanaP2PDirect.seal(key: oc.sendKey!, Data([0x02])) { self.sendFrame(oc.nw, ka) }
            }
            self.repairUnnamedOwners()
            self.retireIdleChannels()
        }

        t.resume()
        keepaliveTimer = t
    }

    /// A channel without a NAMED owner is the silent death of everything that goes by mesh: the owner
    /// count gives zero, the path counts as unassembled, and every draft, receipt and resend goes to held.
    /// Letters still arrive by wake (another road), so the person sees exactly one symptom:
    /// the live set is gone -- and no trace of a reason.
    ///
    /// The name comes in reply to ours, and ours might not have left at all: on a cold owner key
    /// (2^20 stretching) the sending branch gave up silently and NEVER retried -- the channel stayed
    /// nameless to its very end. Here the name is asked again while the channel lives: the key is
    /// warmed once aside, attempts are bounded, and an arriving name stops them itself.
    private var ownerWarming = false
    private static let ownerAskMax = 10
    private func repairUnnamedOwners() {
        let unnamed = outbound.values.filter {
            $0.ready && $0.peerOwnerRef == nil && !$0.channelHash.isEmpty && $0.ownerAsks < Self.ownerAskMax
        }
        guard !unnamed.isEmpty else { return }
        guard let owner = ownerSecretWarm() else {
            guard !ownerWarming else { return }
            ownerWarming = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                _ = self?.ownerSecretCached()   // stretching runs aside, the liveness tick does not wait
                self?.q.async { self?.ownerWarming = false }
            }
            return
        }
        for oc in unnamed {
            oc.ownerAsks += 1
            sendNet(oc, MontanaNetMsg.ownerRef,
                    MTPipe.ownerRef(ownerSecret: owner, sharedSecret: Data(oc.channelHash)))
        }
        MontanaP2PTrace.mark("owner_repair", mid: nil, "nameless=\(unnamed.count)")
    }

    // A mesh that opens a channel to every neighbour it meets has to close them too, or a busy room
    // costs battery and memory without carrying anything. A channel that has passed nothing for three
    // minutes is closed, and beyond the cap the least recently used goes first; presence brings it
    // straight back, so the cost of being wrong is one dial.
    private static let maxChannels = 12
    private static let idleSeconds: TimeInterval = 180
    /// The term within which a channel must say hello. ONE value for both decision points: the dial
    /// watchdog breaks the channel when it expires, and by it the channel counts as alive until then.
    private static let handshakeBudget: TimeInterval = 8
    private func retireIdleChannels() {
        let now = Date()
        for (key, oc) in outbound where !oc.isService && now.timeIntervalSince(oc.lastUsed) > Self.idleSeconds {
            MontanaP2PTrace.mark("chan_idle_close", mid: nil, "peer=\(String(key.prefix(10)))")
            oc.closeWhy = "idle"; oc.nw.cancel(); outbound[key] = nil
        }
        let live = outbound.filter { !$0.value.isService }
        guard live.count > Self.maxChannels else { return }
        // Verified contacts are anchors and are evicted last. A plain address table can only pin
        // endpoints it knows nothing about; here an anchor is a person with a post-quantum identity
        // the owner vouched for, so surrounding this device means reaching into a real circle
        // rather than flooding a table.
        let anchors = Set(MontanaOverlayBook.shared.allEntries().map { $0.ref })
        let ordered = live.sorted { a, b in
            let aA = anchors.contains(a.key), bA = anchors.contains(b.key)
            return aA != bA ? (!aA && bA) : a.value.lastUsed < b.value.lastUsed
        }
        for (key, oc) in ordered.prefix(live.count - Self.maxChannels) {
            MontanaP2PTrace.mark("chan_evict", mid: nil, "peer=\(String(key.prefix(10))) anchor=\(anchors.contains(key))")
            oc.closeWhy = "evict"; oc.nw.cancel(); outbound[key] = nil
        }
    }

    // MARK: send a sealed media blob over the same persistent channel (frame kind 0x00 = blob:
    // [0x00][blobId 64 ascii][sealed...]). A letter opens with its own frame byte, so the two
    // kinds are told apart by the byte itself rather than by whether a letter named its sender.
    /// The transcript of a channel with this peer: the value the two sides share and nobody else
    /// holds. A reference of an owner stands on it, so two senders never land on one value.
    func channelSecret(with ref: String) -> Data? {
        guard let oc = outbound[ref], !oc.channelHash.isEmpty else { return nil }
        return Data(oc.channelHash)
    }

    func sendBlob(toRef: String, ip: String, port: UInt16, blobId: String, sealed: Data) {
        guard blobId.count == 64 else { return }
        var frame = Data([0x00]); frame.append(contentsOf: blobId.utf8); frame.append(sealed)
        send(toRef: toRef, ip: ip, port: port, payload: frame, mid: "blob")
    }

    // MARK: send (initiator / sender)
    func send(toRef: String, ip: String, port: UInt16, payload: Data, mid: String = "") {
        q.async {
            if !mid.isEmpty, mid != "blob" {
                let key = toRef + "|" + mid
                // Suppress only a copy of something already on a live channel. The window exists to stop
                // the fan-out writing the same envelope twice down one link; a retry made because the
                // channel has meanwhile come up is a different thing entirely, and holding it back only
                // added delay to a message that was finally deliverable.
                let onWire = self.outbound[toRef]?.sendKey != nil
                if onWire, let at = self.recentSends[key], Date().timeIntervalSince(at) < Self.raceWindow {
                    MontanaP2PTrace.mark("send_dedup", mid: mid, "to=\(String(toRef.prefix(10)))")
                    return
                }
                self.recentSends[key] = Date()
                if self.recentSends.count > 256 {
                    let cutoff = Date().addingTimeInterval(-Self.raceWindow)
                    self.recentSends = self.recentSends.filter { $0.value > cutoff }
                }
            }
            if let oc = self.outbound[toRef] {   // failed/cancelled are removed by the state handler
                // One connection per peer means a dial that is hanging on an address which no longer
                // answers would swallow every send meant for a different one — measured: fifteen
                // seconds of queueing behind a dead IPv6 endpoint while the peer sat on this very LAN.
                // A dial with no session key after two seconds is abandoned in favour of the address
                // the caller is offering now, carrying whatever it had queued.
                // Any connection without a session key after two seconds is stuck, whether or not the
                // caller is offering the same address: a dial that opened and went silent is exactly as
                // useless as one aimed at a dead endpoint, and it was the same slot both times.
                let stuck = oc.sendKey == nil && Date().timeIntervalSince(oc.dialAt) > 2 && !ip.isEmpty
                if !stuck { self.sendOverlayMessage(oc, payload, mid); return }
                MontanaP2PTrace.mark("dial_abandon", mid: mid, "was=\(oc.peerIP):\(oc.peerPort) now=\(ip):\(port)")
                let rescued = oc.pending; oc.pending = []
                oc.closeWhy = "abandon"; oc.nw.cancel(); self.outbound[toRef] = nil
                self.dial(toRef: toRef, ip: ip, port: port, carry: rescued + [(payload, mid)], redials: 0)
                return
            }
            self.dial(toRef: toRef, ip: ip, port: port, carry: [(payload, mid)], redials: 0)
        }
    }

    // Single dialer (SSOT for the outbound direct channel). `carry` = payloads queued for this connection;
    // `redials` bounds the reconnect so a peer that is truly gone cannot cause a dial storm.
    private func dial(toRef: String, ip: String, port: UInt16, carry: [(Data, String)], redials: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let mid = carry.first?.1 ?? ""
        // A LAN address without Wi-Fi is unreachable BY CONSTRUCTION: the required-wifi
        // connection would only wait out its 5s and write a timeout — noise a road that
        // cannot serve has no right to make (the author's word 28.08). One line, no dial.
        if !MontanaTransport.isGlobalIP(ip), !MontanaP2PNode.shared.wifiOn {
            MontanaP2PTrace.mark("dial_skip", mid: mid, "lan-without-wifi ip=\(ip):\(port)")
            return
        }
        // One dial, one mark, and it names the dress: two lines per dial in the 24.08 trace read as
        // two dials, which never happened.
        // A door is dialled above a standing tunnel, bound to the phone's own interface (MontanaNetWitness.physical): a dead
        // tunnel cannot take the nodes away. A dial that fails there turns the door's road to the tunnel (doorRoadAbove).
        let above = MontanaNodes.isNode(ip) && MontanaNetWitness.tunnelPresent() && Self.doorRoadAbove(MontanaNodes.label(forHost: ip))
        let phys = above ? MontanaNetWitness.physical : nil
        MontanaP2PTrace.mark("dial", mid: mid, "ip=\(ip):\(port)"
            + { if case .websocket = MontanaNodes.dress(forHost: ip) { return " dress=wss" }; return "" }()
            + (phys != nil ? " road=above" : (MontanaNodes.isNode(ip) && MontanaNetWitness.tunnelPresent() ? " road=tunnel" : "")))
        let tcpOpts = NWProtocolTCP.Options()
        tcpOpts.enableKeepalive = true; tcpOpts.keepaliveIdle = 10; tcpOpts.keepaliveInterval = 5; tcpOpts.keepaliveCount = 2
        // A node standing on 443 is reached inside an ordinary secure connection, marked from the
        // inside as the node. A tunnel, a mobile operator and a corporate filter all pass what
        // looks like a visit to a website and drop an unusual port — measured on this very phone,
        // where the mesh port timed out while the site opened. Nothing of the protocol changes:
        // the shell is stripped at the front, and the same bytes reach the same node.
        // The door dress is asked of the door list -- that is where it lives ([I-10]).
        let dress = MontanaNodes.dress(forHost: ip)
        if case .websocket(let path) = dress, let u = URL(string: "wss://\(ip):\(port)\(path)") {
            // A door behind a delivery network. The intermediary speaks only web and terminates the
            // protection, so the label is ordinary while our bytes ride inside the rise to the web
            // socket. Above the wire NOTHING changes: the same frame layout, the same post-quantum
            // handshake, the same introduction. The intermediary is a blind pipe: content, identity
            let tls = NWProtocolTLS.Options()
            ip.withCString { sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, $0) }
            let wsParams = NWParameters(tls: tls, tcp: tcpOpts)
            if let phys { wsParams.requiredInterface = phys }
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            wsParams.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            let nw = MTWire(NWConnection(to: .url(u), using: wsParams), webSocket: true)
            self.arm(nw: nw, toRef: toRef, ip: ip, port: port, carry: carry, redials: redials, mid: mid)
            return
        }
        let dialParams: NWParameters
        if port == 443 {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "mt-node")  // WIRE-CONST: the node ALPN; nginx in Moscow accepts mt-node AND mt-door (transition)
            ip.withCString { sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, $0) }
            dialParams = NWParameters(tls: tls, tcp: tcpOpts)
        } else {
            dialParams = NWParameters(tls: nil, tcp: tcpOpts)
        }
        // IFACE-CHECKED: no interface is banned here. The ban stood so that the mesh would not ride
        // through OUR tunnel, and that one was recognised by the 198.18 range -- which other clients
        // occupy too. The measurement named the price outright: with a third-party tunnel on, every
        // connection fell with "Network is down", and the node was left without a network entirely.
        // Where to let a packet out is decided by the system routing; our business is to ask for a
        // connection and hear the answer. A local network address is reachable ONLY over Wi-Fi, and
        //
        // The system chooses the path itself, and on a phone with both networks it is free to send a
        // packet into cellular -- where 192.168.x.x does not exist. From outside that looks like
        // silence: the dial hangs until the term expires, the channel falls, the letter goes over
        // radio and crawls for minutes. The measurement showed exactly this: a tablet accepted a
        // connection from a laptop instantly and not from a phone with cellular lit next to Wi-Fi.
        if !MontanaTransport.isGlobalIP(ip) { dialParams.requiredInterfaceType = .wifi }
        if let phys { dialParams.requiredInterface = phys }
        let nw = MTWire(NWConnection(host: MontanaP2PDirect.dialHost(ip), port: nwPort, using: dialParams))
        self.arm(nw: nw, toRef: toRef, ip: ip, port: port, carry: carry, redials: redials, mid: mid)
    }

    /// Channel outfitting is ONE for every wire dress ([I-10]). The dial decides what the wire is
    /// dressed in and brings a ready connection here; everything after that is identical to the byte
    /// for a bare door and for a door behind a delivery network.
    private func arm(nw: MTWire, toRef: String, ip: String, port: UInt16,
                     carry: [(Data, String)], redials: Int, mid: String) {
        let oc = OutConn(nw)
        oc.dialAt = Date()
        oc.peerIP = ip
        oc.peerPort = port
        oc.doorKey = MontanaNodes.doorKey(host: ip, port: port)
        oc.redials = redials
        // WHAT A CHANNEL IS, IS DECIDED ONCE, AT ITS BIRTH, BY ITS KEY (30.09): an endpoint key names a door
        // -- a node, a request to the network -- and a reference names a person. Every road that dials arms
        // here: the first knock, the forced redial on a network change, the rescue after a drop. While the
        // nature was written on the first road alone, a node channel reborn by the other two came up as a
        // person's channel, every letter it carried armed the ack watchdog, and six seconds later both node
        // channels were cut -- T1 and T3 under the tunnel, after every switch of the network.
        oc.isService = toRef.hasPrefix("ep:")
        oc.peerRefStr = oc.isService ? "" : toRef
        oc.pending.append(contentsOf: carry)
        self.outbound[toRef] = oc
        nw.stateUpdateHandler = { [weak self, weak oc] st in
            guard let self, let oc else { return }
            switch st {
            case .waiting(let err):
                MontanaP2PTrace.mark("dial_waiting", mid: mid, "ip=\(ip):\(port) err=\(err) \(oc.nw.pathStory)")
                if "\(err)".contains("Too many open files") || "\(err)".contains("rawValue: 24)") { MontanaP2PDirect.noteLocalFault("\(err)") }
            case .failed(let err):
                MontanaP2PTrace.mark("dial_failed", mid: mid, "ip=\(ip):\(port) err=\(err) \(oc.nw.pathStory)")
            default:
                break
            }
            switch st {
            case .ready:
                MontanaP2PTrace.mark("tcp_ready", mid: mid, "ms=\(Int(Date().timeIntervalSince(oc.dialAt) * 1000))")
                if !toRef.hasPrefix("ep:") { MontanaOverlayBook.shared.succeeded(ref: toRef, ip: ip, port: port) }
                self.initiatorHandshake(oc)
            case .failed(let err):
                // The drop names its REASON: a bare ip:port told a remote diagnosis nothing
                // about WHY the network fell (the author's rule 23.08 — the network story
                // must be readable from any device).
                MontanaP2PTrace.mark("conn_drop", mid: mid, "ip=\(ip):\(port) err=\(err) \(oc.nw.pathStory)")
                if MontanaNodes.isNode(ip) { MontanaP2PDirect.noteDoorFail(ip: ip, port: port, why: "\(err)") }
                fallthrough
            case .cancelled:
                // OUR OWN CLOSE IS NOT A DROP (23.09, the critic): a channel reaches .cancelled only by a cancel
                // of ours — a lost race, an idle close, a timeout of ours — and the diary wrote it «conn_drop»,
                // 7 503 lines in three days across the fleet, drowning the falls the network really made. It is
                // written as our close now, with the reason the cancelling line gave it.
                if case .cancelled = st { MontanaP2PTrace.mark("conn_closed", mid: mid, "ip=\(ip):\(port) by=us why=\(oc.closeWhy.isEmpty ? "unnamed" : oc.closeWhy)") }
                // The node is held PERMANENTLY: a break of the channel to a node means an immediate
                // reconnect, we do not wait for the five-second tick. An empty channel is restored too.
                if MontanaNodes.isNode(ip) {
                    // An ordinary break goes through a backoff. openNow() here wiped the backoff of
                    // every door at once, and a door whose far side refuses the introduction after the
                    // handshake hammered twice a second forever (24.08 measurement: 967 knocks, not one
                    // "open"), dragging a healthy one into the storm. open() dials a healthy one at
                    // once (success cleared the backoff) and a broken one on a rising scale up to 15 s.
                    // Forcing belongs to the foreground and to a network change only.
                    DispatchQueue.global(qos: .userInitiated).async { MontanaNodes.open() }
                }
                self.dropLive(oc)
                self.recomputeReady()
                MontanaP2PNode.shared.refreshP2PPresence()   // the globe reflects a break at once
                // Only if this very connection is still the peer's current one: a later dial may have
                // already replaced it, and clearing blindly would erase a live channel and leave the
                // index claiming one exists.
                if self.outbound[toRef] === oc { self.outbound[toRef] = nil }
                // A door must answer. Those awaiting an answer held the channel weakly, and when it
                // died no answer came at all -- 782 knocks gave zero "open" and zero "closed", the
                // failure was silent, and the trace could not name a reason. A channel death is an answer too.
                let orphaned = oc.readyWaiters; oc.readyWaiters = []
                for w in orphaned { w(nil) }
                let rescued = oc.pending
                let stillDialable = MontanaP2PNode.shared.wifiOn || MontanaTransport.isGlobalIP(ip)
                if !rescued.isEmpty && redials < 3 && stillDialable {
                    // Bounded reconnect: a transient Wi-Fi/cellular drop must not strand queued messages
                    // until the 90s sweep. Re-dial once more carrying the un-sent payloads (never the
                    // already-wired-unacked ones — those live in sentAtMsg and are the E2E sweep's job).
                    self.q.asyncAfter(deadline: .now() + 0.5) {
                        if let live = self.outbound[toRef] { for (pl, m) in rescued { self.sendOverlayMessage(live, pl, m) } }
                        else { self.dial(toRef: toRef, ip: ip, port: port, carry: rescued, redials: redials + 1) }
                    }
                } else if !rescued.isEmpty, !oc.isService {
                    // Direct route given up (redials exhausted / egress lost): hand the un-sent envelopes
                    // to the BLE mesh — same envelope format — so the failover chain completes without
                    // waiting for the 90s sweep. Delivered-over-BLE refines the glyph via .montanaP2PSent.
                    for (pl, m) in rescued where m != "blob" {
                        if MontanaBLEMesh.shared.send(to: toRef, envelope: pl) {
                            MontanaP2PTrace.mark("bt_tx", mid: m, "fallback")
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .montanaP2PSent, object: nil,
                                                                userInfo: ["address": toRef, "mid": m, "transport": MontanaTransport.bluetooth.rawValue])
                            }
                        }
                    }
                }
            default: break
            }
        }
        nw.start(queue: self.q)
        // A connection that opens and then says nothing used to hang for good: only the dial had a
        // deadline, never the handshake. It kept the peer's one slot, every later send queued into it,
        // and after eight attempts the message was given up on — measured, with the peer sitting on the
        // same Wi-Fi. The channel now has to be usable within this window or it is torn down and the
        // next path gets its turn.
        self.q.asyncAfter(deadline: .now() + Self.handshakeBudget) { [weak oc] in
            guard let oc, oc.sendKey == nil || !oc.ready else { return }
            MontanaP2PTrace.mark("handshake_timeout", mid: mid, "ip=\(ip):\(port) \(oc.nw.pathStory)")
            if MontanaNodes.isNode(ip) { MontanaP2PDirect.noteDoorFail(ip: ip, port: port, why: "handshake-timeout") }
            // A failure while OUR tunnel holds the route is the tunnel's fact, not the address's (see below).
            if !toRef.hasPrefix("ep:"), !MontanaP2PNode.tunnelUp() { MontanaOverlayBook.shared.fail(ref: toRef, ip: ip, port: port) }
            oc.closeWhy = "handshake-timeout"
            oc.nw.cancel()
        }
        // Connect timeout: a stale same-subnet IP (router switch) gives no RST — the TCP SYN hangs
        // ~75s with no state callback, silently stranding the pending queue. 5s without .ready ->
        // cancel; the drop handler then rescues pending and redials / falls back to BLE.
        self.q.asyncAfter(deadline: .now() + 5) { [weak nw, weak oc] in
            guard let nw, nw.state != .ready else { return }
            // THE WHOLE STORY OF A REFUSAL, NOT THE FACT OF IT. A bare "the term expired" does not
            // tell "the name did not resolve" from "the packet left and there is no answer" -- and a
            // remote analysis hits a wall exactly where the work begins (the author's word 23.08:
            // telemetry must show absolutely everything). Here the path tells about itself: state,
            // interfaces, where the connection actually looks and from which address.
            MontanaP2PTrace.mark("dial_timeout", mid: mid, "ip=\(ip):\(port) \(nw.pathStory)")
            // A door that did not connect in five seconds failed on this road: its record and its road under a tunnel say so.
            if MontanaNodes.isNode(ip) { MontanaP2PDirect.noteDoorFail(ip: ip, port: port, why: "connect-timeout") }
            // An address that does not answer is retired rather than dialled again: a port left from
            // the peer's previous launch used to be hammered every few seconds while the peer was
            // listening on a new one. Once it is gone the route falls through to the peer's other
            // endpoints, then to the mesh lookup, then to Bluetooth.
            // NOT WHILE OUR TUNNEL HOLDS THE ROUTE (the critic 23.09, T1 on 1891): a dial made then dies before it
            // leaves («Network is down», the path unsatisfied), and that death says nothing about the address --
            // yet it retired the peer's address for up to eight hours, and the direct road stayed poisoned long
            // after the VPN was off. Only a failure the address itself could have caused retires it.
            if !toRef.hasPrefix("ep:"), !MontanaP2PDirect.localFaultRecent(), !MontanaP2PNode.tunnelUp(),
               MontanaOverlayBook.shared.fail(ref: toRef, ip: ip, port: port) {
                MontanaP2PTrace.mark("endpoint_retired", mid: mid, "peer=\(String(toRef.prefix(10))) \(ip):\(port)")
                DispatchQueue.main.async { MontanaP2PNode.shared.forgetEndpoint(ref: toRef, ip: ip, port: port) }
            }
            oc?.closeWhy = "dial-timeout"
            nw.cancel()
        }
    }

    private func initiatorHandshake(_ oc: OutConn) {
        // Noise_PQ XX (spec §5.0): read responder static KEM pub, then msg1 -> msg2 -> msg3.
        readFrame(oc.nw) { [weak self, weak oc] pk in
            guard let self, let oc, let pk, pk.count == 1184 else { oc?.closeWhy = "noise-key"; oc?.nw.cancel(); return }
            // The seed of a handshake comes from the core: six sources folded, and a refusal when
            // fewer than three are alive. One source is one point of trust.
            var seed = [UInt8](repeating: 0, count: 32)
            guard mt_random_fast(&seed, 32) == 0 else { oc.closeWhy = "noise-seed"; oc.nw.cancel(); return }
            var msg1 = [UInt8](repeating: 0, count: 2272)
            var state: UnsafeMutableRawPointer? = nil
            let rc = [UInt8](pk).withUnsafeBufferPointer { p in seed.withUnsafeBufferPointer { s in
                mt_noise_initiator_msg1(p.baseAddress, s.baseAddress, &msg1, &state) } }
            guard rc == 0, let state1 = state else { oc.closeWhy = "noise-msg1"; oc.nw.cancel(); return }
            self.sendFrame(oc.nw, Data(msg1))
            self.readFrame(oc.nw) { [weak self, weak oc] msg2 in
                guard let self, let oc, let msg2, msg2.count == 6349 else { mt_noise_state_free_initiator1(state1); oc?.closeWhy = "noise-msg2"; oc?.nw.cancel(); return }
                var state2p: UnsafeMutableRawPointer? = nil
                var state1p: UnsafeMutableRawPointer? = state1
                let rc2 = [UInt8](msg2).withUnsafeBufferPointer { m in mt_noise_initiator_msg2(&state1p, m.baseAddress, &state2p) }
                guard rc2 == 0, let state2 = state2p else { oc.closeWhy = "noise-msg2-open"; oc.nw.cancel(); return }   // the core consumes state1 and nils it
                var msg3 = [UInt8](repeating: 0, count: 5261)
                var ski2r = [UInt8](repeating: 0, count: 32)
                var skr2i = [UInt8](repeating: 0, count: 32)
                var ch = [UInt8](repeating: 0, count: 32)
                var state2p2: UnsafeMutableRawPointer? = state2
                let rc3 = mt_noise_initiator_msg3(&state2p2, &msg3, &ski2r, &skr2i, &ch)
                guard rc3 == 0 else { oc.closeWhy = "noise-msg3"; oc.nw.cancel(); return }   // the core consumes state2 and nils it
                self.sendFrame(oc.nw, Data(msg3))
                oc.sendKey = ski2r; oc.recvKey = skr2i; oc.channelHash = ch; oc.isDialer = true
                MontanaP2PTrace.mark("noise_done", mid: nil, "ms=\(Int(Date().timeIntervalSince(oc.dialAt) * 1000))")
                self.startRegistration(oc)
            }
        }
    }

    // Registration (§5.3) + OverlayFrame (§5.2) inside the Noise_PQ stream. Both peers register their
    // overlay identity to each other (symmetric, order-independent), then messages flow as
    // NetMessage{OVERLAY_FRAME, OverlayFrame{RELAY, dst, src, msg_id, payload}}.
    private func startRegistration(_ oc: OutConn) {
        guard let ident = self.ident else { oc.closeWhy = "no-identity"; oc.nw.cancel(); return }
        oc.myOverlayTag = ident.tag
        var body = Data(ident.authPk); body.append(ident.tag)   // overlay_auth_pub 1952 || overlay_addr 32
        sendNet(oc, MontanaNetMsg.registerInit, body)
        protoLoop(oc)
    }
    private func sendNet(_ oc: OutConn, _ type: UInt8, _ body: Data) {
        guard let key = oc.sendKey, let sealed = MontanaP2PDirect.seal(key: key, MontanaNetMsg.encode(type, body)) else { return }
        sendFrame(oc.nw, sealed)
    }
    private func protoLoop(_ oc: OutConn) {
        readFrame(oc.nw) { [weak self, weak oc] frame in
            guard let self, let oc else { return }
            guard let frame else {
                // A cancel of ours ends the read as well, and its reason stands: the ack watchdog's cut
                // was rewritten here as the peer's close, and the diary blamed the nodes (30.09).
                guard oc.closeWhy.isEmpty else { return }
                // The peer closed the channel. Before, this drowned in a common cancel and the trace
                // lied "cancelled" without a reason -- a far-side refusal of the introduction (24.08:
                // death one round after the first introduction frame) had to be inferred indirectly.
                MontanaP2PTrace.mark("chan_peer_close", mid: nil,
                    "ip=\(oc.peerIP):\(oc.peerPort) ready=\(oc.ready ? 1 : 0) reg=\(oc.myRegConfirmed ? 1 : 0)\(oc.peerRegConfirmed ? 1 : 0)")
                oc.closeWhy = "peer-closed"; oc.nw.cancel(); return
            }
            guard let key = oc.recvKey, let plain = MontanaP2PDirect.open(key: key, frame) else {
                MontanaP2PTrace.mark("chan_bad_frame", mid: nil, "ip=\(oc.peerIP):\(oc.peerPort) bytes=\(frame.count)")
                oc.closeWhy = "bad-frame"; oc.nw.cancel(); return
            }
            if plain.count == 1, plain.first == 0x02 { self.protoLoop(oc); return }   // keepalive
            if let (type, body) = MontanaNetMsg.decode(plain) { self.dispatchNet(oc, type, body) }
            self.protoLoop(oc)
        }
    }
    private func dispatchNet(_ oc: OutConn, _ type: UInt8, _ body: Data) {
        switch type {
        case MontanaNetMsg.registerInit:
            guard body.count == 1984 else { return }   // 1952 + 32
            let authPub = body.subdata(in: body.startIndex..<body.index(body.startIndex, offsetBy: 1952))
            let tag = body.subdata(in: body.index(body.startIndex, offsetBy: 1952)..<body.endIndex)
            guard MontanaOverlayKey.tag(fromAuthPub: [UInt8](authPub)) == tag else { return }   // §3.3 binding
            oc.peerAuthPub = authPub; oc.peerOverlay = tag
            // The challenge lives the whole handshake and goes inside a signature: it is drawn from
            // the gathered source, not the one-frame one, and a refusal to gather refuses the peer.
            var nonce = [UInt8](repeating: 0, count: 16)
            guard mt_random_fast(&nonce, 16) == 0 else { oc.closeWhy = "no-nonce"; oc.nw.cancel(); return }
            oc.challengeNonce = Data(nonce)
            sendNet(oc, MontanaNetMsg.registerChallenge, Data(nonce))
        case MontanaNetMsg.registerChallenge:
            guard body.count == 16, let ident = self.ident,
                  let sig = MontanaOverlayProof.sign(authSk: ident.authSk, opDomain: "mt-reg", resourceId: ident.tag, nonce: body, channelHash: Data(oc.channelHash)) else { return }
            sendNet(oc, MontanaNetMsg.registerProof, sig)
        case MontanaNetMsg.registerProof:
            guard body.count == 3309, let authPub = oc.peerAuthPub, let tag = oc.peerOverlay, let nonce = oc.challengeNonce,
                  MontanaOverlayProof.verify(authPub: authPub, sig: body, opDomain: "mt-reg", resourceId: tag, nonce: nonce, channelHash: Data(oc.channelHash)) else {
                sendNet(oc, MontanaNetMsg.registerResult, Data([0x01])); return
            }
            oc.peerRegConfirmed = true
            sendNet(oc, MontanaNetMsg.registerResult, Data([0x00]))
            maybeReady(oc)
        case MontanaNetMsg.registerResult:
            if body.first == 0x00 { oc.myRegConfirmed = true; maybeReady(oc) }
        case MontanaNetMsg.ownerRef:
            // The neighbour named its owner. Accepted once and only from the neighbour itself; ours,
            // computed on its behalf, will not do -- it would count machines, while owners are protected.
            guard body.count == 16, oc.peerOwnerRef == nil else { return }
            oc.peerOwnerRef = body
            noteOwnerRef(cid: oc.cid, owner: body, ref: oc.peerRefStr, isService: oc.isService)
            MontanaP2PTrace.mark("owner_ref", mid: nil,
                                 "peer=\(oc.peerOverlay.map { MontanaOverlayBook.hex($0) } ?? "")")
        case MontanaNetMsg.overlayFrame:
            if let of = MontanaOverlayFrame.decode(body) { handleOverlayFrame(oc, of) }
        case MontanaNATMsg.endpointRep:
            // RPC replies: hand to the waiter that asked (FIFO — TCP preserves request order per channel).
            if type == MontanaNATMsg.endpointRep {
                _ = MontanaNATService.shared.handle(type: type, body: body, peerOverlay: oc.peerOverlay,
                                                   peerIP: oc.peerIP, peerPort: oc.peerPort)
            }
            if var fifo = oc.netWaiters[type], !fifo.isEmpty {
                let w = fifo.removeFirst(); oc.netWaiters[type] = fifo; w.cb(body)
            }
        case MontanaNATMsg.endpointReq, MontanaNATMsg.punchReq, MontanaNATMsg.punchInfo, MontanaNATMsg.relayData:
            if let (rt, rb) = MontanaNATService.shared.handle(type: type, body: body, peerOverlay: oc.peerOverlay,
                                                             peerIP: oc.peerIP, peerPort: oc.peerPort) { sendNet(oc, rt, rb) }
        default: break
        }
    }
    private var cachedOwnerSecret: Data?
    private let ownerLock = NSLock()
    func ownerSecretWarm() -> Data? { ownerLock.lock(); defer { ownerLock.unlock() }; return cachedOwnerSecret }
    func ownerSecretCached() -> Data? {
        ownerLock.lock(); defer { ownerLock.unlock() }
        if let c = cachedOwnerSecret { return c }
        guard let mn = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(mn),
              let owner = MTPipe.ownerSecret(masterSeed: master) else { return nil }
        cachedOwnerSecret = owner
        return owner
    }

    private func maybeReady(_ oc: OutConn) {
        guard oc.ready, !oc.flushed else { return }
        oc.flushed = true
        MontanaP2PTrace.mark("reg_ready", mid: nil, "peer=\(oc.peerOverlay.map { $0.prefix(4).map { String(format: "%02x", $0) }.joined() } ?? "")")
        // The globe and presence go FIRST, before everything else: onChannelUp waits for neither
        onChannelUp(oc)
        // ownerRef MUST leave BEFORE accumulated messages (otherwise the node does not know the owner
        // -> transit does not assemble -> ack_timeout). From a warm cache, synchronously; on a cold
        // one (the first channel) PBKDF2 runs in the background, then on queue q: ownerRef, THEN the
        // accumulated flush. The ownerRef->pending order holds; the hot globe path is not blocked.
        let ch = oc.channelHash
        if ch.isEmpty { drainPending(oc); return }
        if let owner = ownerSecretWarm() {
            sendNet(oc, MontanaNetMsg.ownerRef, MTPipe.ownerRef(ownerSecret: owner, sharedSecret: Data(ch)))
            drainPending(oc)
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self, oc] in
                guard let self else { return }
                guard let owner = self.ownerSecretCached() else { self.q.async { self.drainPending(oc) }; return }
                let ref = MTPipe.ownerRef(ownerSecret: owner, sharedSecret: Data(ch))
                self.q.async { self.sendNet(oc, MontanaNetMsg.ownerRef, ref); self.drainPending(oc) }
            }
        }
    }

    private func drainPending(_ oc: OutConn) {
        let queued = oc.pending; oc.pending = []
        for (pl, m) in queued { self.sendOverlayMessage(oc, pl, m) }
    }

    // Every established channel is also a mesh peer: bind its three names in the SSOT book, seed the
    // DHT routing table, exchange signed endpoint records, and ask what external address it sees me at.
    private func onChannelUp(_ oc: OutConn) {
        guard let peer = oc.peerOverlay else { return }
        idxLock.lock()
        let ms = Int(Date().timeIntervalSince(oc.dialAt) * 1000)
        liveIndex[oc.cid] = LiveChannel(overlay: peer, ref: oc.peerRefStr, ip: oc.peerIP,
                                        port: oc.peerPort, pathKey: oc.doorKey, door: oc.isDialer, ms: ms)
        let rows = Array(liveIndex.values)
        let paths = Self.doorsHeld(rows).count
        idxLock.unlock()
        if oc.isDialer {
            MontanaP2PTrace.mark("path_up", "at=\(oc.doorKey) ms=\(ms) paths=\(paths)")
            MontanaWakeDoor.note("node")   // the wake's verdict learns the first door that answered
            Self.noteDoorOK(label: oc.doorKey)   // the door answered — its record says so (15.29)
            // The door named its node -- this knowledge outlives the channel, otherwise the probing
            // repeats on every opening and the race returns out of nowhere.
            MontanaNodes.remember(door: oc.doorKey, overlay: peer, ms: ms)
            // An extra path to an already held node is closed AT ONCE: one machine, one channel.
            for f in Self.foldedDoors(rows) {
                MontanaP2PTrace.mark("path_fold", "at=\(f.pathKey) ms=\(f.ms)")
                if let o = self.outbound["ep:\(f.ip):\(f.port)"] { o.closeWhy = "fold"; o.nw.cancel() }
            }
        }
        if !oc.peerRefStr.isEmpty, !oc.peerRefStr.hasPrefix("ep:") {
            MontanaOverlayBook.shared.bind(ref: oc.peerRefStr, overlay: peer, authPub: oc.peerAuthPub)
            if oc.peerPort > 0 { MontanaOverlayBook.shared.learn(ref: oc.peerRefStr, ip: oc.peerIP, port: oc.peerPort, source: "wire") }
        }
        let waiters = oc.readyWaiters; oc.readyWaiters = []
        for w in waiters { w(oc) }
        // The globe turns green AT THE MOMENT of connection: presence is recomputed as soon as the
        // channel is ready, not on a five-second tick -- it is plain to see that the link stood up.
        MontanaP2PNode.shared.refreshP2PPresence()
        // The channel stood up -- that is reachability, and the queue must drain now, not on the next
        // tick. While the event was missing, the first attempt almost always fell for nothing (the
        // channel was still greeting), and a letter waited twenty seconds with a live neighbour.
        if !oc.peerRefStr.isEmpty, !oc.peerRefStr.hasPrefix("ep:") {
            let ref = oc.peerRefStr
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .montanaP2PPeerUp, object: nil, userInfo: ["address": ref])
            }
        }
        MontanaNATService.shared.requestObservedEndpoint(from: peer)
    }
    private func sendOverlayMessage(_ oc: OutConn, _ payload: Data, _ mid: String, to overlay: Data? = nil,
                                    frameId: Data? = nil) {
        // A frame is addressed to a neighbour by its POSITION in this window. The machine claim does
        // not go onto the wire: a constant crossing the path is a direct correlator -- two
        // observations of one value join the ends without breaking anything.
        guard oc.ready, let key = oc.sendKey,
              let dst = overlay ?? oc.peerOverlay.map({ MontanaWindowPos.of($0, MTPipe.window()) })
        else { oc.pending.append((payload, mid)); return }
        // The identifier belongs to the LETTER, not to a copy. While every copy drew its own,
        // network-wide repeat filtering was impossible by construction: one envelope sent to three
        // nodes looked like three different frames and multiplied at each.
        var msgId = frameId ?? Data(count: 16)
        if frameId == nil {
            _ = msgId.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
        }
        if originated.count > Self.frameMemory { originated.removeAll() }
        originated.insert(msgId)
        let of = MontanaOverlayFrame(type: MontanaOverlayFrame.relay, dst: dst, msgId: msgId, payload: payload)
        guard let sealed = MontanaP2PDirect.seal(key: key, MontanaNetMsg.encode(MontanaNetMsg.overlayFrame, of.encode())) else { return }
        // ONLY THE ADDRESSEE'S ACK CAN COME BACK (30.09): it answers down the channel the frame came in on and
        // addresses nobody, so it never crosses a relay. A frame led on by a carrier -- transit, a pipe label
        // laid before the nodes -- is therefore not awaited: waiting for it cut a healthy carrier six seconds
        // later, and on a carrier that lives it would fill this table without end.
        if overlay == nil { oc.sentAtMsg[msgId] = Date() }
        oc.lastUsed = Date()
        // ONE LETTER, TWO ROADS — and until the door was named the two departures were
        // indistinguishable lines, read as a duplicate. A repeat that names its road is a fact; a
        // repeat that names nothing is noise ([I-10]: the line must measure what it calls itself).
        MontanaP2PTrace.mark("of_send", mid: mid, "bytes=\(sealed.count) via=\(overlay == nil ? "direct" : "transit") ep=\(oc.peerIP)*\(oc.peerPort)")
        sendFrame(oc.nw, sealed) { [weak self, weak oc] in
            MontanaP2PTrace.mark("wire_sent", mid: mid, "dir=out ep=\(oc?.peerIP ?? "")*\(oc?.peerPort ?? 0)")
            guard let self, let oc else { return }
            if !mid.isEmpty, mid != "blob", !oc.peerRefStr.isEmpty {
                // Bubble glyph = the wire's ACTUAL physical medium (same classifier as the receive
                // side), refining the flag-based pre-tag on Wi-Fi-Assist / dual-interface edges.
                let tr = MontanaTransport.delivery(cellularEgress: Self.usesCellular(oc.nw))
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .montanaP2PSent, object: nil,
                                                    userInfo: ["address": oc.peerRefStr, "mid": mid, "transport": tr.rawValue])
                }
                // Ack watchdog: a half-open TCP (peer app suspended, AP power-save) fires no state
                // callback; without the overlay ack in 6s the channel is declared dead so the drop
                // handler can rescue pending and redial. Blobs are exempt (large frames on weak links).
                guard overlay == nil else { return }   // a frame led on by a carrier is not awaited (above)
                self.q.asyncAfter(deadline: .now() + 6) { [weak oc] in
                    guard let oc, oc.sentAtMsg[msgId] != nil else { return }
                    MontanaP2PTrace.mark("ack_timeout", mid: mid)
                    oc.closeWhy = "ack-timeout"
                    oc.nw.cancel()
                }
            }
        }
    }
    /// Hand a frame to peers that are NOT the destination, so one of them forwards it (§2.3 role 3,
    /// §5.3). This is the only way two devices that cannot be dialled — two phones on cellular — reach
    /// each other: both hold an outbound channel to a third device, and that device passes the sealed
    /// frame across. It reads nothing: the payload is E2E, and the relay decides on `dst` alone.
    /// Returns true when at least one peer took the frame.
    @discardableResult
    func sendVia(dstOverlay: Data, payload: Data, mid: String, max: Int = 2) -> Bool {
        guard dstOverlay.count == 32 else { return false }
        let target = MontanaWindowPos.of(dstOverlay, MTPipe.window())
        let fid = MontanaP2PDirect.newFrameId()
        // WHETHER THERE IS A CARRIER IS ANSWERED BY THE LEDGER, NOT BY THE QUEUE. This is called
        // from the main thread on every letter; a wait on the network queue froze the app for as
        // long as that queue was busy. The ledger of standing channels is the same one the globe
        // reads, and the writing itself goes on the queue that owns the sockets.
        idxLock.lock()
        let carriers = liveIndex.values.filter { $0.overlay != dstOverlay }.count
        idxLock.unlock()
        guard carriers > 0 else { return false }
        q.async { [self] in
            var used = 0
            for (_, c) in outbound where c.ready && c.peerOverlay != nil && c.peerOverlay != dstOverlay && used < max {
                sendOverlayMessage(c, payload, mid, to: target, frameId: fid); used += 1
            }
            for (_, c) in inbound where c.ready && c.peerOverlay != nil && c.peerOverlay != dstOverlay && used < max {
                sendOverlayMessage(c, payload, mid, to: target, frameId: fid); used += 1
            }
            if used > 0 { MontanaP2PTrace.mark("of_transit_tx", mid: mid, "hops=\(used) dst=\(MontanaOverlayBook.hex(dstOverlay))") }
        }
        return true
    }

    /// Put an envelope onto the local network under its pipe label.
    ///
    /// The peer address does not exist -- the set abolishes it -- so "dialling them" is impossible in
    /// principle. The envelope is laid before ALL reachable nodes under the pipe label: whoever holds
    /// it opens it; whoever does not carries it on. Radio already works exactly so, and exactly this
    /// the wire lacked: I wrote the envelope into a neighbour channel as if to an addressee, and the
    @discardableResult
    func sendUnderTag(_ tag: Data, payload: Data, mid: String) -> Bool {
        guard tag.count == 16 else { return false }
        var dst = tag; dst.append(Data(count: 16))   // the pipe label in the target field, padded to thirty-two
        let fid = MontanaP2PDirect.newFrameId()
        // The same rule as for transit: the ledger answers «is there anyone to carry it», the
        // queue does the carrying. A person's send must never wait on the network queue.
        idxLock.lock(); let carriers = liveIndex.count; idxLock.unlock()
        guard carriers > 0 else { return false }
        q.async { [self] in
            var used = 0
            for (_, c) in outbound where c.ready { sendOverlayMessage(c, payload, mid, to: dst, frameId: fid); used += 1 }
            for (_, c) in inbound where c.ready { sendOverlayMessage(c, payload, mid, to: dst, frameId: fid); used += 1 }
            if used > 0 { MontanaP2PTrace.mark("near_tx", mid: mid, "nodes=\(used) tag=\(tag.prefix(4).map { String(format: "%02x", $0) }.joined())") }
        }
        return true
    }

    /// The identifier of one frame. One place, because whether it is one per letter or one per copy
    /// decides whether repeat filtering works at all.
    static func newFrameId() -> Data {
        var id = Data(count: 16)
        _ = id.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
        return id
    }

    private let ofRxRecent = MTRecentIds(cap: 512)
    private func handleOverlayFrame(_ oc: OutConn, _ of: MontanaOverlayFrame) {
        oc.lastUsed = Date()
        // Every frame that arrives says so, before any decision about it is taken. Without this a
        // frame matching no branch left no trace at all, and the search had nothing to read.
        // THE SECOND DOOR'S COPY IS A COUNT (29.09): every frame comes by two doors, and the copy was a whole line -- one
        // of every twelve lines of the trace. The first sight is written whole; the copies of a window, one line per door.
        if ofRxRecent.firstSight(of.msgId) {
            MontanaP2PTrace.mark("of_rx", mid: nil,
                                 "type=\(of.type) dst=\(MontanaOverlayBook.hex(of.dst)) "
                                 + "id=\(MontanaOverlayBook.hex(of.msgId)) bytes=\(of.payload.count) from=\(oc.peerIP)")
        } else {
            MontanaP2PTrace.markFolded("of_rx", "copy from=\(oc.peerIP)", window: 10, key: "copy:" + oc.peerIP)
        }
        if of.type == MontanaOverlayFrame.ack {
            if let t = oc.sentAtMsg.removeValue(forKey: of.msgId) {
                MontanaP2PTrace.mark("e2e_ack", mid: nil, "rtt_ms=\(Int(Date().timeIntervalSince(t) * 1000))")
            }
            return
        }
        // Our own frame came back. An envelope is laid before several nodes at once, they carry it on,
        // and one of the copies returns to whoever wrote it -- and the pipe label matches for them, so
        // they would accept their own letter as incoming FROM THE PEER. One identifier per letter is
        // enough to recognise one's own hand.
        if originated.contains(of.msgId) { MontanaP2PTrace.mark("of_own_back"); return }
        // A frame that arrives through both doors is ordinary — two roads, one letter. The FACT
        // is worth knowing, the hundred repetitions are not: a count, not a page.
        if seenFrames.contains(of.msgId) { MontanaP2PTrace.markFolded("of_dup", "", window: 60); return }
        // A repeat is neither carried on nor opened twice. The filter stands BEFORE the carrying
        // branch: while it stood after it, a node resent one and the same frame as many times as it
        // heard it, and a letter in a room of three machines multiplied by itself.
        if seenFrames.count > Self.frameMemory { seenFrames.removeAll() }   // 5.3 sliding window
        seenFrames.insert(of.msgId)
        // A frame is mine when it is addressed to MY position in one of the accepted windows. The
        // machine claim no longer appears on the wire at all.
        let mine = MontanaWindowPos.mine(oc.myOverlayTag)
        // The target is either my window position or MY pipe label: an envelope under the label is
        // mine whoever brought it, and that is the only way to receive a letter without having an
        // address. There are TWO labels -- the pipe and the first-contact point -- and they are asked
        // in one question: radio asked both, the wire only the first, and nobody recognised a first letter on the wire.
        let tag16 = Data(of.dst.prefix(16))
        let underTag = of.dst.suffix(16).allSatisfy { $0 == 0 }
        let addressed = underTag ? MTPipeBook.addressed(byTag: tag16) : nil
        switch addressed {
        case .pipe(let c)?:
            MontanaP2PTrace.mark("of_mine", mid: nil, "by=pipe conv=\(String(c.prefix(10)))")
        case .firstContact(let r)?:
            MontanaP2PTrace.mark("of_mine", mid: nil, "by=first-point card=\(MontanaMeetBook.fp(r.base64urlNoPad))")
        case nil:
            break
        }
        if false { }
        else if mine.contains(of.dst) { MontanaP2PTrace.mark("of_mine", mid: nil, "by=window-pos") }
        if !mine.contains(of.dst), addressed == nil {
            // The frame goes on -- to the neighbour whose claim stands CLOSEST to the target in the
            // same order. So the set commands, and so the step converges: every hop halves the
            // distance, and the path comes out as a logarithm of the population. Here stood "pass it
            // on only if the next one IS the recipient" -- that is not a hop but a last mile: a frame
            // two hops from its target died at the first node, and a net of three machines carried nothing.
            //
            // A node knows the claims of those it spoke with, so the step needs neither map nor directory.
            guard of.dst.count == 32 else { return }
            // An envelope under a foreign label: I carry it on to everyone but the one who brought it.
            // A repeat is free -- filtering by frame identifier stands at every node. So radio carries, and so the wire.
            if underTag {
                // A near frame stays near. It arrived by a near transport -- the local network -- and
                // to carry it into the internet means sending a letter into a network without a path
                // and without a single hop seal, that is, exactly what the set forbids a sender. A
                // neighbour an envelope is not meant for carries it to NEIGHBOURS, not outward.
                let near = !MontanaTransport.isGlobalIP(oc.peerIP)
                var carried = 0
                for c in self.liveChannels()
                where c.overlay != oc.peerOverlay && (!near || !MontanaTransport.isGlobalIP(c.ip)) {
                    _ = self.sendNet(toOverlay: c.overlay, type: MontanaNetMsg.overlayFrame, body: of.encode())
                    carried += 1
                }
                MontanaP2PTrace.markChanged("near_carry", "on=\(carried) near=\(near) dst=\(of.dst.prefix(4).map { String(format: "%02x", $0) }.joined())", every: 300, key: of.dst.prefix(4).map { String(format: "%02x", $0) }.joined())
                return
            }
            // The last step: the neighbour whose position in this window is the target itself.
            let w0 = MTPipe.window()
            if let last = self.liveChannels().first(where: { MontanaWindowPos.of($0.overlay, w0) == of.dst }) {
                _ = self.sendNet(toOverlay: last.overlay, type: MontanaNetMsg.overlayFrame, body: of.encode())
                MontanaP2PTrace.mark("of_relay", mid: nil, "pos=\(MontanaOverlayBook.hex(of.dst)) hop=last")
                return
            }
            // The nearest neighbour is strictly nearer than we are: otherwise the frame would return
            // where it came from and walk in a circle. None found -- the path ends here, and it is said aloud.
            let w = MTPipe.window()
            let myPos = MontanaWindowPos.of(oc.myOverlayTag, w)
            let myDist = MontanaP2PDirect.distance(myPos, of.dst)
            var best: (Data, Data)? = nil   // (neighbour overlay, distance in the window space)
            for c in self.liveChannels() {
                let pos = MontanaWindowPos.of(c.overlay, w)
                let d = MontanaP2PDirect.distance(pos, of.dst)
                if d.lexicographicallyPrecedes(myDist), best == nil || d.lexicographicallyPrecedes(best!.1) {
                    best = (c.overlay, d)
                }
            }
            if let (next, _) = best {
                _ = self.sendNet(toOverlay: next, type: MontanaNetMsg.overlayFrame, body: of.encode())
                MontanaP2PTrace.mark("of_relay", mid: nil,
                                     "dst=\(MontanaOverlayBook.hex(of.dst)) via=\(MontanaOverlayBook.hex(next))")
            } else {
                MontanaP2PTrace.mark("of_relay_drop", mid: nil,
                                     "dst=\(MontanaOverlayBook.hex(of.dst)) -- nobody is nearer than us")
            }
            return   // 5.4: a node leads a frame by its target and by nothing else
        }
        if let key = oc.sendKey {
            // An acknowledgement travels back down the channel it came in on, so it addresses
            // nobody: the type is read before the target is ever looked at.
            let ackF = MontanaOverlayFrame(type: MontanaOverlayFrame.ack, dst: Data(count: 32), msgId: of.msgId, payload: Data())
            if let sealed = MontanaP2PDirect.seal(key: key, MontanaNetMsg.encode(MontanaNetMsg.overlayFrame, ackF.encode())) { sendFrame(oc.nw, sealed) }
        }
        let plain = of.payload
        if plain.first == 0x00, plain.count > 65 {
            let idData = plain[plain.index(plain.startIndex, offsetBy: 1)..<plain.index(plain.startIndex, offsetBy: 65)]
            let sealed = plain[plain.index(plain.startIndex, offsetBy: 65)...]
            if let blobId = String(data: idData, encoding: .utf8) {
                // A wake says outright that it is one: a frame recognised by its length alone would
                // swallow any piece that happened to be that long.
                if let w = MontanaWake.readInline(Data(sealed)) {
                    MontanaP2PTrace.mark("wake_rx", mid: nil, "window=\(w.window)")
                    MontanaDeliveryEngine.shared.drainAll()
                    return
                }
                // A point of rendezvous: somebody is standing at the value both sides compute for
                // this window. Answering it is looking at what waits — the same answer a wake gets.
                if let r = MontanaWake.readPoint(Data(sealed)) {
                    MontanaP2PTrace.mark("rendezvous_rx", mid: nil,
                                         "point=\(r.point.prefix(4).map { String(format: "%02x", $0) }.joined()) window=\(r.window)")
                    MontanaDeliveryEngine.shared.drainAll()
                    NotificationCenter.default.post(name: .montanaP2PPeerUp, object: nil,
                                                    userInfo: ["address": oc.peerRefStr])
                    return
                }
                if MontanaArchive.absorb(Data(sealed)) { return }   // a block of this person's own history
                MontanaBlobStore.put(blobId, Data(sealed))
                MontanaP2PTrace.mark("blob_rx", mid: nil, "id=\(String(blobId.prefix(8))) bytes=\(sealed.count)")
            }
        } else if let opening = MontanaP2PNode.parseFirstEnvelope(plain) {
            // The pipe already stands -- so the letter is ordinary, however it may be wrapped.
            //
            // A sender puts a letter into a first-contact envelope until the other side answers with
            // an ordinary letter. If their card is spent, the ciphertext does not open, no answer ever
            // comes, and the circle closes: eleven letters in a row went to refusal while BOTH SIDES
            // HELD THE SHARED SECRET -- the frame label matched the pipe. So the label is older than
            // the envelope: matched, we open the body with the pipe secret, and the door it lands at
            // (MontanaDeliveryEngine.receive) counts the ciphertext as having done its work.
            var pipeConv: String? = nil
            var firstRoot: Data? = nil
            if case .pipe(let c)? = addressed { pipeConv = c }
            if case .firstContact(let r)? = addressed { firstRoot = r }
            if let conv = pipeConv, let (mid, text, snm, sgl, qt, qm, lp) = MontanaP2PNode.openBody(opening.sealed, conv: conv) {
                let tr = MontanaTransport.delivery(cellularEgress: MontanaP2PDirect.usesCellular(oc.nw)).rawValue
                MontanaP2PTrace.mark("open", mid: mid,
                                     "dir=in kind=\(MontanaNotify.kind(for: text)) via=\(tr) from=\(String(conv.prefix(10))) by=pipe-over-first")
                DispatchQueue.main.async {
                    var ui: [String: Any] = ["from": conv, "mid": mid, "text": text, "transport": tr]
                    if let n = snm { ui["senderName"] = n }
                    if let g = sgl { ui["senderGlyph"] = g }
                    if let q = qt, !q.isEmpty { ui["quoteText"] = q }
                    if let m = qm, !m.isEmpty { ui["quoteMid"] = m }
                    if let l = lp, !l.isEmpty { ui["linkPreview"] = l }
                    NotificationCenter.default.post(name: .montanaP2PIncoming, object: nil, userInfo: ui)
                }
                return
            }
            // Somebody wrote first. Which correspondence this is follows from the ciphertext — only
            // its holder can open it — and from nothing the letter says about itself.
            guard let ref = MontanaP2PNode.openFirst(opening.ciphertext, sealed: opening.sealed, at: firstRoot) else {
                // The refusal is said ALOUD. Written only to the log, it read as «nothing arrived»,
                // and two rounds of searching went past the one fact that mattered: the letter is
                // here and this device holds no key to the acquaintance it claims.
                MontanaP2PTrace.mark("first_refused", mid: nil,
                                     "bytes=\(opening.sealed.count) from=\(oc.peerIP) -- there is no card here for this introduction")
                MontanaLog.event("P2P ✗ a first letter this device cannot open — refused")
                return
            }
            // The body of a first letter is sealed with the same secret that has just come out of the
            // ciphertext. It did not open -- the letter is not from the one it pretends to be.
            guard let (mid, text, snm, sgl, qt, qm, lp) = MontanaP2PNode.openBody(opening.sealed, conv: ref) else {
                MontanaP2PTrace.mark("open_refused", mid: nil, "the first letter seal did not match")
                return
            }
            // A letter BROUGHT by a carrier names neither the channel nor the sender machine -- and
            // cannot: the sender address is not in the envelope by construction. Here stood the
            // opposite, and it broke the answer dead. Measured (cellular, two handsets, one node):
            //   16:48:33.204 of_rx  from=montana.quest      -- the node brought the first letter
            //   16:48:33.227 meet_accept                    -- the introduction opened, the node channel
            //                                                 got the label of THIS conversation
            //   16:48:33.237 held owners=0/1 named=0 nodes=1 -- and from that instant the node
            //                                                 stopped counting as an owner in the
            //                                                 path: it "is the peer", hence excluded
            // By the same movement the peer link was bound to the NODE overlay, and the second path --
            // through a carrier -- died together with the first. From outside that looked like "it does
            // not work over cellular": incoming went, outgoing hung forever.
            //
            // A service channel (a node, a request to the network) is a carrier by construction, and it
            // carries no conversation label. A direct link, where the peer dialled US, remains: there
            // the channel really is with them, and knowing their overlay is the only way to answer directly.
            if !oc.isService {
                if oc.peerRefStr.isEmpty {
                    oc.peerRefStr = ref
                    renameOwnerRow(cid: oc.cid, ref: ref)   // the owner ledger reads the name too — the peer's own channel never counts as a carrier
                }
                if let peer = oc.peerOverlay {
                    MontanaOverlayBook.shared.bind(ref: ref, overlay: peer, authPub: oc.peerAuthPub)
                }
            }
            MontanaLog.event("P2P first letter OPENED mid=\(String(mid.prefix(8)))")
            let tr = MontanaTransport.delivery(cellularEgress: MontanaP2PDirect.usesCellular(oc.nw)).rawValue
            DispatchQueue.main.async {
                var ui: [String: Any] = ["from": ref, "mid": mid, "text": text, "transport": tr]
                if let n = snm { ui["senderName"] = n }
                if let g = sgl { ui["senderGlyph"] = g }
                    if let q = qt, !q.isEmpty { ui["quoteText"] = q }
                    if let m = qm, !m.isEmpty { ui["quoteMid"] = m }
                    if let l = lp, !l.isEmpty { ui["linkPreview"] = l }
                NotificationCenter.default.post(name: .montanaP2PIncoming, object: nil, userInfo: ui)
            }
        } else if let (tag, sealed) = MontanaP2PNode.parseEnvelope(plain) {
            // A conversation is named by the LETTER LABEL, not by the channel it arrived on. While the
            // channel named it, a letter through an intermediary landed in a conversation with the
            // intermediary -- that is, delivery rested on the path being direct. The label stands on a
            // secret held by exactly two: a foreign letter matches no row of the book, and that is a refusal, not a guess.
            guard let from = MTPipeBook.match(tag) else {
                MontanaP2PTrace.mark("open_refused", mid: nil,
                                     "tag=\(tag.prefix(4).map { String(format: "%02x", $0) }.joined()) -- not our pipe")
                return
            }
            // The pipe seal is the proof of the sender: the key under it is held by exactly two.
            // It did not match -- the letter was composed by someone who saw the label in transit, and it is refused.
            guard let (mid, text, snm, sgl, qt, qm, lp) = MontanaP2PNode.openBody(sealed, conv: from) else {
                MontanaP2PTrace.mark("open_refused", mid: nil, "the pipe seal did not match -- a forgery or a foreign window")
                return
            }
            // The letter arrived under the PIPE label -- so the other side is already on it; the door it lands at
            // (MontanaDeliveryEngine.receive) reads that as the end of the introduction.
            // A service letter (a receipt, a presence beat) is ten bytes and arrives in volleys —
            // 497 lines in an afternoon saying one thing. A person's letter still gets its own line.
            if MontanaNotify.kind(for: text) == "text" {
                MontanaLog.event("P2P direct RECV mid=\(String(mid.prefix(8))) \(text.utf8.count)B")
            } else {
                MontanaP2PTrace.markFolded("recv_service", "kind=\(MontanaNotify.kind(for: text))", window: 60)
            }
            let tr = MontanaTransport.delivery(cellularEgress: MontanaP2PDirect.usesCellular(oc.nw)).rawValue
            MontanaP2PTrace.mark("open", mid: mid, "dir=in kind=\(MontanaNotify.kind(for: text)) via=\(tr) from=\(String(from.prefix(10))) peer_ip=\(oc.peerIP)")
            DispatchQueue.main.async {
                var ui: [String: Any] = ["from": from, "mid": mid, "text": text, "transport": tr]
                if let n = snm { ui["senderName"] = n }
                if let g = sgl { ui["senderGlyph"] = g }
                    if let q = qt, !q.isEmpty { ui["quoteText"] = q }
                    if let m = qm, !m.isEmpty { ui["quoteMid"] = m }
                    if let l = lp, !l.isEmpty { ui["linkPreview"] = l }
                NotificationCenter.default.post(name: .montanaP2PIncoming, object: nil, userInfo: ui)
            }
        }
    }

    // MARK: receive (acceptor / receiver)
    /// Somebody arrived here from outside. Until that happens this device has no address worth
    /// publishing: a routable-looking one that drops every inbound packet sends correspondents into
    /// dials that time out.
    /// Somebody arrived here from outside recently. Derived from the per-address proof (§4.7) rather
    /// than kept as a second flag: one concept, one source — a node has a node exactly when at least
    /// one of its endpoints has had somebody walk through it inside the proof window.
    var inboundProven: Bool { !MontanaSelfEndpoint.proven().isEmpty }
    /// When somebody last ARRIVED here. The globe stands on this and not on «an address of mine
    /// proved itself at some point», because those are different facts and only one of them means
    /// this device is reachable right now.
    private(set) var lastInboundAt = Date.distantPast
    /// When someone came here FROM THE WORLD, not from the next room. A Wi-Fi neighbour proves
    /// reachability within the flat and says nothing about the network: a lamp lit by it would
    /// promise the person something that is not there.
    private(set) var lastGlobalInboundAt = Date.distantPast
    private func acceptInbound(_ nw: MTWire) {
        var handshook = false
        MontanaP2PTrace.mark("conn_in")
        nw.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                // §4.7: somebody arrived HERE — this exact local address is reachable from where they
                // sit, and that is the only thing that earns it a place in our published record.
                MontanaSelfEndpoint.markProven(MontanaP2PDirect.localIP(nw))
                self.lastInboundAt = Date()
                if let r = nw.raw?.currentPath?.remoteEndpoint,
                   case .hostPort(let h, _) = r,
                   MontanaTransport.isGlobalIP("\(h)") { self.lastGlobalInboundAt = Date() }
                if !handshook { handshook = true; self.inboundHandshake(nw) }
            case .failed, .cancelled:
                if let c = self.inbound[ObjectIdentifier(nw)] { self.dropLive(c) }
                self.inbound[ObjectIdentifier(nw)] = nil; nw.cancel()
            default: break
            }
        }
        nw.start(queue: q)
    }

    private func inboundHandshake(_ nw: MTWire) {
        // Noise_PQ XX responder (spec §5.0): send my static KEM pub, then msg1 -> msg2 -> msg3.
        sendFrame(nw, Data(myKemPk))
        readFrame(nw) { [weak self] msg1 in
            guard let self, let msg1, msg1.count == 2272 else { nw.cancel(); return }
            // Same seed, same source: the responder has no reason to trust one source either.
            var seed = [UInt8](repeating: 0, count: 32)
            guard mt_random_fast(&seed, 32) == 0 else { nw.cancel(); return }
            var msg2 = [UInt8](repeating: 0, count: 6349)
            var state: UnsafeMutableRawPointer? = nil
            let rc = self.myKemSk.withUnsafeBufferPointer { sk in seed.withUnsafeBufferPointer { s in [UInt8](msg1).withUnsafeBufferPointer { m in
                mt_noise_responder_msg1(sk.baseAddress, s.baseAddress, m.baseAddress, &msg2, &state) } } }
            guard rc == 0, let st = state else { nw.cancel(); return }
            self.sendFrame(nw, Data(msg2))
            self.readFrame(nw) { [weak self] msg3 in
                guard let self, let msg3, msg3.count == 5261 else { mt_noise_state_free_responder(st); nw.cancel(); return }
                var ski2r = [UInt8](repeating: 0, count: 32)
                var skr2i = [UInt8](repeating: 0, count: 32)
                var ch = [UInt8](repeating: 0, count: 32)
                var stp: UnsafeMutableRawPointer? = st
                let rc3 = [UInt8](msg3).withUnsafeBufferPointer { m in mt_noise_responder_msg3(&stp, m.baseAddress, &ski2r, &skr2i, &ch) }
                guard rc3 == 0 else { nw.cancel(); return }   // the core consumes st and nils it
                MontanaP2PTrace.mark("noise_srv_done")
                let oc = OutConn(nw); oc.sendKey = skr2i; oc.recvKey = ski2r; oc.channelHash = ch; oc.isDialer = false
                oc.peerIP = MontanaP2PDirect.remoteIP(nw)
                self.inbound[ObjectIdentifier(nw)] = oc   // strong ref: keep the acceptor connection alive
                self.startRegistration(oc)
            }
        }
    }

    // §4.7: on a network where the subscriber has no IPv4 at all, an IPv4 literal is only reachable
    // through address synthesis, which happens on the resolver path — so there the name form is used
    // and the system does the synthesis. Everywhere else the literal is taken as-is, unchanged.
    // NO INTERFACE BAN ON A MESH DIAL (measured twice): a dial that bars the tunnel's interface is not moved to the physical
    // network -- the system leaves it without a path. 04.09 under a third-party tunnel, and 30.09 20:58 MSK on T1 under our own
    // with the rule that no longer holds every route: every node dial «Network is down», the globe red until the VPN went off.
    // The mesh rides whatever the system routes; leaving our tunnel needs a socket bound to a physical interface, measured first.
    static func dialHost(_ ip: String) -> NWEndpoint.Host {
        if !ip.contains(":"), !MontanaSelfEndpoint.hasIPv4() { return .name(ip, nil) }
        return NWEndpoint.Host(ip)
    }

    // Remote IP of a connection (for transport classification: global = internet, LAN = Wi-Fi).
    // Whether a connection egresses over cellular (splits internet vs cellular for the transport tag).
    static func usesCellular(_ nw: MTWire) -> Bool { nw.usesCellular }

    // Which of THIS device's endpoints the connection landed on (§4.7: proof is per local address).
    static func localIP(_ wire: MTWire) -> String {
        guard let nw = wire.raw, case let .hostPort(host, _)? = nw.currentPath?.localEndpoint else { return "" }
        switch host {
        case .ipv4(let a): return "\(a)"
        case .ipv6(let a): return "\(a)".split(separator: "%").first.map(String.init) ?? "\(a)"
        default: return ""
        }
    }

    static func remoteIP(_ wire: MTWire) -> String {
        guard let nw = wire.raw, case let .hostPort(host, _)? = nw.currentPath?.remoteEndpoint else { return "" }
        switch host {
        case .ipv4(let a): return "\(a)"
        case .ipv6(let a): return "\(a)"
        case .name(let n, _): return n
        @unknown default: return ""
        }
    }

    // MARK: mesh services API (Stage 4 NAT §5.4 / Stage 6 DHT §9.1) — request/reply over the very same
    // Noise_PQ XX channels the messages ride. One channel per peer serves chat, DHT and NAT alike.

    private func connection(forOverlay o: Data) -> OutConn? {          // `q` only
        for (_, c) in outbound where c.peerOverlay == o && c.ready { return c }
        for (_, c) in inbound where c.peerOverlay == o && c.ready { return c }
        return nil
    }

    /// 16.6.19 — WHO A DOOR DIES FOR, in one line and by construction. A door can be dead on one
    /// network and the only road on another (a full tunnel that passes only web on 443). The
    /// front sees a TLS reset from 127.0.0.1 (the passthrough masks the phone) and cannot name
    /// the device; only THIS side holds the model, the iOS and the network. The line names the
    /// door, its dress, why it fell, the interfaces under the path and whether a tunnel stands —
    /// so the fleet page reads «which build, which iOS, which network» a door dies for.
    /// THE DOOR'S OWN RECORD (15.29, the author's word 07.09: «telemetry must show a fall or the
    /// absence of need unambiguously»). One reset on a cellular network is a blip when the same
    /// door answered three seconds ago; five refusals in a row with no answer for minutes is a door
    /// down for this phone. The line of a failure now carries the record and the verdict, so a
    /// reader does not have to count for themselves.
    private static var doorLedger: [String: (streak: Int, oks: Int, lastOK: Date?)] = [:]
    private static let ledgerLock = NSLock()
    /// THE DOOR'S ROAD UNDER A TUNNEL (03.10, MontanaNetWitness.physical): while a tunnel stands a door is dialled above it, and
    /// a dial that fails there turns that door's road to the tunnel -- and a failure under the tunnel turns it back. A tunnel
    /// that holds every route refuses the binding, a white list may pass only the tunnel; one failure each way finds the
    /// living road. A new network or a new tunnel starts every door above again. One owner of the choice, beside the record.
    private static var doorUnder: Set<String> = []
    static func doorRoadAbove(_ label: String) -> Bool { ledgerLock.lock(); defer { ledgerLock.unlock() }; return !doorUnder.contains(label) }
    static func resetDoorRoads() { ledgerLock.lock(); doorUnder.removeAll(); ledgerLock.unlock() }
    static func noteDoorOK(label: String) {
        ledgerLock.lock()
        var r = doorLedger[label] ?? (0, 0, nil)
        r.streak = 0; r.oks += 1; r.lastOK = Date()
        doorLedger[label] = r
        ledgerLock.unlock()
    }
    static func noteDoorFail(ip: String, port: UInt16, why: String) {
        let dress: String = { if case .websocket = MontanaNodes.dress(forHost: ip) { return "wss" }; return "raw" }()
        let label = MontanaNodes.label(forHost: ip)
        let tunnel = MontanaNetWitness.tunnelPresent()
        ledgerLock.lock()
        var r = doorLedger[label] ?? (0, 0, nil)
        r.streak += 1
        doorLedger[label] = r
        let road = !tunnel ? "plain" : (doorUnder.contains(label) ? "tunnel" : "above")
        if tunnel { if doorUnder.contains(label) { doorUnder.remove(label) } else { doorUnder.insert(label) } }
        ledgerLock.unlock()
        let since = r.lastOK.map { Int(Date().timeIntervalSince($0)) }
        let verdict = (r.streak >= 3 && (since ?? .max) > 120) ? "down" : "blip"
        let record = "streak=\(r.streak) ok=\(r.oks) last_ok=\(since.map { "\($0)s" } ?? "never") verdict=\(verdict)"
        // SSOT-CONSOLIDATE: one table of failure classes, in MontanaNetProbe — the network-mode
        // probe reads the same words, and two tables would drift on the first fix.
        let cls = MontanaNetProbe.failClass(why)
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        MontanaP2PTrace.markFolded("door_fail",
            "host=\(label) dress=\(dress) why=\(cls) \(record) road=\(road) ifs=\(MontanaNetFacts.interfaces()) vpn=\(tunnel ? 1 : 0) build=\(build)",
            window: 120, key: "\(ip):\(dress):\(cls)")
    }

    func hasLiveChannel(overlay: Data) -> Bool {
        idxLock.lock(); defer { idxLock.unlock() }
        return liveIndex.values.contains { $0.overlay == overlay }
    }

    /// A LOCAL FAULT IS NOT A DOOR'S WORD (05.09). When the process has no descriptors left, every
    /// dial fails alike — the raw door, the web door, a peer — and none of that says anything about
    /// the road. Measured 05.09 12:13: «Too many open files» on the network switch, then the door
    /// walk doubled its step on every door up to the dead ceiling, and both nodes stayed lost for
    /// seven minutes after the descriptors were free again. A fault of our own is remembered for
    /// half a minute: the door verdicts do not move, the endpoints are not retired, the walk knocks
    /// again at once.
    private static var localFaultAt = Date.distantPast
    private static let localFaultLock = NSLock()
    static func noteLocalFault(_ why: String) {
        localFaultLock.lock(); localFaultAt = Date(); localFaultLock.unlock()
        MontanaP2PTrace.markFolded("local_fault", why, window: 60)
    }
    static func localFaultRecent() -> Bool {
        localFaultLock.lock(); defer { localFaultLock.unlock() }
        return Date().timeIntervalSince(localFaultAt) < 30
    }

    /// THE OWNERS OF STANDING CHANNELS LIVE BESIDE THE CHANNELS. Counting them used to mean
    /// entering the network queue and waiting for whatever it was doing — from the main thread,
    /// on every letter a person sends. The ledger is a dictionary under the same short lock the
    /// globe reads: an owner arrives once per channel and leaves with it.
    private var ownerRows: [UInt64: (owner: Data, ref: String, isService: Bool)] = [:]
    func noteOwnerRef(cid: UInt64, owner: Data, ref: String, isService: Bool) {
        idxLock.lock(); ownerRows[cid] = (owner, ref, isService); idxLock.unlock()
    }
    func renameOwnerRow(cid: UInt64, ref: String) {
        idxLock.lock(); if let r = ownerRows[cid] { ownerRows[cid] = (r.owner, ref, r.isService) }; idxLock.unlock()
    }

    /// A break extinguishes EXACTLY its own channel. The node record lives while at least one path to it lives.
    /// Called both by a break and by the object's death -- the second time it finds nothing and stays silent.
    func forget(_ cid: UInt64) {
        idxLock.lock()
        let gone = liveIndex.removeValue(forKey: cid)
        ownerRows[cid] = nil
        let paths = Self.doorsHeld(Array(liveIndex.values)).count
        idxLock.unlock()
        if let g = gone, g.door { MontanaP2PTrace.mark("path_down", "at=\(g.pathKey) paths=\(paths)") }
    }
    private func dropLive(_ oc: OutConn) { forget(oc.cid) }

    /// Owner links of machines whose introduction STANDS right now, except one named.
    /// These are what count when a sender decides whether the path has assembled: each is named by its
    /// own machine, and two machines of one owner give one.
    func ownerRefsOfLiveChannels(excluding ref: String) -> [Data] {
        idxLock.lock(); defer { idxLock.unlock() }
        // The peer is excluded from the count -- they carry a letter to themselves, they do not
        // relay it. But a SERVICE channel is never the peer: it is a node or a request to the
        // network, that is, a carrier by construction. A conversation label on it is the trace of
        // somebody else's error, and the owner count has no right to listen to it.
        return ownerRows.values.filter { $0.isService || $0.ref != ref }.map { $0.owner }
    }

    /// The distance between two claims -- a bytewise exclusive OR. The same order in which the set
    /// finds a label holder: comparison goes byte by byte over the claim, and the nearer one is whose
    /// value is smaller. One place for the whole tree -- two orders would mean two rings.
    static func distance(_ a: Data, _ b: Data) -> Data {
        guard a.count == b.count else { return Data(repeating: 0xFF, count: 32) }
        return Data(zip(a, b).map { $0 ^ $1 })
    }

    /// WHOM we hold -- a row per IDENTITY. Two doors to one machine give one node; which of them is
    /// named is decided by address, so that a trace is reproducible instead of depending on key order.
    func liveChannels() -> [(overlay: Data, ref: String, ip: String, port: UInt16)] {
        idxLock.lock(); let rows = Array(liveIndex.values); idxLock.unlock()
        return Self.peersHeld(rows).map { (overlay: $0.overlay, ref: $0.ref, ip: $0.ip, port: $0.port) }
    }

    /// BY WHICH WAY -- the doors standing right now, keyed by "address:port". The ledger of paths is
    /// separate from the ledger of identities: a break of one path must not extinguish a node that has a second.
    func livePathKeys() -> Set<String> {
        idxLock.lock(); defer { idxLock.unlock() }
        return Self.doorsHeld(Array(liveIndex.values))
    }

    /// The identities behind the named doors: two doors to one machine converge into one.
    func nodeIdentities(behind doors: Set<String>) -> Set<Data> {
        idxLock.lock(); defer { idxLock.unlock() }
        return Self.nodesHeld(Array(liveIndex.values), doors: doors)
    }

    @discardableResult
    func sendNet(toOverlay o: Data, type: UInt8, body: Data) -> Bool {
        guard hasLiveChannel(overlay: o) else { return false }
        q.async { if let c = self.connection(forOverlay: o) { self.sendNet(c, type, body) } }
        return true
    }

    func rpc(overlay: Data, type: UInt8, body: Data, reply: UInt8, _ done: @escaping (Data?) -> Void) {
        q.async {
            guard let c = self.connection(forOverlay: overlay) else { done(nil); return }
            self.rpcOn(c, type: type, body: body, reply: reply, done)
        }
    }

    func rpc(ip: String, port: UInt16, type: UInt8, body: Data, reply: UInt8?, _ done: @escaping (Data?) -> Void) {
        ensureConn(ip: ip, port: port, ref: nil) { [weak self] oc in
            guard let self, let oc else { done(nil); return }
            self.q.async {
                guard let reply else { self.sendNet(oc, type, body); done(nil); return }
                self.rpcOn(oc, type: type, body: body, reply: reply, done)
            }
        }
    }

    private func rpcOn(_ oc: OutConn, type: UInt8, body: Data, reply: UInt8, _ done: @escaping (Data?) -> Void) {
        let id = UUID()
        var fifo = oc.netWaiters[reply] ?? []
        fifo.append((id: id, cb: done))
        oc.netWaiters[reply] = fifo
        sendNet(oc, type, body)
        q.asyncAfter(deadline: .now() + 8) { [weak oc] in
            guard let oc, var f = oc.netWaiters[reply], let i = f.firstIndex(where: { $0.id == id }) else { return }
            let w = f.remove(at: i); oc.netWaiters[reply] = f; w.cb(nil)
        }
    }

    // Bring up (or reuse) a channel to a bare endpoint. When the reference is known the channel is keyed
    // as that chat peer, so a NAT-opened path IS the one the message queue then drains over.
    func ensureChannel(ip: String, port: UInt16, ref: String?, _ done: @escaping (Bool) -> Void) {
        ensureConn(ip: ip, port: port, ref: ref) { done($0 != nil) }
    }

    /// Cycle the channel to a node: after sleep the iOS socket is dead yet counts as alive, and an
    /// ordinary dial waits ~5 s for detection. We drop the old one and dial anew AT ONCE -- the link is instant on opening.
    func reprobeNode(ip: String, port: UInt16, force: Bool = false) {
        q.async {
            let key = "ep:\(ip):\(port)"
            if let oc = self.outbound[key] {
                // A fresh live channel is NOT touched on an ordinary opening. But on a NETWORK CHANGE
                // (force) the socket is dead on the old interface though "fresh" -- we drop it and dial
                // anew immediately. A channel that is GREETING is not a dead channel. Here stood a single
                // "ready" sign, and a handshake that had not finished counted as a corpse. A break of any
                // door called openNow, which dropped the not-yet-standing handshake of the NEIGHBOURING
                // door, its break called openNow again -- two doors killed each other's handshakes twice
                // a second. On a fast network a handshake slipped between the beats, in a tunnel never:
                // the 24.08 measurement on the seventeenth gave 782 knocks, 393 finished Noise and NOT ONE
                // open node, while a neighbouring app on the same network sent freely. The decision is
                // taken from the record of the dial start, not from a readiness sign.
                if !force {
                    if oc.ready, Date().timeIntervalSince(oc.lastUsed) < 10 { return }
                    if !oc.ready, Date().timeIntervalSince(oc.dialAt) < Self.handshakeBudget { return }
                }
                self.dropLive(oc)
                oc.closeWhy = "redial"; oc.nw.cancel(); self.outbound[key] = nil
                self.recomputeReady()
            }
            self.dial(toRef: key, ip: ip, port: port, carry: [], redials: 0)
        }
    }

    private(set) var anyChannelReady = false
    func recomputeReady() {
        let r = outbound.values.contains { $0.ready }
        idxLock.lock(); anyChannelReady = r; idxLock.unlock()
    }

    private func ensureConn(ip: String, port: UInt16, ref: String?, _ done: @escaping (OutConn?) -> Void) {
        q.async {
            let named = (ref?.isEmpty == false) ? ref! : nil
            let key = named ?? "ep:\(ip):\(port)"
            if let c = self.outbound[key] {
                if c.ready { done(c) } else { c.readyWaiters.append(done) }
                return
            }
            self.dial(toRef: key, ip: ip, port: port, carry: [], redials: 0)
            guard let c = self.outbound[key] else { done(nil); return }
            c.readyWaiters.append(done)
            self.q.asyncAfter(deadline: .now() + 10) { [weak c] in
                guard let c, !c.readyWaiters.isEmpty else { return }
                let ws = c.readyWaiters; c.readyWaiters = []
                for w in ws { w(nil) }
            }
        }
    }

    // MARK: framing (4-byte big-endian length prefix + body)
    private func sendFrame(_ nw: MTWire, _ body: Data, _ onSent: (() -> Void)? = nil) {
        var out = Data(count: 4)
        let n = UInt32(body.count).bigEndian
        withUnsafeBytes(of: n) { out.replaceSubrange(0..<4, with: $0) }
        out.append(body)
        nw.write(out) { onSent?() }
    }
    private func readFrame(_ nw: MTWire, _ done: @escaping (Data?) -> Void) {
        nw.readExactly(4) { hdr in
            guard let hdr, hdr.count == 4 else { done(nil); return }
            let b = [UInt8](hdr)
            let len = (Int(b[0]) << 24) | (Int(b[1]) << 16) | (Int(b[2]) << 8) | Int(b[3])   // big-endian, align-safe
            guard len > 0, len <= 1 << 20 else { done(nil); return }   // ≤1 MiB frame
            nw.readExactly(len) { body in done(body?.count == len ? body : nil) }
        }
    }

    // MARK: seal/open a frame with the session key (ChaCha20-Poly1305; nonce prepended by seal_blob)
    static func seal(key: [UInt8], _ payload: Data) -> Data? {
        var nonce = [UInt8](repeating: 0, count: 12)
        guard mt_random_fast(&nonce, 12) == 0 else { return nil }
        var outPtr: UnsafeMutablePointer<UInt8>? = nil; var outLen = 0
        let rc = key.withUnsafeBufferPointer { k in nonce.withUnsafeBufferPointer { n in payload.withUnsafeBytes { pp -> Int32 in
            mt_e2e_seal_blob(k.baseAddress, n.baseAddress, pp.bindMemory(to: UInt8.self).baseAddress, payload.count, &outPtr, &outLen)
        }}}
        guard rc == 0, let ptr = outPtr else { return nil }
        let sealed = Data(bytes: ptr, count: outLen); mt_e2e_free(ptr, outLen)
        return sealed
    }
    static func open(key: [UInt8], _ sealed: Data) -> Data? {
        var outPtr: UnsafeMutablePointer<UInt8>? = nil; var outLen = 0
        let rc = key.withUnsafeBufferPointer { k in sealed.withUnsafeBytes { s -> Int32 in
            mt_e2e_open_blob(k.baseAddress, s.bindMemory(to: UInt8.self).baseAddress, sealed.count, &outPtr, &outLen)
        }}
        guard rc == 0, let ptr = outPtr else { return nil }
        let plain = Data(bytes: ptr, count: outLen); mt_e2e_free(ptr, outLen)
        return plain
    }

}

// -- THE WIRE UNDER A CHANNEL ---------------------------------------------------------
// A thin connection shell -- and the ONLY place where the wire tells about itself.
// A web socket as a second road was rejected by the author's decision 23.08: it did not hold a
// permanent link to the node, and that is already proven on the live contour. One road remains --
// direct -- while the silence on refusal is gone: a path must name its state, its interfaces and
// the resolved address, or a remote analysis hits a wall where the work begins.
final class MTWire {
    private let nw: NWConnection
    /// A web socket is a PIPE, not a layout. Our four-byte frame length stays the only layout in the
    /// tree: a frame leaves as one binary message, while read messages are glued into a stream from
    /// which `readExactly` hands out exactly as much as was asked for.
    /// A second layout for one door would break the single source of truth.
    private let webSocket: Bool
    private var inbox = Data()          // read and written only on the connection queue

    var raw: NWConnection? { nw }
    var state: NWConnection.State { nw.state }
    var usesCellular: Bool { nw.currentPath?.usesInterfaceType(.cellular) ?? false }
    var stateUpdateHandler: ((NWConnection.State) -> Void)? {
        get { nw.stateUpdateHandler }
        set { nw.stateUpdateHandler = newValue }
    }

    init(_ c: NWConnection, webSocket: Bool = false) { nw = c; self.webSocket = webSocket }

    func start(queue: DispatchQueue) { nw.start(queue: queue) }
    func cancel() { nw.cancel() }

    func write(_ d: Data, _ done: (() -> Void)? = nil) {
        guard webSocket else {
            nw.send(content: d, completion: .contentProcessed { _ in done?() })
            return
        }
        let meta = NWProtocolWebSocket.Metadata(opcode: .binary)
        let ctx = NWConnection.ContentContext(identifier: "mt", metadata: [meta])
        nw.send(content: d, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in done?() })
    }

    /// Exactly N bytes and not a byte less: the frame reader waits for a header, then for a body.
    func readExactly(_ n: Int, _ cb: @escaping (Data?) -> Void) {
        guard webSocket else {
            nw.receive(minimumIncompleteLength: n, maximumLength: n) { d, _, _, err in
                cb((d?.count == n && err == nil) ? d : nil)
            }
            return
        }
        if inbox.count >= n {
            let head = inbox.prefix(n)
            inbox.removeFirst(n)
            cb(Data(head))
            return
        }
        nw.receiveMessage { [weak self] data, ctx, _, err in
            guard let self else { cb(nil); return }
            if err != nil { cb(nil); return }
            // A close arrives as its own kind of message, not as an error: taking it for an empty
            // frame would mean reading a closed pipe forever.
            if let m = ctx?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               m.opcode == .close { cb(nil); return }
            guard let data, !data.isEmpty else { cb(nil); return }
            self.inbox.append(data)
            self.readExactly(n, cb)
        }
    }

    /// The whole story of a path in one line: connection state, path availability, which interfaces
    /// are under it, where it actually looks (an empty destination address = THE NAME NEVER RESOLVED
    /// -- a different class of refusal than "the packet left and there is no answer") and from which address.
    var pathStory: String {
        var out = "state=\(Self.name(nw.state))"
        guard let p = nw.currentPath else { return out + " path=none" }
        switch p.status {
        case .satisfied: out += " path=satisfied"
        case .unsatisfied: out += " path=unsatisfied"
        case .requiresConnection: out += " path=requires-connection"
        @unknown default: out += " path=unknown"
        }
        let ifs = p.availableInterfaces.map { i -> String in
            switch i.type {
            case .wifi: return "wifi"
            case .cellular: return "lte"
            case .wiredEthernet: return "wired"
            case .loopback: return "lo"
            case .other: return "tunnel"
            @unknown default: return "?"
            }
        }
        out += " ifs=" + (ifs.isEmpty ? "-" : ifs.joined(separator: ","))
        out += " remote=" + Self.endpoint(p.remoteEndpoint)
        out += " local=" + Self.endpoint(p.localEndpoint)
        out += " expensive=\(p.isExpensive ? 1 : 0) constrained=\(p.isConstrained ? 1 : 0)"
        return out
    }

    private static func endpoint(_ e: NWEndpoint?) -> String {
        guard let e else { return "-" }          // empty = the address is not chosen yet (the name did not resolve)
        switch e {
        case .hostPort(let h, let pt): return "\(h):\(pt)"
        case .service(let n, _, _, _): return n
        case .unix(let path): return path
        case .url(let u): return u.absoluteString
        @unknown default: return "?"
        }
    }

    private static func name(_ st: NWConnection.State) -> String {
        switch st {
        case .setup: return "setup"
        case .waiting(let e): return "waiting(\(e))"
        case .preparing: return "preparing"
        case .ready: return "ready"
        case .failed(let e): return "failed(\(e))"
        case .cancelled: return "cancelled"
        @unknown default: return "?"
        }
    }
}

/// A short memory of frame ids: a copy is told from a first sight without a table that grows. The ring evicts the
/// oldest id past the cap; nothing else is kept.
final class MTRecentIds {
    private var ring: [Data] = []
    private var set = Set([Data]())
    private let cap: Int
    private let lock = NSLock()
    init(cap: Int) { self.cap = cap }
    func firstSight(_ id: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if set.contains(id) { return false }
        set.insert(id); ring.append(id)
        if ring.count > cap { set.remove(ring.removeFirst()) }
        return true
    }
}
