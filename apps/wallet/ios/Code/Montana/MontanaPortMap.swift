import Foundation

// Opening this node's own node, asked of the router by the node itself ([I-10]/[C-1]).
//
// A person does not configure a network. A device behind a household router asks that router for a
// way in, and every router of the last twenty years answers one of two standard requests: NAT-PMP
// (RFC 6886, four bytes on UDP 5351) or UPnP IGD (one discovery datagram and one call). The node
// asks; either it gets a way in and stands as a node for others, or it does not and lives through
// the nodes it knows. Both outcomes are normal and neither asks anything of a person.
//
// Nothing here talks to a service. The router is one hop away on the local wire, the requests are
// the ones its own firmware answers, and they are written on a raw socket rather than through a
// platform network client — so no capability leaves for a third party, and a second implementation
// speaks the same two standards without our help.
//
// What the router reports as the external address is NOT published: an address is proven by an
// inbound connection arriving on it, never by a router's opinion of it. The value only tells the
// trace whether this node stands where it can be dialled at all.
enum MontanaPortMap {

    private static let lock = NSLock()
    private static var mapped = false
    private static var externalIP = ""
    private static var externalPort: UInt16 = 0
    private static var timer: DispatchSourceTimer?
    private static let lifetime: UInt32 = 3600          // seconds of lease; renewed at half of it
    private static let port = MontanaDirectPort.value
    // CONFIG-OK: fixed by the standards themselves — NAT-PMP listens on 5351 (RFC 6886), discovery
    // is the multicast group 239.255.255.250:1900 (UPnP Device Architecture). Neither travels
    // anywhere with a machine, so neither is configuration.
    private static let pmpPort: UInt16 = 5351
    private static let ssdpEndpoint = "239.255.255.250"
    private static let ssdpPort: UInt16 = 1900

    /// What the router said about the way in, for the trace and for the network screen.
    static var state: (open: Bool, external: String, port: UInt16) {
        lock.lock(); defer { lock.unlock() }
        return (mapped, externalIP, externalPort)
    }

    /// The address this node stands at from outside, as the router assigned it — host and port
    /// together, so a node pointing here points at THIS machine and not at whoever asked last.
    static var publicHostPort: String? {
        lock.lock(); defer { lock.unlock() }
        guard mapped, !externalIP.isEmpty, externalPort > 0 else { return nil }
        return "\(externalIP):\(externalPort)"
    }

