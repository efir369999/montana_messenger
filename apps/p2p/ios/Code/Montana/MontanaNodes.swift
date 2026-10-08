import Foundation

// The nodes this node knocks on, and the one place their endpoints live ([I-10]/[C-1]).
//
// A node is not a service and holds nothing of anybody. It is a machine of the mesh whose address
// arrives FROM THE WORLD rather than from the network. The set names this the third source of a
// first connection: "through a node that an operator deliberately opened. A node tells only about
// itself: passing it yields one handshake, never a map."
//
// Three things are true of every node, and they are what keeps this list from being a directory:
//
//   • Passing a node yields ONE handshake. A node is never asked who else it knows, and no address
//     of any correspondent is learned from one.
//   • A node carries sealed cells like any other reachable machine, by the tag they stand under.
//     It reads nothing and is told nothing of who deposits or who collects.
//   • The list is DATA and never code. Not one address stands in this file: it is read from
//     `nodes.txt` beside the app and from whatever the operator of this device wrote under
//     `mt.nodes`, so a node is added, moved or retired without a rebuild — and a second
//     implementation carries its own list rather than ours. An address compiled into a client binds
//     the network to whoever published that client, which is the one thing a protocol must not do.
//
// Reachability of a neighbour is therefore asked of nobody: a device holding a node holds the mesh,
// and a letter deposited under a tag travels from there.
enum MontanaNodes {

    /// What the wire is dressed in up to this door. The dress is a property of the DOOR, not of the
    /// protocol: everything above the wire (the post-quantum handshake, the introduction, the envelopes)
    /// is byte-identical for every door. A bare door: our own stream inside an ordinary secured
    /// connection. A door behind a delivery network: the same stream inside a rise to a web socket --
    /// the only way to carry arbitrary bytes where the intermediary speaks web only. The 24.08
    /// measurement named the reason: the phone tunnel does not carry packets to our address at all (our
    /// wire dies and so does an ordinary site request), while to an address the tunnel does carry, our
    enum Dress: Equatable {
        case raw
        case websocket(path: String)
    }

    struct Node: Equatable {
        let host: String
        let port: UInt16
        var dress: Dress = .raw
        var label: String {
            let base = host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
            if case .websocket = dress { return "wss/" + base }
            return base
        }
        var url: URL? {
            guard case .websocket(let path) = dress else { return nil }
            return URL(string: "wss://\(host):\(port)\(path)")
        }
        static func == (a: Node, b: Node) -> Bool { a.host == b.host && a.port == b.port && a.dress == b.dress }
    }

    /// The door dress by its address -- the one place that knows this ([I-10]). The dial asks the list
    /// instead of carrying the dress through half a dozen function signatures.
    static func dress(forHost host: String) -> Dress {
        list().first { $0.host == host }?.dress ?? .raw
    }

    /// The DOOR key -- name, port and wire dress in one string, computed in one place.
    /// The path ledger stands on it: a bare door and a door behind a delivery network on one name are
    /// different paths, and a shared key would bring back the erasure the ledger was split to remove.
    static func doorKey(host: String, port: UInt16) -> String {
        Node(host: host, port: port, dress: dress(forHost: host)).label
    }

    private static let key = "mt.nodes"
    private static let bookKey = "mt.doorbook"

    /// The door book: which door led to WHICH node and in how long. One record, and it is the only
    /// source of choice: an identity behind a door can be learned only by introduction, so the first
    /// probing is unavoidable while a second must not happen.
    static func book() -> [String: (overlay: Data, ms: Int)] {
        guard let raw = UserDefaults.standard.dictionary(forKey: bookKey) as? [String: String] else { return [:] }
        var out: [String: (overlay: Data, ms: Int)] = [:]
        for (door, v) in raw {
            let parts = v.split(separator: ":")
            guard parts.count == 2, let o = Data(montanaHex: String(parts[0])), let ms = Int(parts[1]) else { continue }
            out[door] = (overlay: o, ms: ms)
        }
        return out
    }

