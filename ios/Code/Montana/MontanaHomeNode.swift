import Foundation
import CryptoKit
import SwiftUI

// YOUR NODE (the author's word 28.09: «your node is your backup of the whole phone. What you choose yourself. A
// machine the person owns, named by its address alone. This file is the first of its rooms: THE COPY OF THE WHOLE
// PHONE goes there and comes back from there.
//
// The node keeps what iCloud keeps (MontanaBackupCloud): the sealed container the engine writes, under the key the
// 24 words open, the words never in it. What differs is the door. iCloud names a copy by the account it belongs
// to; a node of one's own knows no account, so the phone names a shelf by a TOKEN only the words derive (HKDF of
// the entropy under one label, then one HMAC), and the node checks sha256(token) against the shelf's name and
// stores nothing of anybody: no seed, no key, no list. The token rides only inside TLS to the person's own
// machine, and it opens that one shelf and nothing else.
//
// The keeper's word is the only word (the rule of 23.09, tools/mt-cloud-truth-check.py): what the screen says
// about the node is what the node answered -- held, with its size and moment; none; refused; did not answer. The
// bytes this phone has SENT are shown as sending, this phone's own count, and become «held» only when the node has
// echoed the digest of the whole file.
enum MontanaHomeNode {
    static let hostKey = "mt.home.node"        // NOT-UI: the node's address, sealed under the device key, carried by a copy
    static let switchKey = "mt.home.node.on"   // NOT-UI: the daily copies switch, carried by a copy
    static let lastKey = "mt.home.node.at"     // NOT-UI: this device's own clock of its last copy to the node
    static let pinKey = "mt.home.node.pin"     // NOT-UI: the digest of the certificate the node made for itself, carried by a copy
    private static let keyLabel = Data("mt-vault-owner-v1".utf8)   // NOT-UI: the derivation's own label
    private static let tokenLabel = Data("mt-vault-token".utf8)    // NOT-UI: the token's own label
    static let tokenHeader = "X-Montana-Vault"                     // NOT-UI: the header the token rides in
    static let digestHeader = "X-Montana-SHA256"                   // NOT-UI: the header the file's digest rides in
    static let nameHeader = "X-Montana-Name"                       // NOT-UI: the header a copy's name comes back in

    static var host: String { MontanaLocalVault.getString(hostKey) ?? "" }
    static func setHost(_ h: String) {
        let clean = h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "/", with: "")   // NOT-UI: the address, bare
        MontanaLocalVault.setString(hostKey, clean)
        MontanaTrace.mark("home_node", "host set=" + (clean.isEmpty ? "0" : "1"))
    }
    /// THE NODE JOINS ON EVERY LEVEL (decision 606 (a), 04.11.2026): the copies ride while the person's switch is on, in an edition
    /// that carries one's own node (MTEdition.ownNode); taking one's own copy back asks nothing (takeBack).
    static var on: Bool { UserDefaults.standard.bool(forKey: switchKey) && MTEdition.ownNode }
    static func setOn(_ v: Bool) { UserDefaults.standard.set(v, forKey: switchKey) }
    static var last: Double { UserDefaults.standard.double(forKey: lastKey) }
    static func noteCopied(at t: Date) { UserDefaults.standard.set(t.timeIntervalSince1970, forKey: lastKey) }
    /// Due once a day, or when the node holds none of ours.
    static func due(holdsNone: Bool) -> Bool { holdsNone || Date().timeIntervalSince1970 - last >= 86_400 }

    /// The digest of the node's own certificate (a node put up by address, MontanaNodeSetup); empty for a named node.
    static var pin: String { MontanaLocalVault.getString(pinKey) ?? "" }
    static func setPin(_ p: String) { MontanaLocalVault.setString(pinKey, p) }
    /// A pinned node is spoken to straight, on the door's own TLS port; a named one through its front, under /pushwake.
    static func base(_ h: String) -> URL? {
        guard !h.isEmpty else { return nil }
        return URL(string: pin.isEmpty ? "https://" + h + "/pushwake" : "https://" + h + ":" + String(MontanaNodeSetup.tlsPort))
    }

    // ── the shelf's name ────────────────────────────────────────────────────────
    static func vaultKey(entropy: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data(), info: keyLabel, outputByteCount: 32)
    }
    static func token(_ k: SymmetricKey) -> Data { Data(HMAC<SHA256>.authenticationCode(for: tokenLabel, using: k)) }
    static func shelf(token t: Data) -> String { hex(Data(SHA256.hash(data: t))) }
    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
    /// This seed's token, or nil without a seed.
    static func tokenHex() -> String? {
        guard let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return hex(token(vaultKey(entropy: e)))
    }
    /// THE FROZEN VECTORS (computed outside this code: RFC 5869 HKDF-SHA-256, HMAC-SHA-256 and SHA-256 on the counting
    /// bytes 0x00..0x1f; tools/mt-home-node-check.py computes them again on every commit). A reversed root, a swapped
    /// label or a token hashed as hex text all fail them.
    static func keyKAT() -> Bool {
        let counting = Data((0..<32).map { UInt8($0) })
        let k = vaultKey(entropy: counting)
        let t = token(k)
        return hex(k.withUnsafeBytes { Data($0) }) == "aa75b0afc0c9b1b4e31a8fecf371ee72866865e7a77cf61f9f1f0ad457652097"
            && hex(t) == "0695b3db38b3c8525f8d8b7a270ae0bc5504c2d0d58634a937e52c2b9f7d2d28"
            && shelf(token: t) == "125ff41ffac97cae3ce9ba4ab20ae5586587f5c8960fee4055f6aaa8c219b49a"
    }
    /// SHA-256 of a file, a megabyte in hand at a time.
    static func digest(of url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var h = SHA256()
        while true {
            let more: Bool = autoreleasepool {
                guard let d = ((try? fh.read(upToCount: 1 << 20)) ?? nil), !d.isEmpty else { return false }
                h.update(data: d)
                return true
            }
            if !more { break }
        }
        return hex(Data(h.finalize()))
    }
}

