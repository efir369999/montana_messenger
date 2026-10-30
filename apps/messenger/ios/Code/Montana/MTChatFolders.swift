import SwiftUI
import UIKit

/// THE FOLDERS OVER THE CHATS (the author's words 17.10.2026 15:4x UTC: «badges over the chats, the groups and the channels, and
/// their control in the settings»; «left of the chats, the groups and the channels a field All, every chat in it, the groups and
/// the channels too -- and a category Bots, our bot in it»; «the groups and the channels one to one as in the reference»). The
/// reference's own folders: All Chats and the person's folders, each the kinds of chats and the chats it takes and the states and the
/// chats it leaves out; a tab's badge counts the folder's unread conversations and is blue while one of them is not muted. A setting
/// of the person: kept in the vault and carried by the copy (SeedScope.settingKeys).
struct MTChatFolder: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case contacts, nonContacts, groups, channels, bots
        var title: String {
            switch self {
            case .contacts: return String(localized: "Contacts", bundle: MTLanguage.bundle)
            case .nonContacts: return String(localized: "Non-Contacts", bundle: MTLanguage.bundle)
            case .groups: return String(localized: "Groups", bundle: MTLanguage.bundle)
            case .channels: return String(localized: "Channels", bundle: MTLanguage.bundle)
            case .bots: return String(localized: "Bots", bundle: MTLanguage.bundle)
            }
        }
        var glyph: String {
            switch self {
            case .contacts: return "person.crop.circle"
            case .nonContacts: return "person.crop.circle.badge.questionmark"
            case .groups: return "person.2"
            case .channels: return "megaphone"
            case .bots: return "cpu"
            }
        }
        var tint: Color {
            switch self {
            case .contacts: return .blue
            case .nonContacts: return .teal
            case .groups: return .green
            case .channels: return .indigo
            case .bots: return .purple
            }
        }
    }
    enum Leave: String, Codable, CaseIterable {
        case muted, read, archived
        var title: String {
            switch self {
            case .muted: return String(localized: "Muted", bundle: MTLanguage.bundle)
            case .read: return String(localized: "Read", bundle: MTLanguage.bundle)
            case .archived: return String(localized: "Archived", bundle: MTLanguage.bundle)
            }
        }
        var glyph: String {
            switch self {
            case .muted: return "bell.slash"
            case .read: return "checkmark.message"
            case .archived: return "archivebox"
            }
        }
        var tint: Color {
            switch self {
            case .muted: return .red
            case .read: return .blue
            case .archived: return .gray
            }
        }
    }
    var id: String
    /// The person's own words; empty while a first-launch folder keeps the name of its kind in the person's language.
    var title: String = ""
    var preset: Kind? = nil
    var kinds: [Kind] = []
    var chats: [String] = []
    var leaves: [Leave] = [.archived]
    var excluded: [String] = []

    static let allID = "all"
    static let all = MTChatFolder(id: allID, leaves: [])
    var isAll: Bool { id == Self.allID }
    var shownTitle: String {
        if isAll { return String(localized: "All", bundle: MTLanguage.bundle) }   // the author's word 18.10.2026 07:2x UTC: «call it simply All»
        guard title.isEmpty, let p = preset else { return title }
        switch p {
        case .contacts, .nonContacts: return String(localized: "Chats", bundle: MTLanguage.bundle)
        case .groups: return String(localized: "Groups", bundle: MTLanguage.bundle)
        case .channels: return String(localized: "Channels", bundle: MTLanguage.bundle)
        case .bots: return String(localized: "Bots", bundle: MTLanguage.bundle)
        }
    }
    /// The folder of one kind alone: the drawer's Groups and Channels open theirs, and its corner gives birth to that kind.
    var onlyKind: Kind? { kinds.count == 1 && chats.isEmpty ? kinds.first : nil }
    var takesAnything: Bool { !kinds.isEmpty || !chats.isEmpty }
    /// The same folder by what it holds, whatever its name: a recommendation the person already has is not offered again.
    func holdsAlike(_ o: MTChatFolder) -> Bool {
        Set(kinds) == Set(o.kinds) && Set(leaves) == Set(o.leaves) && chats.isEmpty && o.chats.isEmpty
            && excluded.isEmpty && o.excluded.isEmpty
    }
    /// Whether a conversation stands in the folder: taken by its kind or by name, not left out by name or by a state.
    func takes(_ c: Chat, kind: Kind, muted: Bool, unread: Bool, archived: Bool) -> Bool {
        if isAll { return !archived }
        if excluded.contains(c.name) { return false }
        guard kinds.contains(kind) || chats.contains(c.name) else { return false }
        if muted && leaves.contains(.muted) { return false }
        if !unread && leaves.contains(.read) { return false }
        if archived && leaves.contains(.archived) { return false }
        return true
    }
}

