import Foundation
import CryptoKit
import Network
import NetworkExtension
#if canImport(MontanaXray)
import MontanaXray
#endif

// Stage 10 (spec s.3 §4.2, §13 stage 10): built-in VPN client on the Xray-core engine, configured from the "Montana Network" page by pasting a subscription link. This file is the
// deterministic Swift side: the link parser (vless:// Reality-Vision + vmess/trojan/ss), the server
// store, and the Xray outbound config generator. The Xray-core engine + NEPacketTunnelProvider are the
// native tunnel layer (Xray-core is a Go binary — the .xcframework is a separate build artifact).
//
// Reality/X25519 masking is a classical circumvention wrapper ([I-16] A-3, DoS-class): its quantum break
// reveals at most the circumvention destinations, never the messenger content (PQ Noise_PQ + E2E inside).

struct MontanaVPNConfig: Codable, Equatable {
    /// EVERY PROTOCOL THE LINKED ENGINE SPEAKS, AND ONE ROW FOR WHAT IT DOES NOT (29.09, the critic's ledger): the engine in
    /// the framework registers Hysteria 2, WireGuard and SOCKS beside the four this file read (infra/conf imports every
    /// proxy and transport package, and the built binary carries them), and a link of a scheme the engine lacks (TUIC,
    /// AnyTLS, ...) is kept as a row that says so instead of vanishing from the plan.
    enum Proto: String, Codable {
        case vless, vmess, trojan, shadowsocks, hysteria2, wireguard, socks, unsupported
        /// A record sealed by a later build may name a protocol this build does not know: that row reads as one this build
        /// cannot speak, and every other row of the list stays (the critic's P-9: one unknown word emptied the whole list).
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Proto(rawValue: raw) ?? .unsupported
        }
        /// The engine's own name for the protocol in its config.
        var engineName: String { self == .hysteria2 ? "hysteria" : rawValue }
    }
    var uid: String? = nil            // stable identity (survives rename/reorder); assigned on load
    var proto: Proto
    var name: String
    var host: String
    var port: UInt16
    var uuidOrPassword: String        // VLESS/VMess UUID, Trojan/SS password
    // stream / security
    var network: String               // tcp, ws, grpc, xhttp...
    var security: String              // reality, tls, none
    var flow: String                  // xtls-rprx-vision (VLESS Reality)
    var sni: String                   // masking SNI (real site)
    var fingerprint: String           // safari, chrome...
    var publicKey: String             // Reality pbk
    var shortId: String               // Reality sid
    var method: String                // SS cipher (aes-256-gcm...)
    // Transport details a link may carry beyond the reference profile. Optional, so a record sealed
    // by an earlier build decodes unchanged: a missing key is nil, not a failure.
    var path: String? = nil           // ws / xhttp / httpupgrade path
    var hostHeader: String? = nil     // ws / xhttp / httpupgrade Host header (not the SNI)
    var mode: String? = nil           // xhttp mode: auto, packet-up, stream-up, stream-one
    var extra: String? = nil          // xhttp "extra" exactly as the link carried it (JSON text)
    var serviceName: String? = nil    // grpc
    var spiderX: String? = nil        // Reality spx
    var subscription: String? = nil   // the subscription URL this server came from; nil when pasted by hand
    // THE FIELDS A LINK CARRIES THAT THE ENGINE HONOURS (29.09, the critic's P-7, P-8): every one optional, so a record
    // sealed by an earlier build decodes unchanged. Two of them are the post-quantum words of a link -- the VLESS
    // encryption (ML-KEM-768) and the REALITY certificate verification (ML-DSA-65) -- and were the two this file dropped.
    var encryption: String? = nil     // VLESS encryption as the link states it (mlkem768x25519plus...); nil or "none": none
    var pqv: String? = nil            // REALITY mldsa65Verify, the link's pqv
    var alpn: String? = nil           // TLS alpn, comma-separated as the link writes it
    var allowInsecure: Bool? = nil    // the link's allowInsecure, kept for the link's round trip only: the engine removed the feature (29.09, loopback control)
    var pinSHA256: String? = nil      // TLS pinnedPeerCertSha256 (the Hysteria 2 pinSHA256)
    var headerType: String? = nil     // raw tcp "http" obfuscation header; kcp header type (srtp, utp, dtls, ...)
    var seed: String? = nil           // kcp seed
    var authority: String? = nil      // grpc authority
    var multiMode: Bool? = nil        // grpc multiMode (the link's mode=multi)
    var obfsPassword: String? = nil   // Hysteria 2 salamander obfuscation password
    var up: String? = nil             // Hysteria 2 bandwidth up, mbps as the link writes it
    var down: String? = nil           // Hysteria 2 bandwidth down, mbps
    var mport: String? = nil          // Hysteria 2 port hopping range ("20000-30000")
    var presharedKey: String? = nil   // WireGuard pre-shared key
    var localIPs: String? = nil       // WireGuard interface IPs, comma-separated ("10.0.0.2/32,fd00::2/128")
    var reserved: String? = nil       // WireGuard reserved bytes, comma-separated ("1,2,3")
    var mtu: Int? = nil               // WireGuard mtu
    var user: String? = nil           // SOCKS user (the password stands in uuidOrPassword)
    var scheme: String? = nil         // unsupported: the scheme the link came with (tuic, anytls, ...)
    var raw: String? = nil            // unsupported: the link itself, so it can be copied and spoken by a later engine
    var reason: String? = nil         // unsupported: why -- the engine's word (protocol, plugin, transport)
    /// THE ENGINE-JSON ROW IS CARRIED WHOLE (29.09, the author's word after T1: every gRPC row of a JSON plan timed out or
    /// closed its pipe while the reference client measured the same rows in 171-399 ms). A panel that serves whole engine
    /// configs tuned every field of the outbound for its own servers -- the gRPC window size and user agent behind a CDN, the
    /// idle and health-check timers, the socket options -- and a row read into this record and written back lost every field
    /// this record has no name for. The outbound is kept as served (JSON text) and handed to the engine as it is; the record's
    /// own fields stand beside it for the page, the diary and the share link. Nil for a row that came as a link.
    var engineOutbound: String? = nil

    static func empty(_ p: Proto) -> MontanaVPNConfig {
        MontanaVPNConfig(proto: p, name: "", host: "", port: 443, uuidOrPassword: "",
                         network: "tcp", security: "none", flow: "", sni: "", fingerprint: "",
                         publicKey: "", shortId: "", method: "")
    }
}

extension MontanaVPNConfig: Identifiable {
    var id: String { uid ?? "\(proto.rawValue):\(host):\(port):\(uuidOrPassword):\(name)" }
}

enum MontanaVPNParse {
    /// The schemes the wild writes that the linked engine does not speak (no proxy/tuic, proxy/anytls in the module tree):
    /// each is kept as a row that says so (29.09). A scheme outside this set and outside the spoken ones is no server link.
    static let unspoken: Set<String> = ["tuic", "tuic5", "anytls", "ssh", "naive+https", "naive+quic", "snell", "ssr", "hysteria", "hy",
                                        "mieru", "juicity", "shadowtls"]
    // Parse a single subscription line (auto-detect by scheme). Returns nil on malformed input.
    static func parse(_ raw: String) -> MontanaVPNConfig? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sep = s.range(of: "://") else { return nil }
        let scheme = String(s[..<sep.lowerBound]).lowercased()
        let rest = String(s[sep.upperBound...])
        switch scheme {
        case "vless":  return parseVless(rest)
        case "trojan": return parseTrojan(rest)
        case "vmess":  return parseVmess(rest)
        case "ss":     return parseSS(rest)
        case "hysteria2", "hy2": return parseHysteria2(rest)
        case "wireguard", "wg":  return parseWireGuard(rest)
        case "socks", "socks5":  return parseSocks(rest)
        default:
            // http(s) is a plan's link, read by MontanaVPNSubscription; a scheme nobody names is not a server.
            guard unspoken.contains(scheme) else { return nil }
            return unsupported(s, scheme: scheme, reason: "protocol")
        }
    }

    /// The row for a link the engine cannot speak: the link itself is kept whole (copied later, spoken by a later engine),
    /// its host and name are read for the list, and its identity is the link.
    static func unsupported(_ link: String, scheme: String, reason: String) -> MontanaVPNConfig {
        var c = MontanaVPNConfig.empty(.unsupported)
        c.scheme = scheme; c.raw = link; c.reason = reason
        c.uuidOrPassword = link
        let body = link.range(of: "://").map { String(link[$0.upperBound...]) } ?? link
        if let (_, host, port, _, frag) = splitURL(body, userRequired: false) { c.host = host; c.port = port; c.name = frag }
        else if let h = body.firstIndex(of: "#") { c.name = String(body[body.index(after: h)...]).removingPercentEncoding ?? "" }
        if c.name.isEmpty { c.name = c.host.isEmpty ? scheme : c.host }
        return c
    }

    /// What a body's lines became: the servers (rows the engine speaks and rows it does not) and the lines that were no
    /// server link at all. The diary names both, so a plan that came in short is seen short (the critic's P-6).
    struct Report {
        var servers: [MontanaVPNConfig] = []
        var dropped = 0
        var unsupported: [String: Int] {
            servers.reduce(into: [:]) { if $1.proto == .unsupported { $0[$1.scheme ?? "?", default: 0] += 1 } }
        }
        var unsupportedWord: String {
            unsupported.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        }
    }
    // Parse many lines / a base64 subscription blob. A line ends at any newline the platform knows -- "\r\n" is ONE character in
    // Swift, equal to neither "\n" nor "\r", and a body served or saved with CRLF endings lost every server on the line of a
    // header before it (29.09, the harness: the plain-text body of testSubscriptionTextBodies read one server of two).
    static func parseMany(_ raw: String) -> [MontanaVPNConfig] { report(raw).servers }
    static func report(_ raw: String) -> Report {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://"), let d = Data(base64Encoded: pad(text)), let dec = String(data: d, encoding: .utf8) { text = dec }
        var r = Report()
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.contains("://"), !l.hasPrefix("#"), !l.hasPrefix("//") else { continue }
            if let c = parse(l) { r.servers.append(c) } else { r.dropped += 1 }
        }
        return r
    }

    private static func flag(_ v: String?) -> Bool? {
        guard let v = v?.lowercased(), !v.isEmpty else { return nil }
        return v == "1" || v == "true" || v == "yes"
    }

    // vless://UUID@host:port?flow=..&type=..&security=reality&fp=..&sni=..&pbk=..&sid=..&pqv=..&encryption=..#Name
    private static func parseVless(_ s: String) -> MontanaVPNConfig? {
        guard let (uuid, host, port, q, frag) = splitURL(s) else { return nil }
        var c = MontanaVPNConfig.empty(.vless)
        c.uuidOrPassword = uuid; c.host = host; c.port = port
        c.name = frag.isEmpty ? host : frag
        c.flow = q["flow"] ?? ""
        if let e = q["encryption"], !e.isEmpty, e != "none" { c.encryption = e }   // the post-quantum VLESS encryption, verbatim
        stream(&c, q)
        return c.host.isEmpty || c.uuidOrPassword.isEmpty ? nil : c
    }

    /// The query keys every link scheme shares for the stream layer (the Xray share-link form): the transport, the wrapper
    /// and what each of them carries.
    private static func stream(_ c: inout MontanaVPNConfig, _ q: [String: String]) {
        if let t = q["type"], !t.isEmpty { c.network = t }
        if let sec = q["security"], !sec.isEmpty { c.security = sec }
        c.sni = q["sni"] ?? q["host"] ?? c.sni
        c.fingerprint = q["fp"] ?? c.fingerprint
        c.publicKey = q["pbk"] ?? c.publicKey
        c.shortId = q["sid"] ?? c.shortId
        c.path = q["path"]; c.hostHeader = q["host"]; c.extra = q["extra"]
        c.serviceName = q["serviceName"]; c.spiderX = q["spx"]
        c.pqv = q["pqv"]; c.alpn = q["alpn"]; c.seed = q["seed"]; c.authority = q["authority"]
        c.allowInsecure = flag(q["allowInsecure"] ?? q["insecure"])
        if let h = q["headerType"], !h.isEmpty, h != "none" { c.headerType = h }
        if c.network == "grpc" { c.multiMode = q["mode"] == "multi" ? true : nil } else { c.mode = q["mode"] }
    }

    private static func parseTrojan(_ s: String) -> MontanaVPNConfig? {
        guard let (pw, host, port, q, frag) = splitURL(s) else { return nil }
        var c = MontanaVPNConfig.empty(.trojan)
        c.uuidOrPassword = pw; c.host = host; c.port = port; c.name = frag.isEmpty ? host : frag
        c.security = "tls"; c.flow = q["flow"] ?? ""
        stream(&c, q)
        return c.host.isEmpty ? nil : c
    }

    // vmess://base64(json)
    private static func parseVmess(_ b64: String) -> MontanaVPNConfig? {
        guard let d = Data(base64Encoded: pad(b64)),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        func str(_ k: String) -> String? {
            if let s = j[k] as? String { return s.isEmpty ? nil : s }
            if let n = j[k] as? Int { return String(n) }
            return nil
        }
        var c = MontanaVPNConfig.empty(.vmess)
        c.host = str("add") ?? ""
        c.port = UInt16(str("port") ?? "") ?? 443
        c.uuidOrPassword = str("id") ?? ""
        c.name = str("ps") ?? c.host
        c.network = str("net") ?? "tcp"
        let tls = (str("tls") ?? "").lowercased()
        c.security = tls.isEmpty || tls == "none" ? "none" : tls   // "tls" and "reality" alike, as the link says
        c.sni = str("sni") ?? str("host") ?? ""
        c.fingerprint = str("fp") ?? ""; c.alpn = str("alpn")
        c.publicKey = str("pbk") ?? ""; c.shortId = str("sid") ?? ""; c.spiderX = str("spx")
        c.method = str("scy") ?? ""                      // the user's cipher; empty stands for auto
        c.allowInsecure = flag(str("allowInsecure") ?? str("insecure"))
        c.path = str("path"); c.hostHeader = str("host")
        if c.network == "grpc" { c.serviceName = str("path"); c.multiMode = str("mode") == "multi" ? true : nil }
        if c.network == "kcp" { c.seed = str("path") }
        if c.network == "xhttp" { c.mode = str("mode") }
        if let t = str("type"), t != "none", c.network == "tcp" || c.network == "kcp" { c.headerType = t }
        return c.host.isEmpty || c.uuidOrPassword.isEmpty ? nil : c
    }

    // ss://base64(method:password)@host:port?type=..#name  OR  ss://method:password@host:port (the 2022 ciphers: SIP002 in the
    // clear, percent-encoded)  OR  ss://base64(method:password@host:port)#name (the legacy whole-link form)
    private static func parseSS(_ rest: String) -> MontanaVPNConfig? {
        var body = rest; var name = ""
        if let h = body.firstIndex(of: "#") { name = String(body[body.index(after: h)...]).removingPercentEncoding ?? ""; body = String(body[..<h]) }
        var q: [String: String] = [:]
        if let qi = body.firstIndex(of: "?") { q = query(String(body[body.index(after: qi)...])); body = String(body[..<qi]) }
        var method = "", password = "", host = "", portS = ""
        if let at = body.lastIndex(of: "@") {
            let creds = String(body[..<at])
            var dec = Data(base64Encoded: pad(creds)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if !dec.contains(":") { dec = creds.removingPercentEncoding ?? creds }
            if let colon = dec.firstIndex(of: ":") { method = String(dec[..<colon]); password = String(dec[dec.index(after: colon)...]) }
            let hp = String(body[body.index(after: at)...])
            if let c = hp.lastIndex(of: ":") { host = String(hp[..<c]); portS = String(hp[hp.index(after: c)...]) }
        } else if let d = Data(base64Encoded: pad(body)), let dec = String(data: d, encoding: .utf8) {   // legacy base64(all)
            if let at = dec.lastIndex(of: "@"), let colon = dec.firstIndex(of: ":") {
                method = String(dec[..<colon]); password = String(dec[dec.index(after: colon)..<at])
                let hp = String(dec[dec.index(after: at)...])
                if let c = hp.lastIndex(of: ":") { host = String(hp[..<c]); portS = String(hp[hp.index(after: c)...]) }
            }
        }
        var c = MontanaVPNConfig.empty(.shadowsocks)
        c.host = host; c.port = UInt16(portS) ?? 443; c.uuidOrPassword = password; c.method = method
        c.name = name.isEmpty ? host : name
        stream(&c, q)
        guard !c.host.isEmpty else { return nil }
        // A SIP003 plugin (obfs-local, v2ray-plugin) is not in the engine: the row says so instead of failing at the dial.
        if let plugin = q["plugin"], !plugin.isEmpty { return unsupported("ss://" + rest, scheme: "ss+plugin", reason: "plugin") }
        return c
    }

    // hysteria2://AUTH@host:port?sni=..&insecure=1&obfs=salamander&obfs-password=..&pinSHA256=..&mport=..&up=..&down=..#Name
    // (hy2:// is the same link). The wrapper is always TLS over QUIC; the engine names the transport "hysteria".
    private static func parseHysteria2(_ s: String) -> MontanaVPNConfig? {
        guard let (auth, host, port, q, frag) = splitURL(s, userRequired: false) else { return nil }
        var c = MontanaVPNConfig.empty(.hysteria2)
        c.uuidOrPassword = auth.removingPercentEncoding ?? auth
        c.host = host; c.port = port; c.name = frag.isEmpty ? host : frag
        c.network = "hysteria"; c.security = "tls"
        c.sni = q["sni"] ?? q["peer"] ?? ""
        c.alpn = q["alpn"]
        c.allowInsecure = flag(q["insecure"] ?? q["allowInsecure"])
        c.pinSHA256 = q["pinSHA256"]
        if (q["obfs"] ?? "").lowercased() == "salamander", let pw = q["obfs-password"], !pw.isEmpty { c.obfsPassword = pw }
        c.mport = q["mport"]; c.up = q["up"] ?? q["upmbps"]; c.down = q["down"] ?? q["downmbps"]
        return c.host.isEmpty ? nil : c
    }

    // wireguard://PRIVATEKEY@host:port?publickey=..&address=10.0.0.2/32,fd00::2/128&reserved=1,2,3&mtu=1280&presharedkey=..#Name
    // (wg:// is the same link). The keys are base64 and may arrive percent-encoded.
    private static func parseWireGuard(_ s: String) -> MontanaVPNConfig? {
        guard let (key, host, port, q, frag) = splitURL(s) else { return nil }
        var c = MontanaVPNConfig.empty(.wireguard)
        c.uuidOrPassword = key.removingPercentEncoding ?? key
        c.host = host; c.port = port; c.name = frag.isEmpty ? host : frag
        c.network = "udp"; c.security = "none"
        c.publicKey = q["publickey"] ?? q["pk"] ?? q["peer"] ?? ""
        c.presharedKey = q["presharedkey"] ?? q["psk"]
        c.localIPs = q["address"] ?? q["ip"]
        c.reserved = q["reserved"]
        c.mtu = q["mtu"].flatMap(Int.init)
        return c.host.isEmpty || c.uuidOrPassword.isEmpty || c.publicKey.isEmpty ? nil : c
    }

    // socks://base64(user:pass)@host:port#Name, socks://user:pass@host:port#Name, or socks://host:port#Name
    private static func parseSocks(_ s: String) -> MontanaVPNConfig? {
        guard let (creds, host, port, _, frag) = splitURL(s, userRequired: false) else { return nil }
        var c = MontanaVPNConfig.empty(.socks)
        c.host = host; c.port = port; c.name = frag.isEmpty ? host : frag
        c.network = "tcp"; c.security = "none"
        var dec = creds.contains(":") ? (creds.removingPercentEncoding ?? creds)
                                      : (Data(base64Encoded: pad(creds)).flatMap { String(data: $0, encoding: .utf8) } ?? "")
        if !dec.contains(":") { dec = "" }
        if let colon = dec.firstIndex(of: ":") { c.user = String(dec[..<colon]); c.uuidOrPassword = String(dec[dec.index(after: colon)...]) }
        return c.host.isEmpty ? nil : c
    }

    private static func query(_ s: String) -> [String: String] {
        var query: [String: String] = [:]
        for kv in s.split(separator: "&") {
            let p = kv.split(separator: "=", maxSplits: 1)
            if p.count == 2 { query[String(p[0])] = String(p[1]).removingPercentEncoding ?? String(p[1]) }
        }
        return query
    }

    // userinfo@host:port?query#fragment. The userinfo is required unless said otherwise (Hysteria 2 and SOCKS may carry none);
    // a path before the query ("host:443/?sni=") is dropped; a port missing stands as 443.
    private static func splitURL(_ s: String, userRequired: Bool = true) -> (user: String, host: String, port: UInt16, query: [String: String], frag: String)? {
        var rest = s, frag = ""
        if let h = rest.firstIndex(of: "#") { frag = String(rest[rest.index(after: h)...]).removingPercentEncoding ?? ""; rest = String(rest[..<h]) }
        var q: [String: String] = [:]
        if let qi = rest.firstIndex(of: "?") { q = query(String(rest[rest.index(after: qi)...])); rest = String(rest[..<qi]) }
        var user = ""
        if let at = rest.lastIndex(of: "@") { user = String(rest[..<at]); rest = String(rest[rest.index(after: at)...]) }
        else if userRequired { return nil }
        if let slash = rest.firstIndex(of: "/") { rest = String(rest[..<slash]) }
        var host = rest, port: UInt16 = 443
        if !rest.hasSuffix("]"), let colon = rest.lastIndex(of: ":"), !rest[rest.index(after: colon)...].contains(":") {
            host = String(rest[..<colon])
            guard let p = UInt16(rest[rest.index(after: colon)...]) else { return nil }
            port = p
        }
        guard !host.isEmpty else { return nil }
        return (user, host, port, q, frag)
    }

    private static func pad(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return t
    }
}

