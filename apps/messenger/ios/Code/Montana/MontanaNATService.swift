import Foundation
import Network

// THE ADDRESS SERVICE (05.09, the author's word: no UDP in the client). Nothing here punches: the UDP volley
// that stood in this file opened no channel in its whole life (measured 2-3.09 on every attempt: the packet
// lands, the TCP that follows is refused or times out — a hole made by UDP admits no SYN) and cost a
// descriptor per packet: 84 sockets a shot, 2100 in four minutes, «Too many open files» on the network
// switch, both nodes unreachable for seven minutes (05.09 12:13-12:20). Coordination frames stay for the
// wire: a peer tells me the address it sees me at (endpointReq/endpointRep), a relay forwards an opaque frame
// (relayData).
final class MontanaNATService {
    static let shared = MontanaNATService()

    private(set) var observedIP: String?          // my external IP, as a peer reports it back
    private var directPort: UInt16 = 0
    private var announcedTo: [String: Date] = [:]
    private var dialledAt: [String: Date] = [:]
    private let lock = NSLock()

    private init() {}

    func start(directPort: UInt16) { lock.lock(); self.directPort = directPort; lock.unlock() }

    /// The one address of our own a peer can dial by TCP: a global IPv6 of a real interface with the
    /// direct port. A carrier-NAT IPv4 is never named — nobody can dial it, and a word that names it
    /// only spends the peer's dials.
    func selfEndpoint() -> String? {
        lock.lock(); let port = directPort; lock.unlock()
        guard port > 0 else { return nil }
        if let v6 = MontanaSelfEndpoint.candidates().first(where: { $0.contains(":") && MontanaTransport.isGlobalIP($0) }) {
            return "[\(v6)]:\(port)"
        }
        return nil
    }

    /// Name our dialable address to the peer — a silent service word inside the pipe, once a minute
    /// per correspondence. No address of our own — no word.
    func announce(to conv: String) {
        lock.lock()
        let fresh = announcedTo[conv].map { Date().timeIntervalSince($0) < 60 } ?? false
        if !fresh { announcedTo[conv] = Date() }
        lock.unlock()
        guard !fresh else { return }
        guard let mine = selfEndpoint() else {
            MontanaTrace.markFolded("addr_announce", "skip=no-self to=\(String(conv.prefix(10)))", window: 300, key: conv)
            return
        }
        MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: UUID().uuidString,
                                             text: punchEndpointMark + mine, silent: true)
        MontanaTrace.mark("addr_announce", "ep=\(mine) to=\(String(conv.prefix(10)))")
    }

    /// The peer named their address: it goes into the book and is dialled by TCP at once; ours is
    /// named back if it has not been lately.
    func peerAnnounced(conv: String, endpoint: String) {
        guard let (ip, port) = MontanaEndpointParse.split(endpoint) else { return }   // SILENT-OK: a string without a port is not an address
        MontanaTrace.mark("addr_peer", "ep=\(endpoint) from=\(String(conv.prefix(10)))")
        MontanaOverlayBook.shared.learn(ref: conv, ip: ip, port: port, source: "word")
        MontanaDirect.shared.ensureChannel(ip: ip, port: port, ref: conv) { _ in }
        announce(to: conv)
    }

    /// Dial every address the book holds for this peer, by TCP — bounded, so a peer that is gone
    /// cannot cause a dial storm.
    @discardableResult
    func dialAllEndpoints(ref: String) -> Bool {
        let eps = MontanaOverlayBook.shared.endpoints(ref: ref)
        guard !eps.isEmpty else { return false }
        lock.lock()
        let recent = dialledAt[ref].map { Date().timeIntervalSince($0) < 4 } ?? false
        if !recent { dialledAt[ref] = Date() }
        lock.unlock()
        if recent { return true }
        for ep in eps.prefix(3) { MontanaDirect.shared.ensureChannel(ip: ep.ip, port: ep.port, ref: ref) { _ in } }
        MontanaTrace.mark("addr_dial_all", "peer=\(String(ref.prefix(10))) eps=\(eps.count)")
        return true
    }

    // ── incoming coordination frames ───────────────────────────────────────────
    func handle(type: UInt8, body: Data, peerOverlay: Data?, peerIP: String, peerPort: UInt16) -> (reply: UInt8, body: Data)? {
        switch type {
        case MontanaNATMsg.endpointReq:
            // Report the address I actually see this peer at (its external address).
            guard !peerIP.isEmpty else { return nil }
            let ep = MontanaEndpoint(kind: peerIP.contains(":") ? .directV6 : .directV4,
                                     endpoint: peerIP.contains(":") ? "[\(peerIP)]:\(peerPort)" : "\(peerIP):\(peerPort)")
            return (MontanaNATMsg.endpointRep, MontanaNATMsg.encodeEndpoint(ep))

        case MontanaNATMsg.endpointRep:
            guard let ep = MontanaNATMsg.decodeEndpoint(body), let (ip, _) = MontanaEndpointParse.split(ep.endpoint) else { return nil }
            if MontanaTransport.isGlobalIP(ip) {
                let changed = (observedIP != ip)
                observedIP = ip
                MontanaTrace.mark("nat_observed", "ip=\(ip)")
                _ = changed   // there is nowhere left to publish ourselves: there is no directory
            }
            return nil

        case MontanaNATMsg.punchReq, MontanaNATMsg.punchInfo:
            MontanaTrace.markFolded("nat_word_buried", "type=\(type)", window: 300)
            return nil

        case MontanaNATMsg.relayData:
            // Transit role (§2.3 role 3 / §5.3): forward the opaque frame to a live channel for `dst`.
            guard let (dst, frame) = MontanaNATMsg.decodeRelay(body) else { return nil }
            if MontanaDirect.shared.hasLiveChannel(overlay: dst) {
                _ = MontanaDirect.shared.sendNet(toOverlay: dst, type: MontanaNetMsg.overlayFrame, body: frame)
                MontanaTrace.mark("nat_relay_fwd", "dst=\(MontanaOverlayBook.hex(dst))")
            }
            return nil

        default: return nil
        }
    }

    // ── outgoing ───────────────────────────────────────────────────────────────
    // Ask every live peer what address it sees me at (cheap, once per channel).
    func requestObservedEndpoint(from peerOverlay: Data) {
        _ = MontanaDirect.shared.sendNet(toOverlay: peerOverlay, type: MontanaNATMsg.endpointReq, body: Data())
    }
}
