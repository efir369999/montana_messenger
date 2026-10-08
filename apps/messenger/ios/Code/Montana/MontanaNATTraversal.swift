import Foundation
import MontanaBindings
import Network

// Analogues of AutoNAT (observed address), DCUtR (synchronized hole-punch), Circuit Relay (opaque relay
// through a reachable peer). Coordination frames ride inside Noise_PQ XX to a reachable peer-coordinator
// The raw UDP punch packet carries only an opaque nonce.
//
// This file: byte-exact coordination frames, address parsing and the network facts line. The UDP
// hole-punch that stood here left on 05.09 (the author's word): the direct road is TCP by address.

// ── Coordination frames (inside NetMessage / Noise_PQ) ──
enum MontanaNATMsg {
    static let endpointReq: UInt8   = 0x70   // body: empty (ask coordinator for my observed external addr)
    static let endpointRep: UInt8   = 0x71   // body: Endpoint (my addr as the coordinator sees it)
    static let punchReq: UInt8  = 0x72   // body: peer_overlay 32B (ask coordinator to pair me with peer)
    static let punchInfo: UInt8 = 0x73   // body: peer_overlay 32B + Endpoint (peer's observed addr + "punch now")
    static let relayData: UInt8 = 0x74   // body: dst_overlay 32B + opaque frame (fallback: relay through coordinator)

    static func encodeEndpoint(_ ep: MontanaEndpoint) -> Data { ep.encode() }
    static func decodeEndpoint(_ d: Data) -> MontanaEndpoint? { var o = 0; return MontanaEndpoint.decode(d, &o) }

    static func encodePunchInfo(peer: Data, ep: MontanaEndpoint) -> Data {
        precondition(peer.count == 32); var d = peer; d.append(ep.encode()); return d
    }
    static func decodePunchInfo(_ d: Data) -> (peer: Data, ep: MontanaEndpoint)? {
        guard d.count >= 34 else { return nil }
        let b = d.startIndex
        let peer = d.subdata(in: b..<(b+32))
        var o = 32
        guard let ep = MontanaEndpoint.decode(d, &o) else { return nil }
        return (peer, ep)
    }
    static func encodeRelay(dst: Data, frame: Data) -> Data {
        precondition(dst.count == 32); var d = dst; d.append(frame); return d
    }
    static func decodeRelay(_ d: Data) -> (dst: Data, frame: Data)? {
        guard d.count >= 32 else { return nil }
        let b = d.startIndex
        return (d.subdata(in: b..<(b+32)), d.subdata(in: (b+32)..<d.endIndex))
    }
}


// Parse "ip:port" / "[v6]:port" into NWEndpoint host+port.
enum MontanaEndpointParse {
    // Split "ip:port" / "[v6]:port" into raw host and port (SSOT for address strings on the wire).
    static func split(_ s: String) -> (ip: String, port: UInt16)? {
        if s.hasPrefix("[") {
            guard let close = s.firstIndex(of: "]") else { return nil }
            let host = String(s[s.index(after: s.startIndex)..<close])
            let rest = s[s.index(after: close)...]
            guard rest.hasPrefix(":"), let p = UInt16(rest.dropFirst()), !host.isEmpty else { return nil }
            return (host, p)
        }
        guard let colon = s.lastIndex(of: ":") else { return nil }
        let host = String(s[s.startIndex..<colon])
        guard let p = UInt16(s[s.index(after: colon)...]), !host.isEmpty, !host.contains(":") else { return nil }
        return (host, p)
    }

    static func hostPort(_ s: String) -> (host: NWEndpoint.Host, port: NWEndpoint.Port)? {
        var host = "", portStr = ""
        if s.hasPrefix("[") {                       // [v6]:port
            guard let close = s.firstIndex(of: "]") else { return nil }
            host = String(s[s.index(after: s.startIndex)..<close])
            let rest = s[s.index(after: close)...]
            guard rest.hasPrefix(":") else { return nil }
            portStr = String(rest.dropFirst())
        } else {                                    // v4:port
            guard let colon = s.lastIndex(of: ":") else { return nil }
            host = String(s[s.startIndex..<colon]); portStr = String(s[s.index(after: colon)...])
        }
        guard let p = UInt16(portStr), let port = NWEndpoint.Port(rawValue: p), !host.isEmpty else { return nil }
        return (NWEndpoint.Host(host), port)
    }
}

/// What kind of network is underfoot, in one line for the journal: without it "connected slowly"
/// stays a guess, and with it one sees that the phone went through a tunnel.
enum MontanaNetFacts {
    static func interfaces() -> String {
        var out: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return "?" }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let name = String(cString: cur.pointee.ifa_name)
            let flags = Int32(cur.pointee.ifa_flags)
            if (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0, !out.contains(name) { out.append(name) }
            ptr = cur.pointee.ifa_next
        }
        return out.joined(separator: ",")
    }
}
