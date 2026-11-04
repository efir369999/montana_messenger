import Foundation
import MontanaBindings
import Darwin

// THE LOCAL NETWORK'S DISCOVERY IS THE MESH'S (the author's word 03.11.2026 22:44 UTC, link 15863): this file stands in the
// Protocol's target alone and is reached only through the mesh door (MTApps.mesh); Montana Messenger neither announces itself
// on a local network nor looks for anyone there.
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
            MontanaTrace.mark("lan_offer_skipped", "the port is not up yet")
            return [:]
        }
        let txt: [String: Data] = ["d": Data(String(directPort).utf8)]
        // What this device actually PUTS on the air, split by where it came from. Without it a
        // silent record is indistinguishable from a device with nothing to say — and the two need
        // different answers. Counts only: a count says nothing about who anybody talks to.
        MontanaTrace.mark("lan_offer", "port=\(directPort)")
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
