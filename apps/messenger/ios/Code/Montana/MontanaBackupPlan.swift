import SwiftUI
import QuickLook

// WHAT GOES INTO A COPY, AND THE PAGES WHERE A PERSON SEES IT AND CHOOSES (the author, 23.09 01:31:
// make conversations, records and attachments tappable, see everything inside, choose what stays).
//
// Everything goes by default. The plan is what a person left OUT — a conversation, or a kind of
// attachment — and it is kept on this device, sealed like every other list that names correspondents.
// The inventory is COUNTED from what this device holds: the letters in the feed and the files in the
// correspondence store, each file with its size. A number on these pages measures exactly that.

/// What a person chose to leave out of a copy. One owner; sealed under the device key.
/// A conversation, a kind, or ONE file (the author, 23.09: choose any element on its own).
struct CopyPlan: Codable, Equatable {
    var skipChats: [String] = []
    var skipKinds: [String] = []
    var skipFiles: [String] = []
    init() {}
    // A plan sealed before single files could be left out has no such list: it reads as empty.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        skipChats = try c.decodeIfPresent([String].self, forKey: .skipChats) ?? []
        skipKinds = try c.decodeIfPresent([String].self, forKey: .skipKinds) ?? []
        skipFiles = try c.decodeIfPresent([String].self, forKey: .skipFiles) ?? []
    }
    private static let key = "mt.backup.plan"   // NOT-UI
    static func load() -> CopyPlan {
        guard let d = MontanaLocalVault.getDecrypted(key), let p = try? JSONDecoder().decode(CopyPlan.self, from: d) else { return CopyPlan() }
        return p
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { MontanaLocalVault.setEncrypted(Self.key, d) }
    }
    func takes(chat: String) -> Bool { !skipChats.contains(chat) }
    func takes(kind: MontanaBackup.Kind) -> Bool { !skipKinds.contains(kind.rawValue) }
}

/// What this device holds for a copy, counted.
struct CopyInventory {
    struct Conv: Identifiable {
        let id: String            // the conversation's reference
        let chat: Chat
        let title: String
        var letters: Int
        var files: [String]
        var bytes: Int
    }
    var convs: [Conv] = []
    var owner: [String: (conv: String, kind: MontanaBackup.Kind)] = [:]
    var sizes: [String: Int] = [:]    // every file of the store, by name
    var missing = 0                   // files the letters name and this device does not hold
    var letters: [String: [(chat: String, msg: Message)]] = [:]   // every letter naming a file, under the feed's key

    /// A file deleted from its chat leaves the count at once: its letters, its weight, its name.
    mutating func forget(_ file: String) {
        let gone = (letters[file] ?? []).count
        for i in convs.indices where convs[i].files.contains(file) {
            convs[i].files.removeAll { $0 == file }
            convs[i].bytes = max(0, convs[i].bytes - (sizes[file] ?? 0))
            convs[i].letters = max(0, convs[i].letters - gone)
        }
        sizes[file] = nil; owner[file] = nil; letters[file] = nil
    }

    func kindOf(_ file: String) -> MontanaBackup.Kind { owner[file]?.kind ?? MontanaBackup.kind(ofExtension: file) }

    /// The one translation of a plan into what the engine takes ([C-1]): the engine and these pages
    /// read the same answer, so the count shown is the count copied.
    func scope(_ plan: CopyPlan) -> MontanaBackup.Scope {
        var s = MontanaBackup.Scope()
        s.skipConvs = Set(plan.skipChats)
        s.skipKinds = Set(plan.skipKinds.compactMap { MontanaBackup.Kind(rawValue: $0) })
        s.skipFiles = Set(plan.skipFiles)
        s.owner = owner
        // Every name a left-out conversation is known by, and the files of its faces: the page promises that
        // none of its names or faces go into the copy, and the card and the faces' place keep the promise.
        for c in convs where !plan.takes(chat: c.id) {
            s.skipPeople.formUnion([c.id, c.chat.name] + [c.chat.convId].compactMap { $0 })
            let faces = [MTNameBook.manualPhoto(c.id), MTNameBook.publishedPhoto(c.id), c.chat.photoURL]
            s.skipFaces.formUnion(faces.compactMap { $0 }.filter { !$0.isEmpty })
        }
        return s
    }
    func taken(_ plan: CopyPlan) -> (chats: Int, letters: Int, files: Int, bytes: Int) {
        let s = scope(plan)
        let conv = convs.filter { plan.takes(chat: $0.id) }
        let files = sizes.filter { s.takes(file: $0.key) }
        return (conv.count, conv.reduce(0) { $0 + $1.letters }, files.count, files.values.reduce(0, +))
    }
    func kindTotals(_ k: MontanaBackup.Kind) -> (count: Int, bytes: Int) {
        let f = sizes.filter { kindOf($0.key) == k }
        return (f.count, f.values.reduce(0, +))
    }