/// The person's folders in the tabs' order, All Chats among them and never taken away.
final class MTChatFolders: ObservableObject {
    static let shared = MTChatFolders()
    static let key = "chatFolders"
    @Published private(set) var folders: [MTChatFolder]
    /// The way in from a tab's menu: the folders' page opens on the folder named, on its chats, or on the order.
    struct Opening: Equatable {
        var folder: String? = nil
        var addChats = false
        var reorder = false
    }
    @Published var opening: Opening?

    private init() {
        let raw = MontanaLocalVault.getString(Self.key) ?? ""
        let kept = (try? JSONDecoder().decode([MTChatFolder].self, from: Data(raw.utf8))) ?? []
        folders = kept.contains(where: { f in f.isAll }) ? kept : Self.firstFolders
    }
    /// THE FIRST TABS, in the author's order (17.10.2026): All, the chats, the groups, the channels, the bots.
    static let firstFolders: [MTChatFolder] = [
        .all,
        MTChatFolder(id: "chats", preset: .contacts, kinds: [.contacts, .nonContacts]),
        MTChatFolder(id: "groups", preset: .groups, kinds: [.groups]),
        MTChatFolder(id: "channels", preset: .channels, kinds: [.channels]),
        MTChatFolder(id: "bots", preset: .bots, kinds: [.bots])]

    func folder(_ id: String) -> MTChatFolder? { folders.first { f in f.id == id } }
    func folder(only kind: MTChatFolder.Kind) -> MTChatFolder? { folders.first { f in f.onlyKind == kind } }
    func put(_ f: MTChatFolder) {
        if let i = folders.firstIndex(where: { o in o.id == f.id }) { folders[i] = f } else { folders.append(f) }
        save()
    }
    func remove(_ id: String) {
        guard id != MTChatFolder.allID else { return }
        folders.removeAll { f in f.id == id }
        save()
    }
    func move(from: IndexSet, to: Int) {
        folders.move(fromOffsets: from, toOffset: to)
        save()
    }
    private func save() {
        guard let d = try? JSONEncoder().encode(folders), let s = String(data: d, encoding: .utf8) else { return }
        _ = MontanaLocalVault.setString(Self.key, s)
    }

    /// The address book is read only while a folder tells the contacts from the rest: the first folders take both.
    var tellsContacts: Bool { folders.contains { f in f.kinds.contains(.contacts) != f.kinds.contains(.nonContacts) } }
    static func contactRefs() -> Set<String> {
        let raw = MontanaLocalVault.getString("mtContacts") ?? ""
        let book = (try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: Data(raw.utf8))) ?? []
        return Set(book.map { c in c.ref })
    }
    /// What a conversation is to the folders -- one answer for the tabs, their badges and the folders' page.
    static func kind(of c: Chat, contacts: Set<String>?) -> MTChatFolder.Kind {
        if c.name == MTBot.row { return .bots }
        if MTGroup.isKey(c.name) { return MTGroup.shared.kind(c.name) == .channel ? .channels : .groups }
        return contacts?.contains(c.convRef) == true ? .contacts : .nonContacts
    }
    /// A folder's rows in the chats' one order: the rows of the list, and the archived ones where the folder keeps them.
    func rows(of f: MTChatFolder, live: [Chat], archived: [Chat], store: ChatStore, contacts: Set<String>?) -> [Chat] {
        if f.isAll { return live }
        let keep: (Chat, Bool) -> Bool = { c, gone in
            f.takes(c, kind: Self.kind(of: c, contacts: contacts), muted: store.mutedChats.contains(c.name),
                    unread: store.hasUnread(c.name), archived: gone)
        }
        let here = live.filter { c in keep(c, false) }
        return f.leaves.contains(.archived) ? here : here + archived.filter { c in keep(c, true) }
    }
    /// A tab's badge: the folder's unread conversations, and whether one of them is not muted -- the badge's blue.
    static func badge(_ rows: [Chat], store: ChatStore) -> (count: Int, loud: Bool) {
        var count = 0
        var loud = false
        for c in rows where store.hasUnread(c.name) {
            count += 1
            if !store.mutedChats.contains(c.name) { loud = true }
        }
        return (count, loud)
    }
}

