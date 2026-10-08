import SwiftUI
import CryptoKit
import LocalAuthentication
import UniformTypeIdentifiers

/// PASSWORDS (the author's word 06.10.2026 17:4x MSK: «create in Montana a new app on the side panel -- Passwords, with the whole
/// interface for creating and managing one's sensitive data, down to OTP keys and sharing»): the person's secrets -- sign-ins,
/// one-time codes, notes -- in this phone's keychain alone (MontanaKeychain: this device only, never in a backup, parked with the
/// person by a seat), unlocked by the device owner's own check, copied for this device alone and for ninety seconds, and shared
/// only into a Montana chat, end to end, where the receiver saves it into their own Passwords.
struct MTSecretItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case login, code, note
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .login: return "Sign-in"
            case .code: return "One-time code"
            case .note: return "Note"
            }
        }
        var glyph: String {
            switch self {
            case .login: return "key.fill"
            case .code: return "clock.badge.checkmark.fill"
            case .note: return "note.text"
            }
        }
    }
    var id = UUID().uuidString
    var kind = Kind.login
    var title = ""
    var site = ""
    var login = ""
    var password = ""
    var otp = ""      // a base32 key or an otpauth:// link
    var note = ""
    var at = Date().timeIntervalSince1970
}

/// THE ONE OWNER OF THE SECRETS on this phone: read and written whole, as one keychain item of this device.
@MainActor final class MTPasswordVault: ObservableObject {
    static let shared = MTPasswordVault()
    static let key = "mt.passwords"   // NOT-UI: the vault's keychain item (SeedScope.keychainStays, seatKeychain)
    @Published private(set) var items: [MTSecretItem] = []
    @Published private(set) var unlocked = false
    /// The device has no passcode: nothing can be protected, so nothing is shown.
    @Published private(set) var refused = false
    /// A secret a correspondent shared, waiting for the person to save it (MTSecretLetter).
    @Published var incoming: MTSecretItem?

    /// The device owner's own check -- the face, the finger or the passcode; an absent check is a failed one.
    func unlock(then done: (() -> Void)? = nil) {
        if unlocked { done?(); return }
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { refused = true; return }
        let reason = String(localized: "Unlock your passwords", bundle: MTLanguage.bundle)
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async {
                guard ok else { return }
                MTPasswordVault.shared.letIn()
                done?()
            }
        }
    }
    private func letIn() {
        items = Self.read().sorted(by: Self.order)
        unlocked = true
        refused = false
        MontanaP2PTrace.mark("passwords", "unlocked items=\(items.count)")
    }
    func lock() { items = []; unlocked = false }
    func save(_ item: MTSecretItem) {
        guard unlocked else { return }
        var all = items
        var kept = item
        kept.at = Date().timeIntervalSince1970
        if let i = all.firstIndex(where: { e in e.id == item.id }) { all[i] = kept } else { all.append(kept) }
        write(all)
    }
    func remove(_ id: String) {
        guard unlocked else { return }
        write(items.filter { e in e.id != id })
    }
    private func write(_ all: [MTSecretItem]) {
        guard let data = try? JSONEncoder().encode(all), MontanaKeychain.set(Self.key, data) else {
            MontanaP2PTrace.mark("passwords", "write refused items=\(all.count)")
            return
        }
        items = all.sorted(by: Self.order)
    }
    nonisolated static func read() -> [MTSecretItem] {
        guard let data = MontanaKeychain.get(key) else { return [] }
        return (try? JSONDecoder().decode([MTSecretItem].self, from: data)) ?? []
    }
    nonisolated static func order(_ a: MTSecretItem, _ b: MTSecretItem) -> Bool {
        a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
}