// Xray outbound config generator: every protocol the engine speaks, in the engine's own config words (xray-core
// infra/conf: StreamConfig, TLSConfig, REALITYConfig, HysteriaConfig, WireGuardConfig, SocksClientConfig).
enum MontanaXrayConfig {
    static func outbound(_ c: MontanaVPNConfig) -> [String: Any] {
        if let served = servedOutbound(c) { return served }
        // Xray dials any host form natively; strip IPv6 brackets so the JSON address is a clean literal.
        let endpoint = (c.host.hasPrefix("[") && c.host.hasSuffix("]")) ? String(c.host.dropFirst().dropLast()) : c.host
        switch c.proto {
        case .unsupported:
            // Never installed (MontanaVPNSelection refuses the row); a config that reaches the engine by mistake dials nothing.
            return ["protocol": "blackhole", "tag": "proxy"]
        case .wireguard:
            var peer: [String: Any] = ["publicKey": c.publicKey, "endpoint": "\(c.host):\(c.port)"]
            if let psk = c.presharedKey, !psk.isEmpty { peer["preSharedKey"] = psk }
            let ips = list(c.localIPs)
            var settings: [String: Any] = ["secretKey": c.uuidOrPassword, "peers": [peer], "address": ips.isEmpty ? ["10.0.0.2/32"] : ips]
            if let m = c.mtu, 0 < m { settings["mtu"] = m }
            let reserved = list(c.reserved).compactMap(Int.init)
            if !reserved.isEmpty { settings["reserved"] = reserved }
            return ["protocol": "wireguard", "settings": settings, "tag": "proxy"]
        default: break
        }
        var stream: [String: Any] = ["network": c.network, "security": c.security]
        if c.security == "reality" {
            var rs: [String: Any] = ["serverName": c.sni, "fingerprint": c.fingerprint,
                                     "publicKey": c.publicKey, "shortId": c.shortId, "show": false]
            if let x = c.spiderX, !x.isEmpty { rs["spiderX"] = x }
            if let v = c.pqv, !v.isEmpty { rs["mldsa65Verify"] = v }   // the link's post-quantum verification of the certificate
            stream["realitySettings"] = rs
        } else if c.security == "tls" {
            var ts: [String: Any] = ["serverName": c.sni, "fingerprint": c.fingerprint]
            let alpn = list(c.alpn)
            if !alpn.isEmpty { ts["alpn"] = alpn }
            // The link's allowInsecure is never written: the engine removed it (a config that carries it is refused whole,
            // measured on the loopback 29.09), and its road for a self-signed certificate is the pinned hash, hex with or
            // without colons, which the link's pinSHA256 carries.
            if let pin = c.pinSHA256, !pin.isEmpty { ts["pinnedPeerCertSha256"] = pin }
            stream["tlsSettings"] = ts
        }
        // The stream layer by network, named as the engine's own config names it; a plain "tcp" carries nothing extra.
        switch c.network {
        case "tcp", "raw":
            if c.headerType == "http" {
                var request: [String: Any] = ["path": [c.path ?? "/"]]
                let hostWord = c.hostHeader ?? c.sni
                if !hostWord.isEmpty { request["headers"] = ["Host": list(hostWord)] }
                stream["tcpSettings"] = ["header": ["type": "http", "request": request]]
            }
        case "kcp", "mkcp":
            var k: [String: Any] = [:]
            if let v = c.seed, !v.isEmpty { k["seed"] = v }
            if let h = c.headerType, !h.isEmpty { k["header"] = ["type": h] }
            stream["kcpSettings"] = k
        case "ws":
            var w: [String: Any] = ["path": c.path ?? "/"]
            if let h = c.hostHeader, !h.isEmpty { w["host"] = h }
            stream["wsSettings"] = w
        case "httpupgrade":
            var h: [String: Any] = ["path": c.path ?? "/"]
            if let host = c.hostHeader, !host.isEmpty { h["host"] = host }
            stream["httpupgradeSettings"] = h
        case "xhttp", "splithttp":
            var x: [String: Any] = ["path": c.path ?? "/", "mode": c.mode ?? "auto"]
            if let h = c.hostHeader, !h.isEmpty { x["host"] = h }
            if let e = c.extra, let d = e.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { x["extra"] = j }
            stream["xhttpSettings"] = x
        case "grpc":
            var g: [String: Any] = ["serviceName": c.serviceName ?? ""]
            if let a = c.authority, !a.isEmpty { g["authority"] = a }
            if c.multiMode == true { g["multiMode"] = true }
            stream["grpcSettings"] = g
        case "hysteria":
            stream["hysteriaSettings"] = ["version": 2, "auth": c.uuidOrPassword]
            var mask: [String: Any] = [:]
            if let o = c.obfsPassword, !o.isEmpty { mask["udp"] = [["type": "salamander", "settings": ["password": o]]] }
            var quic: [String: Any] = [:]
            if let u = c.up, let n = Int(u), 0 < n { quic["brutalUp"] = "\(n) mbps" }
            if let d = c.down, let n = Int(d), 0 < n { quic["brutalDown"] = "\(n) mbps" }
            if let m = c.mport, !m.isEmpty { quic["udpHop"] = ["ports": m] }
            if !quic.isEmpty { mask["quicParams"] = quic }
            if !mask.isEmpty { stream["finalmask"] = mask }
        default: break
        }
        var settings: [String: Any]
        switch c.proto {
        case .vless:
            let enc = c.encryption ?? ""
            var user: [String: Any] = ["id": c.uuidOrPassword, "encryption": enc.isEmpty ? "none" : enc]
            if !c.flow.isEmpty { user["flow"] = c.flow }
            settings = ["vnext": [["address": endpoint, "port": Int(c.port), "users": [user]]]]
        case .vmess:
            settings = ["vnext": [["address": endpoint, "port": Int(c.port),
                                   "users": [["id": c.uuidOrPassword, "security": c.method.isEmpty ? "auto" : c.method]]]]]
        case .trojan:
            settings = ["servers": [["address": endpoint, "port": Int(c.port), "password": c.uuidOrPassword]]]
        case .shadowsocks:
            settings = ["servers": [["address": endpoint, "port": Int(c.port), "password": c.uuidOrPassword, "method": c.method]]]
        case .hysteria2:
            settings = ["version": 2, "address": endpoint, "port": Int(c.port)]
        case .socks:
            var server: [String: Any] = ["address": endpoint, "port": Int(c.port)]
            if let u = c.user, !u.isEmpty { server["users"] = [["user": u, "pass": c.uuidOrPassword]] }
            settings = ["servers": [server]]
        case .wireguard, .unsupported:
            settings = [:]   // answered above
        }
        return ["protocol": c.proto.engineName, "settings": settings, "streamSettings": stream, "tag": "proxy"]
    }
    /// A comma-separated word of a link as the list the engine takes.
    static func list(_ s: String?) -> [String] {
        (s ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// THE OUTBOUND A JSON PLAN SERVED, AS IT IS (29.09; the reference client runs the panel's config whole, and its gRPC rows
    /// answer where ours closed the pipe). Two words of ours only: the tag the extension and the measure line address, and the
    /// one TLS key this engine refuses (allowInsecure left the engine; a row that leaned on it verifies the certificate now, as
    /// a link's row does). Every other field reaches the engine exactly as the panel wrote it. Nil for a row that came as a link
    /// or whose served text no longer reads.
    static func servedOutbound(_ c: MontanaVPNConfig) -> [String: Any]? {
        guard c.proto != .unsupported, let t = c.engineOutbound, let d = t.data(using: .utf8),
              var ob = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              (ob["protocol"] as? String) == c.proto.engineName else { return nil }
        ob["tag"] = "proxy"
        if var ss = ob["streamSettings"] as? [String: Any], var ts = ss["tlsSettings"] as? [String: Any], ts["allowInsecure"] != nil {
            ts.removeValue(forKey: "allowInsecure")
            ss["tlsSettings"] = ts
            ob["streamSettings"] = ss
        }
        return ob
    }

    /// THE JSON OF A SERVER, COPIED (the author's example menu 29.09: «Copy JSON»): the row's whole engine config in the form the
    /// plan panels serve and this file reads back (fromEngineConfig) -- so the copy pasted into this page, or into any client
    /// that reads that form, is the same server. A served row hands its outbound whole, with every field this record has no
    /// name for; a link's row hands the outbound this file generates. Keys sorted, so two copies of one row are one text.
    /// Nil for a row the engine cannot speak: there is no config of it to copy.
    static func shareJSON(_ c: MontanaVPNConfig) -> String? {
        guard c.proto != .unsupported else { return nil }
        let full: [String: Any] = ["remarks": c.name, "outbounds": [outbound(c), ["protocol": "freedom", "tag": "direct"]]]
        guard let d = try? JSONSerialization.data(withJSONObject: full, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

// Persistent server list for the "Montana Network" page (sealed under the device key).
enum MontanaVPNStore {
    private static let key = "mt.vpn.servers"
    // THE LIST IS HELD IN MEMORY, AND THE SEALED STORE IS READ ONCE PER PROCESS (the author's word
    // 22.09: the globe thought before it drew). A screen asks for the list on every pass of its body
    // -- the page's toolbar, its head, its sections -- and every ask used to cost a sealed read, a
    // decode of every server and, on the first one, a write of them all back. A body may ask only for
    // free answers; the first read happens off the main thread at launch (warm).
    private static let lock = NSLock()
    private static var held: [MontanaVPNConfig]?
    /// The list as it is held, with one rule enforced at the single place it is read: every row has an
    /// identity of its own. A plan may name one machine twice (an "auto" entry beside its country, same
    /// address, same key) and two rows then shared one identity -- the screen drew one of them twice and
    /// selected both at once, because a list identified by that value cannot tell them apart (22.09).
    static func load() -> [MontanaVPNConfig] {
        lock.lock()
        if let h = held { lock.unlock(); return h }
        lock.unlock()
        var l: [MontanaVPNConfig] = []
        var changed = false
        if let d = MontanaLocalVault.getDecrypted(key) {
            l = decodeRows(d)
            var seen = Set<String>()
            for i in l.indices {
                let u = l[i].uid ?? ""
                if u.isEmpty || seen.contains(u) { l[i].uid = UUID().uuidString; changed = true }
                seen.insert(l[i].uid ?? "")
            }
        }
        lock.lock(); held = l; lock.unlock()
        if changed { writeSealed(l) }   // the repair is written once, never from the reading path again
        return l
    }
    /// THE LIST IS READ ROW BY ROW (29.09, the critic's P-9): one row this build cannot decode keeps that one row out and
    /// every other row in -- never the whole list. The whole list first, since that is the cheap road and the usual one.
    static func decodeRows(_ d: Data) -> [MontanaVPNConfig] {
        if let all = try? JSONDecoder().decode([MontanaVPNConfig].self, from: d) { return all }
        guard let rows = try? JSONSerialization.jsonObject(with: d) as? [Any] else { return [] }
        return rows.compactMap { row in
            (try? JSONSerialization.data(withJSONObject: row)).flatMap { try? JSONDecoder().decode(MontanaVPNConfig.self, from: $0) }
        }
    }
    /// Read the sealed store before anybody asks -- off the main thread, so the first page that wants
    /// the list finds it already held and opens on the frame of the touch.
    static func warm() {
        lock.lock(); let have = held != nil; lock.unlock()
        guard !have else { return }
        DispatchQueue.global(qos: .utility).async { _ = load(); _ = MontanaVPNPlans.load() }
    }
    private static func writeSealed(_ list: [MontanaVPNConfig]) {
        if let d = try? JSONEncoder().encode(list) { MontanaLocalVault.setEncrypted(key, d) }
    }
    static func save(_ list: [MontanaVPNConfig]) {
        lock.lock(); held = list; lock.unlock()
        writeSealed(list)
    }
    /// The store was replaced under the list (a copy laid, 23.09): the next ask reads it again, and a server
    /// added afterwards joins the restored list instead of writing the list of the moment before over it.
    static func forgetHeld() { lock.lock(); held = nil; lock.unlock() }
    /// THE HAND-ADD HAS ONE OWNER (29.09): every row that comes in by hand -- a link, a pasted body, a scanned code, a file,
    /// the form -- joins the list here, with an identity of its own; a row the list already holds (the same machine, port
    /// and secret) is not taken twice. Answers how many joined, so the page can say «already in the list» and mean it.
    @discardableResult
    static func add(_ fresh: [MontanaVPNConfig]) -> Int {
        guard !fresh.isEmpty else { return 0 }
        var list = load()
        var joined = 0
        for var f in fresh where !list.contains(where: { $0.host == f.host && $0.port == f.port && $0.uuidOrPassword == f.uuidOrPassword }) {
            if (f.uid ?? "").isEmpty { f.uid = UUID().uuidString }
            list.append(f); joined += 1
        }
        if 0 < joined { save(list) }
        return joined
    }
    @discardableResult
    static func addFromLink(_ raw: String) -> Int { add(MontanaVPNParse.parseMany(raw)) }
    static func remove(at i: Int) { var l = load(); guard l.indices.contains(i) else { return }; l.remove(at: i); save(l) }
}


// The delay of a server, measured the way every reference client measures it: bring the outbound up and
// time an answer from a 204-endpoint THROUGH it. Two earlier answers were wrong for two different reasons,
// both measured on 22.09:
//
//   1. A TCP handshake to the address in the link measures the ENTRY, not the country. These plans put a
//      node near the user in front of every flag — the "Netherlands" of the author's plan answers from
//      Moscow (2 ms from our Moscow node, 46 ms from Amsterdam), so the row honestly said six milliseconds
//      about a machine that is not in the Netherlands.
//   2. With any tunnel up, the handshake never leaves the device at all: the local stack accepts the
//      connection and only then dials out. Measured on the Mac behind a tunnel — 0 ms to Frankfurt, to
//      Moscow and to 1.1.1.1 alike. A number that is the same for every distance measures nothing.
//
// The road below closes both: the engine dials the server for real, speaks its protocol, fetches a
// 204-endpoint and reports milliseconds — and every socket it opens is bound to the physical interface,
// so our own tunnel is not inside the measurement. Verified against live servers from the Mac:
// 71 ms to that same "Netherlands", 68 ms to "Germany", 60 ms to our own Amsterdam.
// The engine's own measurement, reached through the gomobile boundary. The framework is the one the
// tunnel runs; the app links it too, so a measurement needs no tunnel and disturbs none.
enum MontanaEngineDelay {
    static func measure(_ configJSON: String, _ iface: String) -> (ms: Int?, err: String?) {
        #if canImport(MontanaXray)
        var out: Int64 = -1
        var e: NSError?
        let ok = MontanaxrayMeasureDelay(configJSON, "", iface, &out, &e)
        if ok, 0 <= out { return (Int(out), nil) }
        return (nil, reason(e))
        #else
        return (nil, "engine not linked")
        #endif
    }

    /// The call's own road through a server (24.09): the engine asks our node's STUN through the outbound
    /// (MeasureUDP, proved on the loopback in scripts/xray-ios/measure_udp_test.go -- a server that carries UDP
    /// answers, one whose router refuses UDP answers nothing while its TCP passes). An error is the verdict
    /// «this server passes no UDP»; the caller asks only of a server whose TCP answered.
    static func measureUDP(_ configJSON: String, _ stun: String, _ iface: String) -> (ms: Int?, err: String?) {
        #if canImport(MontanaXray)
        var out: Int64 = -1
        var e: NSError?
        let ok = MontanaxrayMeasureUDP(configJSON, stun, iface, &out, &e)
        if ok, 0 <= out { return (Int(out), nil) }
        return (nil, e?.localizedDescription ?? "no answer")
        #else
        return (nil, "engine not linked")
        #endif
    }

    /// SEVERAL SERVERS AT ONCE THROUGH ONE ENGINE INSTANCE (29.09, the critic's P-1): the outbounds as the engine reads them,
    /// `width` at a time, the answers in the outbounds' order; with a STUN named, the call's road instead of the 204 page.
    /// The deadline lives in the engine (8 s per batch), so nothing of a batch outlives the asker (the critic's P-2).
    static func measureMany(_ outbounds: [[String: Any]], _ iface: String, width: Int, stun: String? = nil) -> [(ms: Int?, err: String?)] {
        guard let d = try? JSONSerialization.data(withJSONObject: outbounds), let json = String(data: d, encoding: .utf8) else {
            return outbounds.map { _ in (nil, "connection error") }
        }
        #if canImport(MontanaXray)
        var e: NSError?
        let text = stun.map { MontanaxrayMeasureUDPMany(json, $0, width, iface, 0, &e) } ?? MontanaxrayMeasureMany(json, "", width, iface, 0, &e)
        return answers(text, count: outbounds.count, error: e)
        #else
        return outbounds.map { _ in (nil, "engine not linked") }
        #endif
    }

    /// The engine's batch answer -- [{"ms":71},{"ms":-1,"err":"..."}] -- as rows; a batch that failed as a whole, or answered
    /// a wrong number of rows, fails every row with the engine's word.
    static func answers(_ text: String, count: Int, error: NSError?) -> [(ms: Int?, err: String?)] {
        guard error == nil, let d = text.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]], rows.count == count else {
            return Array(repeating: (nil, classified(error?.localizedDescription ?? "no answer")), count: count)
        }
        return rows.map { row in
            if let ms = row["ms"] as? Int, 0 <= ms { return (ms, nil) }
            return (nil, classified((row["err"] as? String) ?? "no answer"))
        }
    }

    /// The engine answers in its own words; the screen shows a short honest one.
    private static func reason(_ e: NSError?) -> String { reason(e?.localizedDescription ?? "") }
    static func reason(_ word: String) -> String {
        let d = word.lowercased()
        if d.contains("deadline") || d.contains("timeout") { return "timeout" }
        if d.contains("refused") { return "refused" }
        if d.contains("reset") { return "reset" }
        if d == "eof" || d.hasSuffix(": eof") || d.contains("closed") { return "closed" }
        if d.contains("no such host") || d.contains("dns") { return "DNS error" }
        if d.contains("reality") || d.contains("tls") || d.contains("certificate") { return "TLS error" }
        if d.contains("unreachable") || d.contains("network is down") { return "unreachable" }
        return "connection error"
    }
    /// THE ENGINE'S WORD RIDES INTO THE DIARY BEHIND THE CLASS (29.09, T1: sixty-five grpc rows said «timeout» and nothing
    /// could tell a silent drop from a reset or a refused handshake). The class first, then the engine's own words with every
    /// host and address scrubbed and the spaces closed, so a trace field stays one token: «timeout·dial_tcp_[host]:_i/o_timeout».
    static func classified(_ raw: String) -> String {
        let word = scrub(raw)
        let kind = reason(raw)
        return word.isEmpty ? kind : kind + "·" + word
    }
    static func scrub(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: #"\[[0-9A-Fa-f:.]+\](:\d+)?"#, with: "[ip6]", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d+)?"#, with: "[host]", options: .regularExpression)
        t = t.replacingOccurrences(of: " ", with: "_")
        return String(t.prefix(90))
    }
}

enum MontanaVPNDelay {
    /// How many servers one batch measures at once (the author's word 29.09: «ping six servers at once»).
    static let width = 6
    /// The system's own path, watched from the first ask: its first interface is the one the default route rides
    /// (a phone on Wi-Fi and LTE at once names the one it uses, where a fixed order named Wi-Fi every time).
    private static let pathMonitor: NWPathMonitor = {
        let m = NWPathMonitor()
        m.start(queue: DispatchQueue(label: "mt.vpn.path", qos: .utility))
        return m
    }()
    /// The interface a socket must be bound to so the measurement leaves the device: the system's first choice when it
    /// has spoken, else the first live physical one (Wi-Fi, then cellular). Our own tunnel and every other utun/ipsec are
    /// not candidates.
    static func physicalInterface() -> String {
        if let name = pathMonitor.currentPath.availableInterfaces.first(where: { [.wifi, .cellular, .wiredEthernet].contains($0.type) })?.name,
           !name.isEmpty { return name }
        var names: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return "" }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0,
                  let sa = cur.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) || sa.pointee.sa_family == UInt8(AF_INET6) else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            guard !name.hasPrefix("utun"), !name.hasPrefix("ipsec"), !name.hasPrefix("ppp"),
                  !name.hasPrefix("awdl"), !name.hasPrefix("llw"), !name.hasPrefix("lo") else { continue }
            if !names.contains(name) { names.append(name) }
        }
        // en0 is the phone's Wi-Fi, pdp_ip0 its cellular; on a Mac the Wi-Fi may be en1.
        for wanted in ["en0", "en1", "pdp_ip0"] where names.contains(wanted) { return wanted }
        return names.first ?? ""
    }

