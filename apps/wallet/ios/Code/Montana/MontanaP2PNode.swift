import Foundation
import SwiftUI
import Darwin
import Security
import Network
import UserNotifications

/// Self-host P2P node (spec §534, serverless by default). When the app opens, the phone
/// starts ITS OWN node (mt_postman_start, self-route), registers its queue on it and
/// hands out its LAN address. The second phone connects to this address directly and deposits —
/// every device is a node of equal standing. On the same Wi-Fi the link is direct.
/// THE name of an address, and the only place that decides it ([I-10]/[C-1]). Every screen, every
/// banner, every call and the mirror the extensions read ask this and nothing else, in this order:
/// a contact rename, the name the peer sent over its channel, the name it announces on the mesh,
/// and finally the short address — which is not a name but is never wrong.
enum MontanaName {
    // A name reaches this device over the channel the two correspondents hold, and nowhere else.
    // There used to be a registry here fed by announcements: a person's chosen name rode in the
    // clear on every network they walked past, so anybody within range read who had arrived. What a
    // person is called is theirs to tell, to whom they choose.
    static func of(_ ref: String) -> String {
        guard !ref.isEmpty else { return "" }
        // ONE name assembler for the whole client -- the name book ([C-1]). Here stood a second
        // assembly, and it read a closure NOBODY ever assigned: the name a person announced
        // themselves never reached this branch at all, and the short link form went out instead.
        // This caller differs from the screen only in the answer to "nobody named themselves".
        return MTNameBook.known(ref) ?? MontanaConv.short(ref)
    }
    /// Same question asked about a neighbour we are looking at: it carries its announced name even
    /// when its address has not been recognised yet.
    static func of(peer: MontanaPeer) -> String {
        let byEndpoint = peer.neighborRef.isEmpty ? "" : of(peer.neighborRef)
        if !byEndpoint.isEmpty, byEndpoint != MontanaConv.short(peer.neighborRef) { return byEndpoint }
        if !peer.name.isEmpty, !peer.name.hasPrefix("mt-") { return peer.name }
        return byEndpoint.isEmpty ? peer.endpoint : byEndpoint
    }
}

final class MontanaP2PNode: ObservableObject {
    static let shared = MontanaP2PNode()
    let p2p = MontanaP2P()
    private(set) var localPort: UInt16 = 0
    private(set) var lanEndpoint = ""        // LAN IP:port — handed out to the peer
    private(set) var hostKem = Data()    // node's own ML-KEM
    private(set) var overlay = Data()    // SHA256(hostKem)
    @Published private(set) var status = String(localized: "Starting node…", bundle: MTLanguage.bundle)
    @Published private(set) var peers: [MontanaPeer] = []   // neighbors on Wi-Fi (live scan every 5s)
    @Published var selectedPeerId: String? = nil            // addr of the device chosen in the picker
    @Published private(set) var messages: [P2PMsg] = []     // Wi-Fi conversation, delivered directly
    private var scanTimer: DispatchSourceTimer?
    private var lastPeersKey = ""
    // Sticky presence: while the transport (Wi-Fi) is up, a discovered peer stays in the P2P
    // network CONTINUOUSLY — a single missed Bonjour scan never drops it. Cleared only when the
    // network path itself changes/drops (NWPathMonitor). Same principle for any future transport (BLE…).
    private var seenPeers: [String: MontanaPeer] = [:]   // neighborRef -> peer (last known)
    private var seenAt: [String: Date] = [:]            // when each was last heard announcing
    private static let presenceTTL: TimeInterval = 45   // one missed announce is noise; three is absence
    private var pathMonitor: NWPathMonitor?
    private var wifiMonitor: NWPathMonitor?
    private var lteMonitor: NWPathMonitor?
    @Published private(set) var netUp = true       // any network route present (interface satisfied)
    /// Why the last letter did not leave, in the words the screen shows. Empty when it left.
    /// Why the last letter did not leave is a VALUE, not a phrase. The words for it are chosen by the
    /// screen in the system language: a string assembled here would show the person a foreign language,
    /// and no catalogue would pick it up.
    enum Hold: Equatable {
        case none
        case pathNotAssembled(owners: Int, nodes: Int)
        case firstContactRefused
    }
    @Published private(set) var lastHold: Hold = .none
    /// How many times in a row a first letter went to this peer without the pipe standing up.
    private var firstSince: [String: Double] = [:]   // the moment the first first-letter left for a peer whose pipe has not stood up
    @Published private(set) var p2pUp = false      // Montana network: a node this device can hand a message to right now
    /// Whether the lamp has a VERDICT yet. False from birth until the first knock round has
    /// either held a node or honestly failed everywhere — before that the app knows nothing and
    /// says nothing (the red lamp at cold start was a claim, not a measurement).
    @Published private(set) var p2pKnown = false
    private(set) var reachablePeers = 0            // how many of the known peers `plan` currently yields a route to
    private var presenceTimer: DispatchSourceTimer?
    @Published private(set) var wifiOn = false     // Wi-Fi transport available on this device
    @Published private(set) var lteOn = false      // cellular transport available
    @Published private(set) var btPeers: [String] = []   // montana references reachable over the Bluetooth LE mesh
    @Published private(set) var btOn = false             // Bluetooth powered on for this device
    /// Other devices of this same seed, seen on the local network. Not correspondents — the holders that
    /// a reinstalled device asks for its archive (spec s.2 Stages 3-5).
    @Published private(set) var siblings: [MontanaPeer] = []
    /// A new neighbour: push our name to it at once and ask for its own. A name is never advertised to
    /// everyone in radio range — it travels only over an established end-to-end channel, which is why
    /// a device shows an address until the two have actually spoken.

    func setBTPeers(_ endpoints: [String]) {
        DispatchQueue.main.async {
            let fresh = Set(endpoints).subtracting(self.btPeers)
            self.btPeers = endpoints
            for a in fresh where !a.isEmpty {
                NotificationCenter.default.post(name: .montanaP2PPeerUp, object: nil, userInfo: ["address": a])
            }
        }
    }

    /// A neighbour appearing is enough to build the link. Waiting for the user to press send made the
    /// first message of every conversation pay for the dial and the handshake — about two seconds cold,
    /// against eighteen milliseconds once the channel stands. Nothing here is user-visible: the mesh is
    /// joined by being switched on, the way a phone attaches to a network.
    func warmChannel(to peerRef: String) {
        guard Self.stageGate, !peerRef.isEmpty, peerRef != MontanaP2PNode.myRef() else { return }
        guard !hasLiveChannel(peerRef) else { return }
        let p = plan(to: peerRef)
        // Only the NEAR channel is warmed. A direct channel to the peer over the internet is not
        // opened at all: letters would not go over it anyway, while the very fact of such a connection
        // is visible from outside and says exactly what the path hides -- that these two talk.
        guard let ep = p.endpoints.first(where: { MontanaPath.isNear($0) }) else { return }
        MontanaP2PTrace.mark("chan_warm", "peer=\(String(peerRef.prefix(10))) \(ep.hostPort)")
        MontanaP2PDirect.shared.ensureChannel(ip: ep.ip, port: ep.port, ref: peerRef) { _ in }
    }

    // Direct endpoints learned from SIGNED BLE announces (address + direct port): lets two phones
    // that met over BLE also reach each other over the cellular internet — and keeps working across
    // networks while the address stays valid. Persisted 7 days; refreshed by every announce.
    // Endpoints live in ONE place — MontanaOverlayBook (§9.2 records, BLE announces, links all write
    // there). This is a projection for the dial path, not a second store.
    var learnedPeers: [String: MontanaPeer] {
        var out: [String: MontanaPeer] = [:]
        for e in MontanaOverlayBook.shared.allEntries() {
            guard !e.ref.isEmpty, let best = MontanaOverlayBook.shared.endpoints(ref: e.ref).first else { continue }
            out[e.ref] = MontanaPeer(name: String(e.ref.prefix(10)), endpoint: best.hostPort,
                                        neighborRef: e.ref, directPort: best.port)
        }
        return out
    }
    func learnEndpoint(ref: String, ip: String, port: UInt16) {
        guard ref != MontanaP2PNode.myRef(), !ip.isEmpty, port > 0 else { return }
        let before = MontanaOverlayBook.shared.endpoints(ref: ref).first?.hostPort
        MontanaOverlayBook.shared.learn(ref: ref, ip: ip, port: port, source: "ble")
        let hostEndpoint = ip.contains(":") ? "[\(ip)]:\(port)" : "\(ip):\(port)"
        if before != hostEndpoint { MontanaP2PTrace.mark("endpoint_learn", "peer=\(String(ref.prefix(10))) \(hostEndpoint)") }
    }

    // SSOT direct-candidate set: live Bonjour discoveries first, then manual, then BLE-learned endpoints.
    private func directCandidates() -> [MontanaPeer] { peers + Array(learnedPeers.values) }
    /// Montana nodes that answered on this local network. There are few -- a home, not a city -- and
    /// each of them is a path to any conversation: addressing is parsed by the sealed envelope, not by an announcement.
    @Published private(set) var lanNodes: [MontanaPeer] = []

    /// Reachable nodes -- ONE value for the whole client.
    ///
    /// What makes a machine a node is proven reachability, not where it was met. A neighbour on the
    /// local network, a machine with a worldwide address and a node are one and the same thing: a node
    /// that either serves itself or carries somebody else's. Here stood THREE different counts --
    /// "nodes of this network", "live channels" and "the node" -- and they divided not by property but
    /// by way of meeting: one machine fell now into one word, now into another, and a person read that as different things.
    ///
    /// Standing channels stay an internal value of the engine: they answer "with whom is a pipe open
    /// right now", and a person does not ask that question.
    var reachableNodes: Int {
        var seen = Set<String>()
        for c in MontanaP2PDirect.shared.liveChannels() { seen.insert("\(c.ip):\(c.port)") }
        for n in lanNodes where n.directPort > 0 { seen.insert("\(n.ip):\(n.directPort)") }
        return seen.count
    }
    func setBTOn(_ on: Bool) { DispatchQueue.main.async { self.btOn = on } }