    static func remember(door: String, overlay: Data, ms: Int) {
        guard !door.isEmpty else { return }
        var raw = (UserDefaults.standard.dictionary(forKey: bookKey) as? [String: String]) ?? [:]
        raw[door] = overlay.montanaHexString + ":" + String(ms)
        UserDefaults.standard.set(raw, forKey: bookKey)
    }

    /// What to tell the person about a door. There are THREE states, and there must be three words: a
    /// door that is alive and folded away as redundant did answer -- calling that "does not answer"
    /// means reporting a refusal where there is none, and the person reads "the node is lost" off the
    /// Four states — four words (the author's find 26.08: during a door outage the screen
    /// showed a machine it no longer held with a BLANK status — three words for four states).
    /// open — this door is held; sameMachine — alive as the folded spare of a held machine;
    /// lost — the machine was met through this door and is not held right now; silent —
    /// nothing is known and nothing answers.
    enum DoorState { case open, sameMachine, lost, silent }

    static func state(of door: Node, held: Set<String>,
                      book: [String: (overlay: Data, ms: Int)], heldNodes: Set<Data>) -> DoorState {
        if held.contains(door.label) { return .open }
        if let known = book[door.label] {
            return heldNodes.contains(known.overlay) ? .sameMachine : .lost
        }
        return .silent
    }

    /// Which doors to knock at. The rule is ONE and reads aloud: a door is skipped exactly when its node
    /// is ALREADY HELD by another door right now. We hold nothing -- we knock at all of them.
    ///
    /// Before, the shadow was cast by a MEASUREMENT from the book: "this node is reachable faster by
    /// that door, and that one has not failed yet". A measurement outlives a door. A door that left the
    /// network list is hailed by nobody -- so it never "fails" and its shadow stays eternal: the node
    /// knocks at none of its doors and counts as lost while the node is alive. Measured 29.08:
    /// T2 held the Amsterdam machine through an old name, the name left the list on the move to mirror
    /// names -- and the phone stopped knocking at the new doors of the same node entirely.
    ///
    /// A shadow from LIVE holding has no such illness by construction: holding disappears together with
    /// the channel, and at that same instant both doors are in the queue again. The preference for the
    /// fast door is not lost -- it becomes an honest race: whoever answers first holds the node.
    static func doorsToKnock(all: [Node], held: Set<String>,
                             book: [String: (overlay: Data, ms: Int)], failed: Set<String>) -> [Node] {
        let heldNodes = Set(book.filter { held.contains($0.key) }.map { $0.value.overlay })
        return all.filter { d in
            guard !held.contains(d.label) else { return false }
            guard let mine = book[d.label] else { return true }
            return !heldNodes.contains(mine.overlay)
        }
    }