    /// One server as a config the engine can run: the outbound and nothing else. The engine drops inbounds
    /// itself; routing, dns and policy belong to the tunnel, not to a measurement.
    static func probeConfig(_ c: MontanaVPNConfig) -> String? {
        let full: [String: Any] = ["log": ["loglevel": "warning"],
                                   "outbounds": [MontanaXrayConfig.outbound(c), ["protocol": "freedom", "tag": "direct"]]]
        guard let d = try? JSONSerialization.data(withJSONObject: full) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Several servers at once, by the one road (29.09): under a standing tunnel the provider measures them through its own
    /// engine (one instance for the batch); without one the app's engine does, bound to the physical interface. The answers
    /// stand in the list's order.
    static func measureMany(_ list: [MontanaVPNConfig], stun: String? = nil) async -> [(ms: Int?, err: String?)] {
        guard !list.isEmpty else { return [] }
        let outbounds = list.map { MontanaXrayConfig.outbound($0) }
        if let answer = await MontanaVPNTunnel.shared.measureCandidates(outbounds, stun: stun) { return answer }
        let iface = physicalInterface()
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: MontanaEngineDelay.measureMany(outbounds, iface, width: width, stun: stun))
            }
        }
    }

    static func measure(_ c: MontanaVPNConfig) async -> (ms: Int?, err: String?) {
        await measureMany([c]).first ?? (nil, "connection error")
    }
}

/// THE SERVER THE TUNNEL STANDS ON (24.09): one writer of the choice -- the person's tap and the calls'
/// pick both come here; the page's AppStorage reads the same key.
enum MontanaVPNSelection {
    static let key = "mt.vpn.sel"
    /// THE PERSON'S LAST HAND ON THE VPN (30.09): a tap on a row or on the power. Nothing automatic raises another row sooner than
    /// the dead rows' ten minutes after it (MontanaVPNDead.cooldown); the VPN wall's road waits them out (MTVPNWhitelistRoad).
    static let handKey = "mt.vpn.hand"
    static var handAt: Double { UserDefaults.standard.double(forKey: handKey) }
    static func noteHand() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: handKey) }
    /// THE CHOICE IS SPOKEN, NOT ONLY WRITTEN (the author's word 25.09, the iPhone 17: the dead row gave way to a live one and
    /// the green edge stayed on the dead one). The page drew the chosen row from the store's key through the platform's own
    /// observation, and the key carries dots -- a key path to that observation, which never fired for a write from outside
    /// the page. The one owner of the tunnel now publishes the choice (MontanaVPNTunnel.selectedId), and the page draws it.
    @MainActor static func adopt(_ id: String) {
        UserDefaults.standard.set(id, forKey: key)
        MontanaVPNTunnel.shared.noteSelection(id)
    }
    @MainActor static func select(_ cfg: MontanaVPNConfig, why: String) async {
        guard cfg.proto != .unsupported else {   // the row says what it is; nothing is installed from it (29.09)
            MontanaP2PTrace.mark("vpn_ui", "select refused row=\(String(cfg.id.prefix(8))) scheme=\(cfg.scheme ?? "?") -- the engine cannot speak it")
            return
        }
        adopt(cfg.id)
        if why == "hand" { MontanaVPNDead.clear(cfg.id); noteHand() }   // the person's finger outranks the dead mark (25.09) and stands ten minutes (30.09)
        let on = MontanaVPNTunnel.shared.isOn
        MontanaP2PTrace.mark("vpn_ui", "select row=\(String(cfg.id.prefix(8))) net=\(cfg.network) sec=\(cfg.security) by=\(why) restart=\(on)")
        guard on else { return }
        await MontanaVPNTunnel.shared.restart(cfg)
    }
}

/// THE BOOK OF DELAYS (29.09, the critic's P-5): one owner of what every server last answered -- the milliseconds or the
/// error, and the moment. The row draws the last number always (dimmed past half an hour) and a spinner only while a
/// measurement flies, so a list of a hundred rows never stands empty while the line walks it. Kept in the settings under
/// this device's own key: a delay is this network's word about this hour, not a setting a copy carries.
@MainActor final class MontanaVPNDelayBook: ObservableObject {
    static let shared = MontanaVPNDelayBook()
    static let key = "mt.vpn.delays"
    static let stale: TimeInterval = 1800
    struct Entry: Equatable {
        var ms: Int?
        var err: String?
        var at: Double                    // unix seconds of the measurement
        var age: TimeInterval { max(0, Date().timeIntervalSince1970 - at) }
    }
    @Published private(set) var entries: [String: Entry] = [:]
    private init() {
        // The stored form is [id: [ms, at]], ms -1 for an answer of no number; the error's word is not kept across runs.
        let raw = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [Double]] ?? [:]
        for (id, v) in raw where v.count == 2 {
            entries[id] = Entry(ms: v[0] < 0 ? nil : Int(v[0]), err: v[0] < 0 ? "no answer" : nil, at: v[1])
        }
    }
    func record(_ id: String, _ r: (ms: Int?, err: String?)) {
        entries[id] = Entry(ms: r.ms, err: r.ms == nil ? (r.err ?? "no answer") : nil, at: Date().timeIntervalSince1970)
    }
    /// Kept once per batch, never per row (a store write is a broadcast), and only for servers the list still holds.
    func persist() {
        let known = Set(MontanaVPNStore.load().map { $0.id })
        var raw: [String: [Double]] = [:]
        for (id, e) in entries where known.contains(id) { raw[id] = [Double(e.ms ?? -1), e.at] }
        UserDefaults.standard.set(raw, forKey: Self.key)
    }
    /// The stalest of the given servers: never measured first, then the oldest measurement. Nil when there is none to ask.
    func stalest(of list: [MontanaVPNConfig]) -> MontanaVPNConfig? {
        list.filter { $0.proto != .unsupported }.min { (entries[$0.id]?.at ?? 0) < (entries[$1.id]?.at ?? 0) }
    }
}

/// EVERY LOAD OF A PLAN STANDS IN ONE LINE (29.09): the page's refresh and the freshener's beat may ask for one plan in the
/// same second, and two loads writing the list at once would lose the server added by hand between them.
@MainActor enum MontanaVPNLoadLine {
    private static var tail: Task<Void, Never>?
    static func run<T: Sendable>(_ work: @escaping @MainActor () async throws -> T) async throws -> T {
        let prior = tail
        let t = Task<T, Error> { @MainActor in
            await prior?.value
            return try await work()
        }
        tail = Task { _ = try? await t.value }
        return try await t.value
    }
}

/// THE FRESHENER (the author's word 30.09: «the update on the VPN page, too, at a press of the hand or once an hour; ... automatically
/// once an hour it checks natively and slows nothing, strictly in turn, one subscription, then a pause of 13 seconds, then the next;
/// the top six by the person's own order on the VPN wall are checked, the rest by hand»; and 30.09: «a ping only at a press of the
/// hand»). One owner of the quiet beat, alive while the app stands on the screen: once an hour -- and at a return after more than an
/// hour away -- the first six plans of the page's own order are asked again, one at a time with thirteen seconds between: a plan by its
/// link, a correspondent's wall of that correspondent (for a person who shares their presence: an ask at a return says when they came
/// back). The rest wait for the hand: a plan's own update button, a wall's own update button, the pull of the page. Opening the page
/// loads nothing, and nothing here measures a server.
@MainActor final class MontanaVPNFreshener: ObservableObject {
    static let shared = MontanaVPNFreshener()
    static let beat: TimeInterval = 3600
    static let top = 6                                  // the plans a beat asks, in the page's order; the rest are asked by hand
    static let pause: UInt64 = 13_000_000_000           // between two plans of a beat, so a beat never lands as one burst
    @Published private(set) var generation = 0         // moves when a plan was loaded again under the page
    private var timer: Timer?
    private var beating = false
    private var pulling = false
    private var lastBeat = Date.distantPast