    /// Being findable is the person's choice, and it is ONE switch ([I-10]): while it is off this
    /// device announces itself nowhere — not on the local network, not over the radio — and is reached
    /// only by those who already hold its address.
    static var meshDiscoverable: Bool {
        get { UserDefaults.standard.object(forKey: "mt.mesh.discoverable") as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: "mt.mesh.discoverable")
            MontanaBLEMesh.shared.setDiscoverable(newValue)
            // OFF at birth, and the system's local-network question rises only HERE, at the
            // person's own switch (the author's word 27.08): the first advertise/browse is
            // what makes iOS ask, so nothing advertises or browses until the switch says so.
            if newValue { shared.startLocalMeshIfAccepted() }
            shared.applyDiscoverability()
            MontanaP2PTrace.mark("discoverable", "on=\(newValue)")
        }
    }
    func applyDiscoverability() {
        guard Self.stageGate, started else { return }
        // What this switch governs, and nothing besides: whether this device OFFERS ITSELF to the
        // mesh — its announcement on the local network and its radio. Everything a node does to
        // carry letters stands regardless: the nodes it knocks on, the channels it holds, the nodes
        // of this network it finds for the path, the queue it drains. It used to gate all four at
        // once and empty the lists on top, so a person switching off the radio switched off the
        // network — and the trace showed a node that knew nobody while believing itself online.
        if Self.meshDiscoverable {
            p2p.advertiseMDNS(port: localPort, directPort: MontanaP2PDirect.shared.port)
            MontanaBLEMesh.shared.start()
        } else {
            MontanaBonjour.shared.stopAdvertising()
            MontanaBLEMesh.shared.powerDown()
            DispatchQueue.main.async { self.btPeers = [] }
        }
        MontanaP2PTrace.mark("discoverable_applied", "on=\(Self.meshDiscoverable) scan=on relay=on")
        startPeerScan()      // finding a way for a letter is not «being findable», and never was
    }
    private var inboxTimer: DispatchSourceTimer?
    private var started = false
    private var lastIfaces = ""

    /// Our packet tunnel is carrying this device's traffic right now. Read from the system itself —
    /// the provider assigns 198.18.0.1/16 to its utun interface, so its presence is the fact, with no
    /// cross-target dependency on the VPN classes.
    static func tunnelUp() -> Bool {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return false }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let name = String(cString: cur.pointee.ifa_name)
            guard name.hasPrefix("utun"), let sa = cur.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            if isTunnelHost(String(cString: host)) { return true }
        }
        return false
    }

    /// An address our packet tunnel holds: the provider assigns 198.18.0.1/16 and fd6d:6f6e:7461::1/64 to its
    /// utun interface (PacketTunnelProvider, the tunnel's network settings). The one reader of that fact on
    /// this side: tunnelUp above, and the call, which must know when its pair rides the tunnel.
    static func isTunnelHost(_ ip: String) -> Bool {
        ip.hasPrefix("198.18.") || ip.lowercased().hasPrefix("fd6d:6f6e:7461:")
    }

    /// LAN IPv4 (en0 Wi-Fi). nil if not found.
    static func lanIP() -> String? {
        var endpoint: String?
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let sa = cur.pointee.ifa_addr.pointee
            if (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0, sa.sa_family == UInt8(AF_INET) {
                let name = String(cString: cur.pointee.ifa_name)
                if name == "en0" || name.hasPrefix("en") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(cur.pointee.ifa_addr, socklen_t(sa.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        endpoint = String(cString: host)
                        if name == "en0" { break }
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return endpoint
    }

    /// The address of this node as the rest of the mesh can use it. A proven one first (§4.7: somebody
    /// actually arrived on it), and only failing that the local-network address as a hint — a card is
    /// handed to a person standing here, and it carries the overlay address anyway, so a hint that
    /// goes stale costs a lookup rather than the contact. A device with neither belongs to the mesh
    /// through the nodes holding it, and that is what its record carries.
    static func reachableEndpoint() -> String? { MontanaSelfEndpoint.proven().first ?? lanIP() }

    /// The card handed out of band — copied, shown as a QR, followed as a link (spec §9.5, first
    /// contact anchor). Beyond the account address and one endpoint it carries the OVERLAY ADDRESS:
    /// the node identity in the mesh. With it a scan is enough to ask the network where this person is
    /// now, so an endpoint that has gone stale costs nothing; without it there is nothing to ask with,
    /// and a scanned contact with a dead address has no route at all.
    ///
    /// The overlay address is the hash of the ML-DSA identity, not the key itself: a record arriving
    /// later carries the key and proves it hashes to this address, so verification is unchanged while
    /// the card stays small enough to scan reliably — the key alone would be 1952 bytes.


    /// Neighbours added BY ADDRESS no longer exist here.
    ///
    /// There stood an entrance `montana://p2p/<address>/<ip>/<port>`: it accepted the peer's permanent
    /// identifier together with their address and port, laid them on disk and opened a conversation by them.
    /// The set forbids both outright -- a person identifier does not exist, a peer address is not
    /// transmitted -- and a neighbouring entrance in the same file was removed for exactly that, while
    /// this one survived removal because it stood one branch higher and no pattern saw it.
    ///
    /// One can meet by name or by a one-time card, and both go through one resolver.

    /// Bring up own node + register own queue on it. Idempotent.

    // Stage 1 (media/archive): the network P2P layer is DISABLED — neither Bonjour, nor the system prompt
    // "local network", nor the intro screens. Enabled at the network decentralization stage.
    static let stageGate: Bool = true

    private var meshDirectPort: UInt16 = 0
    private var meshStarted = false
    private var seedWatch: NSObjectProtocol?

    /// The LOCAL half, lifted separately and only with the person's consent: the router port
    /// map, the Bonjour announce (when discoverable), the neighbour scan and the radio. The
    /// system's "find devices on local networks" prompt belongs to this half alone — refusing
    /// it costs the mesh, never the nodes.
    func startLocalMeshIfAccepted() {
        guard Self.stageGate, started, Self.meshDiscoverable, !meshStarted else { return }
        meshStarted = true
        MontanaP2PTrace.mark("mesh_start", "discoverable=\(Self.meshDiscoverable ? 1 : 0)")
        // The router's door, asked of the router rather than of a person: NAT-PMP first,
        // then UPnP. A device that gets one becomes reachable for others; a device that
        // does not carries on through the nodes it knows.
        MontanaPortMap.open()
        if Self.meshDiscoverable, meshDirectPort > 0 {
            p2p.advertiseMDNS(port: localPort, directPort: meshDirectPort)
            MontanaP2PTrace.mark("bonjour_publish")
        }
        startPeerScan()
        if Self.meshDiscoverable { MontanaBLEMesh.shared.start() }
    }

    /// An identity is born AFTER launch, and the first core call arrives in a world where the seed is
    /// not there yet. The core left this call silently and rose only on the next opening of the app --
    /// on a first launch there was no node at all. Now it waits for exactly the event it lacks and
    /// rises by itself.
    private func awaitSeed() {
        guard seedWatch == nil else { return }
        MontanaP2PTrace.mark("node_wait_identity")
        seedWatch = NotificationCenter.default.addObserver(forName: .montanaSeedOpened,
                                                              object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if let t = self.seedWatch { NotificationCenter.default.removeObserver(t); self.seedWatch = nil }
            self.autoStart()
        }
    }

    /// Instant restoration of the link to nodes on entering the foreground. autoStart starts the node
    /// once; this method hits the nodes ON EVERY opening, even when the node is already running, so
    /// that the link is instant instead of waiting for the next five-second tick.
    func reconnectNow() {
        guard Self.stageGate, started else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            MontanaNodes.openNow()
            self.refreshP2PPresence()
        }
    }

    func autoStart() {
        guard Self.stageGate else { return }
        // THE CORE AND THE MESH ARE TWO ENTITIES ([C-1]). The core — own postman, the direct
        // listener, the hole punch and the INTERNET nodes — needs no permission and starts
        // always. The mesh — port mapping, the Bonjour announce, the neighbour scan, the
        // radio — is the LOCAL half behind the intro and the system prompt. One gate over
        // both once meant: refuse the local network and the node path died with it.
        if started { startLocalMeshIfAccepted(); return }   // the intro accepted later lifts the mesh over a live core
        // The core lives by ONE condition -- there is an identity. Neither the answer about the local
        // network nor the order in which the seed appeared commands it: the question is about mesh,
        guard let mnemonic = MontanaSeed.mnemonic else { awaitSeed(); return }
        started = true
        MontanaP2PTrace.mark("node_start")
        // Warming the ownerSecret cache (PBKDF2 2^20) in parallel -- by the time the channels are ready
        // ownerRef leaves synchronously and transit routing stands up at once (else the node does not know the owner).
        DispatchQueue.global(qos: .userInitiated).async { _ = MontanaP2PDirect.shared.ownerSecretCached() }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let port = self.p2p.startPostman(bind: "0.0.0.0:0")
            guard port > 0, let kem = self.p2p.postmanKemPubkey() else {
                MontanaLog.event("P2P node FAILED to start port=\(port)")
                self.set(String(localized: "node failed to start", bundle: MTLanguage.bundle)); self.started = false; return
            }
            self.localPort = port
            self.hostKem = kem
            self.overlay = MontanaQueueKeys.sha256(kem)
            let ip = MontanaP2PNode.lanIP() ?? "127.0.0.1"
            self.lanEndpoint = "\(ip):\(port)"
            MontanaLog.event("P2P node UP lan=\(self.lanEndpoint)")
            MontanaP2PTrace.mark("postman_up", "port=\(port)")
            // Announce self on Wi-Fi IMMEDIATELY (Bonjour) — triggers the local network
            // access prompt and makes the node visible without waiting for queue registration.
            // Persistent direct channel (instant push). Advertise the postman port + the direct port
            // ("d" in TXT) once the direct listener is ready, so neighbors push straight to it.
            MontanaP2PDirect.shared.start(mnemonic: mnemonic) { [weak self] dport in
                guard let self else { return }
                MontanaLog.event("P2P advertise name=\(E2E.myDisplayName()) dport=\(dport)")
                MontanaP2PTrace.mark("direct_listener", "port=\(dport)")
                // The address service learns the direct port: our own dialable address (a forwarded
                // port, a global IPv6) names it to peers, and they dial it by TCP.
                MontanaNATService.shared.start(directPort: dport)
                // The nodes this device knows of. A node is a machine of the mesh whose address came
                // from the world rather than from the network: passing one yields a handshake and
                // nothing else, and from that handshake this node is IN the mesh even on a cellular
                // network where nobody can dial it.
                MontanaNodes.open()
                self.meshDirectPort = dport
                self.startLocalMeshIfAccepted()
            }
            self.startPathMonitor()
            // Registering the receiving queue on our own node (loopback) runs in the background so that
            // the core's 4-second loopback connect does NOT hold the globe: node_open (the channel) is
            // already ready, reception rises in parallel. ownerRef synchronously before sending (order 713) holds the transit route.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                guard self.p2p.connect(endpoint: "127.0.0.1:\(port)"), let qw = MontanaQueueKeys.queueWire(mnemonic) else {
                    self.set(String(localized: "node \(self.lanEndpoint), queue not assembled", bundle: MTLanguage.bundle)); return
                }
                let ok = self.p2p.registerDirect(queue: qw)
                MontanaLog.event("P2P register(direct) ok=\(ok)")
                MontanaP2PTrace.mark("register", "ok=\(ok)")
                self.set(ok ? "✅ " + String(localized: "node online at \(self.lanEndpoint)", bundle: MTLanguage.bundle)
                            : String(localized: "node \(self.lanEndpoint), registration failed", bundle: MTLanguage.bundle))
            }
        }
    }

    /// My card (self-host): the peer connects to MY node and deposits into my queue.

    /// Fetch from OWN queue (from own node, loopback) + ack.

    /// Auto-send (serverless, no card): find a neighbor via mDNS → hello → deposit.


    // The peer is reachable RIGHT NOW over the Wi-Fi mesh (persistent direct channel available).
    // One reachability decision, one source: reachable == some transport would carry a message to this
    // peer right now. Reading it off `transport(to:)` keeps the glyph, the status and the route from
    // ever disagreeing — a peer whose endpoint the mesh keeps fresh counts as reachable, exactly as
    // the route does.
    func canReach(_ neighborRef: String) -> Bool { transport(to: neighborRef) != nil }

    /// Is there a DIRECT channel to the peer -- without a single hop. The live view asks exactly this:
    /// what goes often has no right to go through a foreign machine, or that machine sees the rhythm.
    func hasDirectChannel(_ neighborRef: String) -> Bool {
        guard transport(to: neighborRef) != nil else { return false }
        return plan(to: neighborRef).transit == nil
    }

    /// What this device answers for on the mesh: its correspondence with its own other devices.
    /// Both of them derive it from the one branch of the one seed, so it is the same on both and
    /// computable by nobody else. It replaces a public reference of a person — a value read here
    /// from a key that nothing in this tree ever wrote, so every announce carried an empty string
    /// and every sibling check compared nothing with nothing.
    static func myRef() -> String { MontanaSeed.twin ?? "" }

    /// The same value, asked once. `MontanaSeed.twin` reads the keychain, derives a branch of the
    /// seed through the core and opens the sealed book — cheap once, and not cheap inside a timer
    /// that used to fire every three seconds. It is dropped when the device forgets the person,
    /// because that is when it stops being true.
    private var myRefCache: String?
    var myRef: String {
        if let c = myRefCache { return c }
        let v = MontanaP2PNode.myRef()
        if !v.isEmpty { myRefCache = v }
        return v
    }
    func forgetMyRef() { myRefCache = nil }

    // P2P type currently in use. Stage 1: local direct over Wi-Fi (LAN).
    var modeLabel: String {
        if !Self.stageGate { return "" }
        if !started || !status.hasPrefix("✅") { return String(localized: "Starting…", bundle: MTLanguage.bundle) }
        return "Wi-Fi"
    }

    // Transport availability drives presence: while the path is satisfied, peers persist.
    // When the network drops or switches interface, clear presence and re-discover on the new net.

    // THE network indicator, and the only definition of it ([I-10]/[C-1]): the Montana network is up
    // for this device when at least one Montana node can be handed a message right now — a live
    // direct channel, a node discovered on the local network, or a node on the Bluetooth mesh. It is
    // presence in OUR network, measured on our own connections; no outside address is consulted,
    // because whether some distant host answers says nothing about whether a message can be delivered.
    func refreshP2PPresence() {
        // THE globe, and the whole of what it claims: this device is IN the Montana mesh — a message
        // can be taken from it and handed to it, whichever network it sits on. Two ways for that to be
        // true, and no third:
        //   • somebody reaches this node directly — proven by an inbound connection, not by owning an
        //     address that looks reachable;
        //   • or it holds a live channel to a node that relays for it, which is the only way in from a
        //     cellular network, where a device has no address of its own at all.
        // Nothing here is remembered: an address learned yesterday, a neighbour heard on the radio an
        // hour ago and a channel that died in silence all count for nothing. Green on two devices means
        // those two are in touch, anywhere — that is the promise, so it is measured and never inferred.
        // THE LAMP BURNS FOR EXACTLY WHAT IT PROMISES. Before, ANY live channel lit it -- including a
        // channel to a neighbouring phone over Wi-Fi -- and a person saw green while holding not one
        // node: the 24.08 measurement on the second phone caught the line "nodes zero" between two
        // "we hold the node", and the lamp did not blink once. A measure must measure the value it
        // names, or it is not a simplification but a lie: a person decides whether to write by its colour.
        //
        // To be ONLINE means TO HOLD A NODE. And nothing else: the lamp stands on one value, because
        // the values it burns for number exactly as many as it promises -- one.
        // An arrival from outside (the author's word) does not concern the lamp: that is a fact about
        // our reachability, it lives in a one-minute window and therefore BLINKS by itself -- a lamp
        // made of two values of different natures would blink along and mean neither of them.
        // A Wi-Fi neighbour and radio are reachability NEARBY: honest, our own, but promising no network.
        let nodes = MontanaNodes.liveNodes
        let channels = MontanaP2PDirect.shared.liveChannels().count
        let ownDoor = Date().timeIntervalSince(MontanaP2PDirect.shared.lastGlobalInboundAt) < 60
        let radio = MontanaBLEMesh.shared.linkCount > 0 && !btPeers.isEmpty
        let up = started && nodes > 0
        // The verdict exists once we hold a node, or once the doors have been knocked and
        // answered — silence before the first knock is ignorance, not absence.
        let verdict = up || MontanaNodes.knockedOnce
        if verdict != p2pKnown { DispatchQueue.main.async { self.p2pKnown = verdict } }
        if up != p2pUp {
            DispatchQueue.main.async { self.p2pUp = up }
            MontanaLog.event("P2P mesh -> \(up ? "in" : "out") (nodes=\(nodes) inbound=\(ownDoor) near=\(channels) radio=\(radio))")
            // A NODE IS HELD AGAIN — everything waiting rides now (18.09): the queue moves by
            // reachability, and a media intent that waited for a node (media_wait) has just got one.
            // A NODE IS A ROAD LIKE A DOOR (30.09): the letters no node holds knock now, past the ramp and the backoff
            // their tries in the dark set. drainAll alone keeps each letter's rhythm, and on build 1976 (29.09 13:18:28Z)
            // the text letter that had tried seven seconds before, into dead doors, waited for its turn past the node's arrival.
            if up { MontanaDeliveryEngine.shared.drainOnDoorAlive("node:held"); MontanaDeliveryEngine.shared.drainAll() }
        }
        // D-3 (16.1.2): the state line speaks on CHANGE, plus a five-minute keepalive. «Every
        // time» was the answer to invisible flicker — but flicker IS change and is caught by
        // change; the metronome only drowned the diary (a line every 4s, 16 minutes of depth).
        let meshLine = "in=\(up) nodes=\(nodes) inbound=\(ownDoor) near=\(channels) radio=\(radio)"
        MontanaP2PTrace.markChanged("mesh_state", meshLine, every: 300)
        // Diagnostics only: how many correspondents a message would reach right now.
        var reachable = 0
        let known = Set(MontanaOverlayBook.shared.allEntries().map { $0.ref }.filter { !$0.isEmpty })
            .union(seenPeers.keys).union(btPeers)
        for w in known where !plan(to: w).isEmpty { reachable += 1 }
        reachablePeers = reachable
    }

    // ── keeping paths open (one place, [I-10]/[C-1]) ──────────────────────────
    // The direct road is TCP by address (05.09, the author's word): the endpoints the book holds
    // for a peer — a port their router forwards, a global IPv6 of theirs — are dialled on our own
    // cadence, and a dial backs off per address up to a minute: the trace showed a dead endpoint
    // being dialled every five seconds for minutes, which costs battery and tells nobody anything.
    // Nothing is punched: a hole made by UDP admits no SYN, and the volley cost a descriptor per
    // packet — measured 05.09, «Too many open files» and both nodes lost for seven minutes.
    private var pathAt: [String: (at: Date, step: Double)] = [:]
    private static let pathStepMin: Double = 5
    private static let pathStepMax: Double = 60
    private var bleStateAt = Date.distantPast

    private func maintainPaths() {
        guard Self.stageGate, started else { return }
        MontanaNodes.open()
        let now = Date()
        if now.timeIntervalSince(bleStateAt) >= 30 {
            bleStateAt = now
            // A switched-off radio says so ONCE. A line every half minute about a thing that
            // is off is not a measure — the diary drowned in it and rotated away the minutes
            // that mattered. The line returns the moment anything in it changes.
            let s = "on=\(btOn) links=\(MontanaBLEMesh.shared.linkCount) "
                + "peers=\(MontanaBLEMesh.shared.knownPeerCount) queue=\(MontanaBLEMesh.shared.queuedFragments)"
            MontanaP2PTrace.markChanged("ble_state", s)
        }
        MontanaP2PTrace.markChanged("roads", "all")
        var attempts = 0
        // A CALL OWNS THE RADIO (13.09, measured on a cellular call that took twenty-one seconds to
        // find its path): while a call is being set up or held, this walk knocks the doors of EVERY
        // known correspondent — eight dead addresses at a time, each holding a socket until it times
        // out on the cellular radio (thirty such timeouts inside that one call). Not one of them
        // serves the call, and the path the call is looking for is negotiated by its own checks over
        // the same radio. During a call the walk touches ONE correspondent: the one being called.
        let callPeer: String? = MontanaCall.stateSnapshot == "idle" ? nil : MontanaCall.peerSnapshot
        // An IPv6 door of theirs is dialled only from an IPv6 of our own: without one the dial
        // dies with «Network is down» before it leaves, and says so once a minute per address.
        let v6Here = MontanaSelfEndpoint.candidates().contains { $0.contains(":") }
        for e in MontanaOverlayBook.shared.allEntries() where !e.ref.isEmpty {
            if let p = callPeer, e.ref != p { continue }   // a call stands: every other correspondent waits
            if let ov = e.overlay, MontanaP2PDirect.shared.hasLiveChannel(overlay: ov) {
                for ep in e.endpoints { pathAt[ep.hostPort] = nil }      // it answered: forget the backoff
                continue
            }
            // Addresses that never answered are not retried into the ground.
            for ep in e.endpoints where ep.isGlobal && (v6Here || !ep.ip.contains(":")) {
                guard attempts < 4 else { return }
                let cur = pathAt[ep.hostPort]
                let step = cur?.step ?? Self.pathStepMin
                guard now.timeIntervalSince(cur?.at ?? .distantPast) >= step else { continue }
                pathAt[ep.hostPort] = (now, min(step * 2, Self.pathStepMax))
                attempts += 1
                MontanaP2PDirect.shared.ensureChannel(ip: ep.ip, port: ep.port, ref: e.ref) { _ in }
                MontanaP2PTrace.mark("path_try", "ep=\(ep.hostPort) next=\(Int(min(step * 2, Self.pathStepMax)))s")
            }
        }
    }

    private func startPresenceWatch() {
        guard presenceTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + 1, repeating: 5)
        t.setEventHandler { [weak self] in
            self?.refreshP2PPresence(); self?.maintainPaths(); self?.snapshot()
        }
        t.resume(); presenceTimer = t
    }

    /// Everything this node believes about itself, in one line, twice a minute. A path that is
    /// argued about instead of read costs hours; a line that says «nodes=0 nodes=0 channels=0»
    /// costs nothing and answers at once.
    private var snapAt = Date.distantPast
    private func snapshot() {
        guard Date().timeIntervalSince(snapAt) >= 10 else { return }
        snapAt = Date()
        let nodes = MontanaNodes.live().map { $0.label }.joined(separator: ",")
        // The measure is the CHANGE (16.1.2): 47 of 48 lines in a quarter of an hour said the
        // same thing. The line speaks when its content differs from the last one written.
        MontanaP2PTrace.markChanged("net", "disc=\(Self.meshDiscoverable ? 1 : 0) nodes=\(reachableNodes)"
            + "(lan=\(lanNodes.count) chan=\(MontanaP2PDirect.shared.liveChannels().count) "
            + "relay=\(MontanaNodes.liveNodes) doors=\(MontanaNodes.liveDoors))[\(nodes)] "
            + "port=\(MontanaP2PDirect.shared.port) ext=\(MontanaPortMap.state.external):\(MontanaPortMap.state.port) "
            + "wifi=\(wifiOn ? 1 : 0) lte=\(lteOn ? 1 : 0) ble=\(btPeers.count)")
    }

    private func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let up = path.status == .satisfied
            // We react ONLY to a real network up/down transition. Flicker of the interface list
            // (Wi-Fi plus cellular) does NOT trigger a redial: a forced redial on every "change" used
            // to kill a working channel to the node every ~7 s and tear delivery, the live set and notifications.
            guard up != self.netUp else { return }
            DispatchQueue.main.async { self.netUp = up }
            MontanaLog.event("P2P net path -> \(up ? "up" : "down")")
            if !up {
                self.seenPeers.removeAll()
                DispatchQueue.main.async { self.peers = []; self.p2pUp = false }
            } else {
                self.refreshP2PPresence()
                if self.localPort > 0, Self.meshDiscoverable {
                    self.p2p.advertiseMDNS(port: self.localPort, directPort: MontanaP2PDirect.shared.port)
                }
                // The network returned -- a redial WITHOUT force: a live channel is not touched
                // (reprobeNode drops only the certainly dead), we raise only what is missing.
                DispatchQueue.global(qos: .userInitiated).async { MontanaNodes.openNow() }
            }
        }
        m.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = m
        startPresenceWatch()

        let w = NWPathMonitor(requiredInterfaceType: .wifi)
        w.pathUpdateHandler = { [weak self] p in
            guard let self else { return }
            let on = (p.status == .satisfied)
            if !on {
                // Wi-Fi gone: LAN-scoped discoveries are unreachable over cellular by construction —
                // drop them so the direct route cannot pick a dead endpoint (Bonjour re-adds on return).
                self.seenPeers = self.seenPeers.filter { MontanaTransport.isGlobalIP($0.value.ip) }
                let list = Array(self.seenPeers.values)
                DispatchQueue.main.async { self.peers = list; self.wifiOn = false }
            } else {
                DispatchQueue.main.async { self.wifiOn = true }
            }
        }
        w.start(queue: DispatchQueue.global(qos: .utility)); wifiMonitor = w

        let c = NWPathMonitor(requiredInterfaceType: .cellular)
        c.pathUpdateHandler = { [weak self] p in DispatchQueue.main.async { self?.lteOn = (p.status == .satisfied) } }
        c.start(queue: DispatchQueue.global(qos: .utility)); lteMonitor = c
    }

    /// LAN Wi-Fi address of this device (address WITHIN the Wi-Fi network).

    /// Connect link to hand to a peer: this node's address on the network it is on.
    /// montana://p2p/<neighborRef>/<ip>/<directPort>.

    private func startPeerScan() {
        scanTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        // A browse BLOCKS its thread for the whole of its timeout. At one scan every three seconds
        // with a timeout of one and a half, this loop held a background thread for half of all time
        // it existed, and the phone felt it. Presence does not change that fast: a neighbour is
        // heard within a window, and the queue drains on reachability rather than on a scan.
        t.schedule(deadline: .now() + 0.2, repeating: 20)
        t.setEventHandler { [weak self] in
            guard let self, Self.meshDiscoverable else { return }   // a browse raises the local-network prompt — only after the switch
            let ownIP = self.lanEndpoint.split(separator: ":").first.map(String.init) ?? ""
            let all = self.p2p.browseMDNS(timeoutMs: 900).filter {
                !MontanaTransport.isLoopback($0.ip) && $0.ip != ownIP   // CONFIG-OK: our own loopback
            }
            // The Montana nodes of this network are everyone who answered. The announcement does not
            // say WHOM a neighbour answers for, and that is no loss: a letter is sealed with the
            // addressee queue key, so a neighbour it is not meant for cannot open it -- it either
            // carries it on or drops it. EVERY conversation has a path at once, without one mark on the air.
            //
            // From the same follows what is NO LONGER here: a list of peers assembled from the air.
            // It was built on the identifier in the announcement, and while the announcement carried it,
            // everyone within Wi-Fi range read who had arrived. Who stands before us is proven by the
            // CHANNEL; before that a neighbour has only an address, and that is enough to carry.
            let routes = all.filter { $0.directPort > 0 }
            let hadRoutes = !self.lanNodes.isEmpty
            DispatchQueue.main.async { self.lanNodes = routes }
            if !routes.isEmpty, !hadRoutes {
                // A path appeared where there was none. The queue moves by reachability, and
                // reachability has just changed: the engine tries everything waiting, with no reason to await a tick.
                MontanaP2PTrace.mark("lan_routes", "n=\(routes.count)")
                MontanaDeliveryEngine.shared.drainAll()
            }
            let key = routes.map(\.endpoint).sorted().joined(separator: ",")
            if key != self.lastPeersKey {
                self.lastPeersKey = key
                MontanaLog.event("P2P routes on this network: \(routes.count) [\(key)]")
            }
            // A neighbour is one with whom a channel STANDS, not one who announced something. Before,
            // the list was assembled from the air, and so it held an identifier the air has no right to
            // carry. A channel proves address ownership by protocol; nothing weaker enters this list.
            let live = MontanaP2PDirect.shared.liveChannels().filter { !$0.ref.isEmpty }
            let seen = live.map { MontanaPeer(name: String($0.ref.prefix(10)),
                                              endpoint: "\($0.ip):\($0.port)",
                                              neighborRef: $0.ref, directPort: $0.port) }
            DispatchQueue.main.async {
                let fresh = Set(seen.map(\.neighborRef)).subtracting(self.peers.map(\.neighborRef))
                self.peers = seen
                for a in fresh { NotificationCenter.default.post(name: .montanaP2PPeerUp, object: nil,
                                                                 userInfo: ["address": a]) }
            }
        }
        t.resume()
        scanTimer = t
    }

    // iOS suspends a backgrounded app -> its Bonjour advertisement dies and neighbors lose it (red).
    // On return to the foreground re-publish immediately so the neighbor sees us again without waiting.
    func onForeground() {
        guard Self.stageGate else { return }
        // The tunnel extension writes to its own container, which is not readable from outside, so the
        // sovereign wakes it raised are counted here instead — they are this app's own notifications.
        UNUserNotificationCenter.current().getDeliveredNotifications { notes in
            let wakes = notes.filter { ($0.request.content.userInfo["wake"] as? Bool) == true }
            guard !wakes.isEmpty else { return }
            let last = wakes.map { $0.date }.max().map { Int(Date().timeIntervalSince($0)) } ?? -1
            MontanaP2PTrace.mark("wake_seen", "n=\(wakes.count) last_ago_s=\(last)")
        }
        guard started, localPort > 0 else { MontanaLog.event("P2P foreground -> autoStart (node was not up)"); autoStart(); return }
        guard Self.meshDiscoverable else { return }
        MontanaLog.event("P2P foreground -> re-advertise \(lanEndpoint)")
        p2p.advertiseMDNS(port: localPort, directPort: MontanaP2PDirect.shared.port)
    }
    func onBackground() {
        guard Self.stageGate else { return }
        MontanaLog.event("P2P background (advertisement will pause until foreground)")
    }

    // Poll OWN queue every 2s; deliver incoming P2P messages (Wi-Fi) into `messages`.

    /// Send a message DIRECTLY to a neighbor over Wi-Fi: find them on the LAN, deposit the
    /// envelope (my address 0x00 text) into their node's queue. Returns false if they are not on Wi-Fi.
    @discardableResult
    /// SSOT direct-route gate: can this peer's advertised endpoint be dialed over the CURRENT egress?
    /// Wi-Fi egress reaches LAN and global endpoints; cellular egress reaches only global IPs — a
    /// LAN-scoped entry (stale Bonjour discovery from a network we left) is unreachable by construction,
    /// and picking it would both mistag the bubble and mask the reachable BLE fallback.
    private func directDialable(_ p: MontanaPeer) -> Bool {
        p.directPort > 0 && (wifiOn || MontanaTransport.isGlobalIP(p.ip))
    }

    // ── Pre-computed reachability (SSOT) ──────────────────────────────────────
    // Nothing is probed at send time. Every input is already known from a system source that keeps
    // itself current: NWPathMonitor for the interfaces, Bonjour for who is on this LAN, CoreBluetooth
    // for who is in range, the live-channel index for proven links, and the signed DHT records for
    // endpoints off this network. So the shortest route is READ, not measured — and when nothing is
    // proven, every layer that could work is used at once rather than one after another.
    struct ReachPlan {
        var live = false                                 // an established Noise_PQ channel — tens of ms
        var endpoints: [MontanaMeshEndpoint] = []        // dialable endpoints, shortest first
        var transit: Data? = nil                         // destination overlay, reachable THROUGH other peers
        var ble = false                                  // in Bluetooth range
        var nodes = 0                                    // nodes standing right now — a way into the mesh
        var medium: MontanaTransport? = nil              // what a message over this plan is tagged with
        var isEmpty: Bool { !live && endpoints.isEmpty && transit == nil && !ble && nodes == 0 }
        // Named for the trace, so a message that did not move says why in one word.
        var route: String {
            if live { return "live" }
            if !endpoints.isEmpty { return "direct" }
            if transit != nil { return "transit" }
            if nodes > 0 { return "node" }
            return ble ? "bluetooth" : "none"
        }
    }

    func plan(to peerRef: String) -> ReachPlan {
        var p = ReachPlan()
        guard Self.stageGate, !peerRef.isEmpty else { return p }
        p.live = hasLiveChannel(peerRef)
        p.ble = btPeers.contains(peerRef)

        // Addresses, ordered by how short the path is: this LAN first (a Bonjour neighbour answers in
        // under a hundred milliseconds), then globally routable ones, and never a LAN address while
        // this device has no Wi-Fi — over cellular it is unreachable by construction.
        var seen = Set<String>()
        var lan: [MontanaMeshEndpoint] = [], global: [MontanaMeshEndpoint] = []
        let now = Date().timeIntervalSince1970
        for cand in directCandidates() where cand.neighborRef == peerRef && cand.directPort > 0 {
            let ep = MontanaMeshEndpoint(ip: cand.ip, port: cand.directPort, at: now, source: "bonjour")
            guard seen.insert(ep.hostPort).inserted else { continue }
            // A neighbour ANSWERED on this network a moment ago — that answer is the proof the
            // network is there, and it is a better proof than a flag about interfaces. The flag
            // stood here as a gate, and when it lagged behind reality it threw away the only path
            // that existed: the letter then fell to the radio and died of its own deadline, on two
            // devices sitting on one Wi-Fi. A dial that fails costs milliseconds; a path discarded
            // costs the letter.
            if ep.isGlobal { global.append(ep) } else { lan.append(ep) }
        }
        // The nodes of this network DO NOT COME HERE, and that cost us a whole round of checks.
        //
        // I put them here thinking "the envelope is sealed, a neighbour either carries it or drops it".
        // But the near path does not carry: it opens a channel by address and writes the envelope into
        // it. A neighbour the envelope is not meant for reads the label, finds no pipe of its own and
        // drops it -- and the letter dies there. The measurement showed it literally: the phone wrote to
        // the TABLET and rang PHONE 1, because that one stood first in the network node list.
        //
        // The near path takes only the peer's own address. Network nodes remain carriers, and the
        // envelope reaches them another way: by a frame with a window position, which knows how to go
        // further and which needs an assembled path for that.
        for ep in MontanaOverlayBook.shared.endpoints(ref: peerRef) {
            guard seen.insert(ep.hostPort).inserted else { continue }
            // Remembered endpoints are another matter: one learned on a network this device has
            // since left is unreachable, and the flag is all there is to tell. It stays a gate here.
            if ep.isGlobal { global.append(ep) } else if wifiOn { lan.append(ep) }
        }
        p.endpoints = lan + global

        // Neither dialable nor already connected: a peer we DO hold a channel to can pass the frame on
        // (§2.3 role 3). This is the whole of what makes two phones on cellular reach each other —
        // neither accepts an incoming connection, but both keep one open to a third device.
        if !p.live, p.endpoints.isEmpty,
           let dstOverlay = MontanaOverlayBook.shared.overlay(forRef: peerRef) {
            // The peer's own record says which nodes hold it right now. Prefer one of those — a frame
            // handed to a node that has the destination goes across in one hop. Failing that, any node
            // we hold: it forwards if it can and drops if it cannot, and the trace says which.
            let named = MontanaOverlayBook.shared.via(ref: peerRef)
            let live = MontanaP2PDirect.shared.liveChannels().map { $0.overlay }
            if live.contains(where: { o in o != dstOverlay && (named.isEmpty || named.contains(o)) })
                || live.contains(where: { $0 != dstOverlay }) {
                p.transit = dstOverlay
            }
        }

        p.nodes = MontanaNodes.liveNodes
        if p.live || !p.endpoints.isEmpty || p.transit != nil || p.nodes > 0 {
            p.medium = MontanaTransport.delivery(cellularEgress: !wifiOn && lteOn)
        } else if p.ble { p.medium = .bluetooth }
        return p
    }

    /// SSOT transport resolver: the physical medium sendP2P WOULD use for this peer right now.
    /// One decision, one source of truth — used to pre-tag the outgoing message at creation
    /// (so the glyph is fixed next to the clock, like time) and inside sendP2P to pick the route.
    func transport(to peerRef: String) -> MontanaTransport? { plan(to: peerRef).medium }

    /// Why a route came out the way it did, in numbers: neighbours answering for this peer, endpoints
    /// remembered for it, and what this device believes about its own interfaces. A route reported
    /// without its inputs can only be guessed at, and guessing is what cost the last two days.
    func routeWitness(_ peerRef: String) -> String {
        let cands = directCandidates().filter { $0.neighborRef == peerRef && $0.directPort > 0 }.count
        let book = MontanaOverlayBook.shared.endpoints(ref: peerRef).count
        return "cand=\(cands) book=\(book) wifi=\(wifiOn ? 1 : 0) lte=\(lteOn ? 1 : 0)"
    }

    /// 16.6.14/16 — WHICH LETTERS LEFT BY A STANDING ROAD OF OUR OWN (a live near channel, a
    /// near dial), for the delivery engine: such a letter does not ring the bell (measured 04.09
    /// 13:26-13:31 and 13:47-13:49: fifty-four rings in three minutes beside a live channel, the
    /// bell answered 429 and rested up to 1920 s; on the LAN road 20 and 42 rings in two minutes).
    /// The node, the transit and the LAN node still ring — the peer behind them may sleep. The
    /// mark lives a minute and is read once.
    private let roadLock = NSLock()
    private var roadMids: [String: Date] = [:]
    private func noteLeftByStandingRoad(_ mid: String) {
        roadLock.lock(); defer { roadLock.unlock() }
        let cutoff = Date().addingTimeInterval(-60)
        roadMids = roadMids.filter { $0.value > cutoff }
        roadMids[mid] = Date()
    }
    func leftByStandingRoad(_ mid: String) -> Bool {
        roadLock.lock(); defer { roadLock.unlock() }
        return roadMids.removeValue(forKey: mid) != nil
    }

    /// A standing channel to this peer over a NEAR road (the local network) — the only kind a
    /// letter leaves by without the owner bound, hence the only kind that quiets the bell.
    func hasStandingNearChannel(_ peerRef: String) -> Bool {
        guard let ov = MontanaOverlayBook.shared.overlay(forRef: peerRef) else { return false }
        return MontanaP2PDirect.shared.liveChannels().contains { $0.overlay == ov && !MontanaTransport.isGlobalIP($0.ip) }
    }

    /// An already-handshaked channel to this peer exists right now.
    func hasLiveChannel(_ peerRef: String) -> Bool {
        guard let ov = MontanaOverlayBook.shared.overlay(forRef: peerRef) else { return false }
        return MontanaP2PDirect.shared.hasLiveChannel(overlay: ov)
    }

    func sendP2P(to peerRef: String, mid: String, text: String,
                 quoteText: String? = nil, quoteMid: String? = nil,
                 linkPreview: String? = nil) -> MontanaTransport? {
        guard Self.stageGate, !peerRef.isEmpty else { return nil }
        // The envelope names nobody. It used to open with the sender's standing address, which is
        // the identifier the set forbids ([I-17].2) written in the clear at the head of every
        // letter. The receiving side files a letter by the pipe it arrived on, so a name inside it
        // was never what answered the question «from whom» — it was only what leaked it.
        // A first letter carries the ciphertext that lets the other side derive the same secret;
        // every letter after it carries nothing but itself. Both shapes name nobody.
        // The letter body is sealed with the PIPE key -- the one the set calls the inner seal and speaks
        // of directly: "no hop holds that key". Before, the body travelled in the clear inside the
        // channel hop seal, so EVERY carrier -- and by the set there are at least three -- read the whole
        // letter, and the bound on distinct owners protected nothing. The same seal also closes forgery:
        // Poly1305 under a secret held by exactly two is proof of the sender, and a signature beside it
        // is unnecessary -- it would put a permanent key onto the wire.
        guard let secret = MTPipeBook.secret(for: peerRef) else {
            MontanaP2PTrace.mark("send_refused", mid: mid, "no_secret to=\(String(peerRef.prefix(10)))")
            return nil
        }
        var body = Data(mid.utf8); body.append(0); body.append(contentsOf: text.utf8)
        // The sender identity travels IN THE LETTER ITSELF, under the pipe seal -- the same format as in
        // the wake envelope. Before, a live frame carried only text, and the first introduction letter
        // raised a banner "by number": the name caught up a second later in a separate letter.
        // AIR-CHECKED: the fields are under the pipe key; a carrier sees the same sealed bytes.
        body.append(0); body.append(contentsOf: E2E.myDisplayName().utf8)
        body.append(0); body.append(contentsOf: E2E.myFaceGlyph().utf8)
        // The quote rides EVERY leg of the letter ([C-1]) — the envelope leg alone made it
        // a race. Appended tail only when a quote exists: plain letters keep the old bytes,
        // and an old parser's glyph field overflows its 8-char cap into nil, silently.
        if let qt = quoteText, !qt.isEmpty {
            body.append(0); body.append(contentsOf: String(qt.prefix(200)).utf8)
            body.append(0); body.append(contentsOf: (quoteMid ?? "").utf8)
            // AN ANSWER CARRIES ITS CARD TOO (the critic 22.09): the card was attached only to a
            // quote-less letter, so a reply holding a link never grew one. Every living build reads
            // the card as the seventh field regardless of the quote — read from their code, not hoped.
            if let tail = MTLinkPreviewBuilder.wireTailAfterQuote(lp: linkPreview) { body.append(tail) }
        } else if let tail = MTLinkPreviewBuilder.wireTail(lp: linkPreview) {
            body.append(tail)
        }
        guard let sealedBody = MTPipe.sealBody(body, sharedSecret: secret) else {
            MontanaP2PTrace.mark("send_refused", mid: mid, "no_seal to=\(String(peerRef.prefix(10)))")
            return nil
        }
        // A letter that left extinguishes the previous refusal. Here nobody extinguished it: the value
        // was only set on failure, so the "last letter" line showed the last REFUSAL -- forever.
        // Measured: a refusal at 17:26:21, the letter left and was confirmed in 134 ms at 17:26:26,
        // and the screen still showed the refusal. A measure must measure what it names.
        let left: (MontanaTransport?) -> MontanaTransport? = { [weak self] m in
            DispatchQueue.main.async { self?.lastHold = .none }
            return m
        }
        var envelope: Data
        if let ct = MTPipeBook.first(for: peerRef) {
            // A LIVE WORD DOES NOT KNOCK ON A DOOR THAT NEVER OPENED (21.09, the critic: a tablet sent
            // a draft word as a first letter to a silent stranger every half-minute for 23.7 hours).
            // Only a letter a person wrote goes as a first letter; drafts, typing, presence and marks
            // wait for the pipe to stand.
            let liveKind = MontanaNotify.kind(for: text)
            if ["live-draft", "typing", "watch", "presence", "draft", "read", "receipt"].contains(liveKind) {
                MontanaP2PTrace.markFolded("first_hold", "kind=\(liveKind) waits for the pipe to=\(String(peerRef.prefix(10)))", window: 300, key: "fh:" + peerRef)
                return nil
            }
            // While the pipe has not stood up, every letter goes as a first one -- and if the other side
            // holds no card, it is refused there silently. THE MEASURE IS TIME, NOT A COUNT (17.09): the
            // count ran per peer across letters, so six letters in the queue said «the acquaintance
            // was refused» on the third send (T1 21:50:45Z) while the other phone was merely asleep and
            // accepted at 21:52:00Z. What the person is told is how long the other side has answered
            // nothing; a minute of silence after the first first-letter is the honest threshold.
            let now = Date().timeIntervalSince1970
            let since = firstSince[peerRef] ?? now
            firstSince[peerRef] = since
            if now - since >= 60 {
                DispatchQueue.main.async { self.lastHold = .firstContactRefused }
                MontanaP2PTrace.markFolded("first_stuck", "age=\(Int(now - since))s to=\(String(peerRef.prefix(10)))", window: 30, key: "first:" + peerRef)
            }
            envelope = Data([MontanaP2PNode.firstLetterFrame]); envelope.append(ct)
        } else {
            // The pipe stood up -- the clock of stuck first letters starts anew. Without this, one old
            // jam declared an acquaintance failed forever.
            firstSince[peerRef] = nil
            // An ordinary letter carries the label of ITS OWN pipe in this window. Without it a channel
            // named the conversation, and a letter through an intermediary landed in the wrong one; with it anyone can carry it.
            guard let tag = MTPipeBook.myTag(for: peerRef), tag.count == MontanaP2PNode.letterTagBytes else {
                MontanaP2PTrace.mark("send_refused", mid: mid, "no_tag to=\(String(peerRef.prefix(10)))")
                return nil
            }
            envelope = Data([MontanaP2PNode.letterFrame]); envelope.append(tag)
        }
        envelope.append(sealedBody)
        // Prefer the Wi-Fi direct channel (instant persistent push); fall back to the Bluetooth mesh.
        // Per-message glyph = physical medium: cellular egress -> cellular, else Wi-Fi.
        let p = plan(to: peerRef)
        MontanaP2PTrace.mark("send", mid: mid, "dir=out kind=\(MontanaNotify.kind(for: text)) to=\(String(peerRef.prefix(10))) route=\(p.route) via=\(p.medium?.rawValue ?? "none") "
            + "live=\(p.live) eps=\(p.endpoints.map { $0.hostPort }.joined(separator: ",")) transit=\(p.transit != nil) ble=\(p.ble) relay=\(p.nodes) "
            + routeWitness(peerRef))

        // A near transport and a path are different things, and here they are separated.
        //
        // Near: two devices reach each other with their own radios -- inside one local network or over
        // Bluetooth. The constitution calls this a SEPARATE transport with a directly named property,
        // not a short path, and a person chooses a transport, never a degree of privacy.
        //
        // Path: everything that goes over the internet. Here an envelope must cross the number of
        // DISTINCT owners named by the Canon, and while there are fewer, a letter does not leave but
        // waits in the queue. Dialling the peer's global address directly is exactly what the set forbids: "no direct
        // path exists — not as a default, not as a retreat, and not as a choice offered to a person».
        let bleOK = p.ble
        let near = p.endpoints.filter { MontanaPath.isNear($0) }
        // Near transport over the wire: the envelope is laid before ALL nodes of this network under the
        // label of its own pipe. The label holder will open it, the rest will carry it. The peer address
        // is not here and is not needed -- it does not exist by the set, and trying to "dial them" was an
        // error of construction, not of settings.
        if !lanNodes.isEmpty, let tag = MTPipeBook.outgoingTag(for: peerRef) {
            for n in lanNodes where n.directPort > 0 {
                MontanaP2PDirect.shared.ensureChannel(ip: n.ip, port: n.directPort, ref: nil) { _ in }
            }
            if MontanaP2PDirect.shared.sendUnderTag(tag, payload: envelope, mid: mid) {
                // Stage 16.1: the road a letter ACTUALLY left by, one word, at the instant it leaves.
                // The send| line above names the PLAN; sent_route names the FACT — they differ exactly
                // when a fallback fired, and that difference is what the acceptance test reads.
                MontanaP2PTrace.mark("sent_route", mid: mid, "route=lan carrier=lan-node")
                if bleOK { scheduleBluetoothFallback(to: peerRef, envelope: envelope, mid: mid) }
                return left(.wifi)
            }
        }
        let ownerRefs = MontanaP2PDirect.shared.ownerRefsOfLiveChannels(excluding: peerRef)
        let owners = MontanaPath.distinctOwners(among: ownerRefs)
        let pathOK = owners >= MontanaPath.hopMin
        if near.isEmpty, !bleOK, !pathOK {
            MontanaP2PTrace.mark("held", mid: mid, "owners=\(owners)/\(MontanaPath.hopMin) named=\(ownerRefs.count) "
                + "nodes=\(reachableNodes)(lan=\(lanNodes.count) relay=\(MontanaNodes.liveNodes))")
            let hold = Hold.pathNotAssembled(owners: owners, nodes: reachableNodes)
            DispatchQueue.main.async { self.lastHold = hold }
            return nil
        }
        // A standing channel is the shortest there is, but only if it is NEAR. Here it was taken as the
        // shortest always and before any check: a letter went over it directly even when the channel ran
        // through the internet, and the whole owner bound was bypassed by one incoming link.
        if p.live, !near.isEmpty {
            let ep = near.first
            MontanaP2PDirect.shared.send(toRef: peerRef, ip: ep?.ip ?? "", port: ep?.port ?? 0,
                                         payload: envelope, mid: mid)
            noteLeftByStandingRoad(mid)   // 16.6.14: a standing near channel carries — the bell stays quiet
            MontanaP2PTrace.mark("sent_route", mid: mid, "route=lan carrier=live")
            return left(p.medium)
        }

        // How many endpoints to try at once. Without a tunnel an extra dial is free; with a tunnel every
        // stream goes through an extension under a hard memory bound, so the fan narrows to one.
        let fanOut = MontanaP2PNode.tunnelUp() ? 1 : 3
        // Over a near transport -- directly. Into the network -- only when the path is assembled, and
        // then the envelope goes not to the peer address but to carriers: they lead it on by the label.
        var any = false
        for ep in near.prefix(fanOut) {
            MontanaP2PDirect.shared.send(toRef: peerRef, ip: ep.ip, port: ep.port, payload: envelope, mid: mid)
            any = true
        }
        if any {
            noteLeftByStandingRoad(mid)   // 16.6.16: a near dial of our own delivers or fails within seconds — the retry bells then
            MontanaP2PTrace.mark("sent_route", mid: mid, "route=lan carrier=dial")
            if bleOK { scheduleBluetoothFallback(to: peerRef, envelope: envelope, mid: mid) }
            return left(p.medium)
        }

        // A path through a node. There is no near transport and no peer address exists -- so the envelope
        // is laid before reachable machines under the label of OUR OWN pipe, exactly as it is laid before
        // local network nodes. The label holder will open it, the rest will carry it on; the node knows
        // neither sender nor recipient and reads zero bytes.
        if pathOK, MontanaNodes.liveNodes > 0, let tag = MTPipeBook.outgoingTag(for: peerRef),
           MontanaP2PDirect.shared.sendUnderTag(tag, payload: envelope, mid: mid) {
            MontanaP2PTrace.mark("node_tx", mid: mid, "relay=\(MontanaNodes.liveNodes)")
            MontanaP2PTrace.mark("sent_route", mid: mid, "route=node")
            if bleOK { scheduleBluetoothFallback(to: peerRef, envelope: envelope, mid: mid) }
            return left(p.medium ?? MontanaTransport.delivery(cellularEgress: !wifiOn && lteOn))
        }

        // No address of our own to dial: hand the sealed frame to peers we DO reach and let one of them
        // pass it across. The relay reads nothing — the payload is end-to-end and it routes on the
        // destination alone; the receiver's dedup makes a duplicate copy free.
        if pathOK, let dst = p.transit, MontanaP2PDirect.shared.sendVia(dstOverlay: dst, payload: envelope, mid: mid) {
            MontanaP2PTrace.mark("sent_route", mid: mid, "route=transit")
            if bleOK { scheduleBluetoothFallback(to: peerRef, envelope: envelope, mid: mid) }
            return left(p.medium)
        }
        // Nothing on the network at all — radio is the only way left.
        if MontanaBLEMesh.shared.send(to: peerRef, envelope: envelope) {
            MontanaP2PTrace.mark("bt_tx", mid: mid, "only")
            MontanaP2PTrace.mark("sent_route", mid: mid, "route=ble")
            return left(.bluetooth)
        }
        // No route right now: ask the mesh where this peer is (Stage 6 DHT — signed, serverless) and
        // open the path (Stage 4 — UDP warm-up + simultaneous TCP open). The delivery engine holds the
        // message and drains it the moment the channel comes up, so nothing is lost by returning nil.
        openPath(to: peerRef)
        return nil
    }

    /// A dialled address turned out to be dead: drop it from sticky presence too, otherwise the peer
    /// keeps reading as reachable and the route keeps choosing a port nobody listens on. Then look the
    /// peer up in the mesh right away, so the next attempt has a fresh address instead of the dead one.
    func forgetEndpoint(ref: String, ip: String, port: UInt16) {
        if let p = seenPeers[ref], p.ip == ip, p.directPort == port {
            seenPeers[ref] = nil
            peers = Array(seenPeers.values)
        }
        openPath(to: ref)
    }

    /// Radio takes over only when the network tier has had its chance and did not deliver. The wait is
    /// short enough that a failure is not felt, and long enough that a channel coming up wins — which
    /// it usually does in about a hundred milliseconds.
    private func scheduleBluetoothFallback(to peer: String, envelope: Data, mid: String) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.hasLiveChannel(peer) else { return }
            if MontanaBLEMesh.shared.send(to: peer, envelope: envelope) {
                MontanaP2PTrace.mark("bt_tx", mid: mid, "fallback after network tier")
                MontanaP2PTrace.mark("sent_route", mid: mid, "route=ble carrier=fallback")
            }
        }
    }

    /// Bring a path to this peer up out of band: fresh endpoints from the DHT, then punch + dial. Used
    /// by the delivery engine's reachability drive and by the manual mesh test.
    func openPath(to peerRef: String) {
        guard Self.stageGate, !peerRef.isEmpty else { return }
        // There is no longer anyone to ask "where is this machine", and that is no loss: the directory
        // one used to ask is forbidden by the set. We reach with what the acquaintance gave and ask a
        // reachable neighbour to bring us together -- one hop, and the address goes no further.
        MontanaNATService.shared.dialAllEndpoints(ref: peerRef)
    }

    /// Send a sealed media chunk to a peer over the Wi-Fi mesh (same persistent channel as text).
    @discardableResult
    func sendBlobP2P(to peerRef: String, blobId: String, sealed: Data) -> Bool {
        guard Self.stageGate, !peerRef.isEmpty else { return false }
        if let peer = directCandidates().first(where: { $0.neighborRef == peerRef && directDialable($0) }) {
            MontanaP2PDirect.shared.sendBlob(toRef: peerRef, ip: peer.ip, port: peer.directPort, blobId: blobId, sealed: sealed)
            return true
        }
        return MontanaBLEMesh.shared.sendBlob(to: peerRef, blobId: blobId, sealed: sealed)   // cross-network: blob over the BLE mesh
    }

    /// The first byte says what the frame is: a sealed blob opens with zero, a letter with this.
    /// The two used to be told apart by whether the frame began with a sender's address — which
    /// worked only for as long as letters carried one.
    static let letterFrame: UInt8 = 0x01
    /// A letter that also opens the correspondence: the ciphertext of the encapsulation rides in
    /// front of it, and the other side derives from it the secret every later tag stands on.
    static let firstLetterFrame: UInt8 = 0x02

    /// A letter: the label of its own pipe, the letter identifier and the text. Who the sender is is said nowhere.
    ///
    /// The label stands IN THE LETTER ITSELF instead of being derived from the channel it arrived on.
    /// The difference is not cosmetic: while the channel named the conversation, a letter that passed
    /// through ANY intermediary landed in a conversation with the intermediary -- that is, delivery
    /// worked exactly as long as the path was direct. The label lives one window and is computable only
    /// by the two ends of the pipe, so it is not an identifier: an intermediary sees sixteen bytes that
    /// will differ tomorrow and about which it can say neither who nor to whom.
    static let letterTagBytes = 16
    static func parseEnvelope(_ d: Data) -> (tag: Data, sealed: Data)? {
        guard let first = d.first, first == letterFrame, d.count > 1 + letterTagBytes else { return nil }
        let tag = d.subdata(in: d.index(d.startIndex, offsetBy: 1)..<d.index(d.startIndex, offsetBy: 1 + letterTagBytes))
        let sealed = d.subdata(in: d.index(d.startIndex, offsetBy: 1 + letterTagBytes)..<d.endIndex)
        return sealed.isEmpty ? nil : (tag, sealed)
    }

    /// Open the letter body with the pipe secret and parse it. One place for both transports: the wire
    /// and radio ask it instead of each writing its own parsing.
    static func openBody(_ sealed: Data, conv: String) -> (mid: String, text: String, name: String?, glyph: String?, qt: String?, qm: String?, lp: String?)? {
        guard let secret = MTPipeBook.secret(for: conv) else { return nil }
        // First contact is NOT closed here. Closing = the peer HAS MOVED TO THE PIPE label, and there is
        // one proof -- a word of theirs sealed under the pipe, read at the one door every such word
        // lands at (MontanaDeliveryEngine.receive). Opening THEIR letter with MY key proves only my knowledge of the secret: closing the
        // contact here made the device erase the point the peer is still knocking at if my answer never
        // reached them -- and the acquaintance froze forever (precedent 18:32: T1 accepted the first
        // letter in an avalanche, the answer drowned, T2 kept knocking at an erased point).
        let opened = openBody(sealed, secret: secret)
        // THE NAME RENEWS WITH LIFE (12.09): the first word of a peer in an hour makes my name go
        // to them again, and by reciprocity theirs comes back — a book that lost a name (the
        // echo of 1480 wrote the caller's own) heals on the next exchange, on any road, with no
        // direct channel needed. One small letter per peer per hour of exchange, never a face.
        if opened != nil, MTPipeBook.touch(conv) { E2E.shared.renewName(to: conv) }
        return opened
    }
    static func openBody(_ sealed: Data, secret: Data) -> (mid: String, text: String, name: String?, glyph: String?, qt: String?, qm: String?, lp: String?)? {
        guard let body = MTPipe.openBody(sealed, sharedSecret: secret) else { return nil }
        // mid |0| text |0| name |0| glyph |0| quote |0| quote mid |0| link card --
        // every tail is optional: an old body of two fields reads as before. The cut goes by zeros,
        // not "everything after the first zero": otherwise the name would be sewn onto the letter text.
        let parts = body.split(separator: 0, maxSplits: 6, omittingEmptySubsequences: false)
        guard let midD = parts.first, let mid = String(data: Data(midD), encoding: .utf8), !mid.isEmpty else { return nil }
        let text  = parts.count > 1 ? (String(data: Data(parts[1]), encoding: .utf8) ?? "") : ""
        let name  = parts.count > 2 ? String(data: Data(parts[2]), encoding: .utf8) : nil
        let glyph = parts.count > 3 ? String(data: Data(parts[3]), encoding: .utf8) : nil
        let qt    = parts.count > 4 ? String(data: Data(parts[4]), encoding: .utf8) : nil
        let qm    = parts.count > 5 ? String(data: Data(parts[5]), encoding: .utf8) : nil
        let lp    = parts.count > 6 ? String(data: Data(parts[6]), encoding: .utf8) : nil
        return (mid, text,
                (name?.isEmpty == false && (name?.count ?? 99) <= 64) ? name : nil,
                (glyph?.isEmpty == false && (glyph?.count ?? 99) <= 8) ? glyph : nil,
                (qt?.isEmpty == false && (qt?.count ?? 999) <= 200) ? qt : nil,
                (qm?.isEmpty == false && (qm?.count ?? 99) <= 64) ? qm : nil,
                (lp?.isEmpty == false && (lp?.utf8.count ?? 99_999) <= 16384) ? lp : nil)
    }

    /// A first letter: the ciphertext that opens the correspondence, and the letter itself. The
    /// correspondence it belongs to is not stated anywhere — it FOLLOWS from the ciphertext, which
    /// only its intended holder can open.
    static func parseFirstEnvelope(_ d: Data) -> (ciphertext: Data, sealed: Data)? {
        guard let first = d.first, first == firstLetterFrame, d.count > 1 + 1088 else { return nil }
        let ct = d.subdata(in: d.index(d.startIndex, offsetBy: 1)..<d.index(d.startIndex, offsetBy: 1 + 1088))
        let sealed = d.subdata(in: d.index(d.startIndex, offsetBy: 1 + 1088)..<d.endIndex)
        return sealed.isEmpty ? nil : (ct, sealed)
    }

    /// Somebody wrote first. Whether they knocked at a name this device holds or at a card it once
    /// handed out, the answer is the same secret and the same local name for it.
    static func openFirst(_ ct: Data, sealed: Data, at root: Data? = nil) -> String? {
        // The body seal is the proof: a candidate secret must open it, or the card is foreign and the
        // "success" of decapsulation is implicit-rejection garbage giving birth to a phantom chat.
        let proof: (Data) -> Bool = { openBody(sealed, secret: $0) != nil }
        // THE POINT NAMES THE CARD. The letter arrived in a mailbox opened under one root: exactly that
        // one is tried, and there is nothing left to walk through -- a phantom candidate has nowhere to come from.
        if let root {
            if let ref = MontanaCard.accept(firstLetter: ct, root: root, confirmed: proof) { return ref }
            guard let mn = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(mn),
                  let mine = MontanaNames.contactRoot(masterSeed: master), mine == root else { return nil }
            return MontanaFirstContact.accept(firstLetter: ct, masterSeed: master, confirmed: proof)
        }
        // The point is not named (radio: a frame arrives without a window address). The walk remains, but
        // every candidate must present a seal -- a phantom is refused, though it is created.
        MontanaP2PTrace.mark("first_no_point", "fallback=all-cards")
        if let ref = MontanaCard.accept(firstLetter: ct, confirmed: proof) { return ref }
        guard let mn = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(mn) else { return nil }
        return MontanaFirstContact.accept(firstLetter: ct, masterSeed: master, confirmed: proof)
    }

    private func set(_ s: String) { DispatchQueue.main.async { self.status = s }; NSLog("[P2P-node] %@", s) }
}