/// ONE-TIME CODES (RFC 6238 over RFC 4226): the key as base32 or an otpauth:// link, the code of the window of the period now.
/// The algorithm is the site's, an external standard's own: Montana's own security stands on nothing here.
enum MTOneTimeCode {
    struct Spec { let key: Data; let digits: Int; let period: Int; let algorithm: String }
    static func spec(_ raw: String) -> Spec? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("otpauth://"), let link = URLComponents(string: text) {   // NOT-UI: the standard's scheme
            var q: [String: String] = [:]
            for item in link.queryItems ?? [] { q[item.name.lowercased()] = item.value ?? "" }
            guard let key = base32(q["secret"] ?? "") else { return nil }   // NOT-UI: the standard's parameter
            return Spec(key: key, digits: Int(q["digits"] ?? "") ?? 6, period: Int(q["period"] ?? "") ?? 30,   // NOT-UI: the standard's parameters
                        algorithm: (q["algorithm"] ?? "SHA1").uppercased())   // NOT-UI: the standard's parameter
        }
        guard let key = base32(text) else { return nil }
        return Spec(key: key, digits: 6, period: 30, algorithm: "SHA1")   // NOT-UI: the standard's default
    }
    static func base32(_ text: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")   // NOT-UI: RFC 4648
        var value = 0, bits = 0
        var out = Data()
        for ch in text.uppercased() where !"= -".contains(ch) {
            guard let i = alphabet.firstIndex(of: ch) else { return nil }
            value = ((value << 5) | i) & 0xFFFF
            bits += 5
            if 8 <= bits {
                out.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return out.isEmpty ? nil : out
    }
    static func code(_ spec: Spec, at moment: Date) -> String {
        var counter = (UInt64(moment.timeIntervalSince1970) / UInt64(max(1, spec.period))).bigEndian
        let message = Data(bytes: &counter, count: 8)
        let key = SymmetricKey(data: spec.key)
        let mac: [UInt8]
        switch spec.algorithm {
        case "SHA256": mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))   // NOT-UI: the standard's names
        case "SHA512": mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))   // NOT-UI: the standard's names
        default: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        }
        let at = Int(mac[mac.count - 1] & 0x0F)
        let bin = ((Int(mac[at]) & 0x7F) << 24) | (Int(mac[at + 1]) << 16) | (Int(mac[at + 2]) << 8) | Int(mac[at + 3])
        let digits = min(max(spec.digits, 6), 8)
        var modulus = 1
        for _ in 0..<digits { modulus *= 10 }
        let n = String(bin % modulus)
        return String(repeating: "0", count: digits - n.count) + n
    }
}

enum MTPasswordGenerator {
    /// Twenty characters, letters that are not mistaken for one another, digits and a few signs, each drawn without bias.
    static func fresh(_ length: Int = 20) -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_.!?#")   // NOT-UI: the generator's alphabet
        let limit = 256 - 256 % alphabet.count
        var out = ""
        while out.count < length {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { continue }
            if Int(byte) < limit { out.append(alphabet[Int(byte) % alphabet.count]) }
        }
        return out
    }
    /// A secret copied for this device alone, gone from the pasteboard after ninety seconds.
    static func copy(_ value: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: value]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(90)])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// A SECRET SHARED INTO A CHAT: the key glyph and the title on the first line, the machine line under it; it rides the chat's own
/// letter road, end to end, and every preview of it -- the list, the banner -- names no title and no content (MTRowLetter.preview).
enum MTSecretLetter {
    static let link = "montana://secret/1/"   // NOT-UI: the letter's machine line
    static func text(_ item: MTSecretItem) -> String? {
        var shared = item
        shared.id = ""
        guard let data = try? JSONEncoder().encode(shared) else { return nil }
        let code = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return "🔑 " + item.title + "\n" + link + code   // NOT-UI: the key glyph, the same in every language
    }
    static func parse(_ text: String) -> MTSecretItem? {
        guard text.hasPrefix("🔑 "), text.utf8.count <= 65_536,
              let line = text.split(separator: "\n", omittingEmptySubsequences: false).last, line.hasPrefix(link) else { return nil }
        let code = line.dropFirst(link.count).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: code), var item = try? JSONDecoder().decode(MTSecretItem.self, from: data) else { return nil }
        item.id = UUID().uuidString
        return item
    }
}

/// THE APP'S PAGE: the secrets by kind, searched, each with its own page; the plus writes a new one.
struct MTPasswordsPage: View {
    @Environment(\.montanaClose) private var close
    @ObservedObject private var vault = MTPasswordVault.shared
    @State private var search = ""
    @State private var writing = false
    var body: some View {
        NavigationStack {
            Group {
                if vault.unlocked { list } else { locked }
            }
            .scrollContentBackground(.hidden)
            .montanaPageGround()
            .navigationTitle("Passwords")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { vault.lock(); close?() } }
                if vault.unlocked {
                    ToolbarItem(placement: .topBarTrailing) { MontanaBarMark(glyph: "plus", label: "New") { writing = true } }
                }
            }
            .sheet(isPresented: $writing) { MTSecretEditor(item: MTSecretItem()) }
        }
        .onAppear { vault.unlock() }
    }
    private var shown: [MTSecretItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return vault.items }
        return vault.items.filter { e in [e.title, e.site, e.login, e.note].contains { f in f.localizedCaseInsensitiveContains(q) } }
    }
    private var list: some View {
        List {
            if vault.items.isEmpty {
                Text("No passwords yet").foregroundStyle(.secondary).listRowBackground(MTGlassRowPlate())
            }
            ForEach(MTSecretItem.Kind.allCases) { kind in
                let rows = shown.filter { e in e.kind == kind }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { e in
                            NavigationLink { MTSecretDetail(id: e.id) } label: { MTSecretRow(item: e) }
                                .listRowBackground(MTGlassRowPlate())
                        }
                        .onDelete { at in for i in at { vault.remove(rows[i].id) } }
                    } header: { Text(kind.title) }
                }
            }
        }
        .searchable(text: $search)
    }
    private var locked: some View {
        List {
            VStack(spacing: 14) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text(vault.refused ? "Set a passcode on this device — without it the passwords cannot be protected." : "Your passwords unlock with Face ID or your passcode.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if !vault.refused {
                    Button { vault.unlock() } label: { Label("Unlock", systemImage: "lock.open.fill") }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(MTGlassRowPlate())
        }
    }
}

