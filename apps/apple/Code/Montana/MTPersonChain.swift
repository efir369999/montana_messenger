import Foundation
import CryptoKit
import UIKit
import MontanaBindings

/// THE TIMECHAINS OF THE MINTING (the author's words 03.10.2026 21:25 UTC: «in chess too its own TimeChain of the minting for
/// every move, put in order»; the chain's constitution, points 4 and 5: «build by the Architecture of TimeChains», «build the
/// Economy of Time»). Every source of coins keeps its own chain on this phone -- chess, the Pantheon, the VPN wall, the Timer, the
/// chats' letters, the coins received, given and sent: one link per move of coins, numbered, stamped in milliseconds and sealed
/// by SHA-256 over the link and the seal of the one before, so a link changed or moved breaks every seal after it. The book keeps
/// the balance; the chains keep how every coin came. One seam writes them -- the book's keep, where every new move is written --
/// and a move joins its chain once, by its name. Local today; the core's key from the seed signs their heads next.
enum MTTimeChain {
    struct Link: Codable { let n: Int; let at: Int64; let k: String; let c: Int; let ref: String; let prev: String; let hash: String }
    struct Head: Equatable { let n: Int; let hash: String; let whole: Bool }
    static let genesis = String(repeating: "0", count: 64)
    /// ONE MOMENT, THE SAME ON EVERY DEVICE TO THE MILLISECOND (the author's word 06.10.2026 08:2x UTC: «everything to the millisecond,
    /// exact on all nodes, the sender and the receivers above all»): a move is born at a whole millisecond, and every road writes that
    /// millisecond as it is -- the lane, the chains, the book of another device of the words. `Int64(at * 1000)` cut the fraction:
    /// 5 185 of the iPhone 17's 15 331 moves reached the seed's other devices a millisecond earlier than their owner wrote them.
    nonisolated static func ms(_ moment: Double) -> Int64 { Int64((moment * 1000).rounded()) }
    nonisolated static func now() -> Double { Double(ms(Date().timeIntervalSince1970)) / 1000 }
    /// THE CHAINS OF THE BUILDS BEFORE (the author's word 02.11.2026 16:14 UTC, link 14629: «only 1 coin is 1 second, no other way
    /// named»): the games, the chats, the comments, the calls and the letters minted or burned coins on this phone until the chain
    /// alone minted (decisions 375 and 383 «a»). Their chains stay sealed on the phone; the wallet names them by one word, the
    /// builds before, and shows no road of coins by them.
    static let before = Set(["chess", "pantheon", "vpnwall", "timer", "chats", "groups", "channels", "comments", "calls", "letters"])
    /// The sources, each its own chain, in the wallet's order.
    static let sources = ["pi", "chess", "pantheon", "vpnwall", "vpnpay", "timer", "chats", "groups", "channels", "comments", "wall", "received", "spent", "sent", "calls", "letters", "system"]
    private static let q = DispatchQueue(label: "montana.TimeChains", qos: .utility)
    private struct Held { var n: Int; var hash: String; var refs: Set<String> }
    private static var held: [String: Held] = [:]   // each chain read once, on q