    /// Counted off the main thread from a snapshot of the feed -- its rows, names and titles taken on the main thread in one
    /// breath (25.09: the walk over every letter of every chat ran on the main thread at each opening of Data and Storage) --
    /// and sized from the disk.
    @MainActor static func gather(_ done: @escaping (CopyInventory) -> Void) {
        let chats = ChatStore.live?.listChats() ?? []
        let titles = Dictionary(chats.map { ($0.name, ChatStore.live?.title(for: $0) ?? $0.name) }, uniquingKeysWith: { a, _ in a })
        let messages = ChatStore.live?.messages ?? [:]
        DispatchQueue.global(qos: .utility).async {
            var inv = CopyInventory()
            var named = Set<String>()
            for chat in chats {
                var keyed = (messages[chat.name] ?? []).map { (chat.name, $0) }
                if let c = chat.convId, c != chat.name { keyed += (messages[c] ?? []).map { (c, $0) } }
                let rows = keyed.map { $0.1 }
                var files: [String] = []
                for (key, m) in keyed {
                    let pairs: [(String?, MontanaBackup.Kind)] = [(m.imageFile, .photo), (m.videoFile, .video),
                                                                  (m.audioFile, .voice), (m.docFile, .file)]
                    for (f, k) in pairs {
                        guard let f, !f.isEmpty, !f.contains("/") else { continue }
                        inv.owner[f] = (chat.convRef, k)
                        inv.letters[f, default: []].append((key, m))
                        files.append(f)
                        named.insert(f)
                    }
                }
                inv.convs.append(Conv(id: chat.convRef, chat: chat, title: titles[chat.name] ?? chat.name,
                                      letters: rows.count, files: files, bytes: 0))
            }
            let dir = MontanaMediaStore.dir
            let fm = FileManager.default
            for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !n.hasPrefix(".") {
                var isDir: ObjCBool = false
                let path = dir.appendingPathComponent(n).path
                guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }
                inv.sizes[n] = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            }
            inv.missing = named.filter { inv.sizes[$0] == nil }.count
            for i in inv.convs.indices {
                inv.convs[i].bytes = inv.convs[i].files.reduce(0) { $0 + (inv.sizes[$1] ?? 0) }
            }
            inv.convs.sort { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.letters > $1.letters }
            DispatchQueue.main.async { done(inv) }
        }
    }

    /// The daily cloud copy asks for the scope once the feed has been read. A plan that leaves
    /// something out is never applied over an unread feed: without the letters nothing says which
    /// file belongs to which conversation, and a file of a conversation left out would travel.
    @MainActor static func tickSoon() {
        guard MontanaBackupCloud.on else { return }
        MontanaBackupCloud.ready { r in if r { CloudWatch.shared.start() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            CloudWatch.shared.whenAnswered { tickNow(urgent: false) }
        }
    }

    enum TickOutcome { case made, skipped(String), refused(MontanaBackup.Refusal), unmet }
    /// THE ONE ROAD OF A COPY TO iCLOUD (the author, 23.09 18:27: «why does it do the work twice?»). The
    /// daily tick and the switch both come here, and a copy for iCloud is made nowhere else: only after
    /// iCloud has answered, never while the last copy is on its way, refused or without room, and only
    /// when one is due — iCloud holds none of ours, the engine changed, or the last copy is a day old. At
    /// 18:24 the switch made a second 2.9 GB copy while the copy of 18:06 waited for room, and the two
    /// fought for a 5 GB plan. What is being sealed is shown under the iCloud row from its first moment.
    @MainActor static func tickNow(urgent: Bool, _ done: @escaping (TickOutcome) -> Void = { _ in }) {
        guard MontanaBackupCloud.on else { return done(.skipped("off")) }
        let w = CloudWatch.shared
        func skip(_ why: String) { MontanaTrace.mark("backup_cloud", "tick skipped: " + why); done(.skipped(why)) }
        guard w.gathered else { return skip("iCloud has not answered") }
        guard CloudCopy.shared.sealing == nil else { return skip("a copy is being sealed") }
        switch w.state {
        case .none, .held: break
        default: return skip("the last copy is not held by iCloud yet")
        }
        // A DEVICE THAT HAS MET NO COPY OF ITS OWN WHILE iCLOUD HOLDS ONE IS NOT RESTORED YET (the critic, 23.09):
        // its first copy would be a copy of an empty app, and once iCloud held it the keep rule would take the
        // real one away. Nothing is made; the person is asked — restore it, or begin anew from this device.
        if !MontanaBackupCloud.met, w.state != .none {
            MontanaTrace.mark("backup_cloud", "tick held: iCloud holds a copy this device has not met")
            return done(.unmet)
        }
        guard MontanaBackupCloud.due(holdsNone: w.state == .none) else { return skip("not due") }
        let plan = CopyPlan.load()
        let excluding = !plan.skipChats.isEmpty || !plan.skipKinds.isEmpty || !plan.skipFiles.isEmpty
        if excluding, (ChatStore.live?.messages.isEmpty ?? true) { return skip("feed not read, the plan leaves something out") }
        CloudCopy.shared.sealing = 0
        gather { inv in
            MontanaBackupCloud.copyNow(scope: inv.scope(plan), urgent: urgent, progress: { CloudCopy.shared.sealing = $0 }) { r in
                CloudCopy.shared.sealing = nil
                switch r {
                case .success: done(.made)
                case .failure(let e): done(.refused(e))
                }
            }
        }
    }
}

