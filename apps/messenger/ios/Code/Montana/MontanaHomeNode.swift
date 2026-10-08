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
    static var on: Bool { UserDefaults.standard.bool(forKey: switchKey) }
    static func setOn(_ v: Bool) { UserDefaults.standard.set(v, forKey: switchKey) }
    static var last: Double { UserDefaults.standard.double(forKey: lastKey) }
    static func noteCopied(at t: Date) { UserDefaults.standard.set(t.timeIntervalSince1970, forKey: lastKey) }
    /// Due once a day, or when the node holds none of ours.
    static func due(holdsNone: Bool) -> Bool { holdsNone || Date().timeIntervalSince1970 - last >= 86_400 }

    /// The digest of the node's own certificate (a node put up by address, MontanaNodeSetup); empty for a named node.
    static var pin: String { MontanaLocalVault.getString(pinKey) ?? "" }
    static func setPin(_ p: String) { MontanaLocalVault.setString(pinKey, p) }
    /// A NODE IS REACHED OVER THE INTERNET (the author's word 08.10.2026: no local network in this app): an address of a local
    /// network -- private, link-local, an mDNS name -- is never dialled, by the copies or by the set-up.
    static func onLocalNetwork(_ h: String) -> Bool {
        let parts = h.split(separator: ":")
        let bare = h.hasPrefix("[") ? String(h.dropFirst().prefix(while: { $0 != "]" })) : (parts.count == 2 ? String(parts[0]) : h)
        return bare.hasSuffix(".local") || !MontanaTransport.isGlobalIP(bare)
    }
    /// A pinned node is spoken to straight, on the door's own TLS port; a named one through its front, under /pushwake.
    static func base(_ h: String) -> URL? {
        guard !h.isEmpty, !onLocalNetwork(h) else { return nil }
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
        guard let tok = MontanaHomeNode.tokenHex() else { return done(.failure(.noSeed)) }
        busy = true
        sealing = 0
        CopyInventory.gather { [weak self] inv in
            let plan = CopyPlan.load()
            MontanaBackup.create(scope: inv.scope(plan), urgent: urgent, progress: { f in self?.sealing = f }) { r in
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

/// THE PAGE: the address, the node's word, the two acts, and what the node names it can do. The platform's own list,
/// field and switch on the glass rows, as every settings page stands (the author's word 25.09).
struct HomeNodeView: View {
    @ObservedObject private var node = HomeNodeWatch.shared
    @State private var host = MontanaHomeNode.host
    @State private var on = MontanaHomeNode.on
    @State private var word: LocalizedStringKey? = nil
    @FocusState private var editing: Bool
    @State private var login = "root"                  // NOT-UI: the machine's own default login
    @State private var password = ""
    @State private var settingUp = false

    private struct Cap: Identifiable { let id: String; let word: LocalizedStringKey; let glyph: String }
    private static let capWords: [Cap] = [
        Cap(id: "vault", word: "Copies of the whole phone", glyph: "externaldrive.fill"),
        Cap(id: "box", word: "Letters for sleeping phones", glyph: "tray.full.fill"),
        Cap(id: "blob", word: "Attachments in transit", glyph: "paperclip"),
        Cap(id: "signal", word: "Call signalling", glyph: "phone.fill"),
        Cap(id: "turn", word: "Call relay", glyph: "phone.arrow.up.right"),
        Cap(id: "diag", word: "Diaries", glyph: "doc.text.fill"),
        Cap(id: "stun", word: "Reflector", glyph: "dot.radiowaves.left.and.right"),
        Cap(id: "notify", word: "Wakes", glyph: "bell.fill"),
        Cap(id: "gif", word: "Moving pictures", glyph: "photo.on.rectangle"),
        Cap(id: "name", word: "Names", glyph: "at")]

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 29, height: 29).background(Color.gray).clipShape(RoundedRectangle(cornerRadius: 7))
                    TextField("Address", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .focused($editing).onSubmit { commit() }
                        .foregroundColor(.white)
                }
                stateRow
                if settingUp {
                    HStack { Text("Setting up your node…").foregroundColor(.white); Spacer(); ProgressView() }
                }
                if let f = node.sealing { bar("Sealing the copy for your node", f) }
                if let f = node.sending { bar("Sending to your node", f) }
                if let f = node.fetching { bar("Downloading from your node", f) }
                if let f = node.restoring { bar("Restoring from your node", f) }
            } header: {
                Text("YOUR NODE")
            } footer: {
                Text("Your node is a machine you own: your backup, your space. Once a day over Wi-Fi, while Montana is open, a copy of the whole app goes there, sealed with the key your 24 words open; the words are not in it. On a new phone, enter the address and the words, and the copy comes back.")
            }
            .listRowBackground(MTGlassRowPlate())
            // A MACHINE PUT UP FROM HERE (the author's word 28.09: by the root login, the password and the address): the door
            // of Montana goes onto it over its own SSH door, and the digest of the certificate it makes for itself is kept.
            Section {
                HStack(spacing: 12) {
                    settingsToggleLabel("Login", "person.fill", .gray)
                    TextField("Login", text: $login).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing).foregroundColor(.white)
                }
                HStack(spacing: 12) {
                    settingsToggleLabel("Password", "key.fill", .gray)
                    SecureField("Password", text: $password).multilineTextAlignment(.trailing).foregroundColor(.white)
                }
                Button { setUp() } label: {
                    HStack { settingsToggleLabel("Set up your node", "wrench.and.screwdriver.fill", .blue); Spacer() }.contentShape(Rectangle())
                }
                .disabled(host.isEmpty || password.isEmpty || settingUp)
            } footer: {
                Text("Enter the address of a machine you own, its login and password: Montana puts its door on it and keeps only the digest of the certificate the machine makes for itself. The password is used once and kept nowhere.")
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                Toggle(isOn: switchBinding) { settingsToggleLabel("Copies to your node", "arrow.triangle.2.circlepath", .green) }
                    .disabled(host.isEmpty)
                Button { sendNow() } label: {
                    HStack { settingsToggleLabel("Send a copy now", "arrow.up.doc.fill", .green); Spacer() }.contentShape(Rectangle())
                }
                .disabled(host.isEmpty || node.sealing != nil || node.sending != nil)
                Button { restore() } label: {
                    HStack { settingsToggleLabel("Restore from your node", "arrow.down.doc.fill", .orange); Spacer() }.contentShape(Rectangle())
                }
                .disabled(!holds || node.fetching != nil || node.restoring != nil)
            }
            .listRowBackground(MTGlassRowPlate())
            if !node.caps.isEmpty {
                Section {
                    ForEach(Self.capWords) { c in
                        HStack(spacing: 12) {
                            settingsToggleLabel(c.word, c.glyph, node.caps.contains(c.id) ? .blue : .gray)
                            Spacer()
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                                .foregroundColor(.accentColor).opacity(node.caps.contains(c.id) ? 1 : 0)
                        }
                    }
                } header: {
                    Text("WHAT YOUR NODE OFFERS")
                }
                .listRowBackground(MTGlassRowPlate())
            }
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as every page wears it (26.09)
        .navigationTitle("Your node")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { node.ask() }
        .onChange(of: editing) { _, now in if !now { commit() } }
        .alert("Your node", isPresented: Binding(get: { word != nil }, set: { v in if !v { word = nil } })) {
            Button("OK") { word = nil }
        } message: {
            if let w = word { Text(w) }
        }
    }

    @ViewBuilder private var stateRow: some View {
        switch node.state {
        case .unknown, .noHost:
            EmptyView()
        case .asking:
            HStack { Text("Asking your node…").foregroundColor(.white); Spacer(); ProgressView() }
        case .none:
            Text("Your node holds no copy").foregroundColor(.white)
        case .held(let h, _):
            HStack {
                Text("Held by your node").foregroundColor(.white)
                Spacer()
                Text(verbatim: h.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: MTLanguage.locale)) + " · " + mtSize(h.bytes)).foregroundColor(.secondary)   // USER-DATA: a moment and a size
            }
        case .refused(let why):
            HStack { Text("Your node refused").foregroundColor(.red); Spacer(); Text(verbatim: why).font(.footnote).foregroundColor(.secondary) }   // USER-DATA: the node's code
        case .silent(let why):
            HStack { Text("Your node did not answer").foregroundColor(.white); Spacer(); Text(verbatim: why).font(.footnote).foregroundColor(.secondary) }   // USER-DATA: the system's code
        }
    }
    private var holds: Bool { if case .held = node.state { return true } else { return false } }
    private var switchBinding: Binding<Bool> {
        Binding(get: { on }, set: { v in
            on = v; MontanaHomeNode.setOn(v)
            if v { commit(); node.tick() }
        })
    }
    private func bar(_ title: LocalizedStringKey, _ f: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).foregroundColor(.white); Spacer(); Text(verbatim: String(Int(f * 100)) + "%").foregroundColor(.secondary) }   // USER-DATA: a share
            ProgressView(value: f)
        }
        .padding(.vertical, 4)
    }
    private func commit() {
        let before = MontanaHomeNode.host
        MontanaHomeNode.setHost(host)
        host = MontanaHomeNode.host
        if MontanaHomeNode.onLocalNetwork(host) {
            word = "A node is reached over the internet: give the address it has there, not one of your local network."
            return
        }
        if host != before || node.state == .unknown || node.state == .noHost { node.ask() }
    }
    private func setUp() {
        commit()
        guard !MontanaHomeNode.onLocalNetwork(host) else { return }   // the word is said by commit
        settingUp = true
        let h = host, u = login.trimmingCharacters(in: .whitespaces).isEmpty ? "root" : login.trimmingCharacters(in: .whitespaces), pw = password   // NOT-UI
        Task {
            do {
                let fp = try await MontanaNodeSetup.run(host: h, user: u, password: pw)
                MontanaHomeNode.setPin(fp)
                MontanaHomeNode.setOn(true); on = true
                password = ""
                settingUp = false
                word = "Your node is set up: its door stands at \\(h) and its certificate is pinned."
                node.ask()
            } catch {
                settingUp = false
                MontanaTrace.mark("home_node", "set-up refused " + String(String(describing: error).prefix(120)))
                word = "The set-up refused: \\(String(describing: error))"
            }
        }
    }
    private func sendNow() {
        commit()
        node.send(urgent: true, cellular: true) { r in
            switch r {
            case .success(let t): word = "Taken by your node: \(t.chats) conversations, \(t.records) records, \(t.media) attachments."
            case .failure(let e): word = e.spoken(by: .node)
            }
        }
    }
    private func restore() {
        node.takeBack { r in
            switch r {
            case .success(let t): word = "Taken into this device: \(t.chats) conversations, \(t.records) records, \(t.media) attachments."
            case .failure(let e): word = e.spoken(by: .node)
            }
        }
    }
}

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