// Pre-permission page: shown ONCE before the iOS system prompt
// "find devices on local networks" — the user understands why and grants it consciously.
/// The question of notifications: asked by us in words before the system asks it in a box.
///
/// It waits its turn behind the direct link — two system windows at once explain each other away,
/// and the person answers both by reflex. Once the system has been asked, it never asks again:
/// from then on the only node is Settings, and the screen says so instead of pretending a switch.
/// THE SYSTEM'S ANSWER, READ AT EVERY ENTRY AND EVERY RETURN (the author's word 06.10 15:5x: a check of the
/// notifications at the entry; in the bar under the time a crossed speaker, a tap leads to the settings). The gate
/// asked once and kept silent after: on 06.10 T2 refused every letter (Source is not authorized) while nothing on
/// the screen said so, and no diary held the answer. Every reading is now a telemetry line; a refusal stands as the
/// speaker in the bar's first slot; an unanswered question (the app put back, the window dismissed) is asked again.
@Observable final class MTNotifyAllowed {
    static let shared = MTNotifyAllowed()
    private(set) var refused = false
    func read(_ why: String) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let st = s.authorizationStatus
            MontanaLog.event("NOTIFY-AUTHZ status=\(st.rawValue) why=\(why)")
            DispatchQueue.main.async {
                self.refused = st == .denied
                if st == .notDetermined, MontanaSeed.hasSeed { MontanaNotifyGate.ask() }
            }
        }
    }
}