/// THE COPY BEING SEALED FOR iCLOUD, as it is sealed (the author, 23.09 18:27: «it was not visible that it
/// made a copy before it began to sync»): OUR count of bytes sealed, shown under the iCloud row before iCloud
/// has anything to say. Its words say «sealing», never «in iCloud»: this is this phone's work, not iCloud's.
@MainActor final class CloudCopy: ObservableObject {
    static let shared = CloudCopy()
    @Published var sealing: Double? = nil
}
func mtSize(_ bytes: Int) -> String { Int64(bytes).formatted(.byteCount(style: .file).locale(MTLanguage.locale)) }

/// THE CONVERSATIONS OF A COPY — every one this device holds, with its face, its letters and the
/// weight of its attachments. The whole row answers the finger; the mark says what the copy takes.
struct CopyChatsPage: View {
    let inventory: CopyInventory
    @Binding var plan: CopyPlan

    var body: some View {
        List {
            Section {
                ForEach(inventory.convs) { c in
                    Button { toggle(c.id) } label: {
                        HStack(spacing: 12) {
                            AvatarCircle(photoURL: ChatStore.live?.avatarFor(c.chat), color: c.chat.color,
                                         initial: ChatStore.live?.initial(for: c.chat) ?? c.chat.initial, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                // USER-DATA: the correspondent's name, as the list shows it
                                Text(verbatim: c.title).foregroundColor(.primary).lineLimit(1)
                                Text("\(c.letters) letters · \(mtSize(c.bytes))").font(.footnote).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                                .foregroundColor(.accentColor).opacity(plan.takes(chat: c.id) ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("A conversation left out is not read at all: none of its letters, names, faces or attachments go into the copy.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ id: String) {
        if let i = plan.skipChats.firstIndex(of: id) { plan.skipChats.remove(at: i) } else { plan.skipChats.append(id) }
    }
}

/// THE ATTACHMENTS OF A COPY — by kind, each with its count and weight on this device. A row opens
/// the kind's own files; the mark on the row says whether the copy takes that kind.
struct CopyKindsPage: View {
    @Binding var inventory: CopyInventory
    @Binding var plan: CopyPlan

    static func face(_ k: MontanaBackup.Kind) -> (LocalizedStringKey, String, Color) {
        switch k {
        case .photo: return ("Photos", "photo.fill", .blue)
        case .video: return ("Videos", "video.fill", .purple)
        case .voice: return ("Voice messages", "waveform", .orange)
        case .file: return ("Files", "doc.fill", .gray)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(MontanaBackup.Kind.allCases, id: \.self) { k in
                    let (title, icon, color) = Self.face(k)
                    let tot = inventory.kindTotals(k)
                    NavigationLink { CopyFilesPage(inventory: $inventory, kind: k, plan: $plan) } label: {
                        HStack {
                            settingsToggleLabel(title, icon, color)
                            Spacer()
                            Text("\(tot.count) · \(mtSize(tot.bytes))").foregroundColor(.secondary)
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                                .foregroundColor(.accentColor).opacity(plan.takes(kind: k) ? 1 : 0)
                        }
                    }
                }
            } footer: {
                if inventory.missing > 0 {
                    Text("Attachments this device never downloaded are not on it and cannot go into the copy: \(inventory.missing).")
                } else {
                    Text("Every attachment the letters name is on this device.")
                }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Attachments")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// ONE KIND'S FILES (the author, 23.09 01:50 and 02:40): every file of the kind this device holds,
/// heaviest first, each with its own picture drawn by the platform's thumbnailer. Each file is chosen
/// on its own: the round mark says whether the copy takes it; a swipe from the left leaves it out or
/// puts it back, a swipe from the right deletes its letter from the chat. The row opens the file
/// INSIDE this navigation — the back arrow returns to this list and nothing above it closes. The
/// switch at the top is the whole kind's place in the copy.
struct CopyFilesPage: View {
    @Binding var inventory: CopyInventory
    let kind: MontanaBackup.Kind
    @Binding var plan: CopyPlan
    @State private var asking: String? = nil

    private var files: [(name: String, bytes: Int)] {
        inventory.sizes.filter { inventory.kindOf($0.key) == kind }
            .map { (name: $0.key, bytes: $0.value) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
    }
    private func whose(_ file: String) -> String? {
        guard let conv = inventory.owner[file]?.conv else { return nil }
        return inventory.convs.first { $0.id == conv }?.title
    }
    private var inCopy: Binding<Bool> {
        Binding(get: { plan.takes(kind: kind) }, set: { on in
            plan.skipKinds.removeAll { $0 == kind.rawValue }
            if !on { plan.skipKinds.append(kind.rawValue) }
        })
    }
    /// A file is chosen on its own while neither its kind nor its conversation is left out whole.
    private func free(_ file: String) -> Bool {
        guard plan.takes(kind: kind) else { return false }
        guard let c = inventory.owner[file]?.conv else { return true }
        return plan.takes(chat: c)
    }
    private func flip(_ file: String) {
        if let i = plan.skipFiles.firstIndex(of: file) { plan.skipFiles.remove(at: i) } else { plan.skipFiles.append(file) }
    }

    var body: some View {
        let list = files
        let scope = inventory.scope(plan)
        let kept = list.filter { scope.takes(file: $0.name) }
        List {
            Section {
                Toggle(isOn: inCopy) { Text("In the copy") }
            } footer: {
                Text("In the copy: \(kept.count) of \(list.count) · \(mtSize(kept.reduce(0) { $0 + $1.bytes }))")
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                ForEach(list, id: \.name) { f in
                    let takes = scope.takes(file: f.name)
                    let open = free(f.name)
                    let deletable = !(inventory.letters[f.name] ?? []).isEmpty
                    NavigationLink {
                        CopyFileView(file: f.name, title: whose(f.name), kind: kind, deletable: deletable) { delete(f.name) }
                    } label: {
                        HStack(spacing: 8) {
                            Button { flip(f.name) } label: {
                                Image(systemName: takes ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundColor(takes ? .accentColor : .secondary)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .disabled(!open)
                            .accessibilityLabel(takes ? Text("Leave out of the copy") : Text("Put back into the copy"))
                            MTFileIcon(file: f.name, name: f.name, width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                if let w = whose(f.name) {
                                    // USER-DATA: the correspondent's name, as the list shows it
                                    Text(verbatim: w).foregroundColor(.primary).lineLimit(1)
                                } else {
                                    Text("No letter on this device names it").foregroundColor(.secondary).lineLimit(1)
                                }
                                Text(verbatim: mtSize(f.bytes)).font(.footnote).foregroundColor(.secondary)   // USER-DATA: a size
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .swipeActions(edge: .leading) {
                        if open {
                            Button { flip(f.name) } label: {
                                if takes {
                                    Label("Leave out of the copy", systemImage: "minus.circle")
                                } else {
                                    Label("Put back into the copy", systemImage: "plus.circle")
                                }
                            }
                            .tint(takes ? .orange : .green)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if deletable {
                            Button { asking = f.name } label: { Label("Delete from the chat", systemImage: "trash") }
                                .tint(.red)
                        }
                    }
                }
            } footer: {
                Text("A swipe from the left leaves a file out of the copy; a swipe from the right deletes it from the chat.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle(Self.title(kind))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete from the chat?",
                            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { f in
            Button("Delete from the chat", role: .destructive) { delete(f) }
        } message: { _ in
            Text("The letter with this attachment is deleted on this device. The other side keeps its own.")
        }
    }

    /// Delete for me by the chat's own road ([C-1]: ChatStore.deleteLocally), then the store's own
    /// sweep carries off the file no letter names any more; the count on these pages follows at once.
    private func delete(_ file: String) {
        guard let store = ChatStore.live else { return }
        let ls = inventory.letters[file] ?? []
        for l in ls { store.deleteLocally(chat: l.chat, l.msg) }
        store.sweepMediaFiles()
        plan.skipFiles.removeAll { $0 == file }
        inventory.forget(file)
        MontanaTrace.mark("backup_plan", "deleted from chat letters=" + String(ls.count))
    }
    static func title(_ k: MontanaBackup.Kind) -> LocalizedStringKey { CopyKindsPage.face(k).0 }
}

/// ONE FILE, OPENED INSIDE THE PAGE (the author, 23.09 02:40: «it opens within this page, and closing
/// returns to the previous one instead of closing everything»). The list used to raise the chat's
/// document page as a full-screen cover, and that page leaves by the sliding container's own close —
/// the very close of the whole settings page, so one cross took everything down. Here the platform's
/// viewer is pushed into this navigation: the back arrow and the edge swipe return to the list, and
/// nothing above is touched. The bin deletes the file's letter from its chat, then returns.
struct CopyFileView: View {
    let file: String
    let title: String?
    let kind: MontanaBackup.Kind
    let deletable: Bool
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL? = nil
    @State private var searched = false
    @State private var asking = false

    var body: some View {
        Group {
            if let u = url {
                CopyQuickLook(url: u).ignoresSafeArea(edges: .bottom)
            } else if searched {
                VStack(spacing: 14) {
                    Image(systemName: "doc.questionmark").font(.system(size: 44)).foregroundColor(.gray)
                    Text("The file is not on this device. Ask the sender to send it again.")
                        .multilineTextAlignment(.center).foregroundColor(.gray).padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle(title.map { Text(verbatim: $0) } ?? Text(CopyFilesPage.title(kind)))   // USER-DATA: the correspondent's name
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if deletable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { asking = true } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Delete from the chat"))
                }
            }
        }
        .confirmationDialog("Delete from the chat?", isPresented: $asking, titleVisibility: .visible) {
            Button("Delete from the chat", role: .destructive) { onDelete(); dismiss() }
        } message: {
            Text("The letter with this attachment is deleted on this device. The other side keeps its own.")
        }
        .task {
            let f = file
            let found = await Task.detached(priority: .userInitiated) { () -> URL? in
                guard let u = mtMediaFileURL(f) ?? MontanaMediaVault.playableURL(f) else { return nil }
                return MTDocLink.named(u, as: f)
            }.value
            url = found; searched = true
        }
    }
}

/// The platform's viewer as a page's content; the bar above it is the page's own navigation bar.
/// The item and its data source are the chat's document page's own ([C-1]).
struct CopyQuickLook: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        c.overrideUserInterfaceStyle = .dark
        return c
    }
    func updateUIViewController(_ c: QLPreviewController, context: Context) {}
    func makeCoordinator() -> DocPreviewQL.Coordinator { DocPreviewQL.Coordinator(items: [DocPreviewQL.Entry(url: url, title: url.lastPathComponent)]) }
}

/// WHAT THE CLOUD HOLDS — ANSWERED BY THE CLOUD ALONE (the author, 23.09 01:50: the app said a copy of
/// more than two gigabytes was in iCloud; the platform's own storage page listed no Montana at all).
/// The row read the file in the container on THIS phone, and a file handed to the container is not a
/// file in the cloud: the upload is the platform's, later, and may never happen. The one witness of
/// what iCloud holds is iCloud's own metadata — uploaded, uploading with its share, or refused with its
/// own error. This watcher is the only owner of that answer; the screen and the diary read nothing else.
///
/// AND A COPY LEAVES THE CLOUD ONLY ON THE CLOUD'S WORD (the author, 23.09 03:41: «now it vanished from
/// the iCloud storage altogether»). Build 1900 made a new copy to replace one of the old format, and the
/// handing side removed the copy iCloud held AT THE HAND-OVER, before iCloud had taken the new one: the
/// storage page lost Montana while 2.6 GB were still on their way (T1's diary: «cloud holds» at 23:56Z,
/// «handed» at 00:41:56Z, and the older copy removed in that same second). Now the handing side removes
/// nothing. An older copy leaves only here, where iCloud's word is read, and only once iCloud confirms a
/// newer copy it holds. Where iCloud has no room for two, it says so in its own words, and the person —
/// never the code — decides to replace the copy it holds.
///
/// ONE watcher for the process, started with the app: the page reads it, the daily copy waits on it, and
/// the removal of older copies hangs on it. It is the platform's live query, not a patrol: it speaks
/// when iCloud changes.
///
/// ON EVERY iOS AND EVERY DEVICE (the author, 23.09 17:35: an iPhone 17 on mobile data read «iCloud
/// refused the upload: NSFileProviderErrorDomain -1004»). iCloud's word is read through one reading,
/// MontanaBackup.verdict, for both of its dialects: a server it could not reach is a WAIT, not a
/// refusal; over quota is no room, whichever dialect says it; signed out and iCloud Drive off are the
/// person's to fix, and are named so. And the watcher sees only this person's copies: a copy's name
/// proves its owner to its owner alone, so on an iCloud shared by several sets of words nobody's copy
/// is shown, taken back or removed but one's own.
@MainActor final class CloudWatch: ObservableObject {
    static let shared = CloudWatch()
    struct Held: Equatable { let date: Date; let bytes: Int }
    enum State: Equatable {
        case none                                   // iCloud holds no copy of ours
        case sending(Double?, Date, Int)            // handed over, not yet in iCloud; share uploaded if known
        case waiting(String, Date, Int)             // iCloud could not reach its servers; it goes on by itself
        case held(Date, Int)                        // iCloud confirms: uploaded
        case noRoom(Date, Int)                      // iCloud's own quota refusal: no room for this copy
        case signIn(String)                         // iCloud asks the person to sign in again
        case driveOff(String)                       // iCloud Drive is off on this device
        case refused(String, Date)                  // iCloud refused the upload, in its own words
    }
    @Published private(set) var state: State = .none      // the NEWEST copy
    /// The newest copy iCloud confirms it holds, while a newer one is still on its way or refused: the
    /// copy a person can still lean on, named on the screen as what it is.
    @Published private(set) var kept: Held? = nil
    @Published private(set) var url: URL? = nil     // the copy iCloud holds (else the newest) — the restore road reads it
    @Published private(set) var gathered = false    // iCloud has answered at least once
    private var query: NSMetadataQuery?
    private var tokens: [NSObjectProtocol] = []
    private var leaving: Set<URL> = []
    private var keptURL: URL? = nil
    /// Copies named before names carried a proof: whose they are is learned by opening their first frame
    /// on this device, once, off the main thread. Not local, or not yet known: not ours to touch.
    private var legacy: [String: Bool] = [:]
    private var checking: Set<String> = []
    private var root: (words: String, entropy: Data)? = nil
    private func entropyNow() -> Data? {
        guard let mn = MontanaSeed.mnemonic else { root = nil; return nil }
        if let r = root, r.words == mn { return r.entropy }
        guard let e = MontanaSeedKeys.entropyFrom(mnemonic: mn), e.count == 32 else { return nil }
        root = (mn, e)
        return e
    }

    func start() {
        guard query == nil else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        q.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "montana-*." + MontanaBackup.ext)
        let nc = NotificationCenter.default
        for n in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            tokens.append(nc.addObserver(forName: n, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.read() }
            })
        }
        query = q
        q.start()
    }

    private func read() {
        guard let q = query else { return }
        q.disableUpdates(); defer { q.enableUpdates() }
        readFetch(q)
        func size(_ i: NSMetadataItem) -> Int { (i.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.intValue ?? 0 }
        func uploaded(_ i: NSMetadataItem) -> Bool { (i.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? NSNumber)?.boolValue ?? false }
        func urlOf(_ i: NSMetadataItem) -> URL? { i.value(forAttribute: NSMetadataItemURLKey) as? URL }
        func local(_ i: NSMetadataItem) -> Bool {
            let st = i.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            return st == NSMetadataUbiquitousItemDownloadingStatusCurrent || st == NSMetadataUbiquitousItemDownloadingStatusDownloaded
        }
        gathered = true
        // ONLY OUR OWN COPIES ARE READ, SHOWN, TAKEN BACK OR REMOVED (23.09, «on any device»): another
        // person's copy in the same iCloud is proven another's by its name and never touched.
        guard let entropy = entropyNow() else { publish(.none, nil, nil); return }
        let owner = MontanaBackup.ownerKey(entropy: entropy)
        var items: [(born: Date, item: NSMetadataItem)] = []
        for case let item as NSMetadataItem in q.results {
            guard let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String,
                  let born = MontanaBackup.born(ofName: name) else { continue }
            switch MontanaBackup.owned(name: name, by: owner) {
            case .some(true): items.append((born, item))
            case .some(false): continue
            case .none:
                if let known = legacy[name] {
                    if known { items.append((born, item)) }
                } else if local(item), let u = urlOf(item), !checking.contains(name) {
                    checking.insert(name)
                    DispatchQueue.global(qos: .utility).async {
                        let mine = MontanaBackup.opens(u, entropy: entropy)
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.checking.remove(name)
                            if let mine { self.legacy[name] = mine; self.read() }
                        }
                    }
                }
            }
        }
        items.sort { $0.born > $1.born }   // the newest first
        guard let top = items.first else { publish(.none, nil, nil); return }
        let s: State
        if uploaded(top.item) {
            s = .held(top.born, size(top.item))
        } else if let err = top.item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError {
            let why = err.domain + " " + String(err.code)
            switch MontanaBackup.verdict(err) {
            case .waiting: s = .waiting(why, top.born, size(top.item))
            case .noRoom: s = .noRoom(top.born, size(top.item))
            case .signIn: s = .signIn(why)
            case .driveOff: s = .driveOff(why)
            case .refused: s = .refused(why, top.born)
            }
        } else {
            let pct = (top.item.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? NSNumber)?.doubleValue
            s = .sending(pct.map { $0 / 100 }, top.born, size(top.item))
        }
        let heldAt = items.firstIndex { uploaded($0.item) }
        // WHICH COPIES LEAVE is one pure decision of the engine, proven by mt-copy-roundtrip: the newest and
        // the newest held stay; a held copy leaves only behind a newer held one or by the person's word.
        let facts = items.map { MontanaBackup.CloudCopyFact(born: $0.born, held: uploaded($0.item), noRoom: false) }
        var shaped = facts
        if case .noRoom = s { shaped[0] = MontanaBackup.CloudCopyFact(born: facts[0].born, held: false, noRoom: true) }
        let out = MontanaBackup.leaving(shaped, now: Date(), alwaysReplace: UserDefaults.standard.bool(forKey: Self.replaceKey))
        if !out.isEmpty {
            leave(out.sorted().compactMap { urlOf(items[$0].item) }, "by the keep rule: " + out.sorted().map(String.init).joined(separator: ","))
        }
        let kept = heldAt.flatMap { $0 == 0 || out.contains($0) ? nil : items[$0] }
        keptURL = kept.flatMap { urlOf($0.item) }
        publish(s, kept.map { Held(date: $0.born, bytes: size($0.item)) },
                heldAt.flatMap { urlOf(items[$0].item) } ?? urlOf(top.item))
    }

    /// THE PERSON'S ACT, NEVER THE CODE'S: iCloud has no room for the new copy next to the one it holds,
    /// and the person, told that iCloud will hold no copy until the new one is up, chose to replace it —
    /// once, or from now on (`always`: the same word stands for every day's copy that finds no room).
    static let replaceKey = "mt.backup.icloud.replace"   // NOT-UI
    func replaceKept(always: Bool = false) {
        if always { UserDefaults.standard.set(true, forKey: Self.replaceKey) }
        guard let u = keptURL else { return }
        leave([u], "by the person's choice: iCloud had no room for two")
    }

    /// A COPY ASKED BACK FROM iCLOUD, answered by iCloud (the critic, 23.09: a fixed three-minute wait failed any
    /// copy of gigabytes on an ordinary network). How much has come is iCloud's own count; a wait for its
    /// servers is shown as a wait; a refusal carries its code; only the person stops it — never a clock.
    enum Fetch: Equatable { case coming(Double?), waiting(String) }
    @Published private(set) var fetching: Fetch? = nil
    private var fetchWait: (name: String, url: URL, done: (Result<URL, MontanaBackup.Refusal>) -> Void)? = nil
    func fetch(_ url: URL, _ done: @escaping (Result<URL, MontanaBackup.Refusal>) -> Void) {
        fetchWait = (url.lastPathComponent, url, done)
        fetching = .coming(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do { try FileManager.default.startDownloadingUbiquitousItem(at: url) } catch {
                let ns = error as NSError
                let why = "fetch " + ns.domain + " " + String(ns.code)
                Task { @MainActor [weak self] in self?.endFetch(.failure(.cloudRefused(why))) }
                return
            }
            Task { @MainActor [weak self] in self?.read() }
        }
    }
    func cancelFetch() { endFetch(.failure(.stopped)) }
    private func endFetch(_ r: Result<URL, MontanaBackup.Refusal>) {
        guard let w = fetchWait else { return }
        fetchWait = nil
        fetching = nil
        switch r {
        case .success: MontanaTrace.mark("backup_cloud", "fetched")
        case .failure(let e): MontanaTrace.mark("backup_cloud", "fetch ended: " + String(describing: e))
        }
        w.done(r)
    }
    private func readFetch(_ q: NSMetadataQuery) {
        guard let w = fetchWait else { return }
        var found: NSMetadataItem? = nil
        for case let item as NSMetadataItem in q.results where (item.value(forAttribute: NSMetadataItemFSNameKey) as? String) == w.name {
            found = item
        }
        guard let item = found else { return }
        let st = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        if st == NSMetadataUbiquitousItemDownloadingStatusCurrent { return endFetch(.success(w.url)) }
        if let err = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError {
            let why = err.domain + " " + String(err.code)
            if MontanaBackup.verdict(err) == .waiting { fetching = .waiting(why) } else { endFetch(.failure(.cloudRefused("fetch " + why))) }
            return
        }
        let pct = (item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? NSNumber)?.doubleValue
        fetching = .coming(pct.map { $0 / 100 })
    }

    /// Runs `f` once iCloud has answered at least once — at once when it already has.
    private var answered: [() -> Void] = []
    func whenAnswered(_ f: @escaping () -> Void) {
        if gathered { f() } else { answered.append(f) }
    }

    private func leave(_ urls: [URL], _ why: String) {
        let fresh = urls.filter { !leaving.contains($0) }
        guard !fresh.isEmpty else { return }
        leaving.formUnion(fresh)
        DispatchQueue.global(qos: .utility).async {
            var gone = 0
            for u in fresh {
                var err: NSError?
                NSFileCoordinator().coordinate(writingItemAt: u, options: .forDeleting, error: &err) { v in
                    if (try? FileManager.default.removeItem(at: v)) != nil { gone += 1 }
                }
            }
            MontanaTrace.mark("backup_cloud", "older copies removed n=" + String(gone) + " " + why)
        }
    }

    private func publish(_ s: State, _ k: Held?, _ u: URL?) {
        state = s; kept = k; url = u
        var m: String
        switch s {
        case .none: m = "cloud holds none"
        case .sending(let f, _, let b): m = "sending bytes=" + String(b) + " pct=" + (f.map { String(Int($0 * 100)) } ?? "-")
        case .waiting(let why, _, let b): m = "waiting for iCloud's servers " + why + " bytes=" + String(b)
        case .held(_, let b): m = "cloud holds bytes=" + String(b)
        case .noRoom(_, let b): m = "no room bytes=" + String(b)
        case .signIn(let why): m = "sign-in asked " + why
        case .driveOff(let why): m = "iCloud Drive off " + why
        case .refused(let why, _): m = "refused " + why
        }
        if let k { m += " kept bytes=" + String(k.bytes) }
        MontanaTrace.markChanged("backup_cloud", m)   // the tracer's one change-gate ([C-1], P-112), not a variable of our own
        if gathered, !answered.isEmpty {
            let waiting = answered
            answered = []
            waiting.forEach { $0() }
        }
    }
}

/// THE COPY BEFORE IT IS MADE (the author, 23.09 01:50): what the copy will take, by kind, each opening
/// its files; the conversations it takes; the whole weight. The checkmark makes it; then the bar
/// measures bytes sealed, and the finished file goes to the platform's share sheet.
struct CopyPreviewSheet: View {
    @Binding var inventory: CopyInventory
    @Binding var plan: CopyPlan
    let onDone: (Result<MontanaBackup.Made, MontanaBackup.Refusal>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sealing = false
    @State private var share: Double = 0

    var body: some View {
        let now = inventory.taken(plan)
        NavigationStack {
            List {
                if sealing {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: share)
                            Text("Sealing the copy: \(Int(share * 100))%").foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(MTGlassRowPlate())
                }
                Section {
                    NavigationLink { CopyChatsPage(inventory: inventory, plan: $plan) } label: {
                        HStack {
                            settingsToggleLabel("Conversations", "bubble.left.and.bubble.right.fill", .blue)
                            Spacer()
                            Text("\(now.chats) / \(inventory.convs.count)").foregroundColor(.secondary)
                        }
                    }
                    ForEach(MontanaBackup.Kind.allCases, id: \.self) { k in
                        let (title, icon, color) = CopyKindsPage.face(k)
                        let tot = inventory.kindTotals(k)
                        NavigationLink { CopyFilesPage(inventory: $inventory, kind: k, plan: $plan) } label: {
                            HStack {
                                settingsToggleLabel(title, icon, color)
                                Spacer()
                                Text("\(tot.count) · \(mtSize(tot.bytes))").foregroundColor(.secondary)
                                Image(systemName: "checkmark").font(.body.weight(.semibold))
                                    .foregroundColor(.accentColor).opacity(plan.takes(kind: k) ? 1 : 0)
                            }
                        }
                    }
                } header: {
                    Text("IN THE COPY")
                } footer: {
                    Text("Total: \(mtSize(now.bytes)) of attachments and \(now.letters) records. The copy is sealed with the key your 24 words open; the words are not in it.")
                }
                .listRowBackground(MTGlassRowPlate())
                .disabled(sealing)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Create backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if !sealing { MontanaCloseMark { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { if !sealing { MontanaDoneMark { seal() } } }
            }
            .interactiveDismissDisabled(sealing)
        }
        .preferredColorScheme(.dark)
    }

    private func seal() {
        guard !sealing else { return }
        sealing = true
        MontanaBackup.create(scope: inventory.scope(plan), urgent: true, progress: { share = $0 }) { r in
            sealing = false
            dismiss()
            onDone(r)
        }
    }
}