struct MTSecretRow: View {
    let item: MTSecretItem
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.glyph).font(.title3).foregroundStyle(.white).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                // USER-DATA: the secret's title as its owner wrote it
                Text(verbatim: item.title.isEmpty ? (item.site.isEmpty ? "—" : item.site) : item.title).font(.body).lineLimit(1)
                if !item.login.isEmpty {
                    // USER-DATA: the login of the sign-in
                    Text(verbatim: item.login).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.kind == .code, let spec = MTOneTimeCode.spec(item.otp) {
                MTCodeLive(spec: spec, compact: true)
            }
        }
        .frame(minHeight: 44)
    }
}

/// The code of the window now, turning with its period, and the seconds left in it as the platform's own ring.
struct MTCodeLive: View {
    let spec: MTOneTimeCode.Spec
    var compact = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let left = spec.period - Int(now.timeIntervalSince1970) % max(1, spec.period)
            HStack(spacing: 8) {
                // USER-DATA: the one-time code of this moment
                Text(verbatim: MTOneTimeCode.code(spec, at: now)).font((compact ? Font.body : Font.title2).monospacedDigit().weight(.semibold))
                Gauge(value: Double(left), in: 0...Double(max(1, spec.period))) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity).scaleEffect(compact ? 0.45 : 0.6).frame(width: compact ? 24 : 32, height: compact ? 24 : 32)
            }
        }
    }
}

/// ONE SECRET'S OWN PAGE: every field copied by a tap, the password shown on asking, the code live; the pencil edits it, the
/// sharing glyph sends it into a chat.
struct MTSecretDetail: View {
    let id: String
    @ObservedObject private var vault = MTPasswordVault.shared
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false
    @State private var editing = false
    @State private var sharing = false
    @State private var asking = false
    private var item: MTSecretItem? { vault.items.first { e in e.id == id } }
    var body: some View {
        List {
            if let item {
                Section {
                    if !item.site.isEmpty { field("Site", item.site) }
                    if !item.login.isEmpty { field("Login", item.login) }
                    if !item.password.isEmpty {
                        Button { MTPasswordGenerator.copy(item.password) } label: {
                            LabeledContent {
                                // USER-DATA: the password, shown only when its owner asks
                                Text(verbatim: shown ? item.password : String(repeating: "•", count: 10)).font(.body.monospaced())
                            } label: { Text("Password") }
                        }
                        Button { shown.toggle() } label: { Label(shown ? "Hide password" : "Show password", systemImage: shown ? "eye.slash" : "eye") }
                    }
                    if let spec = MTOneTimeCode.spec(item.otp) {
                        Button { MTPasswordGenerator.copy(MTOneTimeCode.code(spec, at: Date())) } label: {
                            LabeledContent { MTCodeLive(spec: spec) } label: { Text("Code") }
                        }
                    }
                    if !item.note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Note").font(.subheadline)
                            // USER-DATA: the note its owner wrote
                            Text(verbatim: item.note).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                } footer: { Text("A tap copies for this device alone; the copy is gone in ninety seconds.") }
                .listRowBackground(MTGlassRowPlate())
                Section {
                    Button(role: .destructive) { asking = true } label: { Label("Delete", systemImage: "trash") }
                        .listRowBackground(MTGlassRowPlate())
                }
            }
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()
        // USER-DATA: the secret's title as the page's title
        .navigationTitle(Text(verbatim: item?.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { MontanaBarMark(glyph: "square.and.arrow.up", label: "Share") { sharing = true } }
            ToolbarItem(placement: .topBarTrailing) { MontanaBarMark(glyph: "pencil", label: "Edit") { editing = true } }
        }
        .sheet(isPresented: $editing) { if let item { MTSecretEditor(item: item) } }
        .sheet(isPresented: $sharing) { if let item { MTSecretShareSheet(item: item) } }
        .confirmationDialog("Delete this password?", isPresented: $asking, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { vault.remove(id); dismiss() }
        }
    }
    private func field(_ label: LocalizedStringKey, _ value: String) -> some View {
        Button { MTPasswordGenerator.copy(value) } label: {
            LabeledContent {
                // USER-DATA: a field of the secret as its owner wrote it
                Text(verbatim: value).lineLimit(1)
            } label: { Text(label) }
        }
    }
}

/// A NEW SECRET OR A CHANGED ONE: the kind, and the fields the kind holds; the die draws a password.
struct MTSecretEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: MTSecretItem
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Kind", selection: $item.kind) {
                        ForEach(MTSecretItem.Kind.allCases) { k in Text(k.title).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Title", text: $item.title)
                    if item.kind == .login {
                        TextField("Site", text: $item.site).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Login", text: $item.login).textInputAutocapitalization(.never).autocorrectionDisabled()
                        HStack {
                            SecureField("Password", text: $item.password).textContentType(.password)
                            Button { item.password = MTPasswordGenerator.fresh() } label: { Image(systemName: "dice.fill") }
                                .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel(Text("Generate password"))
                        }
                    }
                    if item.kind != .note {
                        TextField("One-time code key", text: $item.otp).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    TextField("Note", text: $item.note, axis: .vertical).lineLimit(3...8)
                } footer: {
                    if item.kind != .note { Text("The key of a one-time code: the letters a site shows, or its otpauth:// link.") }
                }
                .listRowBackground(MTGlassRowPlate())
            }
            .scrollContentBackground(.hidden)
            .montanaPageGround()
            .navigationTitle("New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    MontanaBarMark(glyph: "checkmark", label: "Save") { MTPasswordVault.shared.save(item); dismiss() }
                }
            }
        }
    }
}