    /// A plan moved by another hand than a load (a correspondent's wall landed): the page reloads by the same word.
    func moved() { generation += 1 }
    func appActive(_ active: Bool) {
        timer?.invalidate(); timer = nil
        guard active else { return }
        MTVPNWall.shared.appReturned()   // the VPN wall is carried at a return, to whoever holds an older page -- unless the person hides their presence (29.09)
        timer = Timer.scheduledTimer(withTimeInterval: Self.beat, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.hourBeat(reason: "hour") }
        }
        if Self.beat <= Date().timeIntervalSince(lastBeat) { Task { await hourBeat(reason: "return") } }
    }
    /// The pull of the page, the person's own hand: every plan is loaded now, one after another.
    func coinRefresh() async {
        guard !pulling else { return }
        pulling = true
        defer { pulling = false }
        var refreshed = 0
        for plan in MontanaVPNPlans.load() {
            guard !MTVPNWall.isWallKey(plan.url), let url = URL(string: plan.url) else { continue }
            if (try? await MontanaVPNStore.addFromSubscription(url)) != nil { refreshed += 1 }
        }
        if 0 < refreshed { generation += 1 }
        MontanaP2PTrace.mark("vpn_ui", "fresh coin plans=\(refreshed)")
    }

    private func hourBeat(reason: String) async {
        guard !beating else { return }
        beating = true
        defer { beating = false }
        lastBeat = Date()
        let first = Array(MontanaVPNPlans.ordered(wallRank: MTVPNWall.chatRank()).prefix(Self.top))
        let asks = MontanaPresencePrivacy.sharing
        var asked = 0
        for plan in first {
            if 0 < asked { try? await Task.sleep(nanoseconds: Self.pause) }
            asked += 1
            if let conv = plan.wallOf, MTVPNWall.isWallKey(plan.url) {
                if asks { MTVPNWall.shared.ask(conv) }
            } else if let url = URL(string: plan.url), (try? await MontanaVPNStore.addFromSubscription(url)) != nil {
                generation += 1
            }
        }
        if asks { MTVPNWall.shared.askMissing() }
        MontanaP2PTrace.mark("vpn_ui", "fresh \(reason) plans=\(asked) of=\(MontanaVPNPlans.load().count)")
    }
}

// The words for a failed start of the tunnel (the system's own error, said shortly).
enum MontanaVPNPing {
    // Short label for a tunnel-start failure (NEVPNManager errors) shown under the connect button.
    static func startErr(_ e: Error) -> String {
        let ns = e as NSError
        if ns.domain == NEVPNErrorDomain, let c = NEVPNError.Code(rawValue: ns.code) {
            switch c {
            case .configurationInvalid, .configurationDisabled, .configurationReadWriteFailed, .configurationStale, .configurationUnknown:
                return "VPN permission denied"
            default: return "tunnel error"
            }
        }
        let d = ns.localizedDescription.lowercased()
        if d.contains("permission") || d.contains("denied") || d.contains("not permitted") { return "VPN permission denied" }
        return "tunnel error"
    }
}


// Rename a stored server (long-press menu) and reconstruct a shareable link (copy).
extension MontanaVPNStore {
    static func rename(at i: Int, to name: String) {
        var l = load(); guard l.indices.contains(i) else { return }
        l[i].name = name; save(l)
    }
}

extension MontanaVPNParse {
    static func serialize(_ c: MontanaVPNConfig) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=#?"))
        func e(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        let frag = c.name.isEmpty ? "" : "#" + e(c.name)
        switch c.proto {
        case .vless:
            var q = ["type=\(c.network)", "security=\(c.security)"]
            if !c.flow.isEmpty { q.append("flow=\(c.flow)") }
            if let v = c.encryption, !v.isEmpty { q.append("encryption=\(e(v))") }
            q += wrapperQuery(c, e) + transportQuery(c, e)
            return "vless://\(c.uuidOrPassword)@\(c.host):\(c.port)?\(q.joined(separator: "&"))\(frag)"
        case .trojan:
            var q = ["type=\(c.network)", "security=\(c.security)"]
            if !c.flow.isEmpty { q.append("flow=\(c.flow)") }
            q += wrapperQuery(c, e) + transportQuery(c, e)
            return "trojan://\(c.uuidOrPassword)@\(c.host):\(c.port)?\(q.joined(separator: "&"))\(frag)"
        case .vmess:
            let path = (c.network == "grpc" ? c.serviceName : (c.network == "kcp" ? c.seed : c.path)) ?? ""
            var j: [String: Any] = ["v": "2", "ps": c.name, "add": c.host, "port": "\(c.port)",
                                    "id": c.uuidOrPassword, "net": c.network, "type": c.headerType ?? "none",
                                    "tls": c.security == "none" ? "" : c.security, "sni": c.sni, "host": c.hostHeader ?? "",
                                    "path": path, "aid": "0", "scy": c.method.isEmpty ? "auto" : c.method, "fp": c.fingerprint]
            if let a = c.alpn, !a.isEmpty { j["alpn"] = a }
            if !c.publicKey.isEmpty { j["pbk"] = c.publicKey; j["sid"] = c.shortId }
            if let m = c.mode, !m.isEmpty { j["mode"] = m }
            let d = (try? JSONSerialization.data(withJSONObject: j)) ?? Data()
            return "vmess://" + d.base64EncodedString()
        case .shadowsocks:
            let creds = "\(c.method):\(c.uuidOrPassword)".data(using: .utf8)?.base64EncodedString() ?? ""
            let q = wrapperQuery(c, e) + transportQuery(c, e)
            let tail = c.network == "tcp" && q.isEmpty ? "" : "?" + (["type=\(c.network)", "security=\(c.security)"] + q).joined(separator: "&")
            return "ss://\(creds)@\(c.host):\(c.port)\(tail)\(frag)"
        case .hysteria2:
            var q: [String] = []
            if !c.sni.isEmpty { q.append("sni=\(e(c.sni))") }
            if c.allowInsecure == true { q.append("insecure=1") }
            if let o = c.obfsPassword, !o.isEmpty { q.append("obfs=salamander"); q.append("obfs-password=\(e(o))") }
            if let v = c.pinSHA256, !v.isEmpty { q.append("pinSHA256=\(e(v))") }
            if let v = c.mport, !v.isEmpty { q.append("mport=\(e(v))") }
            if let v = c.up, !v.isEmpty { q.append("up=\(e(v))") }
            if let v = c.down, !v.isEmpty { q.append("down=\(e(v))") }
            if let v = c.alpn, !v.isEmpty { q.append("alpn=\(e(v))") }
            return "hysteria2://\(e(c.uuidOrPassword))@\(c.host):\(c.port)?\(q.joined(separator: "&"))\(frag)"
        case .wireguard:
            var q = ["publickey=\(e(c.publicKey))"]
            if let v = c.localIPs, !v.isEmpty { q.append("address=\(e(v))") }
            if let v = c.reserved, !v.isEmpty { q.append("reserved=\(e(v))") }
            if let v = c.mtu { q.append("mtu=\(v)") }
            if let v = c.presharedKey, !v.isEmpty { q.append("presharedkey=\(e(v))") }
            return "wireguard://\(e(c.uuidOrPassword))@\(c.host):\(c.port)?\(q.joined(separator: "&"))\(frag)"
        case .socks:
            let user = c.user ?? ""
            let creds = user.isEmpty ? "" : ("\(user):\(c.uuidOrPassword)".data(using: .utf8)?.base64EncodedString() ?? "") + "@"
            return "socks://\(creds)\(c.host):\(c.port)\(frag)"
        case .unsupported:
            return c.raw ?? ""
        }
    }

    /// The wrapper's own words (TLS and REALITY), the same for every scheme that carries them.
    private static func wrapperQuery(_ c: MontanaVPNConfig, _ e: (String) -> String) -> [String] {
        var q: [String] = []
        if !c.sni.isEmpty { q.append("sni=\(e(c.sni))") }
        if !c.fingerprint.isEmpty { q.append("fp=\(c.fingerprint)") }
        if !c.publicKey.isEmpty { q.append("pbk=\(e(c.publicKey))") }
        if !c.shortId.isEmpty { q.append("sid=\(c.shortId)") }
        if let v = c.pqv, !v.isEmpty { q.append("pqv=\(e(v))") }
        if let v = c.alpn, !v.isEmpty { q.append("alpn=\(e(v))") }
        if c.allowInsecure == true { q.append("allowInsecure=1") }
        if let v = c.pinSHA256, !v.isEmpty { q.append("pinSHA256=\(e(v))") }
        return q
    }

    private static func transportQuery(_ c: MontanaVPNConfig, _ e: (String) -> String) -> [String] {
        var q: [String] = []
        if let v = c.path, !v.isEmpty { q.append("path=\(e(v))") }
        if let v = c.hostHeader, !v.isEmpty { q.append("host=\(e(v))") }
        if let v = c.mode, !v.isEmpty { q.append("mode=\(v)") }
        if c.multiMode == true { q.append("mode=multi") }
        if let v = c.extra, !v.isEmpty { q.append("extra=\(e(v))") }
        if let v = c.serviceName, !v.isEmpty { q.append("serviceName=\(e(v))") }
        if let v = c.authority, !v.isEmpty { q.append("authority=\(e(v))") }
        if let v = c.spiderX, !v.isEmpty { q.append("spx=\(e(v))") }
        if let v = c.headerType, !v.isEmpty { q.append("headerType=\(v)") }
        if let v = c.seed, !v.isEmpty { q.append("seed=\(e(v))") }
        return q
    }
}


// A subscription link (https://…) — one address that hands out every server of the plan. Five body
// forms exist in the wild and all five are read: a base64 blob of share links, plain text with
// `#profile-*` header lines before the links, the JSON array of whole engine configs that the
// panels serve to one popular client, the sing-box JSON and the Clash YAML (29.09). Measured 22.09 on the author's three links: every panel behind
// them (Remnawave and its kin) hands real profiles only to a request that names a device by `x-hwid`
// and answers a placeholder "App not supported" without it — the name of the application is not what
// they check. The id is random, minted once per install and sealed with the device key: the provider
// learns a number of ours, never the phone's own identifier. A plan that counts devices counts this
// one as one of them.
enum MontanaVPNSubscription {
    private static let deviceKey = "mt.vpn.hwid"

    static func isSubscriptionURL(_ s: String) -> URL? {
        let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = raw.lowercased()
        guard low.hasPrefix("https://") || low.hasPrefix("http://") else { return nil }
        // The fragment names the profile for a human; the server never sees it.
        let bare = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? raw
        return URL(string: bare)
    }

    static func deviceId() -> String {
        if let d = MontanaLocalVault.getDecrypted(deviceKey), let s = String(data: d, encoding: .utf8), !s.isEmpty { return s }
        let fresh = UUID().uuidString.lowercased()
        MontanaLocalVault.setEncrypted(deviceKey, Data(fresh.utf8))
        return fresh
    }

    /// SERVER-DEBT-ACK: the paid subscription's own panel, and nothing of ours — the person pastes the
    /// link their provider gave them, and this is the road that reads it. No Montana server stands on it, no
    /// identifier of a person and no letter travels it: only the shape that panel's protocol asks for. The
    /// link itself lies in the sealed store on the device.
    static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var sys = utsname(); uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
        req.setValue("Montana/\(ver) (iOS)", forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue(deviceId(), forHTTPHeaderField: "x-hwid")
        req.setValue("iOS", forHTTPHeaderField: "x-device-os")
        req.setValue("\(os.majorVersion).\(os.minorVersion)", forHTTPHeaderField: "x-ver-os")
        req.setValue(model, forHTTPHeaderField: "x-device-model")
        return req
    }

    enum FetchError: Error, Equatable {
        case status(Int), network, empty, form(String)
        // The words the screen shows for a failure: the code when the panel answered, the class when it did not, the form
        // of a body that named no server (an HTML page in place of a plan).
        var label: String {
            switch self {
            case .status(let c): return "HTTP \(c)"
            case .network: return "network"
            case .empty: return "empty"
            case .form(let f): return "body: \(f)"
            }
        }
    }

    struct Fetched {
        var servers: [MontanaVPNConfig]
        var title: String
        var userinfo: [String: Int64]     // upload / download / total / expire as the panel states them
        var updateHours: Int?             // profile-update-interval, hours
        var form: String = ""             // the body's form, as body(_:) names it
        var dropped = 0                   // lines with a scheme that were no server link
    }

    static let attempts = 4
    /// One attempt is not an answer: the panel behind the author's link returned 502 on three requests of
    /// eight (measured 22.09) and a client that gave up on the first one reported a dead plan that was
    /// alive. A 5xx or a network fault is retried with a short pause; a 4xx is the panel's word and stands.
    static func fetch(_ url: URL, onAttempt: ((Int) -> Void)? = nil) async throws -> Fetched {
        var last: FetchError = .network
        for attempt in 1...attempts {
            onAttempt?(attempt)
            do {
                let (data, resp) = try await URLSession.shared.data(for: request(url))   // SERVER-DEBT-ACK: the subscription panel behind the person's own link (see request(_:))
                let http = resp as? HTTPURLResponse
                let code = http?.statusCode ?? 0
                if (200..<300).contains(code) {
                    let read = body(data)
                    let list = read.servers.map { c -> MontanaVPNConfig in var m = c; m.subscription = url.absoluteString; return m }
                    let title = headerText(http, "profile-title")
                    let info = userinfo(headerText(http, "subscription-userinfo"))
                    // The link carries the plan's secret; the diary gets the host and the numbers only -- and what of the body
                    // was not read: the rows the engine cannot speak, by scheme, and the lines that were no server (29.09).
                    let unspoken = MontanaVPNParse.Report(servers: list).unsupportedWord
                    MontanaP2PTrace.mark("vpn_sub", "plan=\(MontanaLog.label(url.absoluteString)) try=\(attempt) status=\(code) bytes=\(data.count) form=\(read.form) servers=\(list.count) unsupported=\(unspoken.isEmpty ? "-" : unspoken) dropped=\(read.dropped)")
                    guard !list.isEmpty else {
                        throw ["links", "base64", "engine-json", "sing-box", "clash"].contains(read.form) ? FetchError.empty : FetchError.form(read.form)
                    }
                    return Fetched(servers: list, title: title, userinfo: info, updateHours: Int(headerText(http, "profile-update-interval")),
                                   form: read.form, dropped: read.dropped)
                }
                MontanaP2PTrace.mark("vpn_sub", "plan=\(MontanaLog.label(url.absoluteString)) try=\(attempt) status=\(code) bytes=\(data.count)")
                last = .status(code)
                if code < 500 { throw last }
            } catch let e as FetchError {
                if case .status(let c) = e, 500 <= c { last = e } else { throw e }
            } catch {
                MontanaP2PTrace.mark("vpn_sub", "plan=\(MontanaLog.label(url.absoluteString)) try=\(attempt) err=\((error as NSError).code)")
                last = .network
            }
            if attempt < attempts { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        }
        throw last
    }

    // "base64:..." or plain, as the panels write the profile title header; no header — the host stands.
    // COMPAT-LOCAL: a panel's HTTP header read on this device — never a word between Montana builds.
    static func headerText(_ http: HTTPURLResponse?, _ name: String) -> String {
        guard let raw = http?.value(forHTTPHeaderField: name)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return "" }
        if raw.lowercased().hasPrefix("base64:") {
            let b = String(raw.dropFirst("base64:".count))
            var pad = b; while pad.count % 4 != 0 { pad += "=" }
            if let d = Data(base64Encoded: pad), let s = String(data: d, encoding: .utf8) { return s }
        }
        return raw
    }