/// OUR BOT (the author's word 17.10.2026 15:4x UTC: «a category Bots, and our bot there»): Montana's bot, the door to the wallet
/// and to Montana as its Mini App. A row of the Bots folder and of All Chats; a tap opens the bot where it lives -- it speaks no letter
/// here and keeps no conversation on this phone.
enum MTBot {
    static let row = "bot:MTBusiness_bot"
    static let name = "MTBusiness_bot"   // the name the bot claimed where it lives
    static let link = "https://t.me/MTBusiness_bot"
    static var chat: Chat { Chat(name: row, lastMessage: "", time: "", unread: 0) }
    static var model: ChatRowModel {
        ChatRowModel(ref: row, color: .blue, title: name, face: montanaRoomFace, initial: "M", local: false, montana: false,
                     presenceActive: false, selfFace: 0, selfGlyph: "", muted: false, blocked: false, status: nil, time: "",
                     draft: nil, reaction: nil, reactionMine: false, mediaKind: nil, mediaFile: nil, mediaMine: false, picture: -1,
                     preview: String(localized: "bot", bundle: MTLanguage.bundle), forced: false, unread: 0, pinned: false)
    }
    static func open() {
        guard let u = URL(string: link) else { return }
        UIApplication.shared.open(u)
    }
}

/// THE FOLDERS' TABS, the reference's strip: one glass capsule the page's width, the names from its left edge with the reference's
/// measures (44 points high, 26 between two names, 14 from the edge, the chosen name on a 36-point lens that slides to the next),
/// each name followed by its badge; All Chats says All when the names do not fit, and then the strip scrolls under the finger. A
/// hold on a tab is the platform's menu of that folder.
struct MTFolderTabs: View {
    struct Tab: Identifiable, Equatable {
        let id: String
        let title: String
        let short: String
        let unread: Int
        let loud: Bool
    }
    let tabs: [Tab]
    let chosen: String
    let pick: (String) -> Void
    let menu: (String) -> AnyView
    @Namespace private var lens
    private static let font = UIFont.systemFont(ofSize: 14, weight: .medium)
    private static let countFont = UIFont.systemFont(ofSize: 14)