enum MontanaNotifyGate {
    private static let K = "mt.notify.asked"
    static var asked: Bool {
        get { UserDefaults.standard.bool(forKey: K) }
        set { UserDefaults.standard.set(newValue, forKey: K) }
    }
    static func ask() {
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            MTNotifyAllowed.shared.read("answered")   // the bar learns the answer the moment it is given
        }
    }
    static func systemStatus(_ done: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { done(s.authorizationStatus) }
        }
    }
    /// Whether the person's name stands on the lock screen when the system hides previews
    /// («Show Previews: When Unlocked / Never»). On by default, a switch in Notifications.
    static var nameOnLockScreen: Bool { UserDefaults.standard.object(forKey: "notifLockName") as? Bool ?? true }
    /// THE ONE REGISTRATION OF THE NOTIFICATION CATEGORIES ([C-1]): at launch and whenever the
    /// lock-screen name switch flips. With previews hidden by the system setting, iOS hides the
    /// title together with the body and writes the app's name — unless the category says the
    /// title may stand: the native option hiddenPreviewsShowTitle; the body then reads the
    /// category's placeholder. Our categories carried no option, so a locked phone read
    /// «Montana» where the extension had already written the person's name (18.09).
    static func registerCategories() {
        let opts: UNNotificationCategoryOptions = nameOnLockScreen ? [.hiddenPreviewsShowTitle] : []
        // quick reply directly from the notification
        let reply = UNTextInputNotificationAction(identifier: "REPLY", title: "Reply",
                        options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        let cat = UNNotificationCategory(identifier: "MESSAGE", actions: [reply], intentIdentifiers: [],
                        hiddenPreviewsBodyPlaceholder: String(localized: "New message", bundle: MTLanguage.bundle), options: opts)
        // Missed call: the lock screen names the fact even with previews off; long-press offers Call back.
        let callBack = UNNotificationAction(identifier: "CALLBACK", title: String(localized: "Call back", bundle: MTLanguage.bundle),
                        options: [.foreground])
        let missed = UNNotificationCategory(identifier: "MISSED_CALL", actions: [callBack], intentIdentifiers: [],
                        hiddenPreviewsBodyPlaceholder: String(localized: "Missed call", bundle: MTLanguage.bundle), options: opts)
        UNUserNotificationCenter.current().setNotificationCategories([cat, missed])
    }
    /// THE EXTENSION READS THE NOTIFICATION SETTINGS FROM THE SHARED KEYCHAIN, never from this app's store,
    /// so they are mirrored whenever they may have changed under it: the page's appearance, and a copy laid
    /// (23.09) — without it a restored «hide the text» stood in the store while the extension showed the text.
    static func mirrorSettings() {
        let d = UserDefaults.standard
        func on(_ k: String) -> Bool { (d.object(forKey: k) as? NSNumber)?.boolValue ?? true }
        MontanaKeychain.set("notifSound", Data([on("notifSound") ? 1 : 0]))
        MontanaKeychain.set("notifPreview", Data([on("notifPreview") ? 1 : 0]))
        MontanaKeychain.set("notifSender", Data([on("notifSender") ? 1 : 0]))
        registerCategories()
    }
}