    private static func file(_ chain: String) -> URL? { MTTimeChainPlace.file(chain) }
    /// The person lifted into the seat: the chains held in memory belong to the person who left, and the lifted person's chains of
    /// the builds before are laid into their TimeChain folder at the next ask.
    static func forget() { q.async { held = [:]; MTTimeChainPlace.settle() } }
    /// The seal: SHA-256 over the link's fields, one per line, the previous seal last.
    static func seal(n: Int, at: Int64, k: String, c: Int, ref: String, prev: String) -> String {
        let body = [String(n), String(at), k, String(c), ref, prev].joined(separator: "\n")
        return SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func links(_ chain: String) -> [Link] {
        guard let u = file(chain), let text = try? String(contentsOf: u, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(Link.self, from: Data($0.utf8)) }
    }
    private static func state(_ chain: String) -> Held {
        if let h = held[chain] { return h }
        let all = links(chain)
        let h = Held(n: all.last?.n ?? 0, hash: all.last?.hash ?? genesis, refs: Set(all.map(\.ref)))
        held[chain] = h
        return h
    }
    /// Links in one turn of the queue, not a turn for every link (04.10): the book's whole past joins so (MTTimeChain.appendPast).
    static func notePast(_ links: [(chain: String, kind: String, coins: Int, ref: String, at: Double)]) {
        q.async { for l in links { write(l.chain, kind: l.kind, coins: l.coins, ref: l.ref, at: l.at) } }
    }
    /// One link that is not a move of coins (a level of π reached): the same seal, the same once-by-name.
    static func note(_ chain: String, kind: String, coins: Int, ref: String, at moment: Double = Date().timeIntervalSince1970) {
        q.async { write(chain, kind: kind, coins: coins, ref: ref, at: moment) }
    }
    /// THE WALL'S CHAIN (the author's word 03.10.2026 23:38 UTC): my wall's posts as they stand -- a post not yet chained joins as
    /// born (post), one whose words or files moved as changed (edit), one chained and no longer standing as taken down (gone); the
    /// births in the order the posts were born. One queue, so every link keeps its place.
    static func wall(_ posts: [(id: String, sig: String, at: Double)]) {
        q.async {
            let refs = state("wall").refs
            var chained = Set<String>(), gone = Set<String>()
            for r in refs {
                let parts = r.split(separator: ":", omittingEmptySubsequences: false)
                if parts.count == 3, parts[0] == "post" { chained.insert(String(parts[1])) }
                if parts.count == 2, parts[0] == "gone" { gone.insert(String(parts[1])) }
            }
            let now = Date().timeIntervalSince1970
            for p in posts.sorted(by: { a, b in a.at < b.at }) {
                let ref = "post:" + p.id + ":" + p.sig
                guard !refs.contains(ref) else { continue }
                let changed = chained.contains(p.id)
                write("wall", kind: changed ? "edit" : "post", coins: 0, ref: ref, at: changed ? now : p.at)
                chained.insert(p.id)
            }
            let standing = Set(posts.map { p in p.id })
            for id in chained.subtracting(standing).subtracting(gone).sorted() {
                write("wall", kind: "gone", coins: 0, ref: "gone:" + id, at: now)
            }
        }
    }
    /// Queue-only: one link joins its chain, once by its name.
    private static func write(_ chain: String, kind: String, coins: Int, ref: String, at moment: Double) {
        let at = ms(moment)
        do {
            var h = state(chain)
            guard !h.refs.contains(ref), let u = file(chain) else { return }
            let n = h.n + 1
            let hash = seal(n: n, at: at, k: kind, c: coins, ref: ref, prev: h.hash)
            guard var line = try? JSONEncoder().encode(Link(n: n, at: at, k: kind, c: coins, ref: ref, prev: h.hash, hash: hash)) else { return }
            line.append(0x0A)
            // THE LINKS OF A SECOND RIDE ONE WRITE (the author's word 04.10.2026 09:27 UTC, the heat of the minting): the seal is
            // made at once and the link waits a second for its file with the others. A write that fails leaves the link out of the
            // file, and the next reading of the book appends it again by its name (MTLocalCoinLedger.load).
            waiting[u, default: Data()].append(line)
            h.n = n; h.hash = hash; h.refs.insert(ref)
            held[chain] = h
            if !due {
                due = true
                q.asyncAfter(deadline: .now() + 1) { writeWaiting() }
            }
        }
    }
    private static var waiting: [URL: Data] = [:]   // on q: the links sealed and not yet in their files
    private static var due = false
    /// Queue-only: every waiting link into its chain's file.
    private static func writeWaiting() {
        due = false
        let all = waiting
        waiting = [:]
        for (u, data) in all {
            if !MTDiskDoor.append(data, to: u, "time-chain"), !FileManager.default.fileExists(atPath: u.path) {
                // Born only where none stands: a chain that stands but would not open is never written over.
                MTDiskDoor.write(data, to: u, "time-chain", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }
    /// The app leaves the screen: the waiting links are written now.
    static func flush() { q.async { writeWaiting() } }
    /// Every link of a chain as its file holds it (the chain's own page, the history's seals).
    static func read(_ chain: String, done: @escaping ([Link]) -> Void) {
        q.async {
            let all = links(chain)
            DispatchQueue.main.async { done(all) }
        }
    }
    /// The chain read whole from its file and every seal checked from the genesis: its length, its head, whether it is whole.
    static func head(_ chain: String, done: @escaping (Head) -> Void) {
        q.async {
            var prev = genesis, whole = true, n = 0
            for l in links(chain) {
                n += 1
                guard l.n == n, l.prev == prev, l.hash == seal(n: l.n, at: l.at, k: l.k, c: l.c, ref: l.ref, prev: l.prev) else { whole = false; break }
                prev = l.hash
            }
            let h = Head(n: n, hash: prev, whole: whole)
            DispatchQueue.main.async { done(h) }
        }
    }
}

// MARK: - THE CHAIN OF THE PERSON (the author's words 10.10.2026 10:4x UTC, 12:0x UTC and 12:2x UTC)

/// THE CHAIN OF THE PERSON COUNTS THE SECONDS THE WORDS WERE ON THE NETWORK (the author's word 10.10.2026 10:4x UTC: «in this
/// section the first TimeChain is called Person: it shows the levels of the person, and the count goes only for the seconds this
/// seed was actually online on any device»; App, «The chains of time a client shows»). A second counts while the wallet stands on
/// the screen and a node answers its exchanges: the seconds are the node's own, read from the answer's Date header, never this
/// phone's clock, and two answers at most `reach` apart vouch for every second between them. The seconds are kept as spans and
/// joined with the spans every other device of the words laid under the words' own key -- one sealed piece a device on every
/// node, beside the coin book -- so two devices present in one second add one second. The level is the number of whole doublings
/// of the count (Canon, «The level of the chain of the person»: bit_length(s) - 1, none below one second); one link a level, at
/// the second the count reached it, sealed on the one before by MTTimeChain's own seal, so the same union gives the same chain on
/// every device. The person sees it; it is published nowhere and leaves the phone only sealed under the words.
@MainActor final class MTPersonChain: ObservableObject {
    static let shared = MTPersonChain()
    struct Span: Codable, Equatable { var a: Int64; var b: Int64 }   // node seconds, both ends counted
    struct Away: Codable { var at: Int64; var level: Int }
    /// Two answers this far apart or nearer vouch for every second between them: the wallet asks the nodes every three seconds
    /// while it stands open, and an answer slow by a beat or two still continues the span.
    static let reach: Int64 = 10
    @Published private(set) var seconds: Int64 = 0
    @Published private(set) var links: [MTTimeChain.Link] = []
    var level: Int? { Self.level(seconds) }
    private var spans: [Span] = []
    private var lane = Data()
    private var last: Int64?   // the node second of the last answer in this stretch on the screen
    private var away: Away?    // the app left the screen: the node second of its last answer and the Global Level of then
    private var loaded = false, dirty = false, putting = false, keepDue = false, checked = false
    private var putAt: Double = 0, gotAt: Double = 0
    private var opened: [String: Data] = [:]   // a piece's name: its lane, opened once
    private var mine: [String: String] = [:]   // a node's door: the piece of this lane it holds now
    private var stale = Set<String>()

    /// THE LEVEL (Canon, «The level of the chain of the person»): the whole doublings of the count, none below one second.
    nonisolated static func level(_ s: Int64) -> Int? { s < 1 ? nil : 63 - s.leadingZeroBitCount }
    /// THE FROZEN VECTORS (Canon: level(1) = 0, level(3) = 1, level(1048576) = 20, none below one second) and the doubling's edge at
    /// every power: three refuses a logarithm rounded upward, one refuses a bit length taken without its minus one, the edges refuse
    /// a level that opens a second early or late.
    nonisolated static func levelKAT() -> Bool {
        guard level(1) == 0, level(3) == 1, level(1_048_576) == 20, level(0) == nil, level(-5) == nil else { return false }
        for k in 1...62 where level(Int64(1) << k) != k || level((Int64(1) << k) - 1) != k - 1 { return false }
        return level(Int64.max) == 62
    }
    /// THE GLOBAL LEVEL OF THE PERSON, THE ONE READING OF IT (the author's words 10.10.2026 12:0x UTC: «the lowest level among the
    /// chain of the person and the chain of the wallet becomes the Global Level of the person»; 17.10.2026 19:24 UTC and 19:41 UTC: the
    /// third level, the Fabric of Time, «bears on the Global level by the rule of the minimum», «under the word level we mean only the
    /// global one»; Canon, «The level of a person»: min(p, w, f)): the lowest of the person's level, the wallet's level of π and the
    /// level of the fabric of time this turn (MTFabricLevel). A fabric this life has not read yet adds no third term -- an unknown
    /// level is never said as none. Every place that speaks of the person's level asks this and computes nothing of its own.
    nonisolated static func global(person: Int?, wallet: Int) -> Int {
        MTFabricRules.levelOfPerson(person ?? 0, wallet, MTFabricLevel.now ?? Int.max)
    }
    nonisolated static func global(person: Int?, balance: Int) -> Int {
        global(person: person, wallet: MTFabricRules.walletLevel(balance))
    }
    /// My Global Level on a page that reads it live (slice S2b b7c): the wallet's term from my available behind the coin door, and
    /// none where the edition carries no coins (link 14822). A page watches MTApps.balanceWatch to be drawn again.
    @MainActor static func global(person: Int?) -> Int {
        global(person: person, wallet: MTApps.coins.map { MTFabricRules.walletLevel($0.available) } ?? Int.max)
    }
    /// THE WALLET'S TERM OF THE LEVEL (link 14822: in an edition without coins the balance is no criterion of a level): the wallet's
    /// level of π as the coin door says it where the edition carries coins; Int.max -- no term -- where it carries none; nil while
    /// the book is unread, so the level is not said before it is known.
    nonisolated static var walletTerm: Int? {
        guard let coins = MTApps.coins else { return Int.max }
        return coins.walletLevel
    }

    private struct Kept: Codable { var lane: String; var spans: [Span]; var away: Away? }
    private static var file: URL? { MTTimeChainPlace.dir()?.appendingPathComponent("person-seconds.json") }
    private func load() {
        guard !loaded else { return }
        loaded = true
        if let u = Self.file, let d = try? Data(contentsOf: u), let k = try? JSONDecoder().decode(Kept.self, from: d),
           let l = Data(base64Encoded: k.lane), l.count == 16 {
            lane = l; spans = Self.joined(k.spans); away = k.away
        } else {
            lane = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        }
        MTFabric.shared.prime()   // the third level is read with the first (MTFabric)
        recount(write: false)
    }
    private func keep() {
        guard let u = Self.file, let d = try? JSONEncoder().encode(Kept(lane: lane.base64EncodedString(), spans: spans, away: away)) else { return }
        MTDiskDoor.write(d, to: u, "person-kept", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func keepSoon() {
        guard !keepDue else { return }
        keepDue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.keepDue = false; self?.keep() }
    }
    /// A person lifted into the seat: the seconds of the person who left go with their folder; the seated person's are read next.
    func reread() {
        loaded = false; spans = []; links = []; seconds = 0; last = nil; away = nil
        opened = [:]; mine = [:]; stale = []; dirty = false
        MTPersonLevel.set(nil)
        MTFabric.shared.reread()   // the fabric of the person who left goes with their folder too
    }
    /// The seconds are read before a node's answer asks for them: a face that shows the level, and a word that says it, need them now.
    func prime() { load() }

    /// Spans joined: sorted, and any two that touch or overlap become one -- a second is counted once however many devices held it.
    nonisolated static func joined(_ all: [Span]) -> [Span] {
        var out: [Span] = []
        for s in all.filter({ x in x.a <= x.b }).sorted(by: { x, y in x.a < y.a }) {
            if let l = out.last, s.a <= l.b + 1 { out[out.count - 1].b = max(l.b, s.b) } else { out.append(s) }
        }
        return out
    }
    /// One link a level, at the node second the count reached 2^k, each sealed on the one before (MTTimeChain.seal).
    nonisolated static func chain(_ spans: [Span]) -> [MTTimeChain.Link] {
        var out: [MTTimeChain.Link] = [], count: Int64 = 0, next: Int64 = 1, prev = MTTimeChain.genesis
        for s in spans {
            let len = s.b - s.a + 1
            while next <= count + len {
                let at = (s.a + (next - count) - 1) * 1000
                let k = out.count, ref = "level:" + String(out.count)
                let hash = MTTimeChain.seal(n: k + 1, at: at, k: "level", c: k, ref: ref, prev: prev)
                out.append(MTTimeChain.Link(n: k + 1, at: at, k: "level", c: k, ref: ref, prev: prev, hash: hash))
                prev = hash
                guard next <= Int64.max / 2 else { return out }
                next *= 2
            }
            count += len
        }
        return out
    }
    /// The count and the links read again; the chain's file (TimeChain/wallet-person.jsonl, seen in Files) follows a new level.
    private func recount(write: Bool = true) {
        seconds = spans.reduce(0) { n, s in n + (s.b - s.a + 1) }
        MTPersonLevel.set(level)
        MTFabric.shared.refresh()   // the ceiling stands on the person's level (MTFabric)
        MTLevelDistribution.shared.changed()
        let fresh = Self.chain(spans)
        guard fresh.last?.hash != links.last?.hash else { return }   // the head's seal seals the whole chain
        links = fresh
        guard write, let u = MTTimeChainPlace.file("person") else { return }
        var body = Data()
        for l in fresh { if let d = try? JSONEncoder().encode(l) { body.append(d); body.append(0x0A) } }
        MTDiskDoor.write(body, to: u, "person-chain", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// A node answered an exchange of this app (MTSeedVault.post): while the app stands on the screen its second counts, and so does
    /// every second back to the answer before it when they are no further apart than the reach.
    func answered(_ resp: URLResponse?) {
        guard UIApplication.shared.applicationState == .active,
              let hdr = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date"),
              let at = MontanaWakePush.httpDateFormatter.date(from: hdr) else { return }
        load()
        let s = Int64(at.timeIntervalSince1970)
        if away != nil { away = nil; keep() }   // a leave kept by a build before 2320 is let go
        let from = last.flatMap { l in l <= s && s - l <= Self.reach ? l : nil } ?? s
        last = max(last ?? s, s)
        let before = seconds
        spans = Self.joined(spans + [Span(a: from, b: s)])
        recount()
        guard seconds != before else { return }
        dirty = true
        keepSoon()
    }

    /// THE APP LEAVING THE SCREEN ENDS THE STRETCH (the author's word 10.10.2026 12:0x UTC once paid the seconds away here, one coin
    /// each): since build 2320 nothing local mints (the author's decision 375 «a») -- absence is not presence, and the chain mints only
    /// while the person is here (fold-7).
    func left() {
        load()
        last = nil
    }

    // MARK: the devices of the words join their seconds: one sealed piece a device, beside the coin book on every node
    private static let aad = Data("mt.person.chain".utf8)   // NOT-UI: the words the piece's seal is bound to
    private struct Piece: Codable { var lane: String; var spans: [Span] }
    /// The wallet's live beat asks this every turn: the other devices' pieces every half minute, this device's union when it moved,
    /// once a minute at most.
    func tick() async {
        load()
        if !checked { checked = true; MontanaTrace.mark("person_self", "ok=\(Self.levelKAT() ? 1 : 0) fabric=\(MTFabricRules.selfCheck() ? 1 : 0)") }
        let now = Date().timeIntervalSince1970
        if 30 <= now - gotAt { gotAt = now; await gather() }
        if dirty, 60 <= now - putAt { await put() }
    }
    private func put() async {
        guard !putting, let k = MTSeedVault.personRow(),
              let plain = try? JSONEncoder().encode(Piece(lane: lane.base64EncodedString(), spans: spans)),
              let sealed = try? ChaChaPoly.seal(plain, using: k.seal, authenticating: Self.aad).combined else { return }
        putting = true
        defer { putting = false }
        putAt = Date().timeIntervalSince1970
        dirty = false
        let token = MontanaHomeNode.hex(k.token)
        let id = MontanaHomeNode.hex(Data(SHA256.hash(data: sealed)))
        var laid = 0
        for door in MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) {
            let gone = Array(stale.union(mine[door].map { p in [p] } ?? [])).filter { p in p != id }
            let (code, o) = await MTSeedVault.post(door + "/vault-put", ["token": token, "blob": sealed.base64EncodedString(), "replace": gone], timeout: 10)
            guard code == 200, let piece = o?["piece"] as? String else { continue }
            mine[door] = piece
            opened[piece] = lane
            laid += 1
        }
        if 0 < laid { stale = [] } else { dirty = true }
        MontanaTrace.markFolded("person_put", "spans=\(spans.count) seconds=\(seconds) doors=\(laid)", window: 60)
    }
    private func gather() async {
        guard let k = MTSeedVault.personRow() else { return }
        let gen = MTSeatTurn.now
        let token = MontanaHomeNode.hex(k.token)
        for door in MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) {
            guard case let (200, o?) = await MTSeedVault.post(door + "/vault-get", ["token": token, "have": Array(opened.keys.prefix(256))], timeout: 6),
                  let held = o["held"] as? [String] else { continue }
            guard gen == MTSeatTurn.now else { return }   // the seat moved during the wait: nothing of the person who left joins
            let horizon = Int64(MontanaWakePush.nodeNow()) + 60   // no second of the future is a second lived
            var got: [Span] = []
            for x in (o["pieces"] as? [[String: Any]]) ?? [] {
                guard let id = x["piece"] as? String, let b = (x["blob"] as? String).flatMap({ s in Data(base64Encoded: s) }),
                      MontanaHomeNode.hex(Data(SHA256.hash(data: b))) == id,   // a piece is its own name
                      let box = try? ChaChaPoly.SealedBox(combined: b),
                      let plain = try? ChaChaPoly.open(box, using: k.seal, authenticating: Self.aad),
                      let p = try? JSONDecoder().decode(Piece.self, from: plain), let l = Data(base64Encoded: p.lane) else { continue }
                opened[id] = l
                if l == lane {
                    if mine[door] != id { stale.insert(id) }
                    continue
                }
                got += p.spans.filter { s in s.b <= horizon }
            }
            let standing = Set(held)
            opened = opened.filter { e in standing.contains(e.key) }
            let before = seconds
            spans = Self.joined(spans + got)
            recount()
            if seconds != before { dirty = true; keepSoon() }
            MontanaTrace.markFolded("person_get", "seconds=\(seconds) level=\(level ?? -1) joined=\(seconds - before)", window: 60)
            return
        }
    }
}

/// THE SEED'S VAULT ON THE NODES (the coin book by the seed, 04.10.2026; shared since slice S2b b7f2 -- the person's chain is every
/// edition's, docs/APPS-API.md section 3): the seal and the owner key the words derive for the vault of every node, the person's own
/// row under them, and the one exchange with a node. The coins lay their book under the same seal (MTCoinVault). The labels are
/// frozen: every device of the same words derives the same keys, and tools/mt-top-check.py holds their vectors (MTCoinVault.keyKAT).
enum MTSeedVault {
    private static let sealLabel = Data("mt-coins-vault-key-v1".utf8)      // NOT-UI: the seal's derivation label
    private static let ownerLabel = Data("mt-coins-vault-owner-v1".utf8)   // NOT-UI: the row's derivation label
    private static let personLabel = Data("mt-person-chain-token".utf8)    // NOT-UI: the chain of the person's row label (MTPersonChain)
    static func seal(_ entropy: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data(), info: sealLabel, outputByteCount: 32)
    }
    static func owner(_ entropy: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data(), info: ownerLabel, outputByteCount: 32)
    }
    /// The chain of the person's row and seal (MTPersonChain): the vault's seal, and a row of its own under the owner key.
    @MainActor static func personRow() -> (seal: SymmetricKey, token: Data)? {
        guard let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return (seal(e), Data(HMAC<SHA256>.authenticationCode(for: personLabel, using: owner(e))))
    }
    /// One exchange with a node's vault: the body as JSON, the node's code and its JSON answer; every answer is a second of the
    /// person on the network.
    @MainActor static func post(_ url: String, _ body: [String: Any], timeout: Double) async -> (Int, [String: Any]?) {
        guard let u = URL(string: url), let d = try? JSONSerialization.data(withJSONObject: body) else { return (-1, nil) }   // SERVER-DEBT-ACK: the accelerator node (rung 4), the seed's sealed book
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = timeout   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = d
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return (-1, nil) }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        MTPersonChain.shared.answered(resp)   // a node's answer is a second of the person on the network (MTPersonChain)
        return ((resp as? HTTPURLResponse)?.statusCode ?? -1, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// MARK: - THE FABRIC OF TIME (the author's words 17.10.2026 19:24 UTC, 19:41 UTC, 19:50 UTC and 20:18 UTC)

/// THE TIMECHAIN FOLDER (the author's words 04.10.2026 10:42 UTC: «in the Montana folder make a folder TimeChain, so I see it on all
/// devices, with the wallet's TimeChain of each device in it»; «TimeChain is written so, exactly, everywhere»): the one folder the
/// Files app shows as On My iPhone, Montana, TimeChain -- the comment chains a person wrote (MTBoardSeen, the author's word 02.10
/// 15:09) and the wallet's chains, one file a source (wallet-pantheon.jsonl, wallet-chats.jsonl ...). The folder is the seated
/// person's (SeedScope.seatFolders): parked and lifted with them, so no chain of one person stays to the next. Laid once a seat:
/// the comment chains' folder of the builds before («Timechain») takes the one name -- through a step on a disk that knows no case,
/// its files moving in on one that does -- and the wallet's chains of the builds before move in from the book's folder.
enum MTTimeChainPlace {
    private static let lock = NSLock()
    private static var laid = false
    static func dir() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let root = docs.appendingPathComponent(MontanaPaths.root).appendingPathComponent("TimeChain", isDirectory: true)
        lock.lock(); defer { lock.unlock() }
        if !laid {
            laid = true
            lay(root, before: docs.appendingPathComponent(MontanaPaths.root).appendingPathComponent("Timechain", isDirectory: true))
        }
        return root
    }
    static func file(_ chain: String) -> URL? { dir()?.appendingPathComponent("wallet-" + chain + ".jsonl") }
    /// A seat's move: the lifted person's folder is laid again at the next ask.
    static func settle() { lock.lock(); laid = false; lock.unlock() }
    private static func lay(_ root: URL, before old: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: old.path) {
            let was = (try? old.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
            let now = (try? root.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
            if let was, let now, was.isEqual(now) {
                let step = old.deletingLastPathComponent().appendingPathComponent("TimeChain-" + UUID().uuidString, isDirectory: true)
                if (try? fm.moveItem(at: old, to: step)) != nil { try? fm.moveItem(at: step, to: root) }
            } else if !fm.fileExists(atPath: root.path) {
                try? fm.moveItem(at: old, to: root)
            } else {
                for n in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] where !fm.fileExists(atPath: root.appendingPathComponent(n).path) {
                    try? fm.moveItem(at: old.appendingPathComponent(n), to: root.appendingPathComponent(n))
                }
                if ((try? fm.contentsOfDirectory(atPath: old.path)) ?? ["held"]).isEmpty { try? fm.removeItem(at: old) }
            }
        }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        guard let coins = MTApps.coins?.chainsBefore, let names = try? fm.contentsOfDirectory(atPath: coins.path) else { return }
        var moved = 0
        for n in names where n.hasPrefix("chain-") && n.hasSuffix(".jsonl") {
            let to = root.appendingPathComponent("wallet-" + String(n.dropFirst("chain-".count)))
            guard !fm.fileExists(atPath: to.path) else { continue }
            if (try? fm.moveItem(at: coins.appendingPathComponent(n), to: to)) != nil { moved += 1 }
        }
        if 0 < moved { MontanaTrace.mark("timechain_place", "laid=\(moved)") }
    }
}