#if !MONTANA_MESSENGER   // one's own node: its watch and its meters, reached by no path of Messenger (word 16428)
/// WHAT THE NODE ANSWERS, AND THIS PHONE'S OWN WORK ON THE WAY TO IT. One per process; the page observes it.
@MainActor final class HomeNodeWatch: ObservableObject {
    static let shared = HomeNodeWatch()
    struct Held: Equatable { let name: String; let date: Date; let bytes: Int }
    enum State: Equatable {
        case unknown                    // not asked yet
        case noHost                     // no address named
        case asking
        case none(free: Int)            // the node answered: it holds no copy of ours
        case held(Held, free: Int)      // the node answered: it holds this copy
        case refused(String)            // the node's own refusal, by its code
        case silent(String)             // the node did not answer, by the system's code
    }
    @Published private(set) var state: State = .unknown
    @Published private(set) var caps: [String] = []      // what the node names it can do (/health)
    @Published var sealing: Double? = nil                  // this phone seals a copy for the node: its own count
    @Published var sending: Double? = nil                  // bytes sent, this phone's own count
    @Published var fetching: Double? = nil                 // bytes come, this phone's own count
    @Published var restoring: Double? = nil                // frames filed, this phone's own count
    private var busy = false
    private var answered: [() -> Void] = []

    private static func session(cellular: Bool) -> URLSession {
        let c = URLSessionConfiguration.default
        c.allowsCellularAccess = cellular
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 6 * 3600
        return URLSession(configuration: c)
    }
    private static func request(_ path: String, token: String?) -> URLRequest? {
        guard let b = MontanaHomeNode.base(MontanaHomeNode.host), let u = URL(string: b.absoluteString + path) else { return nil }
        var r = URLRequest(url: u)
        if let token { r.setValue(token, forHTTPHeaderField: MontanaHomeNode.tokenHeader) }
        r.networkServiceType = .background
        return r
    }
    private static func code(_ e: Error) -> String { let ns = e as NSError; return ns.domain + " " + String(ns.code) }

    /// Runs `f` once the node has answered this ask -- at once when the state is already settled.
    func whenAnswered(_ f: @escaping () -> Void) {
        if case .asking = state { answered.append(f) } else { f() }
    }
    private func settle(_ s: State) {
        state = s
        let waiting = answered; answered = []
        waiting.forEach { $0() }
    }