    /// Ask for the node, then keep asking while the app runs. Idempotent.
    static func open() {
        // SILENT-OK: the second call is the same call — the timer already runs and already asks.
        // Nothing is refused here and nothing is lost by returning.
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + 1, repeating: .seconds(Int(lifetime / 2)))
        t.setEventHandler { attempt() }
        t.resume()
        timer = t
    }

    private static func attempt() {
        guard let gw = gateway() else { MontanaP2PTrace.mark("portmap_no_gateway"); return }
        if natpmp(gateway: gw) { return }
        if upnp() { return }
        lock.lock(); mapped = false; lock.unlock()
        MontanaP2PTrace.mark("portmap_none", "gw=\(gw) — router answers neither standard")
    }

    // ── where the router stands ───────────────────────────────────────────────
    // Two ways, and neither reads a routing table: the operating system of a phone does not hand
    // one to an application. First the router itself answers the discovery datagram and its own
    // address is in that answer. Failing that, the first address of this device's own subnet, which
    // is where a household router stands on every network anybody ships.
    static func gateway() -> String? {
        if let (_, router) = discover() { return router }
        guard let mine = MontanaP2PNode.lanIP() else { return nil }
        let parts = mine.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.prefix(3).joined(separator: ".") + ".1"
    }

    // ── NAT-PMP (RFC 6886), four bytes out and sixteen back ───────────────────
    private static func natpmp(gateway gw: String) -> Bool {
        guard let ext = pmpExternal(gw) else { return false }
        var ok = false
        var assigned: UInt16 = 0
        for proto: UInt8 in [1, 2] {                    // 1 = UDP, 2 = TCP
            var req = Data([0, proto, 0, 0])
            req.append(contentsOf: withUnsafeBytes(of: port.bigEndian) { Array($0) })       // internal
            req.append(contentsOf: withUnsafeBytes(of: port.bigEndian) { Array($0) })       // requested
            req.append(contentsOf: withUnsafeBytes(of: lifetime.bigEndian) { Array($0) })
            guard let rep = udpAsk(gw, pmpPort, req), rep.count >= 16, rep[3] == 0 else { continue }
            ok = true
            // The port the router ACTUALLY gave, which is not always the one asked for: several
            // devices of one home ask for the same number, and only the first of them gets it.
            let given = UInt16(rep[10]) << 8 | UInt16(rep[11])
            if proto == 2, given > 0 { assigned = given }
        }
        guard ok else { return false }
        lock.lock(); mapped = true; externalIP = ext; externalPort = assigned == 0 ? port : assigned; lock.unlock()
        MontanaP2PTrace.mark("portmap_open", "by=nat-pmp external=\(ext):\(assigned == 0 ? port : assigned) asked=\(port)")
        return true
    }

    private static func pmpExternal(_ gw: String) -> String? {
        guard let rep = udpAsk(gw, pmpPort, Data([0, 0])), rep.count >= 12, rep[3] == 0 else { return nil }
        return "\(rep[8]).\(rep[9]).\(rep[10]).\(rep[11])"
    }

    private static func udpAsk(_ host: String, _ port: UInt16, _ payload: Data,
                               timeout: Int = 2, multicast: Bool = false) -> Data? {
        udpAskFrom(host, port, payload, timeout: timeout, multicast: multicast)?.0
    }

    private static func udpAskFrom(_ host: String, _ port: UInt16, _ payload: Data,
                                   timeout: Int = 2, multicast: Bool = false) -> (Data, String)? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        if multicast {
            var ttl: UInt8 = 2
            setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        }
        var endpoint = sockaddr_in()
        endpoint.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        endpoint.sin_family = sa_family_t(AF_INET)
        endpoint.sin_port = port.bigEndian
        endpoint.sin_addr.s_addr = inet_addr(host)
        let sent = payload.withUnsafeBytes { p -> Int in
            withUnsafePointer(to: &endpoint) { ap in
                ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, p.baseAddress, payload.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_in()
        var flen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &from) { fp in
            fp.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(fd, &buf, buf.count, 0, sa, &flen)
            }
        }
        guard n > 0 else { return nil }
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var raw = from.sin_addr
        inet_ntop(AF_INET, &raw, &ipBuf, socklen_t(INET_ADDRSTRLEN))
        return (Data(buf[0..<n]), String(cString: ipBuf))
    }

    // ── UPnP IGD: discovery, description, one call — all on raw sockets ───────
    private static func upnp() -> Bool {
        guard let (loc, _) = discover(), let (host, hport, path) = split(loc) else { return false }
        guard let xml = httpGet(host: host, port: hport, path: path),
              let control = controlPath(xml) else { return false }
        let target = control.hasPrefix("http") ? split(control) : (host, hport, control)
        guard let (ch, cp, cpath) = target else { return false }
        var any = false
        for proto in ["TCP", "UDP"] where addMapping(host: ch, port: cp, path: cpath, proto: proto) { any = true }
        guard any else { return false }
        lock.lock(); mapped = true; externalPort = port; lock.unlock()
        MontanaP2PTrace.mark("portmap_open", "by=upnp port=\(port)")
        return true
    }

    /// The description the router publishes, and the address it answered from.
    private static func discover() -> (String, String)? {
        let msg = Data(("M-SEARCH * HTTP/1.1\r\nHOST: \(ssdpEndpoint):\(ssdpPort)\r\n"
            + "ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\nMX: 2\r\n"
            + "MAN: \"ssdp:discover\"\r\n\r\n").utf8)
        guard let (d, from) = udpAskFrom(ssdpEndpoint, ssdpPort, msg, timeout: 3, multicast: true),
              let text = String(data: d, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\r\n") where line.lowercased().hasPrefix("location:") {
            return (line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces), from)
        }
        return nil
    }

    private static func split(_ url: String) -> (String, UInt16, String)? {
        guard let r = url.range(of: "://") else { return nil }
        let rest = url[r.upperBound...]
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        let hostPort = String(rest[rest.startIndex..<slash])
        let path = slash == rest.endIndex ? "/" : String(rest[slash...])
        if let colon = hostPort.lastIndex(of: ":"), let p = UInt16(hostPort[hostPort.index(after: colon)...]) {
            return (String(hostPort[hostPort.startIndex..<colon]), p, path)
        }
        return (hostPort, 80, path)
    }

    private static func controlPath(_ xml: String) -> String? {
        for service in ["WANIPConnection", "WANPPPConnection"] {
            guard let r = xml.range(of: service) else { continue }
            let tail = xml[r.upperBound...]
            guard let open = tail.range(of: "<controlURL>"), let close = tail.range(of: "</controlURL>") else { continue }
            return String(tail[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func httpGet(host: String, port: UInt16, path: String) -> String? {
        let req = "GET \(path) HTTP/1.0\r\nHost: \(host):\(port)\r\nConnection: close\r\n\r\n"
        return call(host: host, port: port, request: Data(req.utf8))
    }

    private static func addMapping(host: String, port cport: UInt16, path: String, proto: String) -> Bool {
        guard let mine = MontanaP2PNode.lanIP() else { return false }
        let soap = "<?xml version=\"1.0\"?>"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\""
            + " s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
            + "<u:AddPortMapping xmlns:u=\"urn:schemas-upnp-org:service:WANIPConnection:1\">"
            + "<NewRemoteHost></NewRemoteHost><NewExternalPort>\(port)</NewExternalPort>"
            + "<NewProtocol>\(proto)</NewProtocol><NewInternalPort>\(port)</NewInternalPort>"
            + "<NewInternalClient>\(mine)</NewInternalClient><NewEnabled>1</NewEnabled>"
            + "<NewPortMappingDescription>Montana</NewPortMappingDescription>"
            + "<NewLeaseDuration>\(lifetime)</NewLeaseDuration>"
            + "</u:AddPortMapping></s:Body></s:Envelope>"
        let req = "POST \(path) HTTP/1.0\r\nHost: \(host):\(cport)\r\n"
            + "Content-Type: text/xml; charset=\"utf-8\"\r\n"
            + "SOAPAction: \"urn:schemas-upnp-org:service:WANIPConnection:1#AddPortMapping\"\r\n"
            + "Content-Length: \(soap.utf8.count)\r\nConnection: close\r\n\r\n" + soap
        guard let reply = call(host: host, port: cport, request: Data(req.utf8)) else { return false }
        return reply.hasPrefix("HTTP/1.1 200") || reply.hasPrefix("HTTP/1.0 200")
    }

    private static func call(host: String, port: UInt16, request: Data) -> String? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 4, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var endpoint = sockaddr_in()
        endpoint.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        endpoint.sin_family = sa_family_t(AF_INET)
        endpoint.sin_port = port.bigEndian
        endpoint.sin_addr.s_addr = inet_addr(host)
        let connected = withUnsafePointer(to: &endpoint) { ap in
            ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }
        let sent = request.withUnsafeBytes { p in send(fd, p.baseAddress, request.count, 0) }
        guard sent > 0 else { return nil }
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            out.append(contentsOf: buf[0..<n])
            if out.count > 262_144 { break }
        }
        return String(data: out, encoding: .utf8)
    }
}