    // "upload=0; download=40333815636; total=0; expire=1820218794"
    static func userinfo(_ s: String) -> [String: Int64] {
        var out: [String: Int64] = [:]
        for part in s.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, let v = Int64(kv[1]) { out[kv[0]] = v }
        }
        return out
    }

    /// What a body became and in what form it came (the critic's P-6: a plan that came in short is seen short).
    struct Body {
        var servers: [MontanaVPNConfig] = []
        var dropped = 0
        var form = ""          // links, base64, engine-json, sing-box, clash, wireguard, hysteria, openvpn, profile, html, binary
    }
    // Pure: the body in any of its forms to the servers it names. The name is the file's own, for a form that carries none
    // (a WireGuard interface, a Hysteria 2 config, one engine config without remarks); a plan's body names its rows itself.
    static func parseBody(_ data: Data) -> [MontanaVPNConfig] { body(data).servers }
    static func body(_ data: Data, name: String = "") -> Body {
        guard let text = String(data: data, encoding: .utf8) else { return Body(form: "binary") }
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var b = Body()
        if s.hasPrefix("[") || s.hasPrefix("{"), let j = try? JSONSerialization.jsonObject(with: data) {
            if let one = j as? [String: Any], let outs = one["outbounds"] as? [[String: Any]],
               outs.contains(where: { $0["type"] != nil && $0["protocol"] == nil }) {
                b.form = "sing-box"; b.servers = outs.compactMap(fromSingBox); return b
            }
            let configs = (j as? [[String: Any]]) ?? ((j as? [String: Any]).map { [$0] } ?? [])
            b.form = "engine-json"; b.servers = configs.compactMap { fromEngineConfig($0, name: name) }; b.dropped = configs.count - b.servers.count
            return b
        }
        // THE PROFILE FILES (29.09), each by its shape, never by its extension: the platform's own VPN profile is XML and would
        // read as a page, so it is asked before the page; the WireGuard interface, the Hysteria 2 config and the OpenVPN
        // profile after the Clash body, whose `proxies:` names it first.
        if MontanaVPNFile.looksLikeProfile(s) { b.form = "profile"; b.servers = MontanaVPNFile.profile(data, name: name).map { [$0] } ?? []; return b }
        if s.hasPrefix("<") { b.form = "html"; return b }
        if MontanaVPNClash.looksLike(s) { b.form = "clash"; b.servers = MontanaVPNClash.servers(s); return b }
        if MontanaVPNFile.looksLikeWireGuard(s) { b.form = "wireguard"; b.servers = MontanaVPNFile.wireGuard(s, name: name).map { [$0] } ?? []; return b }
        if MontanaVPNFile.looksLikeHysteria(s) { b.form = "hysteria"; b.servers = MontanaVPNFile.hysteria(s, name: name).map { [$0] } ?? []; return b }
        if MontanaVPNFile.looksLikeOpenVPN(s) { b.form = "openvpn"; b.servers = [MontanaVPNFile.openVPN(text, name: name)]; return b }   // the profile kept whole, as the file holds it
        let r = MontanaVPNParse.report(s)
        b.form = s.contains("://") ? "links" : "base64"; b.servers = r.servers; b.dropped = r.dropped
        return b
    }

    static func port(_ v: Any?) -> UInt16 {
        if let n = v as? Int { return UInt16(exactly: n) ?? 0 }
        if let t = v as? String { return UInt16(t) ?? 0 }
        return 0
    }

    // One whole engine config (as the panels serve them) to the server it dials: the outbound tagged "proxy", or the first
    // one of a protocol we speak. Everything else in the config — inbounds, routing, dns — is that client's own policy and
    // is not ours to carry.
    static func fromEngineConfig(_ c: [String: Any], name fallback: String = "") -> MontanaVPNConfig? {
        let outs = (c["outbounds"] as? [[String: Any]]) ?? []
        let speak: [String: MontanaVPNConfig.Proto] = ["vless": .vless, "vmess": .vmess, "trojan": .trojan, "shadowsocks": .shadowsocks,
                                                       "hysteria": .hysteria2, "wireguard": .wireguard, "socks": .socks]
        guard let ob = outs.first(where: { ($0["tag"] as? String) == "proxy" && speak[($0["protocol"] as? String) ?? ""] != nil })
                ?? outs.first(where: { speak[($0["protocol"] as? String) ?? ""] != nil }),
              let proto = speak[(ob["protocol"] as? String) ?? ""],
              let settings = ob["settings"] as? [String: Any] else { return nil }
        var cfg = MontanaVPNConfig.empty(proto)
        cfg.name = (c["remarks"] as? String) ?? ""
        if cfg.name.isEmpty { cfg.name = fallback }   // a file's own name, when the config carries none (29.09)
        // The outbound as the panel served it, whole (see engineOutbound): the fields below are the record's reading of it.
        if let d = try? JSONSerialization.data(withJSONObject: ob, options: [.sortedKeys]), let t = String(data: d, encoding: .utf8) { cfg.engineOutbound = t }
        switch proto {
        case .vless, .vmess:
            guard let v = (settings["vnext"] as? [[String: Any]])?.first,
                  let u = (v["users"] as? [[String: Any]])?.first else { return nil }
            cfg.host = (v["address"] as? String) ?? ""
            cfg.port = port(v["port"])
            cfg.uuidOrPassword = (u["id"] as? String) ?? ""
            cfg.flow = (u["flow"] as? String) ?? ""
            if proto == .vless, let e = u["encryption"] as? String, !e.isEmpty, e != "none" { cfg.encryption = e }
            if proto == .vmess, let sec = u["security"] as? String, sec != "auto" { cfg.method = sec }
        case .trojan, .shadowsocks:
            guard let v = (settings["servers"] as? [[String: Any]])?.first else { return nil }
            cfg.host = (v["address"] as? String) ?? ""
            cfg.port = port(v["port"])
            cfg.uuidOrPassword = (v["password"] as? String) ?? ""
            cfg.method = (v["method"] as? String) ?? ""
        case .socks:
            guard let v = (settings["servers"] as? [[String: Any]])?.first else { return nil }
            cfg.host = (v["address"] as? String) ?? ""
            cfg.port = port(v["port"])
            if let u = (v["users"] as? [[String: Any]])?.first { cfg.user = u["user"] as? String; cfg.uuidOrPassword = (u["pass"] as? String) ?? "" }
        case .hysteria2:
            cfg.host = (settings["address"] as? String) ?? ""
            cfg.port = port(settings["port"])
        case .wireguard:
            cfg.uuidOrPassword = (settings["secretKey"] as? String) ?? ""
            cfg.localIPs = (settings["address"] as? [String])?.joined(separator: ",")
            if let m = settings["mtu"] as? Int, 0 < m { cfg.mtu = m }
            if let r = settings["reserved"] as? [Int] { cfg.reserved = r.map(String.init).joined(separator: ",") }
            if let peer = (settings["peers"] as? [[String: Any]])?.first {
                cfg.publicKey = (peer["publicKey"] as? String) ?? ""
                cfg.presharedKey = peer["preSharedKey"] as? String
                let ep = (peer["endpoint"] as? String) ?? ""
                if let colon = ep.lastIndex(of: ":") { cfg.host = String(ep[..<colon]); cfg.port = UInt16(ep[ep.index(after: colon)...]) ?? 0 }
            }
            cfg.network = "udp"
            if cfg.name.isEmpty { cfg.name = cfg.host }
            return cfg.host.isEmpty || cfg.port == 0 || cfg.uuidOrPassword.isEmpty || cfg.publicKey.isEmpty ? nil : cfg
        case .unsupported:
            return nil
        }
        let ss = (ob["streamSettings"] as? [String: Any]) ?? [:]
        cfg.network = (ss["network"] as? String) ?? (proto == .hysteria2 ? "hysteria" : "tcp")
        cfg.security = (ss["security"] as? String) ?? (proto == .hysteria2 ? "tls" : "none")
        if cfg.network == "splithttp" { cfg.network = "xhttp" }
        if cfg.network == "raw" { cfg.network = "tcp" }
        if cfg.network == "mkcp" { cfg.network = "kcp" }
        if let rs = ss["realitySettings"] as? [String: Any] {
            cfg.sni = (rs["serverName"] as? String) ?? ""
            cfg.fingerprint = (rs["fingerprint"] as? String) ?? ""
            cfg.publicKey = (rs["publicKey"] as? String) ?? ""
            cfg.shortId = (rs["shortId"] as? String) ?? ""
            cfg.spiderX = rs["spiderX"] as? String
            cfg.pqv = rs["mldsa65Verify"] as? String
        } else if let ts = ss["tlsSettings"] as? [String: Any] {
            cfg.sni = (ts["serverName"] as? String) ?? ""
            cfg.fingerprint = (ts["fingerprint"] as? String) ?? ""
            cfg.alpn = (ts["alpn"] as? [String])?.joined(separator: ",")
            if ts["allowInsecure"] as? Bool == true { cfg.allowInsecure = true }
            cfg.pinSHA256 = ts["pinnedPeerCertSha256"] as? String
        }
        if let x = (ss["xhttpSettings"] ?? ss["splithttpSettings"]) as? [String: Any] {
            cfg.path = x["path"] as? String; cfg.hostHeader = x["host"] as? String; cfg.mode = x["mode"] as? String
            if let e = x["extra"], let d = try? JSONSerialization.data(withJSONObject: e), let t = String(data: d, encoding: .utf8) { cfg.extra = t }
        } else if let w = ss["wsSettings"] as? [String: Any] {
            cfg.path = w["path"] as? String
            cfg.hostHeader = (w["host"] as? String) ?? ((w["headers"] as? [String: Any])?["Host"] as? String)
        } else if let h = ss["httpupgradeSettings"] as? [String: Any] {
            cfg.path = h["path"] as? String; cfg.hostHeader = h["host"] as? String
        } else if let g = ss["grpcSettings"] as? [String: Any] {
            cfg.serviceName = g["serviceName"] as? String; cfg.authority = g["authority"] as? String
            if g["multiMode"] as? Bool == true { cfg.multiMode = true }
        } else if let k = ss["kcpSettings"] as? [String: Any] {
            cfg.seed = k["seed"] as? String; cfg.headerType = (k["header"] as? [String: Any])?["type"] as? String
        } else if let t = (ss["tcpSettings"] ?? ss["rawSettings"]) as? [String: Any],
                  let h = t["header"] as? [String: Any], (h["type"] as? String) == "http" {
            cfg.headerType = "http"
            let req = h["request"] as? [String: Any]
            cfg.path = (req?["path"] as? [String])?.first
            cfg.hostHeader = ((req?["headers"] as? [String: Any])?["Host"] as? [String])?.first
        }
        if let hs = ss["hysteriaSettings"] as? [String: Any] { cfg.uuidOrPassword = (hs["auth"] as? String) ?? "" }
        if let fm = ss["finalmask"] as? [String: Any] {
            for m in (fm["udp"] as? [[String: Any]]) ?? [] where (m["type"] as? String) == "salamander" {
                cfg.obfsPassword = (m["settings"] as? [String: Any])?["password"] as? String
            }
            if let qp = fm["quicParams"] as? [String: Any] {
                cfg.up = mbps(qp["brutalUp"]); cfg.down = mbps(qp["brutalDown"])
                if let hop = qp["udpHop"] as? [String: Any] { cfg.mport = (hop["ports"] as? String) ?? (hop["ports"] as? Int).map(String.init) }
            }
        }
        if cfg.name.isEmpty { cfg.name = cfg.host }
        return cfg.host.isEmpty || cfg.port == 0 || (proto != .socks && cfg.uuidOrPassword.isEmpty) ? nil : cfg
    }

    /// The engine's Bandwidth word ("100 mbps", "1 gbps", a bare number of bps) to the link's mbps number.
    static func mbps(_ v: Any?) -> String? {
        if let n = v as? Int { return n < 1_000_000 ? nil : String(n / 1_000_000) }
        guard let s = (v as? String)?.lowercased().trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let digits = s.prefix { $0.isNumber || $0 == "." }
        guard let n = Double(digits), 0 < n else { return nil }
        let unit = s.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        switch unit {
        case "g", "gb", "gbps": return String(Int(n * 1000))
        case "k", "kb", "kbps": return n < 1000 ? nil : String(Int(n / 1000))
        case "", "b", "bps": return n < 1_000_000 ? nil : String(Int(n / 1_000_000))
        default: return String(Int(n))
        }
    }

    /// One outbound of a sing-box config (the JSON body a panel serves that client): its words to ours. A type the
    /// engine lacks keeps a row that says so; the selector, urltest, direct, block and dns outbounds are no servers.
    static func fromSingBox(_ o: [String: Any]) -> MontanaVPNConfig? {
        let type = ((o["type"] as? String) ?? "").lowercased()
        let name = (o["tag"] as? String) ?? ""
        let known: [String: MontanaVPNConfig.Proto] = ["vless": .vless, "vmess": .vmess, "trojan": .trojan, "shadowsocks": .shadowsocks,
                                                       "hysteria2": .hysteria2, "wireguard": .wireguard, "socks": .socks]
        guard let proto = known[type] else {
            if ["selector", "urltest", "direct", "block", "dns", ""].contains(type) { return nil }
            var u = MontanaVPNConfig.empty(.unsupported)
            u.scheme = type; u.reason = "protocol"; u.name = name.isEmpty ? type : name
            u.host = (o["server"] as? String) ?? ""; u.port = port(o["server_port"])
            u.uuidOrPassword = "\(type):\(u.host):\(u.port):\(name)"
            if let d = try? JSONSerialization.data(withJSONObject: o), let t = String(data: d, encoding: .utf8) { u.raw = t }
            return u
        }
        var c = MontanaVPNConfig.empty(proto)
        c.name = name
        c.host = (o["server"] as? String) ?? ""; c.port = port(o["server_port"])
        switch proto {
        case .vless: c.uuidOrPassword = (o["uuid"] as? String) ?? ""; c.flow = (o["flow"] as? String) ?? ""
        case .vmess: c.uuidOrPassword = (o["uuid"] as? String) ?? ""; if let sec = o["security"] as? String, sec != "auto" { c.method = sec }
        case .trojan: c.uuidOrPassword = (o["password"] as? String) ?? ""
        case .shadowsocks:
            c.uuidOrPassword = (o["password"] as? String) ?? ""; c.method = (o["method"] as? String) ?? ""
            if let plugin = o["plugin"] as? String, !plugin.isEmpty { var u = c; u.proto = .unsupported; u.scheme = "ss+plugin"; u.reason = "plugin"; return u }
        case .hysteria2:
            c.uuidOrPassword = (o["password"] as? String) ?? ""; c.network = "hysteria"; c.security = "tls"
            if let ob = o["obfs"] as? [String: Any], (ob["type"] as? String) == "salamander" { c.obfsPassword = ob["password"] as? String }
            if let n = o["up_mbps"] as? Int, 0 < n { c.up = String(n) }
            if let n = o["down_mbps"] as? Int, 0 < n { c.down = String(n) }
            if let ports = o["server_ports"] as? [String], !ports.isEmpty { c.mport = ports.joined(separator: ",").replacingOccurrences(of: ":", with: "-") }
        case .wireguard:
            c.uuidOrPassword = (o["private_key"] as? String) ?? ""; c.publicKey = (o["peer_public_key"] as? String) ?? ""
            c.presharedKey = o["pre_shared_key"] as? String
            c.localIPs = (o["local_address"] as? [String])?.joined(separator: ",")
            if let r = o["reserved"] as? [Int] { c.reserved = r.map(String.init).joined(separator: ",") }
            if let m = o["mtu"] as? Int, 0 < m { c.mtu = m }
            c.network = "udp"
        case .socks: c.user = o["username"] as? String; c.uuidOrPassword = (o["password"] as? String) ?? ""
        case .unsupported: return nil
        }
        if let t = o["tls"] as? [String: Any], (t["enabled"] as? Bool) == true, proto != .wireguard {
            c.security = "tls"
            c.sni = (t["server_name"] as? String) ?? ""
            if (t["insecure"] as? Bool) == true { c.allowInsecure = true }
            c.alpn = (t["alpn"] as? [String])?.joined(separator: ",")
            c.fingerprint = ((t["utls"] as? [String: Any])?["fingerprint"] as? String) ?? ""
            if let r = t["reality"] as? [String: Any], (r["enabled"] as? Bool) == true {
                c.security = "reality"; c.publicKey = (r["public_key"] as? String) ?? ""; c.shortId = (r["short_id"] as? String) ?? ""
            }
        }
        if let tr = o["transport"] as? [String: Any], proto != .hysteria2, proto != .wireguard {
            switch ((tr["type"] as? String) ?? "").lowercased() {
            case "ws": c.network = "ws"; c.path = tr["path"] as? String; c.hostHeader = (tr["headers"] as? [String: Any])?["Host"] as? String
            case "grpc": c.network = "grpc"; c.serviceName = tr["service_name"] as? String
            case "httpupgrade": c.network = "httpupgrade"; c.path = tr["path"] as? String; c.hostHeader = tr["host"] as? String
            case "http":   // sing-box's h2 transport, which the engine removed in favour of xhttp
                var u = c; u.proto = .unsupported; u.scheme = type + "+h2"; u.reason = "transport"; return u
            default: break
            }
        }
        if c.name.isEmpty { c.name = c.host }
        return c.host.isEmpty || c.port == 0 || (proto != .socks && c.uuidOrPassword.isEmpty) ? nil : c
    }
}

/// THE CLASH BODY (29.09): the YAML a panel serves the Clash family -- `proxies:` and one map per server. Read by a small
/// reader of its own shape (a list of maps, nested maps by indentation, flow maps and flow lists on one line, quoted
/// scalars): no YAML library stands in the app, and the plan's servers are worth reading either way.
enum MontanaVPNClash {
    struct Line { let indent: Int; let text: String }