    /// The node's word, asked afresh: what it can do, and what it holds of ours.
    func ask() {
        guard !MontanaHomeNode.host.isEmpty else { return settle(.noHost) }
        guard let tok = MontanaHomeNode.tokenHex(), let have = Self.request("/vault-have", token: tok),
              let health = Self.request("/health", token: nil) else { return settle(.noHost) }
        if case .asking = state { return }
        state = .asking
        Task {
            let s = Self.session(cellular: true)
            var r1 = have; r1.timeoutInterval = 15
            var r2 = health; r2.timeoutInterval = 15
            if let (d, resp) = try? await s.data(for: r2, delegate: MTNodeTrust()), (resp as? HTTPURLResponse)?.statusCode == 200,
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let c = j["caps"] as? [String: Any] {
                caps = c.filter { ($0.value as? Bool) == true }.map { $0.key }.sorted()
            }
            do {
                let (d, resp) = try await s.data(for: r1, delegate: MTNodeTrust())
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                guard code == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                    MontanaTrace.mark("home_node", "have refused code=" + String(code))
                    return settle(.refused(String(code)))
                }
                let free = (j["free"] as? Int) ?? 0
                let held = (j["held"] as? [[String: Any]]) ?? []
                MontanaTrace.markChanged("home_node", "holds n=" + String(held.count) + " free=" + String(free))
                if let top = held.first, let n = top["name"] as? String, let b = top["bytes"] as? Int {
                    let born = MontanaBackup.born(ofName: n) ?? Date(timeIntervalSince1970: TimeInterval((top["at"] as? Int) ?? 0))
                    settle(.held(Held(name: n, date: born, bytes: b), free: free))
                } else {
                    settle(.none(free: free))
                }
            } catch {
                MontanaTrace.mark("home_node", "no answer " + Self.code(error))
                settle(.silent(Self.code(error)))
            }
        }
    }

    /// A COPY TO THE NODE: sealed by the engine, sent whole, and held only on the node's echo of its digest.
    /// The daily road rides Wi-Fi alone; the person's own tap may ride the cellular network.
    func send(urgent: Bool, cellular: Bool, _ done: @escaping (Result<MontanaBackup.Tally, MontanaBackup.Refusal>) -> Void = { _ in }) {
        guard !busy, CloudCopy.shared.sealing == nil else { return done(.failure(.stopped)) }   // one copy is sealed at a time
        guard MTEdition.ownNode else {   // an edition without one's own node sends nothing to it (decision 531 (a))
            MontanaTrace.mark("home_node", "send refused: no node in this edition")
            return done(.failure(.stopped))
        }
        guard let tok = MontanaHomeNode.tokenHex() else { return done(.failure(.noSeed)) }
        busy = true
        sealing = 0
        CopyInventory.gather { [weak self] inv in
            let plan = CopyPlan.load()
            // THE COPY STAYS LIGHT (18.10): a file the node already keeps in pieces is not sealed into the copy a second time;
            // the book brings it back (MTHomeShelf).
            var scope = inv.scope(plan)
            scope.skipFiles.formUnion(MTHomeBook.shared.kept())
            MontanaBackup.create(scope: scope, urgent: urgent, progress: { f in self?.sealing = f }) { r in
                guard let self else { return }
                self.sealing = nil
                switch r {
                case .failure(let e): self.busy = false; done(.failure(e))
                case .success(let made): self.hand(made, token: tok, cellular: cellular, done)
                }
            }
        }
    }
    private func hand(_ made: MontanaBackup.Made, token: String, cellular: Bool,
                      _ done: @escaping (Result<MontanaBackup.Tally, MontanaBackup.Refusal>) -> Void) {
        let name = made.url.lastPathComponent
        sending = 0
        Task {
            let digest = await Task.detached { MontanaHomeNode.digest(of: made.url) }.value
            guard let digest, var req = Self.request("/vault-put?name=" + name + "&sha256=" + digest, token: token) else {
                sending = nil; busy = false
                MontanaBackup.discard(made)
                return done(.failure(.cloudRefused("digest")))
            }
            req.httpMethod = "PUT"
            req.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
            req.setValue(digest, forHTTPHeaderField: MontanaHomeNode.digestHeader)
            let meter = MTSentMeter { f in Task { @MainActor [weak self] in self?.sending = f } }
            do {
                let (d, resp) = try await Self.session(cellular: cellular).upload(for: req, fromFile: made.url, delegate: meter)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let j = (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
                sending = nil; busy = false
                MontanaBackup.discard(made)   // handed: the shelf copy leaves either way; the node's word decides what is held
                guard code == 200, (j["sha256"] as? String) == digest else {
                    MontanaTrace.mark("home_node", "put refused code=" + String(code))
                    ask()
                    return done(.failure(.cloudRefused("put " + String(code) + " " + ((j["error"] as? String) ?? ""))))
                }
                MontanaHomeNode.noteCopied(at: MontanaBackup.born(ofName: name) ?? Date())
                MontanaTrace.mark("home_node", "held bytes=" + String(made.tally.bytes) + " (the node echoed the digest)")
                ask()
                done(.success(made.tally))
            } catch {
                sending = nil; busy = false
                MontanaBackup.discard(made)
                MontanaTrace.mark("home_node", "put no answer " + Self.code(error))
                settle(.silent(Self.code(error)))
                done(.failure(.cloudRefused("put " + Self.code(error))))
            }
        }
    }

    /// THE DAILY ROAD (launch and the switch): the node is asked first; a copy is sealed and sent only when one is
    /// due -- the node holds none of ours, or this device's last copy is a day old -- and rides Wi-Fi alone.
    func tickSoon() {
        guard MontanaHomeNode.on, !MontanaHomeNode.host.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.tick() }
    }
    func tick() {
        guard MontanaHomeNode.on, !MontanaHomeNode.host.isEmpty, !busy else { return }
        ask()
        whenAnswered { [weak self] in
            guard let self else { return }
            let none: Bool
            switch self.state {
            case .none: none = true
            case .held: none = false
            default: return
            }
            guard MontanaHomeNode.due(holdsNone: none) else { return MontanaTrace.mark("home_node", "tick skipped: not due") }
            self.send(urgent: false, cellular: false)
        }
    }

    /// THE NEWEST COPY THE NODE HOLDS comes back to the shelf and is laid into this device by the engine -- it merges,
    /// it never erases (MontanaBackup.restore). The bar measures bytes come, then frames filed.
    func takeBack(_ done: @escaping (Result<MontanaBackup.Tally, MontanaBackup.Refusal>) -> Void) {
        guard !busy, let tok = MontanaHomeNode.tokenHex(), let req = Self.request("/vault-get", token: tok),
              let shelf = try? MontanaBackup.shelf() else { return done(.failure(.stopped)) }
        busy = true
        fetching = 0
        Task {
            let landing = shelf.appendingPathComponent(UUID().uuidString + ".part")   // NOT-UI: the unfinished name
            let meter = MTComeMeter(landing: landing) { f in Task { @MainActor [weak self] in self?.fetching = f } }
            do {
                let (tmp, resp) = try await Self.session(cellular: true).download(for: req, delegate: meter)
                let http = resp as? HTTPURLResponse
                let code = http?.statusCode ?? -1
                let got = meter.landed ?? tmp
                guard code == 200, let name = http?.value(forHTTPHeaderField: MontanaHomeNode.nameHeader),
                      MontanaBackup.born(ofName: name) != nil else {
                    fetching = nil; busy = false
                    MontanaBackup.discard(MontanaBackup.Made(url: got, tally: MontanaBackup.Tally()))
                    MontanaTrace.mark("home_node", "get refused code=" + String(code))
                    return done(.failure(code == 404 ? .empty : .cloudRefused("get " + String(code))))
                }
                let dst = shelf.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: dst.path) { MontanaBackup.discard(MontanaBackup.Made(url: dst, tally: MontanaBackup.Tally())) }
                try FileManager.default.moveItem(at: got, to: dst)
                fetching = nil
                restoring = 0
                MontanaTrace.mark("home_node", "fetched " + name)
                MontanaBackup.restore(from: dst, progress: { [weak self] f in self?.restoring = f }) { [weak self] r in
                    self?.restoring = nil; self?.busy = false
                    MontanaBackup.discard(MontanaBackup.Made(url: dst, tally: MontanaBackup.Tally()))
                    if case .success = r { MontanaHomeNode.noteCopied(at: MontanaBackup.born(ofName: name) ?? Date()) }
                    done(r)
                }
            } catch {
                fetching = nil; busy = false
                MontanaTrace.mark("home_node", "get no answer " + Self.code(error))
                done(.failure(.cloudRefused("get " + Self.code(error))))
            }
        }
    }
}