/// The one node to the system settings of this app. Named once so two screens cannot drift apart.
enum MontanaSystemSettings {
    /// iOS ENDS THE APP WHEN A PRIVACY SWITCH CHANGES (24.09, iPhone 15 13:02:39 and 13:05:5x: the person went from the
    /// privacy page to Settings in the middle of a call with the screen shared, changed the photos' access, and iOS
    /// ended Montana — the call froze on the far phone, the broadcast stopped with the system's own error). The platform
    /// does not warn; this door does, while a call stands, and the person decides knowing it. A caller whose own words
    /// already say it (the camera alert) passes `callWarned`.
    static func open(callWarned: Bool = false) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        guard !callWarned, MontanaCall.isBusy else { UIApplication.shared.open(url); return }
        // A call whose peer rebuilds in place goes on after the restart (24.09): the words say what will happen.
        let goesOn = MontanaCall.shared.outlivesItsProcess
        let alert = UIAlertController(title: goesOn ? String(localized: "The call will pause", bundle: MTLanguage.bundle)
                                                    : String(localized: "The call will end", bundle: MTLanguage.bundle),
                                      message: goesOn ? String(localized: "iOS restarts Montana when an access is changed in Settings. Come back to Montana within a minute, and the call goes on.", bundle: MTLanguage.bundle)
                                                      : String(localized: "iOS restarts Montana when an access is changed in Settings, and the call ends.", bundle: MTLanguage.bundle),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel", bundle: MTLanguage.bundle), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Open Settings", bundle: MTLanguage.bundle), style: .default) { _ in
            MontanaP2PTrace.mark("privacy_access", "settings opened under a call")
            UIApplication.shared.open(url)
        })
        guard MTTop.controller != nil else { UIApplication.shared.open(url); return }
        MontanaP2PTrace.mark("privacy_access", "call warned before settings goes_on=\(goesOn ? 1 : 0)")
        MTTop.present(alert, kind: "alert")
    }
}