    /// The list as the operator of this device set it: one node per line, `host` or `host:port`.
    /// Empty means the list beside the app stands.
    static var external: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            MontanaP2PTrace.mark("nodes_set", "n=\(parse(newValue).count)")
        }
    }

    /// The list shipped beside the app, editable without touching a line of code.
    static func shipped() -> String {
        guard let u = Bundle.main.url(forResource: "nodes", withExtension: "txt"),
              let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        return s
    }

    // THE NETWORK NAMES ITS OWN DOORS. The list a node hands out (/doors) supersedes the
    // shipped bootstrap: a new door reaches every install as DATA, never as a rebuild —
    // the same law the TURN uris already live by. The operator's own list (mt.nodes)
    // still overrides everything: the device owner outranks the network.
    private static let learnedKey = "mt.nodes.learned"
    static func learned() -> String { UserDefaults.standard.string(forKey: learnedKey) ?? "" }
    static func learn(_ raw: String) {
        guard !parse(raw).isEmpty, raw != learned() else { return }
        UserDefaults.standard.set(raw, forKey: learnedKey)
        MontanaP2PTrace.mark("doors_learned", "n=\(parse(raw).count)")
    }

    // THE MACHINES BEHIND THE DOORS (15.22). The door book learns which door leads to which
    // node only by a handshake through that door — so a door that never shook hands stood
    // alone in a flat list while its twin stood under a node, and two phones of one build drew
    // two different pages (T1 held both doors of each node, T2 only the api ones; 07.09). The
    // network already hands out the doors; it now hands out which doors are one machine, and
    // the page groups by that word ALWAYS — the handshake only colours the state.
    private static let machinesKey = "mt.nodes.machines"
    static func learnMachines(_ groups: [(id: String, doors: [String])]) {
        let arr: [[String: Any]] = groups.map { ["id": $0.id, "doors": $0.doors] }
        guard let d = try? JSONSerialization.data(withJSONObject: arr), let s = String(data: d, encoding: .utf8) else { return }
        guard s != UserDefaults.standard.string(forKey: machinesKey) else { return }
        UserDefaults.standard.set(s, forKey: machinesKey)
        MontanaP2PTrace.mark("machines_learned", "n=\(groups.count)")
    }
    static func machines() -> [(id: String, doors: [Node])] {
        guard let s = UserDefaults.standard.string(forKey: machinesKey),
              let arr = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let id = m["id"] as? String, let ds = m["doors"] as? [String] else { return nil }
            return (id, parse(ds.joined(separator: "\n")))
        }
    }

    static func parse(_ raw: String) -> [Node] {
        var out: [Node] = []
        // A comment is dropped BY THE LINE. Cutting the whole text on spaces first turned every
        // word of every comment into a node, and the trace showed this device knocking at «the»,
        // «list» and «operator» — a reader of that list would have called it working.
        let words = raw.split(separator: "\n").flatMap { line -> [Substring] in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { return [] }
            return t.split(whereSeparator: { $0 == "," || $0 == " " })
        }
        for piece in words {
            var s = piece.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, !s.hasPrefix("#") else { continue }
            var host = s, port = MontanaDirectPort.value
            // The string names its own dress: `wss://name/path` is a door behind a delivery network,
            // bare `host:port` is as before. A device operator changes either without a rebuild, and a
            // foreign implementation carries its own list.
            var dress = Dress.raw
            if s.lowercased().hasPrefix("wss://") {
                let body = String(s.dropFirst(6))
                let slash = body.firstIndex(of: "/")
                let hostPart = slash.map { String(body[body.startIndex..<$0]) } ?? body
                let path = slash.map { String(body[$0...]) } ?? "/"
                guard !hostPart.isEmpty else { continue }
                dress = .websocket(path: path)
                port = 443
                s = hostPart
                host = hostPart
            }
            if s.hasPrefix("[") {                                   // [v6]:port
                guard let close = s.firstIndex(of: "]") else { continue }
                host = String(s[s.index(after: s.startIndex)..<close])
                let rest = s[s.index(after: close)...]
                if rest.hasPrefix(":"), let p = UInt16(rest.dropFirst()) { port = p }
            } else if s.filter({ $0 == ":" }).count == 1, let colon = s.lastIndex(of: ":") {
                let tail = String(s[s.index(after: colon)...])
                if let p = UInt16(tail) { host = String(s[s.startIndex..<colon]); port = p }
            }
            guard !host.isEmpty, port > 0 else { continue }
            let d = Node(host: host, port: port, dress: dress)
            if !out.contains(d) { out.append(d) }
        }
        return out
    }

    static func list() -> [Node] {
        let ext = parse(external)
        let net = parse(learned())
        let raw = !ext.isEmpty ? ext : (!net.isEmpty ? net : parse(shipped()))
        // A machine is not its own node. Its address can stand in the list like anyone else's, and a
        // channel to it is a channel to ITSELF: the lamp goes green, the count of nodes grows, and
        // there is nobody on the other side.
        let ownLan = MontanaP2PNode.lanIP() ?? ""
        return raw.filter { $0.host != ownLan }
    }

    // A node that does not answer is not knocked into the ground: the delay doubles per failure and
    // is spread, the same shape the endpoint book uses, so a whole list never retries in step.
    private static let lock = NSLock()
    private static var triedAt: [String: (at: Date, step: Double, failed: Bool)] = [:]
    // A node is a meeting and transit point; the link to it is held permanently. Reconnection is fast
    // and with a low ceiling: a fallen channel to a node is restored in seconds rather than minutes, or
    // letters hang in transit for all the time the channel is away.
    private static let stepMin: Double = 2
    private static let stepMax: Double = 15
    /// A door that has REFUSED many times in a row rests longer — up to ten minutes. With the
    /// step capped at fifteen seconds, four dead doors cost sixteen knocks a minute for as long
    /// as the network stayed down (measured 20:06 with every node off). A door that answers
    /// again resets to the fast step: reconnection stays a matter of seconds for a living door.
    private static let stepDeadMax: Double = 600

    /// Whether a full knock round has happened at all in this life of the app. Until it has, the
    /// absence of a held node means «not asked yet», never «nobody answers» — and a lamp must not
    /// turn that into a red verdict (the author's word 29.08: a red globe for a couple of seconds
    /// after opening a notification, then green).
    private(set) static var knockedOnce = false

    /// Knock on every node this node does not already hold. Idempotent and cheap: a node with a
    /// standing channel is skipped, a node that just failed waits out its delay.
    static func open() {
        // "We hold" is taken from the PATH registry, not from the identity index: while this number
        // stood on identity, a second door to the same node counted as open for not one second, and the
        // dial hammered at it forever -- `node_open` lines with `connect_ms=0` came in batches.
        let held = MontanaP2PDirect.shared.livePathKeys()
        let now = Date()
        // "Failed" means the door REFUSED, not "an attempt is in progress". While the mere fact of an
        // attempt stood here, the fast door's backoff instantly opened the road to the slow one, and the race returned.
        lock.lock(); let failed = Set(triedAt.filter { $0.value.failed }.keys); lock.unlock()
        let all = list()
        let wanted = doorsToKnock(all: all, held: held, book: book(), failed: failed)
        // A DOOR LEFT OUT SAYS SO. A silently skipped door is indistinguishable from a door
        // that answers, and that silence cost a whole evening: the phone held nothing and
        // knocked nowhere, while the trace showed only the doors it did knock.
        let wantedKeys = Set(wanted.map { $0.label })
        // D-3 (16.1.2): the same four skip lines repeated every knock round — ~500 lines an
        // hour saying one unchanged fact. The summary speaks when its content changes.
        let skipLine = all.filter { !wantedKeys.contains($0.label) }
            .map { "\($0.label)=\(held.contains($0.label) ? "held" : "node-held-elsewhere")" }
            .sorted().joined(separator: " ")
        if !skipLine.isEmpty { MontanaP2PTrace.markChanged("node_skip", skipLine) }
        for d in wanted {
            lock.lock()
            let cur = triedAt[d.label]
            let step = cur?.step ?? stepMin
            let due = now.timeIntervalSince(cur?.at ?? .distantPast) >= step
            if due {
                let spread = Double.random(in: 0.8...1.4)   // LOCAL-RANDOM-OK: spread of a retry, not a quantity of the protocol
                // The ceiling depends on the door's word: one that refused keeps doubling toward
                // the dead ceiling, one still unanswered stays under the fast one.
                let ceiling = (cur?.failed ?? false) ? stepDeadMax : stepMax
                triedAt[d.label] = (now, min(ceiling, step * 2 * spread), cur?.failed ?? false)
            }
            lock.unlock()
            guard due else { continue }
            let knockAt = Date()   // measuring the connect time to the node in milliseconds
            knockedOnce = true
            MontanaP2PTrace.mark("node_knock", "at=\(d.label)")
            MontanaP2PDirect.shared.ensureChannel(ip: d.host, port: d.port, ref: nil) { ok in
                // A node that did not answer says so: silence here would leave a node standing
                // outside the mesh with nothing in the trace to say why.
                if ok {
                    lock.lock(); triedAt[d.label] = nil; lock.unlock()
                    MontanaP2PTrace.mark("node_open", "at=\(d.label) connect_ms=\(Int(Date().timeIntervalSince(knockAt) * 1000))")
                } else if MontanaP2PDirect.localFaultRecent() {
                    // Not the door's word: the process itself could not open a socket. The door
                    // keeps the fast step and is not judged (05.09) — but it is knocked again AFTER
                    // the fast step, not this instant: «at once» spun into twenty knocks a
                    // half-second on a door that answered with a TLS alert while a local fault was
                    // still within its half-minute (08.09, T1 on the diaries door).
                    lock.lock(); triedAt[d.label] = (Date(), stepMin, false); lock.unlock()
                    MontanaP2PTrace.markFolded("node_shut", "at=\(d.label) local-fault — the door is not judged", window: 5, key: d.label)
                } else {
                    lock.lock()
                    if let c = triedAt[d.label] { triedAt[d.label] = (c.at, c.step, true) }
                    lock.unlock()
                    // ONE DEATH, ONE LINE. The callback fires per WAITER: a door with two letters
                    // queued on it reported its single closure twice, with different ages, and the
                    // trace read as two failures (19:27, four lines for two doors). The channel is
                    // the thing that shut; the waiters merely heard about it.
                    MontanaP2PTrace.markFolded("node_shut", "at=\(d.label) after_ms=\(Int(Date().timeIntervalSince(knockAt) * 1000))",
                                               window: 5, key: d.label)
                }
            }
        }
    }

    /// Instant restoration of the link to nodes: it drops the delays and knocks right now.
    /// Called on every opening of the app -- a node must be in touch at that same instant.
    /// The human label of a door by its host, for the diary (the list holds label→host).
    static func label(forHost host: String) -> String {
        list().first { $0.host == host }?.label ?? host
    }

    /// 16.6.19 — A DOOR IS JUDGED AFRESH ON EACH NETWORK. A verdict «dead» earned on plain
    /// cellular (where the raw port and UDP serve and the web door is pointless) must not carry
    /// into a full tunnel that passes ONLY web on 443 — there that very door is the only road.
    /// The witness calls this when the interface set or the tunnel fact changes: every door gets
    /// one fresh knock on the new network, and none stays dead by a memory from another.
    static func onNetworkChanged() {
        lock.lock(); triedAt.removeAll(); lock.unlock()
        MontanaP2PTrace.mark("doors_rejudged", "network changed — every door knocks fresh")
        openNow(force: true)
    }

    static func openNow(force: Bool = false) {
        // Knock NOW — but keep what the door has said. Wiping the table forgot that a door had
        // refused, and every opening of the app restarted all four dead doors at the fast step
        // (measured 03.09 20:00-20:13: seven openings, intervals 5-20 s, ~70 lines a minute at
        // rest — the storm 16.1.3 closed, back through this one line). The step and the verdict
        // stay; only the clock is reset, so each door gets one immediate knock.
        lock.lock()
        for (k, v) in triedAt { triedAt[k] = (Date.distantPast, v.step, v.failed) }
        lock.unlock()
        // Cycle the channels to the nodes by force: a socket dead after sleep counts as alive and an
        // ordinary open passes it by as "held". We drop it and dial anew -- instantly.
        for d in list() { MontanaP2PDirect.shared.reprobeNode(ip: d.host, port: d.port, force: force) }
        open()
    }

    /// Whether an address is a node -- so that a break of a channel to a node is healed immediately.
    static func isNode(_ ip: String) -> Bool { list().contains { $0.host == ip } }

    /// Nodes this node stands in right now — measured on the channels themselves and never
    /// remembered: a node held yesterday is not a node held now.
    static func live() -> [Node] {
        let held = MontanaP2PDirect.shared.livePathKeys()
        return list().filter { held.contains($0.label) }
    }

    /// How many DOORS stand. A value about paths, and it is named by paths.
    static var liveDoors: Int { live().count }

    /// How many NODES we hold: two doors to one machine are one node. The lamp and "online" stand on
    /// this number, because a person is promised a network, not a count of wires to it.
    static var liveNodes: Int {
        MontanaP2PDirect.shared.nodeIdentities(behind: Set(live().map { $0.label })).count
    }
}