/// The bytes sent, as the system counts them on the way out.
final class MTSentMeter: MTNodeTrust {
    private let say: (Double) -> Void
    init(_ say: @escaping (Double) -> Void) { self.say = say }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        say(Double(totalBytesSent) / Double(max(1, totalBytesExpectedToSend)))
    }
}
/// The bytes come, as the system counts them on the way in; the finished file is moved to its landing in the
/// delegate's own moment, before the system takes the temporary one away.
final class MTComeMeter: MTNodeTrust, URLSessionDownloadDelegate {
    private let say: (Double) -> Void
    private let landing: URL
    private(set) var landed: URL? = nil
    init(landing: URL, _ say: @escaping (Double) -> Void) { self.landing = landing; self.say = say }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        say(Double(totalBytesWritten) / Double(max(1, totalBytesExpectedToWrite)))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if (try? FileManager.default.moveItem(at: location, to: landing)) != nil { landed = landing }
    }
}

#endif

/// EVERY REFUSAL IS SPOKEN, BY ONE READING (28.09): the node's page and the first screen speak the same words, and the
/// keeper's own refusals carry the keeper's name -- the node's or iCloud's.
extension MontanaBackup.Refusal {
    enum Keeper { case node, cloud }
    func spoken(by keeper: Keeper) -> LocalizedStringKey {
        switch self {
        case .empty: return keeper == .node ? "Your node holds no copy yet." : "iCloud holds no copy of this identity yet."
        case .cloudRefused(let why): return keeper == .node ? "Your node did not take the copy: \(why)" : "iCloud refused: \(why)"
        case .stopped: return "Stopped."
        case .noSeed: return "This device holds no identity yet. Enter your 24 words first, then restore."
        case .noVault: return "The storage of this device did not open just now. Try again in a moment."
        case .noEntropy: return "The core refused to draw randomness. Try again in a moment."
        case .noSpace: return "The disk has no room left. Free some space and try again."
        case .diskRefused(let why): return "The disk refused: \(why)"
        case .notOurs: return "This file is not a Montana backup."
        case .version: return "This backup was made by a newer version of Montana."
        case .wrongWords: return "These 24 words do not open this backup: it belongs to another phrase."
        case .unopened: return "These 24 words do not open this file: it is a backup of another phrase, or not a Montana backup at all."
        case .torn: return "This backup is cut short or damaged. Whatever could be read has been filed."
        }
    }
}


// ── THE FILES ON YOUR NODE ────────────────────────────────────────────────────────────────────────────────────────
// The author's word 18.10.2026 17:1x UTC: «make my Lauterbourg node my personal storage for T1, so I clear the cache in the
// app and it weighs nothing, and even after deleting the app I come back and load everything from my own node».
//
// Every file of this phone's media store is sealed by this phone under a key of its own, cut into the pieces the doors
// already carry, and laid on the shelf of the words' token beside the copies (/home-put). Which file is which pieces is THE
// BOOK; it lies on the node as well, sealed under a key the words alone derive and named by a name the words alone derive --
// so the 24 words bring the book back, and the book every file. The node holds what it says it holds (/home-have): a file
// leaves this phone only when the node has just named every one of its pieces, and comes back at a look or a tap.

/// The node's rooms for the pieces, and the keys the words derive for them.
enum MTHomeShelf {
    private static let bookKeyLabel = Data("mt-home-book-key".utf8)     // NOT-UI: the derivation's own label
    private static let bookNameLabel = Data("mt-home-book-name".utf8)   // NOT-UI: the book's name on the shelf
    private static let fileKeyLabel = Data("mt-home-file-key".utf8)     // NOT-UI: a file's own key
    static let chunk = MontanaMedia.chunkSize