/// SHARING INTO A CHAT: the person's own chats; a tap sends the secret as a letter of that chat, end to end.
struct MTSecretShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: MTSecretItem
    @State private var chats: [Chat] = []
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if chats.isEmpty {
                        Text("No chats yet").foregroundStyle(.secondary).listRowBackground(MTGlassRowPlate())
                    }
                    ForEach(chats, id: \.name) { c in
                        Button { send(to: c) } label: {
                            HStack(spacing: 12) { MontanaChatFace(chat: c); Spacer(minLength: 0) }
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(MTGlassRowPlate())
                    }
                } header: { Text("Share with") } footer: { Text("Sent end to end as a letter of the chat; the person saves it to their own Passwords.") }
            }
            .scrollContentBackground(.hidden)
            .montanaPageGround()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { dismiss() } } }
        }
        .onAppear {
            guard let store = ChatStore.live else { return }
            chats = store.listChats().filter { c in !c.isGroup && !ChatStore.isLocalRoom(c.name) && c.convId != nil && MontanaConv.holds(c.convId ?? c.name) }
        }
    }
    private func send(to c: Chat) {
        guard let store = ChatStore.live, let text = MTSecretLetter.text(item) else { return }
        let m = store.send(text: text, chat: c.name, convRef: c.convId ?? c.name, silent: false, noLinkCard: true)
        MontanaP2PTrace.mark("passwords", "shared sent=\(m.text.isEmpty ? 0 : 1)")
        dismiss()
    }
}

/// A SECRET A CORRESPONDENT SHARED: what it holds, saved into the person's own Passwords after the device owner's check.
struct MTSecretSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: MTSecretItem
    var body: some View {
        NavigationStack {
            List {
                Section {
                    // USER-DATA: the shared title
                    LabeledContent { Text(verbatim: item.title) } label: { Text("Title") }
                    if !item.site.isEmpty {
                        // USER-DATA: the shared site
                        LabeledContent { Text(verbatim: item.site) } label: { Text("Site") }
                    }
                    if !item.login.isEmpty {
                        // USER-DATA: the shared login
                        LabeledContent { Text(verbatim: item.login) } label: { Text("Login") }
                    }
                }
                .listRowBackground(MTGlassRowPlate())
            }
            .scrollContentBackground(.hidden)
            .montanaPageGround()
            .navigationTitle("Save to Passwords")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    MontanaBarMark(glyph: "checkmark", label: "Save") {
                        let kept = item
                        MTPasswordVault.shared.unlock { MTPasswordVault.shared.save(kept); dismiss() }
                    }
                }
            }
        }
    }
}