    var body: some View {
        GeometryReader { geo in
            let short = geo.size.width < Self.width(tabs, short: false)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tabs) { t in tab(t, short: short) }
                    }
                    .padding(.horizontal, 4)
                    .frame(minWidth: geo.size.width, minHeight: 44, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onAppear { proxy.scrollTo(chosen, anchor: .center) }
                .onChange(of: chosen) { _, id in
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .frame(height: 44)
        .montanaOctagonFace(bar: true)   // the time panel's own plate (the author's word 18.10.2026 07:2x UTC)
    }

    /// The strip's width with every name whole, by the platform's own measure of the words.
    static func width(_ tabs: [Tab], short: Bool) -> CGFloat {
        var sum: CGFloat = 8
        for t in tabs {
            let words = (short ? t.short : t.title) as NSString
            var inner = ceil(words.size(withAttributes: [.font: font]).width)
            if 0 < t.unread {
                let digits = String(t.unread) as NSString
                inner += 4 + max(18, ceil(digits.size(withAttributes: [.font: countFont]).width) + 8)
            }
            sum += max(44, inner + 20)
        }
        return sum + CGFloat(max(0, tabs.count - 1)) * 6
    }

    private func tab(_ t: Tab, short: Bool) -> some View {
        let on = t.id == chosen
        return Button { pick(t.id) } label: {
            HStack(spacing: 4) {
                Text(short ? t.short : t.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize()
                if 0 < t.unread {
                    Text("\(t.unread)")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 4)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(t.loud || on ? Color.blue : Color(uiColor: .systemGray)))
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 36)
            .background {
                if on {
                    MTBarPuck().matchedGeometryEffect(id: "lens", in: lens)   // the time panel's own puck under the chosen name
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(t.id)
        .contextMenu { menu(t.id) }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// THE FOLDERS' PAGE, the reference's own on the platform's list: what folders are for, the way to a new one, the folders with the
/// count of their chats (All Chats among them, never taken away), the folders the reference recommends. The pencil turns the list to
/// its editing -- the order by the handles, a folder away by the minus -- and the checkmark ends it.
struct MTFolderSettingsPage: View {
    @EnvironmentObject private var store: ChatStore
    @ObservedObject private var book = MTChatFolders.shared
    @State private var editing: EditMode = .inactive
    @State private var editor: MTChatFolder?
    @State private var addChatsAtOnce = false

    private struct Suggestion: Identifiable {
        let id: String
        let folder: MTChatFolder
        let title: String
        let words: String
    }
    /// What the reference recommends and the person has not got yet: the unread, the personal chats, and each first folder taken away.
    private var suggestions: [Suggestion] {
        let all: [MTChatFolder.Kind] = MTChatFolder.Kind.allCases
        let offered = [
            Suggestion(id: "unread", folder: MTChatFolder(id: "", kinds: all, leaves: [.read, .archived]),
                       title: String(localized: "Unread", bundle: MTLanguage.bundle),
                       words: String(localized: "New messages from all chats.", bundle: MTLanguage.bundle)),
            Suggestion(id: "personal", folder: MTChatFolder(id: "", kinds: [.contacts, .nonContacts]),
                       title: String(localized: "Personal", bundle: MTLanguage.bundle),
                       words: String(localized: "Only messages from personal chats.", bundle: MTLanguage.bundle)),
            Suggestion(id: "groups", folder: MTChatFolder(id: "", preset: .groups, kinds: [.groups]),
                       title: String(localized: "Groups", bundle: MTLanguage.bundle),
                       words: String(localized: "Only messages from groups.", bundle: MTLanguage.bundle)),
            Suggestion(id: "channels", folder: MTChatFolder(id: "", preset: .channels, kinds: [.channels]),
                       title: String(localized: "Channels", bundle: MTLanguage.bundle),
                       words: String(localized: "Only messages from channels.", bundle: MTLanguage.bundle)),
            Suggestion(id: "bots", folder: MTChatFolder(id: "", preset: .bots, kinds: [.bots]),
                       title: String(localized: "Bots", bundle: MTLanguage.bundle),
                       words: String(localized: "Only messages from bots.", bundle: MTLanguage.bundle))]
        return offered.filter { s in !book.folders.contains { f in f.holdsAlike(s.folder) } }
    }
    private var contacts: Set<String>? { book.tellsContacts ? MTChatFolders.contactRefs() : nil }

    var body: some View {
        let live = MTFolderChatPicker.pool(store)
        let known = contacts
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.primary)
                    Text("Create folders for different groups of chats and quickly switch between them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)
            Section {
                Button { open(MTChatFolder(id: UUID().uuidString), addChats: false) } label: {
                    Text("Create a Folder").foregroundColor(.blue)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .deleteDisabled(true)
                .moveDisabled(true)
                ForEach(book.folders) { f in
                    folderRow(f, count: f.isAll ? 0 : book.rows(of: f, live: live, archived: [], store: store, contacts: known).count)
                        .deleteDisabled(f.isAll)
                }
                .onMove { from, to in book.move(from: from, to: to) }
                .onDelete { at in
                    let ids = at.map { i in book.folders[i].id }
                    for id in ids { book.remove(id) }
                }
            } header: {
                Text("Folders")
            } footer: {
                Text("Tap the pencil to change the order or delete folders.")
            }
            .listRowBackground(MTGlassRowPlate())
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { s in suggestionRow(s) }
                } header: {
                    Text("Recommended Folders")
                }
                .listRowBackground(MTGlassRowPlate())
            }
        }
        .environment(\.editMode, $editing)
        .scrollContentBackground(.hidden)
        .montanaPageGround()
        .navigationTitle("Folders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editing.isEditing {
                    MontanaDoneMark { withAnimation { editing = .inactive } }
                } else {
                    MontanaBarMark(glyph: "pencil", label: "Edit") { withAnimation { editing = .active } }
                }
            }
        }
        .navigationDestination(item: $editor) { f in
            MTFolderEditPage(folder: f, isNew: book.folder(f.id) == nil, addChats: addChatsAtOnce)
        }
        .onAppear { take(book.opening) }
        .onChange(of: book.opening) { _, o in take(o) }
    }

    private func open(_ f: MTChatFolder, addChats: Bool) {
        addChatsAtOnce = addChats
        editor = f
    }
    /// A tab's menu asked for this page: the folder it named, at once at its chats, or the order of the tabs.
    private func take(_ o: MTChatFolders.Opening?) {
        guard let o else { return }
        book.opening = nil
        if o.reorder { editing = .active }
        if let id = o.folder, let f = book.folder(id) { open(f, addChats: o.addChats) }
    }

    private func folderRow(_ f: MTChatFolder, count: Int) -> some View {
        Button { if !f.isAll { open(f, addChats: false) } } label: {
            HStack {
                Text(f.shownTitle).foregroundColor(.primary)
                Spacer()
                if 0 < count { Text("\(count)").foregroundColor(.secondary) }
                if !f.isAll {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func suggestionRow(_ s: Suggestion) -> some View {
        Button {
            var f = s.folder
            f.id = UUID().uuidString
            if f.preset == nil { f.title = s.title }
            withAnimation { book.put(f) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).foregroundColor(.primary)
                    Text(s.words).font(.footnote).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white, Color.blue)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(s.title))
    }
}

/// A FOLDER'S PAGE, the reference's: its name, the chats it takes -- kinds and conversations -- and the chats it leaves out -- states
/// and conversations; each line goes by the platform's swipe. The checkmark keeps it; the cross leaves it, asking first when
/// something was changed.
struct MTFolderEditPage: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var book = MTChatFolders.shared
    let original: MTChatFolder
    let isNew: Bool
    @State private var draft: MTChatFolder
    @State private var name: String
    @State private var pickingIn: Bool
    @State private var pickingOut = false
    @State private var askDiscard = false

    init(folder: MTChatFolder, isNew: Bool, addChats: Bool) {
        original = folder
        self.isNew = isNew
        _draft = State(initialValue: folder)
        _name = State(initialValue: isNew ? "" : folder.shownTitle)
        _pickingIn = State(initialValue: addChats)
    }
    private var typed: String { name.trimmingCharacters(in: .whitespaces) }
    private var changed: Bool { draft != original || typed != (isNew ? "" : original.shownTitle) }
    private var canKeep: Bool { !typed.isEmpty && draft.takesAnything }

    var body: some View {
        let pool = MTFolderChatPicker.pool(store)
        List {
            Section {
                TextField("Folder Name", text: $name)
                    .frame(minHeight: 44)
            } header: {
                Text("Folder Name")
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                Button { pickingIn = true } label: { addLine("Add Chats", glyph: "plus.circle.fill") }
                    .buttonStyle(.plain)
                ForEach(draft.kinds, id: \.self) { k in kindLine(k.glyph, k.tint, k.title) }
                    .onDelete { at in draft.kinds.remove(atOffsets: at) }
                ForEach(draft.chats, id: \.self) { n in chatLine(n, pool: pool) }
                    .onDelete { at in draft.chats.remove(atOffsets: at) }
            } header: {
                Text("Included Chats")
            } footer: {
                Text("Choose chats and types of chats that will appear in this folder.")
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                Button { pickingOut = true } label: { addLine("Add Chats to Exclude", glyph: "minus.circle.fill") }
                    .buttonStyle(.plain)
                ForEach(draft.leaves, id: \.self) { l in kindLine(l.glyph, l.tint, l.title) }
                    .onDelete { at in draft.leaves.remove(atOffsets: at) }
                ForEach(draft.excluded, id: \.self) { n in chatLine(n, pool: pool) }
                    .onDelete { at in draft.excluded.remove(atOffsets: at) }
            } header: {
                Text("Excluded Chats")
            } footer: {
                Text("Choose chats and types of chats that will never appear in this folder.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()
        .navigationTitle(isNew ? Text("New Folder") : Text("Edit Folder"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                MontanaCloseMark { if changed { askDiscard = true } else { dismiss() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                MontanaDoneMark { keep() }
                    .disabled(!canKeep)
                    .opacity(canKeep ? 1 : 0.4)
            }
        }
        .alert("You have changed the filter. Discard changes?", isPresented: $askDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $pickingIn) { MTFolderChatPicker(taking: true, folder: $draft) }
        .sheet(isPresented: $pickingOut) { MTFolderChatPicker(taking: false, folder: $draft) }
    }

    private func keep() {
        var f = draft
        // A first folder keeps following the person's language while its name is the one it was given.
        if !isNew, original.title.isEmpty, typed == original.shownTitle {
            f.title = ""
        } else {
            f.title = typed
            f.preset = nil
        }
        book.put(f)
        dismiss()
    }

    private func addLine(_ title: LocalizedStringKey, glyph: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 22))
                .foregroundStyle(.white, Color.blue)
                .frame(width: 32, height: 32)
            Text(title).foregroundColor(.blue)
            Spacer()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func kindLine(_ glyph: String, _ tint: Color, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(tint, in: Circle())
            Text(title).foregroundColor(.primary)
        }
        .frame(minHeight: 44)
    }

    private func chatLine(_ n: String, pool: [Chat]) -> some View {
        let c = pool.first { c in c.name == n } ?? Chat(name: n, lastMessage: "", time: "", unread: 0)
        return HStack(spacing: 12) {
            MTFolderChatPicker.face(c, side: 32)
            Text(MTFolderChatPicker.title(c, store: store)).foregroundColor(.primary).lineLimit(1)
        }
        .frame(minHeight: 44)
    }
}

/// THE CHATS OF A FOLDER, CHOSEN (the reference's own): the kinds first -- or the states, for the chats left out -- then every
/// conversation, each a line with the platform's tick; the checkmark returns to the folder.
struct MTFolderChatPicker: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let taking: Bool
    @Binding var folder: MTChatFolder
    @State private var query = ""

    /// Every conversation a folder can name: the list's own, and our bot.
    static func pool(_ store: ChatStore) -> [Chat] { store.listChats() + [MTBot.chat] }
    static func title(_ c: Chat, store: ChatStore) -> String {
        c.name == MTBot.row ? MTBot.name : MontanaAvatar.spokenName(store.title(for: c))
    }
    @ViewBuilder static func face(_ c: Chat, side: CGFloat) -> some View {
        if c.name == MTBot.row {
            MTChatFace(face: montanaRoomFace, color: .blue, initial: "M", local: false, size: side)
        } else {
            MTChatAvatar(chat: c, size: side)
        }
    }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let shown = Self.pool(store).filter { c in q.isEmpty || Self.title(c, store: store).localizedCaseInsensitiveContains(q) }
        NavigationStack {
            List {
                if q.isEmpty {
                    Section {
                        if taking {
                            ForEach(MTChatFolder.Kind.allCases, id: \.self) { k in
                                Button { flip(kind: k) } label: { typeLine(k.glyph, k.tint, k.title, on: folder.kinds.contains(k)) }
                                    .buttonStyle(.plain)
                            }
                        } else {
                            ForEach(MTChatFolder.Leave.allCases, id: \.self) { l in
                                Button { flip(leave: l) } label: { typeLine(l.glyph, l.tint, l.title, on: folder.leaves.contains(l)) }
                                    .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Chat Types")
                    }
                    .listRowBackground(MTGlassRowPlate())
                }
                Section {
                    ForEach(shown) { c in
                        let on = taking ? folder.chats.contains(c.name) : folder.excluded.contains(c.name)
                        Button { flip(chat: c.name) } label: {
                            HStack(spacing: 12) {
                                Self.face(c, side: 40)
                                Text(Self.title(c, store: store)).foregroundColor(.primary).lineLimit(1)
                                Spacer()
                                tick(on)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Chats")
                }
                .listRowBackground(MTGlassRowPlate())
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .scrollContentBackground(.hidden)
            .montanaPageGround()
            .navigationTitle(taking ? Text("Include Chats") : Text("Exclude Chats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { MontanaDoneMark { dismiss() } }
            }
        }
    }

    private func tick(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(on ? Color.white : Color.secondary)
    }
    private func typeLine(_ glyph: String, _ tint: Color, _ title: String, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(tint, in: Circle())
            Text(title).foregroundColor(.primary)
            Spacer()
            tick(on)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    private func flip(kind k: MTChatFolder.Kind) {
        if let i = folder.kinds.firstIndex(of: k) { folder.kinds.remove(at: i) } else { folder.kinds.append(k) }
    }
    private func flip(leave l: MTChatFolder.Leave) {
        if let i = folder.leaves.firstIndex(of: l) { folder.leaves.remove(at: i) } else { folder.leaves.append(l) }
    }
    private func flip(chat n: String) {
        if taking {
            folder.excluded.removeAll { e in e == n }
            if let i = folder.chats.firstIndex(of: n) { folder.chats.remove(at: i) } else { folder.chats.append(n) }
        } else {
            folder.chats.removeAll { e in e == n }
            if let i = folder.excluded.firstIndex(of: n) { folder.excluded.remove(at: i) } else { folder.excluded.append(n) }
        }
    }
}