    /// Files go to the node while its copies do (the switch); taking one's own files back asks nothing.
    static var keeping: Bool { MontanaHomeNode.on && bringing }
    static var bringing: Bool { !MontanaHomeNode.host.isEmpty && entropy() != nil }
    static func entropy() -> Data? {
        guard let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return e
    }
    static func bookKey(entropy e: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: e), salt: Data(), info: bookKeyLabel, outputByteCount: 32)
    }
    static func bookName(entropy e: Data) -> String {
        MontanaHomeNode.hex(Data(HMAC<SHA256>.authenticationCode(for: bookNameLabel, using: bookKey(entropy: e))))
    }
    /// A file's key, from the words and the file's name: the same file sealed again gives the same pieces, so a pass cut short
    /// goes on from what the node already holds.
    static func fileKey(entropy e: Data, name: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: fileKeyLabel + Data(name.utf8), using: bookKey(entropy: e)))
    }
    private static func raw(_ k: SymmetricKey) -> [UInt8] { k.withUnsafeBytes { [UInt8]($0) } }
    /// THE FROZEN VECTORS (computed outside this code: RFC 5869 HKDF-SHA-256 and HMAC-SHA-256 on the counting bytes 0x00..0x1f and
    /// the name img_a1.jpg; tools/mt-home-node-check.py computes them again on every commit). A drifted label loses the book of
    /// every phone before it: the shelf's label in place of the book's, the name before its label, or img_1a.jpg all fail them.
    static func keyKAT() -> Bool {
        let counting = Data((0..<32).map { UInt8($0) })
        return MontanaHomeNode.hex(Data(raw(bookKey(entropy: counting)))) == "9bece1c15302a5154b382514015c9d888be32876f01e00963cecdaf7156bb992"
            && bookName(entropy: counting) == "5d536d3dc037f357cc0430d317072ac117cc72efaafcae76d4a9e923edbe28a1"
            && MontanaHomeNode.hex(fileKey(entropy: counting, name: "img_a1.jpg")) == "0362e58cd7c26c3fd0735391a2b64c012744647e42bacbe6745d1373d6775901"   // NOT-UI: a vector's name
    }

    // ── the wire ──
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()
    private static func post(_ path: String, _ body: [String: Any]) async -> (Int, [String: Any])? {
        guard let tok = MontanaHomeNode.tokenHex(), let b = MontanaHomeNode.base(MontanaHomeNode.host),
              let u = URL(string: b.absoluteString + path), let d = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(tok, forHTTPHeaderField: MontanaHomeNode.tokenHeader)
        r.httpBody = d
        guard let (data, resp) = try? await session.data(for: r, delegate: MTNodeTrust()) else { return nil }
        return ((resp as? HTTPURLResponse)?.statusCode ?? -1, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }
    static func get(_ bid: String) async -> Data? {
        guard let (code, j) = await post("/home-get", ["bid": bid]), code == 200, let s = j["data"] as? String else { return nil }
        return Data(base64Encoded: s)
    }
    /// The node's own word on which of these pieces it holds; nil when it did not answer.
    static func have(_ bids: [String]) async -> Set<String>? {
        var out = Set<String>()
        var at = 0
        while at < bids.count {
            let part = Array(bids[at..<min(at + 4096, bids.count)])
            guard let (code, j) = await post("/home-have", ["bids": part]), code == 200, let h = j["have"] as? [String] else { return nil }
            out.formUnion(h)
            at += part.count
        }
        return out
    }
    /// True only on the node's «held».
    static func put(_ bid: String, _ sealed: Data, over: Bool = false) async -> Bool {
        guard let (code, j) = await post("/home-put", ["bid": bid, "data": sealed.base64EncodedString(), "over": over]) else { return false }
        if code != 200 { MontanaTrace.markFolded("home_put", "refused code=\(code) \((j["error"] as? String) ?? "")", window: 60) }
        return code == 200 && (j["held"] as? Bool) == true
    }

    // ── the book on the node ──
    static func putBook(entropy e: Data) async {
        guard let plain = MTHomeBook.shared.json(), let sealed = MTNodeWire.sealBlob(key: raw(bookKey(entropy: e)), plain) else { return }
        let ok = await put(bookName(entropy: e), sealed, over: true)
        MontanaTrace.mark("home_book", "put files=\(MTHomeBook.shared.count) bytes=\(sealed.count) held=\(ok ? 1 : 0)")
    }
    static func takeBook(entropy e: Data) async {
        guard let sealed = await get(bookName(entropy: e)), let plain = MontanaDirect.open(key: raw(bookKey(entropy: e)), sealed) else {
            MontanaTrace.mark("home_book", "none on your node")
            return
        }
        let n = MTHomeBook.shared.merge(plain)
        MontanaTrace.mark("home_book", "taken files=\(n)")
    }

    // ── a file to the node ──
    private static func piece(_ url: URL, _ i: Int, _ size: Int, _ key: Data) -> MontanaMedia.SealedChunk? {
        autoreleasepool {
            guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? h.close() }
            let len = min(chunk, size - i * chunk)
            guard (try? h.seek(toOffset: UInt64(i * chunk))) != nil, let d = try? h.read(upToCount: len), d.count == len else { return nil }
            return MontanaMedia.sealPiece(d, blobKey: key, index: i)
        }
    }
    /// Every piece's name first (each sealed once to learn it), the node's word on them, then what it lacks, three at a time.
    static func keepFile(_ name: String, size: Int, entropy e: Data) async -> MTHomeBook.Entry? {
        let key = fileKey(entropy: e, name: name), url = MontanaMediaStore.url(name)
        let count = (size + chunk - 1) / chunk
        guard 0 < count else { return nil }
        var bids: [String] = []
        for i in 0..<count {
            guard let sc = piece(url, i, size, key) else { return nil }
            bids.append(sc.blobId)
        }
        guard let held = await have(bids) else { return nil }
        let missing = (0..<count).filter { !held.contains(bids[$0]) }
        let ok = await withTaskGroup(of: Bool.self) { g -> Bool in
            var next = 0, good = true
            func launch() {
                let i = missing[next]; next += 1
                g.addTask {
                    guard let sc = piece(url, i, size, key), sc.blobId == bids[i] else { return false }   // the file changed under us
                    return await put(sc.blobId, sc.sealed)
                }
            }
            while next < min(3, missing.count) { launch() }
            for await r in g {
                if !r { good = false; g.cancelAll(); break }
                if next < missing.count { launch() }
            }
            return good
        }
        return ok ? MTHomeBook.Entry(z: size, p: bids, at: Date().timeIntervalSince1970) : nil
    }

    /// THE PASS: every file of the store the book does not name at its size goes to the node; the book follows every
    /// twenty-five files and at the end. The answer is the node's word on the whole book.
    static func keepPass(progress: @escaping @Sendable (Double) -> Void) async -> MTHomeKeep.Word {
        guard let e = entropy() else { return .silent("seed") }
        let book = MTHomeBook.shared
        book.ensure()
        if book.count == 0 { await takeBook(entropy: e) }
        let fm = FileManager.default
        var todo: [(String, Int)] = []
        for n in MontanaMediaStore.names() where !MontanaMediaStore.newborn(n) && !n.hasSuffix(MTStreamLoader.partTail) && !n.hasSuffix(MTStreamLoader.ledgerTail) {
            guard let size = (try? fm.attributesOfItem(atPath: MontanaMediaStore.url(n).path))?[.size] as? Int, 0 < size else { continue }
            if book.entry(n)?.z == size { continue }
            todo.append((n, size))
        }
        let total = max(1, todo.reduce(0) { $0 + $1.1 })
        var done = 0, laid = 0, since = 0, refused = 0
        MontanaTrace.mark("home_keep", "begin files=\(todo.count) bytes=\(total) kept=\(book.count)")
        for (n, size) in todo {
            if Task.isCancelled { break }
            if let entry = await keepFile(n, size: size, entropy: e) {
                book.set(n, entry); laid += 1; since += 1
            } else {
                refused += 1
                if 3 <= refused, laid == 0 { break }   // the node does not take anything now: the next pass goes on
            }
            done += size
            progress(Double(done) / Double(total))
            if 25 <= since { book.save(); await putBook(entropy: e); since = 0 }
        }
        if 0 < since { book.save(); await putBook(entropy: e) }
        MontanaTrace.mark("home_keep", "end laid=\(laid) refused=\(refused) kept=\(book.count)")
        return await word()
    }
    /// What the node holds of the book, in its own word, asked now.
    static func word() async -> MTHomeKeep.Word {
        let all = MTHomeBook.shared.all()
        guard let held = await have(all.values.flatMap { $0.p }) else { return .silent("no answer") }
        let whole = all.filter { $0.value.p.allSatisfy(held.contains) }
        return .held(files: whole.count, bytes: whole.values.reduce(0) { $0 + $1.z }, at: Date())
    }

    /// THE CACHE CLEARED: a file leaves this phone only when the node has just named every one of its pieces.
    static func clearPass() async -> (files: Int, bytes: Int)? {
        guard let r = await removeHeld(nil) else { return nil }
        return (r.gone.count, r.bytes)
    }
    /// A FILE LEAVES THIS PHONE ONLY ON THE NODE'S WORD ASKED NOW, whoever asks (18.10.2026, Agent 93, the author's word «everything I
    /// delete is only the local cache, and my node holds it»): the hand's clearing, and the files the person chose on a kind's page
    /// (CopyFilesPage) -- `only` names them, nil takes every file. A file the node does not hold whole stays; no letter is touched.
    static func removeHeld(_ only: Set<String>?) async -> (gone: Set<String>, bytes: Int)? {
        MTHomeBook.shared.ensure()
        let all = MTHomeBook.shared.all(), here = MontanaMediaStore.names(), inHand = MontanaMediaStore.held
        let fm = FileManager.default
        let candidates = all.filter { n, e in
            (only?.contains(n) ?? true) && here.contains(n) && !inHand.contains(n) && !MontanaMediaStore.newborn(n)
                && ((try? fm.attributesOfItem(atPath: MontanaMediaStore.url(n).path))?[.size] as? Int) == e.z
        }
        guard let held = await have(candidates.values.flatMap { e in e.p }) else { return nil }
        let gone = candidates.filter { kv in kv.value.p.allSatisfy(held.contains) }
        MontanaMediaStore.remove(Array(gone.keys))
        let bytes = gone.values.reduce(0) { a, e in a + e.z }
        MontanaTrace.mark("home_clear", "files=\(gone.count) bytes=\(bytes) of=\(candidates.count) kept=\(all.count) chosen=\(only?.count ?? -1)")
        return (Set(gone.keys), bytes)
    }

    /// THE CACHE KEEPS ITSELF (the reference's «keep media» and «maximum cache size»): a file the node holds and nobody opened
    /// within the person's term leaves this phone, and past the person's ceiling the files opened longest ago leave first -- each
    /// only on the node's word asked now, as the hand's clearing.
    static func trimPass(days: Int, limitGB: Int) async -> (files: Int, bytes: Int)? {
        guard 0 < days + limitGB else { return (0, 0) }
        MTHomeBook.shared.ensure()
        let all = MTHomeBook.shared.all(), inHand = MontanaMediaStore.held
        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .contentModificationDateKey, .fileSizeKey]
        var files: [(name: String, at: Date, size: Int, kept: Bool)] = []
        for n in MontanaMediaStore.names() where !inHand.contains(n) && !MontanaMediaStore.newborn(n) {
            guard let v = try? MontanaMediaStore.url(n).resourceValues(forKeys: keys), let size = v.fileSize else { continue }
            files.append((n, v.contentAccessDate ?? v.contentModificationDate ?? Date(), size, all[n]?.z == size))
        }
        let edge = Date().addingTimeInterval(-Double(days) * 86_400)
        var going = Set(files.filter { f in f.kept && 0 < days && f.at < edge }.map { f in f.name })
        if 0 < limitGB {
            var total = files.reduce(0) { a, f in a + f.size } - files.filter { f in going.contains(f.name) }.reduce(0) { a, f in a + f.size }
            let ceiling = limitGB * 1_073_741_824
            for f in files.sorted(by: { a, b in a.at < b.at }) where ceiling < total {
                guard f.kept, !going.contains(f.name) else { continue }
                going.insert(f.name); total -= f.size
            }
        }
        guard !going.isEmpty else { return (0, 0) }
        guard let held = await have(going.compactMap { n in all[n]?.p }.flatMap { p in p }) else { return nil }
        let gone = going.filter { n in all[n]?.p.allSatisfy(held.contains) == true }
        MontanaMediaStore.remove(Array(gone))
        let bytes = gone.reduce(0) { a, n in a + (all[n]?.z ?? 0) }
        MontanaTrace.mark("home_trim", "files=\(gone.count) bytes=\(bytes) days=\(days) limit_gb=\(limitGB)")
        return (gone.count, bytes)
    }

    /// A file back from the node into the store, by the one road of every piece (MTCargoLane, MontanaWakePush.bringChunk).
    static func bring(_ name: String, _ e: MTHomeBook.Entry) async -> Bool {
        guard let en = entropy() else { return false }
        let manifest = manifest(e)
        guard case .complete = await MontanaWakePush.fetchChunks(manifest, need: .look) else {
            MontanaTrace.mark("home_bring", "FAIL name=\(String(name.prefix(20))) -- your node did not give every piece")
            return false
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("home_" + UUID().uuidString)
        guard await MontanaMedia.downloadToFile(manifest: manifest, blobKey: fileKey(entropy: en, name: name), totalSize: e.z, dest: tmp),
              MontanaMediaStore.adopt(from: tmp, name: name) else {
            try? FileManager.default.removeItem(at: tmp)
            MontanaTrace.mark("home_bring", "FAIL name=\(String(name.prefix(20))) -- the pieces did not open")
            return false
        }
        MontanaBlobStore.drop(e.p)
        MontanaTrace.mark("home_bring", "name=\(String(name.prefix(20))) bytes=\(e.z)")
        return true
    }
    static func manifest(_ e: MTHomeBook.Entry) -> [[String: Any]] {
        e.p.enumerated().map { ["bid": $0.element, "cs": min(chunk, e.z - $0.offset * chunk)] }
    }
    /// A video or a track of the book plays from its first pieces, as a letter's does (MTStreamLoader).
    static func streamSource(_ name: String) -> MTStreamSource? {
        guard let e = MTHomeBook.shared.entry(name), let en = entropy() else { return nil }
        let pieces = e.p.enumerated().map { MTPieceRef(bid: $0.element, cs: min(chunk, e.z - $0.offset * chunk)) }
        return MTStreamSource(name: name, ext: (name as NSString).pathExtension, size: e.z, key: fileKey(entropy: en, name: name),
                              chunks: pieces, folder: MontanaMediaStore.dir)
    }
}