    static func looksLike(_ s: String) -> Bool {
        s.split(whereSeparator: \.isNewline).contains { $0.hasPrefix("proxies:") }   // COMPAT-LOCAL: a panel's Clash body read on this device, never a word between Montana builds
    }
    static func servers(_ s: String) -> [MontanaVPNConfig] { items(s).compactMap(server) }

    /// The maps under `proxies:`, each as its lines with the indentation relative to the item's first key.
    static func items(_ s: String) -> [[String: Any]] {
        let lines = s.components(separatedBy: .newlines).map { $0.replacingOccurrences(of: "\t", with: "  ") }
        guard let start = lines.firstIndex(where: { $0.hasPrefix("proxies:") }) else { return [] }   // COMPAT-LOCAL: the panel's body, this device's reading
        var out: [[String: Any]] = []
        var block: [Line] = []
        var base = 0
        func flush() { if !block.isEmpty { out.append(map(block[...])); block = [] } }
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent == 0 { break }                       // the next top-level key: the list has ended
            if t.hasPrefix("- ") {
                flush(); base = indent + 2
                block.append(Line(indent: 0, text: String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else if !block.isEmpty {
                block.append(Line(indent: max(0, indent - base), text: t))
            }
        }
        flush()
        return out
    }

    /// The whole document as one map, for a client config that is one map from the top (the Hysteria 2 config, 29.09): every
    /// line with its own indentation, read by the same reader the proxies' maps are.
    static func document(_ s: String) -> [String: Any] {
        var lines: [Line] = []
        for raw in s.components(separatedBy: .newlines) {
            let l = raw.replacingOccurrences(of: "\t", with: "  ")
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            lines.append(Line(indent: l.prefix { $0 == " " }.count, text: t))
        }
        return map(lines[...])
    }

    /// Lines of one map: `key: scalar`, `key:` followed by deeper lines (a nested map, or a list of scalars), or a whole
    /// flow map `{k: v, ...}` on the first line.
    static func map(_ lines: ArraySlice<Line>) -> [String: Any] {
        var m: [String: Any] = [:]
        var i = lines.startIndex
        while i < lines.endIndex {
            let l = lines[i]
            if l.text.hasPrefix("{") { m.merge(flowMap(l.text)) { _, new in new }; i += 1; continue }
            guard let colon = keyColon(l.text) else { i += 1; continue }
            let key = String(l.text[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(l.text[l.text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            var j = i + 1
            while j < lines.endIndex, l.indent < lines[j].indent { j += 1 }
            if rest.isEmpty, i + 1 < j {
                let inner = lines[(i + 1)..<j]
                if inner.first?.text.hasPrefix("- ") == true { m[key] = inner.map { scalar(String($0.text.dropFirst(2))) } }
                else { m[key] = map(inner) }
            } else {
                m[key] = value(rest)
            }
            i = j
        }
        return m
    }

    /// The colon that ends a key: the first one followed by a space or by the end of the line (a URL's "://" is never one).
    static func keyColon(_ t: String) -> String.Index? {
        var i = t.startIndex
        while i < t.endIndex {
            if t[i] == ":" {
                let next = t.index(after: i)
                if next == t.endIndex || t[next] == " " { return i }
            }
            i = t.index(after: i)
        }
        return nil
    }

    static func value(_ rest: String) -> Any {
        if rest.hasPrefix("{") { return flowMap(rest) }
        if rest.hasPrefix("[") {
            let inner = String(rest.dropFirst().dropLast(rest.hasSuffix("]") ? 1 : 0))
            return splitTop(inner).map { scalar($0) }
        }
        return scalar(rest)
    }

    /// A scalar as the map holds it: a quoted word bare, true and false as Bool, digits as Int, the rest as text.
    static func scalar(_ raw: String) -> Any {
        var t = raw.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, let f = t.first, let l = t.last, f == l, f == "\"" || f == "'" { t = String(t.dropFirst().dropLast()) }
        if t == "true" { return true }
        if t == "false" { return false }
        if !t.isEmpty, t.allSatisfy({ $0.isNumber }), let n = Int(t) { return n }
        return t
    }

    static func flowMap(_ s: String) -> [String: Any] {
        var m: [String: Any] = [:]
        let inner = String(s.dropFirst().dropLast(s.hasSuffix("}") ? 1 : 0))
        for part in splitTop(inner) {
            guard let colon = keyColon(part) else { continue }
            let k = String(part[..<colon]).trimmingCharacters(in: .whitespaces)
            m[k] = value(String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
        return m
    }

    /// Split on the commas that stand outside braces, brackets and quotes.
    static func splitTop(_ s: String) -> [String] {
        var out: [String] = []; var cur = ""; var depth = 0; var quote: Character? = nil
        for ch in s {
            if let q = quote { cur.append(ch); if ch == q { quote = nil }; continue }
            if ch == "\"" || ch == "'" { quote = ch; cur.append(ch); continue }
            if ch == "{" || ch == "[" { depth += 1 } else if ch == "}" || ch == "]" { depth -= 1 }
            if ch == "," && depth == 0 { out.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur) }
        return out
    }

    /// One Clash proxy map to a server, in the engine's words.
    static func server(_ m: [String: Any]) -> MontanaVPNConfig? {
        func str(_ k: String) -> String? {
            if let t = m[k] as? String { return t.isEmpty ? nil : t }
            if let n = m[k] as? Int { return String(n) }
            return nil
        }
        func bool(_ k: String) -> Bool? {
            if let b = m[k] as? Bool { return b }
            if let t = m[k] as? String { return t == "true" ? true : (t == "false" ? false : nil) }
            return nil
        }
        func sub(_ k: String) -> [String: Any] { (m[k] as? [String: Any]) ?? [:] }
        let type = (str("type") ?? "").lowercased()
        let name = str("name") ?? ""
        let known: [String: MontanaVPNConfig.Proto] = ["vless": .vless, "vmess": .vmess, "trojan": .trojan, "ss": .shadowsocks,
                                                       "hysteria2": .hysteria2, "wireguard": .wireguard, "socks5": .socks]
        guard let proto = known[type] else {
            guard !type.isEmpty else { return nil }
            var u = MontanaVPNConfig.empty(.unsupported)
            u.scheme = type; u.reason = "protocol"; u.host = str("server") ?? ""; u.port = UInt16(str("port") ?? "") ?? 0
            u.name = name.isEmpty ? type : name; u.uuidOrPassword = "\(type):\(u.host):\(u.port):\(name)"
            return u
        }
        var c = MontanaVPNConfig.empty(proto)
        c.name = name; c.host = str("server") ?? ""; c.port = UInt16(str("port") ?? "") ?? 0
        c.sni = str("servername") ?? str("sni") ?? str("peer") ?? ""
        c.fingerprint = str("client-fingerprint") ?? ""
        c.alpn = (m["alpn"] as? [Any])?.compactMap { $0 as? String }.joined(separator: ",")
        if bool("skip-cert-verify") == true { c.allowInsecure = true }
        switch proto {
        case .vless:
            c.uuidOrPassword = str("uuid") ?? ""; c.flow = str("flow") ?? ""
            c.security = bool("tls") == true ? "tls" : "none"
        case .vmess:
            c.uuidOrPassword = str("uuid") ?? ""
            if let cipher = str("cipher"), cipher != "auto" { c.method = cipher }
            c.security = bool("tls") == true ? "tls" : "none"
        case .trojan:
            c.uuidOrPassword = str("password") ?? ""; c.security = "tls"
        case .shadowsocks:
            c.uuidOrPassword = str("password") ?? ""; c.method = str("cipher") ?? ""
            if str("plugin") != nil { var u = c; u.proto = .unsupported; u.scheme = "ss+plugin"; u.reason = "plugin"; return u }
        case .hysteria2:
            c.uuidOrPassword = str("password") ?? ""; c.network = "hysteria"; c.security = "tls"
            if (str("obfs") ?? "") == "salamander" { c.obfsPassword = str("obfs-password") }
            c.up = mbpsWord(str("up")); c.down = mbpsWord(str("down"))
            c.mport = str("ports"); c.pinSHA256 = str("fingerprint")
        case .wireguard:
            c.uuidOrPassword = str("private-key") ?? ""; c.publicKey = str("public-key") ?? ""
            c.presharedKey = str("pre-shared-key")
            c.localIPs = [str("ip"), str("ipv6")].compactMap { $0 }
                .map { $0.contains("/") ? $0 : ($0.contains(":") ? $0 + "/128" : $0 + "/32") }.joined(separator: ",")
            if let r = m["reserved"] as? [Any] { c.reserved = r.compactMap { ($0 as? Int).map(String.init) ?? ($0 as? String) }.joined(separator: ",") }
            c.mtu = Int(str("mtu") ?? "")
            c.network = "udp"
        case .socks:
            c.user = str("username"); c.uuidOrPassword = str("password") ?? ""
        case .unsupported:
            return nil
        }
        if let r = m["reality-opts"] as? [String: Any] {
            c.security = "reality"; c.publicKey = (r["public-key"] as? String) ?? ""
            c.shortId = (r["short-id"] as? String) ?? ((r["short-id"] as? Int).map(String.init) ?? "")
        }
        let network = (str("network") ?? "tcp").lowercased()
        if proto != .hysteria2, proto != .wireguard {
            switch network {
            case "ws":
                c.network = "ws"; let w = sub("ws-opts"); c.path = w["path"] as? String
                c.hostHeader = (w["headers"] as? [String: Any])?.first { $0.key.lowercased() == "host" }?.value as? String
            case "grpc":
                c.network = "grpc"; c.serviceName = sub("grpc-opts")["grpc-service-name"] as? String
            case "h2", "http":
                var u = c; u.proto = .unsupported; u.scheme = type + "+" + network; u.reason = "transport"; return u
            default: break
            }
        }
        if c.name.isEmpty { c.name = c.host }
        return c.host.isEmpty || c.port == 0 || (proto != .socks && c.uuidOrPassword.isEmpty) ? nil : c
    }
    /// Clash writes bandwidth as "100 Mbps" or a bare number of mbps.
    static func mbpsWord(_ s: String?) -> String? {
        guard let s = s?.lowercased() else { return nil }
        let n = Int(s.prefix { $0.isNumber }) ?? 0
        return 0 < n ? String(n) : nil
    }
}

/// THE PROFILE FILES (the author's word 29.09: «a VPN profile as a .config file, or any other proper VPN file, from the menu
/// too»): a file is read by its shape, never by its extension -- a .config may hold an engine JSON, a WireGuard interface, a
/// Hysteria 2 client config, a Clash body or a list of links, and each shape has one reader (MontanaVPNSubscription.body).
/// Two shapes name a protocol the engine does not speak -- the OpenVPN profile and the platform's own VPN profile (IKEv2,
/// IPSec) -- and stand as a row that says so, as an unspoken link does (MontanaVPNParse.unsupported).
enum MontanaVPNFile {
    // -- WireGuard: [Interface] PrivateKey / Address / MTU, [Peer] PublicKey / PresharedKey / Endpoint / Reserved ----------
    static func looksLikeWireGuard(_ s: String) -> Bool {
        let low = s.lowercased()
        return low.contains("[interface]") && low.contains("privatekey")
    }
    /// The first peer is the server; the interface's secret and the peer's key are the two the engine dials with.
    static func wireGuard(_ s: String, name: String) -> MontanaVPNConfig? {
        var iface: [String: String] = [:], peer: [String: String] = [:]
        var section = "", peers = 0
        for raw in s.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                section = line.lowercased()
                if section == "[peer]" { peers += 1 }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if section == "[interface]" { iface[k] = v } else if section == "[peer]", peers == 1 { peer[k] = v }
        }
        var c = MontanaVPNConfig.empty(.wireguard)
        c.network = "udp"; c.security = "none"
        c.uuidOrPassword = iface["privatekey"] ?? ""
        c.publicKey = peer["publickey"] ?? ""
        c.presharedKey = peer["presharedkey"]
        let ips = MontanaXrayConfig.list(iface["address"])
        c.localIPs = ips.isEmpty ? nil : ips.joined(separator: ",")
        c.mtu = iface["mtu"].flatMap(Int.init)
        let reserved = MontanaXrayConfig.list(peer["reserved"] ?? iface["reserved"])
        c.reserved = reserved.isEmpty ? nil : reserved.joined(separator: ",")
        let endpoint = peer["endpoint"] ?? ""
        if !endpoint.hasSuffix("]"), let colon = endpoint.lastIndex(of: ":"), !endpoint[endpoint.index(after: colon)...].contains(":") {
            c.host = String(endpoint[..<colon]); c.port = UInt16(endpoint[endpoint.index(after: colon)...]) ?? 0
        } else { c.host = endpoint; c.port = 51820 }
        c.name = name.isEmpty ? c.host : name
        return c.host.isEmpty || c.port == 0 || c.uuidOrPassword.isEmpty || c.publicKey.isEmpty ? nil : c
    }

    // -- Hysteria 2: the client config, one map from the top -- server, auth, tls, obfs, bandwidth --------------------------
    static func looksLikeHysteria(_ s: String) -> Bool {
        var server = false, auth = false
        for l in s.split(whereSeparator: \.isNewline) {
            // COMPAT-LOCAL: a client config read on this device, never a word between Montana builds
            if l.hasPrefix("server:") { server = true } else if l.hasPrefix("auth:") { auth = true }
        }
        return server && auth
    }
    static func hysteria(_ s: String, name: String) -> MontanaVPNConfig? {
        let m = MontanaVPNClash.document(s)
        guard let server = m["server"] as? String, !server.isEmpty else { return nil }
        var c = MontanaVPNConfig.empty(.hysteria2)
        c.network = "hysteria"; c.security = "tls"
        // host:port, and the hopping ports beside it as the config writes them ("host:443,20000-30000", "host:20000-30000").
        var host = server, ports = ""
        if !server.hasSuffix("]"), let colon = server.lastIndex(of: ":"), !server[server.index(after: colon)...].contains(":") {
            host = String(server[..<colon]); ports = String(server[server.index(after: colon)...])
        }
        c.host = host
        let words = ports.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let plain = words.first { UInt16($0) != nil }
        let leading = String((words.first ?? "").prefix { $0.isNumber })
        c.port = plain.flatMap { UInt16($0) } ?? UInt16(leading) ?? 443
        let hopping = words.filter { $0 != plain }
        if !hopping.isEmpty { c.mport = hopping.joined(separator: ",") }
        if let a = m["auth"] as? String { c.uuidOrPassword = a } else if let n = m["auth"] as? Int { c.uuidOrPassword = String(n) }
        if let tls = m["tls"] as? [String: Any] {
            c.sni = (tls["sni"] as? String) ?? ""
            if (tls["insecure"] as? Bool) == true { c.allowInsecure = true }
            c.pinSHA256 = tls["pinSHA256"] as? String
        }
        if let obfs = m["obfs"] as? [String: Any], (obfs["type"] as? String) == "salamander" {
            c.obfsPassword = (obfs["salamander"] as? [String: Any])?["password"] as? String
        }
        if let bw = m["bandwidth"] as? [String: Any] { c.up = MontanaVPNSubscription.mbps(bw["up"]); c.down = MontanaVPNSubscription.mbps(bw["down"]) }
        c.name = name.isEmpty ? c.host : name
        return c.host.isEmpty || c.uuidOrPassword.isEmpty ? nil : c
    }

    // -- OpenVPN: the profile the engine does not speak; its `remote host port` names the machine for the row ------------
    static func looksLikeOpenVPN(_ s: String) -> Bool {
        var remote = false, client = false
        for l in s.split(whereSeparator: \.isNewline) {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("remote ") { remote = true }
            if t == "client" || t.hasPrefix("dev ") || t.hasPrefix("proto ") || t.hasPrefix("<ca>") { client = true }
        }
        return remote && client
    }
    /// The row that says so; the profile itself is kept whole, as an unspoken link is, so it can be copied on.
    static func openVPN(_ s: String, name: String) -> MontanaVPNConfig {
        var c = MontanaVPNConfig.empty(.unsupported)
        c.scheme = "openvpn"; c.reason = "protocol"; c.raw = s; c.port = 1194
        for l in s.split(whereSeparator: \.isNewline) {
            let words = l.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
            guard words.first == "remote", 1 < words.count else { continue }
            c.host = words[1]
            if 2 < words.count, let p = UInt16(words[2]) { c.port = p }
            break
        }
        c.name = name.isEmpty ? c.host : name
        c.uuidOrPassword = "openvpn:\(c.host):\(c.port):\(c.name)"   // the row's identity, as a sing-box row the engine lacks spells it
        return c
    }

    // -- The platform's own VPN profile (a property list): IKEv2, IPSec, L2TP -- named, never dialled by this engine -------
    static func looksLikeProfile(_ s: String) -> Bool {
        s.hasPrefix("<?xml") && s.contains("com.apple.vpn.managed")   // COMPAT-LOCAL: a profile read on this device
    }
    static func profile(_ data: Data, name: String) -> MontanaVPNConfig? {
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let payloads = plist["PayloadContent"] as? [[String: Any]],
              let vpn = payloads.first(where: { ($0["PayloadType"] as? String) == "com.apple.vpn.managed" }) else { return nil }
        var c = MontanaVPNConfig.empty(.unsupported)
        let kind = ((vpn["VPNType"] as? String) ?? "vpn").lowercased()
        c.scheme = kind; c.reason = "protocol"; c.port = 0
        var remote = ""
        for key in ["IKEv2", "IPSec", "VPN", "PPP"] {
            guard let part = vpn[key] as? [String: Any] else { continue }
            if let r = (part["RemoteAddress"] ?? part["CommRemoteAddress"]) as? String, !r.isEmpty { remote = r; break }
        }
        if !remote.hasSuffix("]"), let colon = remote.lastIndex(of: ":"), !remote[remote.index(after: colon)...].contains(":") {
            c.host = String(remote[..<colon]); c.port = UInt16(remote[remote.index(after: colon)...]) ?? 0
        } else { c.host = remote }
        let title = (vpn["UserDefinedName"] as? String) ?? (plist["PayloadDisplayName"] as? String) ?? ""
        c.name = !title.isEmpty ? title : (name.isEmpty ? c.host : name)
        c.uuidOrPassword = "\(kind):\(c.host):\(c.port):\(c.name)"
        return c
    }
}

/// EVERY ROAD IN IS ONE ROAD (29.09): the clipboard, the camera, a file, the hand and the plan's link hand a text here, and the
/// text is read by its shape -- a plan's link is fetched (the page loads it), everything else is read in place by the one
/// body reader and its rows join the hand-added section. A file's name stands for a form that carries none.
enum MontanaVPNIntake {
    enum Read {
        case subscription(URL)
        case servers(MontanaVPNSubscription.Body)
    }
    /// A file over this is no profile: the biggest honest one -- an OpenVPN profile with its certificates -- is a few kilobytes.
    static let fileMax = 1_048_576
    static func read(_ text: String, name: String = "") -> Read {
        if let url = MontanaVPNSubscription.isSubscriptionURL(text) { return .subscription(url) }
        return .servers(MontanaVPNSubscription.body(Data(text.utf8), name: name))
    }
    /// The files the picker handed over, read off the main thread under their security scope, closed after the read: the name
    /// and the text of each that read, and how many did not (a binary, or a file over the bound). The name is the file's own,
    /// without its extension, for a form that carries none.
    static func readFiles(_ urls: [URL]) async -> (texts: [(name: String, text: String)], unreadable: Int) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var texts: [(name: String, text: String)] = []
                var unreadable = 0
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    let data = size <= fileMax ? (try? Data(contentsOf: url)) : nil
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    if let data, let text = String(data: data, encoding: .utf8) {
                        texts.append((name: url.deletingPathExtension().lastPathComponent, text: text))
                    } else {
                        unreadable += 1
                    }
                }
                cont.resume(returning: (texts: texts, unreadable: unreadable))
            }
        }
    }
}

// One subscription link and what it said the last time it answered — the header the screen draws
// above the plan's servers. Sealed beside the servers; the link itself is the plan's secret.
struct MontanaVPNPlan: Codable, Equatable, Identifiable {
    var url: String
    var title: String
    var updatedAt: Double        // unix seconds of the last successful load
    var count: Int
    var upload: Int64? = nil
    var download: Int64? = nil
    var total: Int64? = nil      // 0 or absent — unlimited
    var expire: Double? = nil    // unix seconds; 0 or absent — no end
    var lastError: String? = nil // the label of the last failed load; nil once a load succeeds
    var unsupported: Int? = nil    // rows of the last load the engine cannot speak (29.09)
    var unsupportedKinds: String? = nil   // their schemes, "tuic:3,anytls:1"
    var updateInterval: Int? = nil // hours, as the panel's profile-update-interval header states it (kept, not acted on)
    // The person's own arrangement of the page, sealed with the plan (the author's word 24.09): the link is the
    // plan's secret, and a list of links kept beside the vault would be a second copy of it in the clear.
    var folded: Bool? = nil        // its servers folded under the header by the arrow
    var pinnedAt: Double? = nil    // unix seconds of the pin; the newest pin stands highest
    var wallOf: String? = nil      // the correspondent whose wall carried this plan's link (29.09); nil for a plan the person pasted
    var id: String { url }
    var host: String { URL(string: url)?.host ?? url }
    var shownTitle: String { title.isEmpty ? host : title }
}

enum MontanaVPNPlans {
    private static let key = "mt.vpn.plans"
    // HELD IN MEMORY, read from the sealed store once -- the same law the server list keeps: the page
    // asks for the plans from its body, and a body may ask only for free answers (22.09).
    private static let lock = NSLock()
    private static var held: [MontanaVPNPlan]?
    static func load() -> [MontanaVPNPlan] {
        lock.lock()
        if let h = held { lock.unlock(); return h }
        lock.unlock()
        var l: [MontanaVPNPlan] = []
        if let d = MontanaLocalVault.getDecrypted(key),
           let decoded = try? JSONDecoder().decode([MontanaVPNPlan].self, from: d) { l = decoded }
        lock.lock(); held = l; lock.unlock()
        return l
    }
    static func save(_ l: [MontanaVPNPlan]) {
        lock.lock(); held = l; lock.unlock()
        if let d = try? JSONEncoder().encode(l) { MontanaLocalVault.setEncrypted(key, d) }
    }
    static func forgetHeld() { lock.lock(); held = nil; lock.unlock() }
    static func upsert(_ p: MontanaVPNPlan) {
        var l = load()
        if let i = l.firstIndex(where: { $0.url == p.url }) { l[i] = p } else { l.append(p) }
        save(l)
    }
    static func remove(_ url: String) { save(load().filter { $0.url != url }) }
    /// The order the page shows them in, named ONCE ([C-1]): the pinned first, the newest pin highest (the
    /// author's word 24.09: «every new pin stands above the others»), then the rest by title. The page takes
    /// this both when it is born and when it reloads, so the first frame and every later one stand alike.
    /// THE ORDER OF THE PAGE (the author's word 30.09: «on the VPN wall one's own stand on top, and the others below, as one scrolls
    /// down»; and 29.09 evening: «the priority of appearance follows the order of the chats in the feed, the freshest first»): the
    /// person's own first -- the pinned, the newest pin highest, then the rest of their own by name; then the walls of the
    /// correspondents in the chats' own order, the freshest chat first, a correspondent's paid plan above their servers. A wall that
    /// arrives is pinned at its arrival, so a pin alone must not lift it over the person's own. `wallRank` is the chats' order
    /// (MTVPNWall.chatRank), read by the page.
    static func ordered(wallRank: [String: Int] = [:]) -> [MontanaVPNPlan] { ordered(load(), wallRank: wallRank) }
    /// Pure: the order itself, of any list of plans.
    static func ordered(_ plans: [MontanaVPNPlan], wallRank: [String: Int]) -> [MontanaVPNPlan] {
        func rank(_ p: MontanaVPNPlan) -> (Int, Int, Int) {
            guard let conv = p.wallOf else { return (0, p.pinnedAt == nil ? 1 : 0, 0) }
            return (1, wallRank[conv] ?? Int.max, MTVPNWall.isWallKey(p.url) ? 1 : 0)
        }
        return plans.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            switch (a.pinnedAt, b.pinnedAt) {
            case let (x?, y?): return y < x
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.shownTitle.localizedCaseInsensitiveCompare(b.shownTitle) == .orderedAscending
            }
        }
    }
    /// The fold, kept with the plan: the page folds at once and the sealed record remembers it.
    static func setFolded(_ url: String, _ folded: Bool) {
        guard var p = load().first(where: { $0.url == url }) else { return }
        p.folded = folded ? true : nil
        upsert(p)
    }
    /// The pin, kept with the plan: pinned now stands above every pin made before it.
    static func setPinned(_ url: String, _ pinned: Bool) {
        guard var p = load().first(where: { $0.url == url }) else { return }
        p.pinnedAt = pinned ? Date().timeIntervalSince1970 : nil
        upsert(p)
    }
    /// THE HAND-ADDED SECTION WEARS A PIN TOO (the author's word 24.09: «for the servers added by hand, the same
    /// pin of the category in its menu»). Its moment is kept in the settings beside the plans' own -- a moment
    /// with no link in it, so nothing to seal -- and it travels with a copy as every arrangement of the page does.
    static let manualPinKey = "mt.vpn.manualPin"
    static var manualPinnedAt: Double? {
        let at = UserDefaults.standard.double(forKey: manualPinKey)
        return 0 < at ? at : nil
    }
    static func setManualPinned(_ pinned: Bool) {
        let now = Date().timeIntervalSince1970
        if pinned { UserDefaults.standard.set(now, forKey: manualPinKey) }
        else { UserDefaults.standard.removeObject(forKey: manualPinKey) }
    }
    /// The hand-added section's fold outlives the page as a plan's does (the author's word 24.09: «do it» -- the
    /// arrow of the hand-added servers forgot what it had folded at every opening). Kept beside its pin.
    static let manualFoldKey = "mt.vpn.manualFolded"
    static var manualFolded: Bool { UserDefaults.standard.bool(forKey: manualFoldKey) }
    static func setManualFolded(_ folded: Bool) {
        if folded { UserDefaults.standard.set(true, forKey: manualFoldKey) }
        else { UserDefaults.standard.removeObject(forKey: manualFoldKey) }
    }
    /// Where the hand-added section stands among the plans `ordered()` returns, named here beside that order ([C-1]). It is the
    /// person's own, so it stands among their own plans and above every correspondent's wall: pinned, among their pins by its
    /// moment, the newest pin highest; unpinned, after their own plans.
    static func manualSlot(in plans: [MontanaVPNPlan], pinnedAt: Double?) -> Int {
        let own = plans.firstIndex { $0.wallOf != nil } ?? plans.count
        guard let at = pinnedAt else { return own }
        return plans.prefix(own).firstIndex { ($0.pinnedAt ?? 0) < at } ?? own
    }
}

/// WHEN THE GLOBE WAS TOUCHED. The page cannot time its own opening -- it does not exist yet at the
/// touch -- so the touch leaves the instant here and the page reports the milliseconds it took to
/// draw. One number answers "why does it think before it opens" (the author's word 22.09).
enum MontanaVPNOpen {
    static var tappedAt: Date?
    static func tap() { tappedAt = Date() }
    /// Milliseconds from the touch to this call, once; a second ask gets nothing.
    static func msSinceTap() -> Int? {
        guard let t = tappedAt else { return nil }
        tappedAt = nil
        return Int(Date().timeIntervalSince(t) * 1000)
    }
}

extension MontanaVPNStore {
    // Every server of the plan behind one link: the servers this link gave last time are replaced by
    // what it gives now (a plan changes its servers), a server the same link already holds keeps its
    // identity so the selection survives, and a server added by hand is never touched. A failed load
    // keeps the servers and writes its reason on the plan, so the screen says what happened.
    @discardableResult
    static func addFromSubscription(_ url: URL, onAttempt: ((Int) -> Void)? = nil) async throws -> Int {
        try await MontanaVPNLoadLine.run { try await addFromSubscriptionNow(url, onAttempt: onAttempt) }
    }
    private static func addFromSubscriptionNow(_ url: URL, onAttempt: ((Int) -> Void)?) async throws -> Int {
        let key = url.absoluteString
        guard !MTVPNWall.isWallKey(key), !MTVPNPay.isPlan(key) else { return 0 }   // a wall is asked of its owner, the nodes' rows of their door (MTVPNPay)
        let fetched: MontanaVPNSubscription.Fetched
        do { fetched = try await MontanaVPNSubscription.fetch(url, onAttempt: onAttempt) }
        catch let e as MontanaVPNSubscription.FetchError {
            if var p = MontanaVPNPlans.load().first(where: { $0.url == key }) { p.lastError = e.label; MontanaVPNPlans.upsert(p) }
            else { MontanaVPNPlans.upsert(MontanaVPNPlan(url: key, title: "", updatedAt: 0, count: 0, lastError: e.label)) }
            Task { @MainActor in MTVPNWall.shared.schedulePush() } // a failed owner plan must leave the wall now
            throw e
        }
        var list = load()
        let old = list.filter { $0.subscription == key }
        list.removeAll { $0.subscription == key }
        // A plan may name one machine twice under two names (an "auto" entry beside its country); both stay,
        // as the plan lists them. Only a server already held from elsewhere is not taken a second time.
        let others = list
        // An identity held from the last load is handed to at most ONE row: the plan lists the same
        // machine twice under two names, and handing both the same identity is what made the screen
        // draw one row twice. Taken from the pool, never copied.
        var pool = old
        for var f in fetched.servers {
            if others.contains(where: { $0.host == f.host && $0.port == f.port && $0.uuidOrPassword == f.uuidOrPassword }) { continue }
            if let k = pool.firstIndex(where: { $0.host == f.host && $0.port == f.port && $0.uuidOrPassword == f.uuidOrPassword && $0.name == f.name }) {
                f.uid = pool.remove(at: k).uid ?? UUID().uuidString
            } else if let k = pool.firstIndex(where: { $0.host == f.host && $0.port == f.port && $0.uuidOrPassword == f.uuidOrPassword }) {
                f.uid = pool.remove(at: k).uid ?? UUID().uuidString
            } else {
                f.uid = UUID().uuidString
            }
            list.append(f)
        }
        save(list)
        let prev = MontanaVPNPlans.load().first(where: { $0.url == key })
        let ui = fetched.userinfo
        let unspoken = MontanaVPNParse.Report(servers: fetched.servers.filter { $0.proto == .unsupported })
        MontanaVPNPlans.upsert(MontanaVPNPlan(
            url: key, title: fetched.title.isEmpty ? (prev?.title ?? "") : fetched.title,
            updatedAt: Date().timeIntervalSince1970, count: fetched.servers.count,
            upload: ui["upload"], download: ui["download"], total: ui["total"],
            expire: ui["expire"].map(Double.init), lastError: nil,
            unsupported: unspoken.servers.isEmpty ? nil : unspoken.servers.count, unsupportedKinds: unspoken.servers.isEmpty ? nil : unspoken.unsupportedWord,
            updateInterval: fetched.updateHours ?? prev?.updateInterval,
            folded: prev?.folded, pinnedAt: prev?.pinnedAt, wallOf: prev?.wallOf))   // a load renews what the panel says, not the person's arrangement
        return fetched.servers.count
    }

    static func subscriptions() -> [URL] {
        var seen: [String] = MontanaVPNPlans.load().map { $0.url }
        for c in load() { if let s = c.subscription, !seen.contains(s) { seen.append(s) } }
        return seen.filter { !MTVPNWall.isWallKey($0) && !MTVPNPay.isPlan($0) }.compactMap(URL.init(string:))
    }

    // Refresh every plan; a plan whose server is silent keeps what it had.
    static func refreshSubscriptions(onAttempt: ((Int) -> Void)? = nil) async -> Int {
        var n = 0
        for u in subscriptions() { n += (try? await addFromSubscription(u, onAttempt: onAttempt)) ?? 0 }
        return n
    }

    // The plan and every server it brought leave together; a server pasted by hand stays.
    static func removeSubscription(_ url: String) {
        save(load().filter { $0.subscription != url })
        MontanaVPNPlans.remove(url)
    }
}


// THE VPN WALL (the author's word 29.09 evening): «when T1 and T3 paste their links into the VPN they must appear for everyone, the
// same way as the posts feed -- a wall of VPN: the hand-added links and the paid plans, everyone's for everyone». It rides the
// wall's own road (MTBoard): one service token, a page of the whole set carried to the latest correspondents after a change and
// at every return, a version so no page is carried twice, an ask for a page never received, and a build that does not know the
// token buries it unread ([P2P-COMPAT]). No node keeps a wall: the page is a letter, sealed as every letter is.
// What the page carries: the servers this person added by hand (the share link, and the served outbound of a JSON row) and
// the links of the plans this person pasted -- never what came to this phone by someone else's wall (a wall is one's own).
// What arrives: the correspondent's servers stand under the correspondent's name as a pinned plan of their own, and the
// correspondent's plans are loaded by this phone as plans of its own (the provider counts this phone as a device of that plan;
// said to the author 29.09). Nothing that came by a wall is chosen by itself for the tunnel (the
// tunnel's fallbacks are gone): another person's exit is data the person sees and picks by hand.
struct MTVPNWallRow: Codable, Equatable {
    var id: String
    var n: String                  // the name
    var k: String                  // "s" a server: l its share link, j its served outbound; "p" a plan: l its link
    var l: String? = nil
    var j: String? = nil
}
struct MTVPNWallWord: Codable {
    var t: String                  // page, ask
    var v: String? = nil           // the page's version
    var rows: [MTVPNWallRow]? = nil
}
@MainActor final class MTVPNWall: ObservableObject {
    static let shared = MTVPNWall()
    static let mark = "\u{200B}\u{200B}VW:"
    static let keyPrefix = "montana://vpn-wall/"
    static let pushTo = 128        // the latest correspondents carried, as the posts' wall carries (MTBoard.pushTo)
    static let rowsMax = 12        // rows a page names, servers and plans together (a letter stays a letter)
    static let jsonMax = 3072      // a served outbound longer than this rides as its share link alone
    static let inFlightFor: TimeInterval = 1800   // a page handed to the queue is not handed again for this long (MTBoard.onItsWay)
    private static let sentKey = "vpnwall.sent"     // conv: the version they said they hold (their «got»)
    private static let askedKey = "vpnwall.asked"   // conv: the moment they were last asked for their page
    private static let capKey = "vpnwall.cap"       // the correspondents whose build proved it speaks the VPN wall
    private var sent: [String: String]
    private var asked: [String: Double]
    private var cap: Set<String>
    private var inFlight: [String: (v: String, at: Date)] = [:]
    private var laid: [String: String] = [:]         // conv: the version of their page last laid here, this run
    private var answeredAt: [String: Date] = [:]
    private var pushWork: DispatchWorkItem?

    private init() {
        sent = (UserDefaults.standard.data(forKey: Self.sentKey)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        asked = (UserDefaults.standard.data(forKey: Self.askedKey)).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        cap = Set((UserDefaults.standard.data(forKey: Self.capKey)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
        // A correspondent whose wall already lies here spoke the VPN wall before this build learned to remember it: without
        // this two phones that already hold each other's walls would each wait for the other to speak first, for ever.
        cap.formUnion(MontanaVPNPlans.load().compactMap { $0.wallOf })
    }
    private func persist() {
        if let d = try? JSONEncoder().encode(sent) { UserDefaults.standard.set(d, forKey: Self.sentKey) }
        if let d = try? JSONEncoder().encode(asked) { UserDefaults.standard.set(d, forKey: Self.askedKey) }
        if let d = try? JSONEncoder().encode(cap.sorted()) { UserDefaults.standard.set(d, forKey: Self.capKey) }
    }

    nonisolated static func planKey(_ conv: String) -> String { keyPrefix + conv }
    nonisolated static func isWallKey(_ key: String?) -> Bool { key?.hasPrefix(keyPrefix) == true }
    /// A page of the VPN wall, told from its other words -- for the queue, which keeps one page per person (the posts' law, N1).
    nonisolated static func isPage(_ text: String) -> Bool { text.hasPrefix(mark) && text.contains("\"t\":\"page\"") }
    /// A row that came by a wall: a correspondent's server, or a row of a plan a correspondent's wall carried.
    nonisolated static func cameByWall(_ c: MontanaVPNConfig) -> Bool {
        guard let s = c.subscription else { return false }
        if s.hasPrefix(keyPrefix) { return true }
        return MontanaVPNPlans.load().contains { $0.url == s && $0.wallOf != nil }
    }

    // -- the page of this phone ------------------------------------------------------------------
    /// Pure: the page from the list and the plans.  A subscription may be spoken only when this
    /// phone has a fresh successful measurement for at least one of its servers.
    /// A WIREGUARD ROW IS NEVER CARRIED (29.09): its private key is one device's identity at the server, and two phones on one
    /// key knock each other off the tunnel -- the owner's own connection would break the moment a correspondent used it.
    nonisolated static func page(servers: [MontanaVPNConfig], plans: [MontanaVPNPlan], live: Set<String>? = nil, now: Double = Date().timeIntervalSince1970) -> [MTVPNWallRow] {
        var rows: [MTVPNWallRow] = []
        // The pasted plans first: a paid plan is shared from the top (the author's word 29.09 evening).
        for p in plans where p.wallOf == nil && !isWallKey(p.url) && (p.url.hasPrefix("https://") || p.url.hasPrefix("http://")) {
            let validUntil = p.expire.map { $0 == 0 || now < $0 } ?? true
            let livePlan = live.map { liveIDs in servers.contains { $0.subscription == p.url && liveIDs.contains($0.id) } } ?? true
            guard validUntil, p.lastError == nil, 0 < p.count, livePlan else { continue }
            rows.append(MTVPNWallRow(id: "plan:" + hex(p.url).prefix(16), n: String(p.shownTitle.prefix(64)), k: "p", l: p.url))
        }
        for c in servers where c.subscription == nil && c.proto != .unsupported && c.proto != .wireguard && (live.map { $0.contains(c.id) } ?? true) {
            var r = MTVPNWallRow(id: c.id, n: String(c.name.prefix(64)), k: "s", l: MontanaVPNParse.serialize(c))
            if let j = c.engineOutbound, j.count <= jsonMax { r.j = j }
            rows.append(r)
        }
        return Array(rows.prefix(rowsMax))
    }
    /// The chats' own order, the freshest first: a correspondent's rank for the page's order of the walls (MontanaVPNPlans.ordered).
    static func chatRank() -> [String: Int] {
        var rank: [String: Int] = [:]
        for (i, conv) in (ChatStore.live?.listChats() ?? []).compactMap({ $0.convId }).enumerated() where rank[conv] == nil { rank[conv] = i }
        return rank
    }
    static func page() -> [MTVPNWallRow] {
        let book = MontanaVPNDelayBook.shared
        let live = Set(book.entries.compactMap { id, entry in
            entry.ms != nil && entry.age <= MontanaVPNDelayBook.stale ? id : nil
        })
        return page(servers: MontanaVPNStore.load(), plans: MontanaVPNPlans.load(), live: live)
    }
    /// Pure: the version of a page -- the same rows in any order give the same word.
    nonisolated static func version(_ rows: [MTVPNWallRow]) -> String {
        let sorted = rows.sorted { $0.id < $1.id }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        guard let d = try? enc.encode(sorted) else { return "" }
        return String(SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined().prefix(16))
    }
    private nonisolated static func hex(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
    /// THE PAGE ONE CORRESPONDENT MAY SEE (the author's word 29.09: «the privacy settings as for my own wall»): the whole page,
    /// or -- for one the rule of my VPN wall leaves out -- the empty page with the empty wall's version, so the refusal itself
    /// says nothing (the posts' law, MTBoard.spokenVersion). The whole page is read once per carry and handed in.
    nonisolated static func page(for conv: String, whole: [MTVPNWallRow]) -> [MTVPNWallRow] {
        MTBoardRule.admits(conv, to: .vpn) ? whole : []
    }

    // -- carrying ---------------------------------------------------------------------------------
    /// THE OWNER CARRIES THE VPN WALL AS THE POSTS' WALL IS CARRIED (the author's word 29.09: «as in the feed -- a post published
    /// appears for everyone -- so the VPN wall»). After a change of the list, the plans or the rule, and at a return: half a
    /// second to fold a burst, then every latest correspondent whose build proved it speaks the VPN wall and whose version of it
    /// moved, a few frames apart. T1 29.09 before this law: one unchanged page carried to 21 correspondents at every return, 36
    /// times in a day, because «held» was written only by a receipt that a service word never gets. Now «held» is the
    /// correspondent's own «got»; a page on its way is not handed again for half an hour (a build without «got» is carried again
    /// after that); one the rule no longer admits is carried the empty page, beyond the latest too. A person who hides their
    /// presence carries at their own acts alone: a carry at a return would say when they came back (the posts' N6).
    func schedulePush() {
        pushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pushDue() }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func appReturned() {
        if MontanaPresencePrivacy.sharing { schedulePush() }   // not the beacons' door (P-48 counts those two); the asks ride the hour's beat (30.09)
    }
    private func pushDue() {
        let whole = Self.page()
        let empty = Self.version([])
        let latest = (ChatStore.live?.listChats() ?? []).compactMap { $0.convId }.filter { cap.contains($0) }
        let withdrawn = sent.filter { $0.value != empty && !MTBoardRule.byRule($0.key, to: .vpn) }.map { $0.key }
        var due = Array(latest.prefix(Self.pushTo))
        for c in withdrawn where !due.contains(c) { due.append(c) }
        var n = 0
        for conv in due where MontanaConv.holds(conv) && !ChatStore.refusesCold(conv) {
            let rows = Self.page(for: conv, whole: whole)
            let v = Self.version(rows)
            guard sent[conv] != v, !onItsWay(conv, v) else { continue }
            let wait = 0.15 * Double(n); n += 1
            inFlight[conv] = (v, Date())
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self, self.sent[conv] != v else { return }
                self.send(MTVPNWallWord(t: "page", v: v, rows: rows), to: conv)
            }
        }
        MontanaP2PTrace.mark("vpn_wall", "push rows=\(whole.count) cap=\(cap.count) to=\(n)")
    }
    /// The same page already stands in the queue for them, handed less than half an hour ago.
    private func onItsWay(_ conv: String, _ v: String) -> Bool {
        guard let f = inFlight[conv], f.v == v else { return false }
        return Date().timeIntervalSince(f.at) < Self.inFlightFor
    }
    /// A correspondent whose wall this phone never received is asked for it, once a day at most: the ask is also how a build
    /// that speaks the VPN wall is found (its answer, and its own ask, are the proof).
    func askMissing() {
        let now = Date().timeIntervalSince1970
        let have = Set(MontanaVPNPlans.load().compactMap { $0.wallOf })
        let latest = (ChatStore.live?.listChats() ?? []).compactMap { $0.convId }
        var n = 0
        for conv in latest.prefix(Self.pushTo) where MontanaConv.holds(conv) && !ChatStore.refusesCold(conv) && !have.contains(conv) {
            if let t = asked[conv], now - t < 86400 { continue }
            asked[conv] = now; n += 1
            send(MTVPNWallWord(t: "ask"), to: conv)
        }
        if 0 < n { persist(); MontanaP2PTrace.mark("vpn_wall", "ask to=\(n)") }
    }
    /// The page is asked of one correspondent again (the plan's own update button).
    func ask(_ conv: String) {
        asked[conv] = Date().timeIntervalSince1970; persist()
        send(MTVPNWallWord(t: "ask"), to: conv)
    }
    private func send(_ w: MTVPNWallWord, to conv: String) {
        guard MontanaConv.holds(conv), !ChatStore.refusesCold(conv),
              let d = try? JSONEncoder().encode(w), let js = String(data: d, encoding: .utf8) else { return }
        MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: UUID().uuidString, text: Self.mark + js, silent: true)
        MontanaP2PTrace.mark("vpn_wall", "tx t=\(w.t) to=\(String(conv.prefix(10)))")
    }
    /// The receipt of a page letter, where one comes: the version it carried is the one that correspondent holds.
    nonisolated static func delivered(text: String, to conv: String) {
        guard isPage(text), let d = String(text.dropFirst(mark.count)).data(using: .utf8),
              let w = try? JSONDecoder().decode(MTVPNWallWord.self, from: d), let v = w.v else { return }
        Task { @MainActor in shared.held(v, by: conv) }
    }
    /// The version a correspondent holds, by their «got» or a receipt: never carried to them again until it moves.
    private func held(_ v: String, by conv: String) {
        sent[conv] = v
        if inFlight[conv]?.v == v { inFlight[conv] = nil }
        persist()
    }
    /// A correspondent spoke the VPN wall -- any word of it: from now on the owner carries the page to them ([P2P-COMPAT]: never
    /// to a build that has not shown it reads the VPN wall).
    private func learnCap(_ conv: String) {
        guard !conv.isEmpty, cap.insert(conv).inserted else { return }
        persist()
        MontanaP2PTrace.mark("vpn_wall", "cap +1 now=\(cap.count)")
        if MontanaPresencePrivacy.sharing { schedulePush() }
    }

    // -- receiving --------------------------------------------------------------------------------
    /// A word of the VPN wall arrived. True when it was ours to read: the letter is service and never becomes a row.
    @discardableResult
    nonisolated static func handle(_ text: String, from conv: String, isFromMe: Bool) -> Bool {
        guard text.hasPrefix(mark) else { return false }
        guard !isFromMe, !ChatStore.refusesCold(conv), let d = String(text.dropFirst(mark.count)).data(using: .utf8),
              let w = try? JSONDecoder().decode(MTVPNWallWord.self, from: d) else { return true }
        Task { @MainActor in shared.apply(w, from: conv) }
        return true
    }
    private func apply(_ w: MTVPNWallWord, from conv: String) {
        MontanaP2PTrace.mark("vpn_wall", "rx t=\(w.t) from=\(String(conv.prefix(10))) rows=\(w.rows?.count ?? 0)")
        learnCap(conv)   // a word of the VPN wall is the proof its build speaks it
        switch w.t {
        case "ask":
            if let t = answeredAt[conv], Date().timeIntervalSince(t) < 30 { return }   // one answer in thirty seconds
            answeredAt[conv] = Date()
            let rows = Self.page(for: conv, whole: Self.page())
            let v = Self.version(rows)
            inFlight[conv] = (v, Date())
            send(MTVPNWallWord(t: "page", v: v, rows: rows), to: conv)
        case "page":
            // «GOT»: the version is said back, so the owner never carries this page again (a build before 29.09 skips the word).
            // The same version twice -- the box and the live lane both bring it -- is laid once.
            if let v = w.v { send(MTVPNWallWord(t: "got", v: v), to: conv) }
            if let v = w.v, laid[conv] == v { return }
            if let v = w.v { laid[conv] = v }
            Self.lay(w.rows ?? [], from: conv)
            MontanaVPNFreshener.shared.moved()
        case "got":
            if let v = w.v { held(v, by: conv) }
        default: break
        }
    }

    /// Pure: the correspondent's server rows as rows of the list under their key, identities kept from the last page.
    nonisolated static func servers(of rows: [MTVPNWallRow], key: String, old: [MontanaVPNConfig]) -> [MontanaVPNConfig] {
        var out: [MontanaVPNConfig] = []
        for r in rows.prefix(rowsMax) where r.k == "s" {
            var c: MontanaVPNConfig?
            if let j = r.j, let d = j.data(using: .utf8), let ob = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                c = MontanaVPNSubscription.fromEngineConfig(["remarks": r.n, "outbounds": [ob]])
            }
            if c == nil, let l = r.l { c = MontanaVPNParse.parse(l) }
            guard var cfg = c, cfg.proto != .unsupported else { continue }
            if !r.n.isEmpty { cfg.name = r.n }
            cfg.subscription = key
            cfg.uid = old.first(where: { $0.host == cfg.host && $0.port == cfg.port && $0.uuidOrPassword == cfg.uuidOrPassword })?.uid ?? UUID().uuidString
            out.append(cfg)
        }
        return out
    }
    /// The correspondent's page lands: their servers under their name (a plan of their own, pinned when it first arrives), their
    /// plans loaded by this phone as plans of its own; what the page no longer names leaves.
    static func lay(_ rows: [MTVPNWallRow], from conv: String) {
        let key = planKey(conv)
        let now = Date().timeIntervalSince1970
        var list = MontanaVPNStore.load()
        let old = list.filter { $0.subscription == key }
        list.removeAll { $0.subscription == key }
        let servers = servers(of: rows, key: key, old: old)
        list.append(contentsOf: servers)
        MontanaVPNStore.save(list)
        let prev = MontanaVPNPlans.load().first(where: { $0.url == key })
        if servers.isEmpty {
            MontanaVPNPlans.remove(key)
        } else {
            MontanaVPNPlans.upsert(MontanaVPNPlan(url: key, title: MTNameBook.display(conv: conv), updatedAt: now, count: servers.count,
                                                  folded: prev?.folded, pinnedAt: prev?.pinnedAt ?? now, wallOf: conv))
        }
        let links = rows.filter { $0.k == "p" }.compactMap { $0.l }.filter { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
        let plans = MontanaVPNPlans.load()
        for p in plans where p.wallOf == conv && !isWallKey(p.url) && !links.contains(p.url) { MontanaVPNStore.removeSubscription(p.url) }
        for l in links where !plans.contains(where: { $0.url == l }) {
            guard let u = URL(string: l) else { continue }
            let title = rows.first(where: { $0.l == l })?.n ?? ""
            MontanaVPNPlans.upsert(MontanaVPNPlan(url: l, title: title, updatedAt: 0, count: 0, pinnedAt: now, wallOf: conv))
            Task { _ = try? await MontanaVPNStore.addFromSubscription(u) }
        }
        MontanaP2PTrace.mark("vpn_wall", "laid from=\(String(conv.prefix(10))) servers=\(servers.count) plans=\(links.count)")
    }
}