/// THE BOOK: each file this phone gave its node, by name -- its size, its pieces in order, and when the node named them all.
/// Its copy on this phone is a cache of the one on the node (MTHomeShelf.putBook): the words bring it back. ONE BOOK PER
/// PERSON: its file is named by the words, so a second person seated on this phone never reads the first one's book as theirs.
final class MTHomeBook: @unchecked Sendable {
    static let shared = MTHomeBook()
    struct Entry: Codable, Equatable { var z: Int; var p: [String]; var at: Double }
    private let lock = NSLock()
    private var files: [String: Entry] = [:]
    private var bids = Set<String>()
    private var tag = ""   // the person whose book is in hand
    private static let dir: URL = {
        let fm = FileManager.default
        var d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana", isDirectory: true).appendingPathComponent("HomeBook", isDirectory: true)
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        if (try? d.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true {
            var rv = URLResourceValues(); rv.isExcludedFromBackup = true
            try? d.setResourceValues(rv)
        }
        return d
    }()
    private static func file(_ tag: String) -> URL { dir.appendingPathComponent("book-" + tag + ".json") }   // NOT-UI: the file's own name
    private static func person() -> String { MTHomeShelf.entropy().map { String(MTHomeShelf.bookName(entropy: $0).prefix(16)) } ?? "" }
    private init() { ensure() }
    /// The book of the person seated now: read again when the seat changed.
    func ensure() {
        let t = Self.person()
        lock.lock(); let same = t == tag; lock.unlock()   // LOCK-OK: a word in memory
        guard !same else { return }
        var f: [String: Entry] = [:]
        if !t.isEmpty, let d = try? Data(contentsOf: Self.file(t)), let read = try? JSONDecoder().decode([String: Entry].self, from: d) { f = read }
        lock.lock(); tag = t; lock.unlock()   // LOCK-OK: a word in memory
        lay(f)
    }
    private func lay(_ f: [String: Entry]) {
        lock.lock()   // LOCK-OK: two values in memory
        files = f
        bids = Set(f.values.flatMap { $0.p })
        lock.unlock()
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return files.count }   // LOCK-OK: a word in memory
    func holds(_ bid: String) -> Bool { lock.lock(); defer { lock.unlock() }; return bids.contains(bid) }   // LOCK-OK: a word in memory
    func entry(_ name: String) -> Entry? { lock.lock(); defer { lock.unlock() }; return files[name] }   // LOCK-OK: a word in memory
    func all() -> [String: Entry] { lock.lock(); defer { lock.unlock() }; return files }   // LOCK-OK: a word in memory
    /// The names whose every piece the node named: a copy for the node leaves them out (HomeNodeWatch.send).
    func kept() -> Set<String> { lock.lock(); defer { lock.unlock() }; return Set(files.filter { 0 < $0.value.at }.keys) }   // LOCK-OK: a word in memory
    func set(_ name: String, _ e: Entry) {
        lock.lock()   // LOCK-OK: two values in memory
        files[name] = e
        bids.formUnion(e.p)
        lock.unlock()
    }
    func json() -> Data? { try? JSONEncoder().encode(all()) }
    /// The node's book joins this phone's: what either names stays named.
    @discardableResult func merge(_ plain: Data) -> Int {
        guard let f = try? JSONDecoder().decode([String: Entry].self, from: plain) else { return 0 }
        var mine = all()
        for (n, e) in f where mine[n] == nil { mine[n] = e }
        lay(mine)
        save()
        return f.count
    }
    func save() {
        lock.lock(); let t = tag; lock.unlock()   // LOCK-OK: a word in memory
        guard !t.isEmpty, let d = json() else { return }
        MTDiskDoor.write(d, to: Self.file(t), "home-book", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// THE KEEPER ON THIS PHONE: the pass to the node, the cache cleared, a file brought back. One per process; pages observe it.
@MainActor final class MTHomeKeep: ObservableObject {
    static let shared = MTHomeKeep()
    enum Word: Equatable {
        case unknown
        case held(files: Int, bytes: Int, at: Date)   // the node's own word on the book
        case silent(String)
    }
    @Published private(set) var sending: Double? = nil   // this phone's own count of the pass
    @Published private(set) var word: Word = .unknown
    @Published private(set) var clearing = false
    nonisolated static let keepDaysKey = "home.keep.days"     // NOT-UI: the person's term for a file nobody opened; 0 -- for ever
    nonisolated static let limitKey = "home.cache.limit"      // NOT-UI: the person's ceiling of the cache in gigabytes; 0 -- none
    nonisolated static var keepDays: Int { UserDefaults.standard.integer(forKey: keepDaysKey) }
    nonisolated static var limitGB: Int { UserDefaults.standard.integer(forKey: limitKey) }
    /// The person moved the term or the ceiling: the cache keeps itself now, not at the next pass.
    func trim() {
        guard MTHomeShelf.bringing else { return }
        Task.detached(priority: .utility) {
            _ = await MTHomeShelf.trimPass(days: MTHomeKeep.keepDays, limitGB: MTHomeKeep.limitGB)
            await MainActor.run { ChatStore.live?.objectWillChange.send() }
        }
    }
    private var running = false
    private var bringing = Set<String>()

    /// At launch: the node's book first on a phone that has none, then a pass over Wi-Fi when the copies ride.
    func tickSoon() {
        guard MTHomeShelf.bringing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self else { return }
            MTHomeBook.shared.ensure()
            if MTHomeShelf.keeping { self.keep(cellular: false) }
            else if MTHomeBook.shared.count == 0, let e = MTHomeShelf.entropy() { Task { await MTHomeShelf.takeBook(entropy: e) } }
        }
    }
    func keep(cellular: Bool) {
        guard MTHomeShelf.keeping, !running else { return }
        if !cellular, MontanaNet.shared.isCellular { return MontanaTrace.mark("home_keep", "waits for Wi-Fi") }
        running = true
        sending = 0
        Task.detached(priority: .utility) {
            let w = await MTHomeShelf.keepPass { f in Task { @MainActor in MTHomeKeep.shared.sending = f } }
            _ = await MTHomeShelf.trimPass(days: MTHomeKeep.keepDays, limitGB: MTHomeKeep.limitGB)   // the cache keeps itself after the pass
            await MainActor.run {
                let me = MTHomeKeep.shared
                me.running = false; me.sending = nil; me.word = w
            }
        }
    }
    func ask() {
        guard MTHomeShelf.bringing, MTHomeBook.shared.count != 0 else { return }
        Task.detached(priority: .utility) {
            let w = await MTHomeShelf.word()
            await MainActor.run { MTHomeKeep.shared.word = w }
        }
    }
    func clear(_ done: @escaping ((files: Int, bytes: Int)?) -> Void) {
        guard MTHomeShelf.bringing, !clearing else { return done(nil) }
        clearing = true
        Task.detached(priority: .userInitiated) {
            let r = await MTHomeShelf.clearPass()
            await MainActor.run {
                MTHomeKeep.shared.clearing = false
                ChatStore.live?.objectWillChange.send()
                done(r)
            }
        }
    }
    /// A LOOK BRINGS IT BACK (as the reference does): a file the book names and this phone no longer holds comes from the
    /// node when its bubble stands on the screen and the attachments of this network download by themselves; a tap always.
    nonisolated static func want(_ name: String) { Task { @MainActor in shared.bring(name, force: false) } }
    func bring(_ name: String, force: Bool) {
        guard !bringing.contains(name), !MontanaMediaStore.exists(name), let e = MTHomeBook.shared.entry(name), MTHomeShelf.bringing else { return }
        if !force, !MontanaNet.shared.autoDownloadAllowed { return }
        bringing.insert(name)
        Task.detached(priority: .userInitiated) {
            let ok = await MTHomeShelf.bring(name, e)
            await MainActor.run {
                MTHomeKeep.shared.bringing.remove(name)
                guard ok, let store = ChatStore.live else { return }
                let chat = store.messages.first { _, rows in
                    rows.contains { m in [m.imageFile, m.videoFile, m.audioFile, m.docFile].contains(name) }
                }?.key
                if let chat { store.fillMedia(chat, name: name) } else { store.objectWillChange.send() }
            }
        }
    }
}
