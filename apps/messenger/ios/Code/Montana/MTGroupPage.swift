import SwiftUI

// ════════════════════════════════════════════════════════════
// A GROUP'S PAGE AS THE REFERENCE LAYS IT (the author's words 17.10.2026 15:4x-15:5x UTC: «channels and groups fully as in the
// reference folder, 1 to 1»; «we do not need our own kinds of pages inside groups and channels -- everything as in the reference»):
// the head's count, the people's rows and the invite link's page. The group's state and its words stay MTGroup's; this file only
// draws them, and the page (MontanaPeerInfoScreen) asks it for a group alone -- a channel keeps its own road.
// ════════════════════════════════════════════════════════════

enum MTGroupPage {
    /// «N members, M online», the reference's head of a group, said once for the chat's top and the page alike: M is this phone and
    /// whoever of the group it sees online by the one ladder (presenceWord) -- the owner's phone everyone it carries to, a member's
    /// phone the owner; nothing is said of the others. A channel says its count alone.
    @MainActor
    static func head(_ key: String, store: ChatStore) -> String {
        let n = MTGroup.shared.people(key) ?? 1
        let members = String(localized: "\(n) members", bundle: MTLanguage.bundle)
        guard MTGroup.shared.kind(key) == .group else { return members }
        let lit = 1 + MTGroup.shared.heldConversations(key).filter { c in (store.presenceWord(c)?.tier ?? 0) != 0 }.count
        guard lit != 1 else { return members }
        return members + ", " + String(localized: "\(lit) online", bundle: MTLanguage.bundle)
    }

    /// The conversation this phone holds with a pipe: the road to a person's own page and to a letter to them.
    @MainActor
    static func row(of pipe: String, store: ChatStore) -> Chat? {
        let root = MTSamePair.root(pipe)
        return store.listChats().first { c in !c.isGroup && MTSamePair.root(c.convRef) == root }
    }

    /// THE PEOPLE OF A GROUP'S PAGE, AS THE REFERENCE LISTS THEM: the owner first, the administrators after, everyone else by name,
    /// this phone among them under its own name. Each row carries what this phone may do to the person: the owner names and
    /// dismisses administrators and takes anyone out; an administrator takes out a member who is none (MTGroup.kick asks the owner).
    @MainActor
    static func lines(_ key: String, store: ChatStore, remove: @escaping (String) -> Void, open: @escaping (Chat) -> Void,
                      write: @escaping (Chat) -> Void, promote: @escaping (String) -> Void = { _ in }) -> [MTGroupMemberLine] {
        guard let g = MTGroup.shared.state(key) else { return [] }
        let owns = g.mine && g.left != true
        let iAdmin = !g.mine && g.left != true && MTGroup.adminCan(g, seat: g.me, .ban)   // «Ban Users» (G.6)
        var people = MTGroup.shared.pagePeople(key)
        people.append((seat: g.me, name: MTGroup.clean(E2E.myDisplayName(), MTGroup.nameLimit)))
        func role(_ seat: String) -> MTSpeakerHead.Role? {
            seat == MTGroup.ownerSeat ? .owner : (g.admins?.contains(seat) == true ? .admin : nil)
        }
        func rank(_ seat: String) -> Int { role(seat) == .owner ? 0 : (role(seat) == .admin ? 1 : 2) }
        let ordered = people.sorted { a, b in
            rank(a.seat) != rank(b.seat) ? rank(a.seat) < rank(b.seat) : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return ordered.map { p in
            let me = p.seat == g.me
            let ref = MTGroup.speaker(g.id, p.seat)
            let pipe = me ? nil : MTGroup.shared.speakerPipe(ref)
            let chat = pipe.flatMap { x in row(of: x, store: store) }
            let r = role(p.seat)
            let mayRemove = !me && (owns || (iAdmin && r == nil))
            var deeds: [MTMemberDeed] = []
            if let chat { deeds.append(MTMemberDeed(id: "send", title: "Send Message", icon: "message") { write(chat) }) }
            if owns, !me, g.kind == .group {
                // the admin's rights page, as the reference's «Promote» and «Edit Admin Rights» open it (G.6)
                if r == .admin {
                    deeds.append(MTMemberDeed(id: "rights", title: "Edit Admin Rights", icon: "person.badge.shield.checkmark") { promote(p.seat) })
                    deeds.append(MTMemberDeed(id: "dismiss", title: "Dismiss Admin", icon: "person.badge.minus") {
                        MTGroup.shared.setAdmin(key, seat: p.seat, on: false, store: store) })
                } else {
                    deeds.append(MTMemberDeed(id: "promote", title: "Promote to Admin", icon: "person.badge.shield.checkmark") { promote(p.seat) })
                }
            }
            if mayRemove {
                deeds.append(MTMemberDeed(id: "remove", title: "Remove from Group", icon: "person.fill.xmark", destructive: true) { remove(p.seat) })
            }
            let name = p.name.isEmpty ? MTGroup.memberWord : p.name
            return MTGroupMemberLine(seat: p.seat, name: name, me: me,
                                     face: pipe.flatMap { x in store.avatarFor(ref: x) }, tint: MTSpeakerFace.tint(ref),
                                     presence: me ? String(localized: "online", bundle: MTLanguage.bundle)
                                                  : pipe.flatMap { x in store.presenceWord(x)?.text },
                                     role: r, rank: MTGroup.shared.rank(key, seat: p.seat), deeds: deeds,
                                     remove: mayRemove ? { remove(p.seat) } : nil,
                                     open: chat.map { c in { open(c) } })
        }
    }
}

/// One person of a group's page: what the row shows and what the hand may do there.
struct MTGroupMemberLine {
    let seat: String
    let name: String
    let me: Bool
    let face: String?
    let tint: Color
    let presence: String?
    let role: MTSpeakerHead.Role?
    /// The custom title the owner gave (G.6), worn instead of the role's own word.
    let rank: String?
    let deeds: [MTMemberDeed]
    /// The swipe's «Delete»: the person taken out of the group, asked first; nil where this phone may not.
    let remove: (() -> Void)?
    /// The person's own page, where this phone holds their pipe.
    let open: (() -> Void)?
}

/// A PERSON'S ROW ON A GROUP'S PAGE, AS THE REFERENCE DRAWS IT: the face, the name, whether they are online under it, the role on a
/// capsule of its own colour at the right (owner in violet, admin in green); the row opens the person, a hold names the deeds, a swipe
/// to the left takes them out.
struct MTGroupMemberRow: View {
    let line: MTGroupMemberLine
    var body: some View {
        Button { line.open?() } label: {
            HStack(spacing: 12) {
                face
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: line.name).foregroundColor(.primary).lineLimit(1)   // USER-DATA: a person's name
                    if let p = line.presence {
                        // USER-DATA: the presence ladder's own word, already in the person's language (ChatStore.presenceWord)
                        Text(verbatim: p).font(.caption).foregroundColor(.gray).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let role = line.role {
                    (line.rank.map { t in Text(verbatim: t) } ?? Text(role.word)).font(.subheadline).foregroundColor(role.tint)   // USER-DATA: the owner's custom title
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(role.tint.opacity(0.2), in: Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 56)
            .contentShape(Rectangle())   // the whole row answers (the author's word 22.09)
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(line.deeds) { d in
                Button(role: d.destructive ? .destructive : nil, action: d.action) { Label(d.title, systemImage: d.icon) }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let r = line.remove { Button(role: .destructive, action: r) { Text("Delete") } }
        }
    }
    @ViewBuilder private var face: some View {
        if line.me {
            MTSelfFace(size: 40, initial: MontanaAvatar.initial(title: line.name, name: ""))
        } else {
            AvatarCircle(photoURL: line.face, color: line.tint, initial: MontanaAvatar.initial(title: line.name, name: line.seat), size: 40)
        }
    }
}

/// THE GROUP'S INVITE LINK, AS THE REFERENCE'S PAGE KEEPS IT (stage R.6 laid the link; the author's word 17.10.2026 moves it here
/// from the group's page): the link, «Copy» and «Share» under it, and «Revoke Link» -- a new mark that ends every link given
/// before (MTGroup.resetInvite), asked first. Whoever opens the link meets the owner by its card and asks with the mark.
struct MTGroupInviteLinksPage: View {
    let chat: String
    @State private var link: URL?
    @State private var askRevoke = false
    @State private var approval = false
    var body: some View {
        List {
            Section {
                if let link {
                    Text(verbatim: link.absoluteString).foregroundColor(.primary).lineLimit(1).truncationMode(.middle)   // USER-DATA: the group's link
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.url = link
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: { Text("Copy").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent)
                        Button { MTShare.present([link]) } label: { Text("Share").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.borderedProminent)
                    }
                    .tint(.blue)
                }
            } header: {
                Text("Invite Link")
            } footer: {
                Text("Anyone who follows this link will be able to join your group.")
            }
            .listRowBackground(MTGlassRowPlate())
            if MTGroup.shared.manages(chat) {
                // THE LINK ASKS THE OWNER FIRST (G.8): who opens it waits among the requests
                Section {
                    Toggle(isOn: Binding(get: { approval }, set: { on in approval = on; MTGroup.shared.setApproval(chat, on: on) })) {
                        Text("Request Admin Approval")
                    }
                    .frame(minHeight: 44)
                } footer: {
                    if approval { Text("New users will be able to join the group only after having been approved by the admins.") }
                    else { Text("New users will be able to join the group without being approved by the admins.") }
                }
                .listRowBackground(MTGlassRowPlate())
            }
            if MTGroup.shared.manages(chat) {   // the owner alone ends the links given before
                Section {
                    Button(role: .destructive) { askRevoke = true } label: {
                        Text("Revoke Link").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                }
                .listRowBackground(MTGlassRowPlate())
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Invite Links").navigationBarTitleDisplayMode(.inline)
        // the owner's own link, or -- to an administrator who may invite (G.6) -- the one the owner handed it
        .onAppear {
            link = MTGroup.shared.inviteLink(chat) ?? MTGroup.shared.state(chat)?.link.flatMap { s in URL(string: s) }
            approval = MTGroup.shared.state(chat)?.approval == true
        }
        .confirmationDialog(Text("Are you sure you want to revoke this link? Once you do, no one will be able to join the group using it."),
                            isPresented: $askRevoke, titleVisibility: .visible) {
            Button("Revoke", role: .destructive) {
                MTGroup.shared.resetInvite(chat)
                link = MTGroup.shared.inviteLink(chat)
            }
        }
    }
}

/// «CLEAR MESSAGES» OF A GROUP, AS THE REFERENCE ASKS IT: every letter and event of the group's feed leaves this phone alone, after the
/// platform's own question; the others keep theirs.
struct MTGroupClearAsk: ViewModifier {
    @EnvironmentObject private var store: ChatStore
    let chat: Chat
    @Binding var asked: Bool
    func body(content: Content) -> some View {
        content.confirmationDialog(Text("Are you sure you want to delete all messages in \(store.title(for: chat))?"),
                                   isPresented: $asked, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { store.deleteLocally(chat: chat.name, store.messages[chat.name] ?? []) }
        }
    }
}

/// THE LINE UNDER A GROUP'S NAME IN ITS CHAT (the reference's head): who types, while anyone does -- the green dot of the pair's own
/// «typing…» beside it -- and «N members, M online» otherwise. A view of its own, so a typing word redraws this line, never the feed.
struct MTGroupHeadLine: View {
    @EnvironmentObject private var store: ChatStore
    @ObservedObject private var typing = MTGroupTyping.shared
    let key: String
    var body: some View {
        if let t = typing.line(key) {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 9, height: 9)
                Text(verbatim: t).truncationMode(.tail)   // USER-DATA: the typing people's names inside the catalogue's sentence
            }
        } else {
            Text(verbatim: MTGroupPage.head(key, store: store))   // USER-DATA: the catalogue's count, said by MTGroupPage.head
        }
    }
}

/// «N SEEN» OVER A GROUP LETTER'S MENU (the reference's small group, the checklist's B.13): how many read a letter of mine, and a tap
/// opens their names under it; «Nobody Viewed» while none has.
struct MTSeenByRow: View {
    let names: [String]
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if !names.isEmpty { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
            } label: {
                HStack {
                    if names.isEmpty { Text("Nobody Viewed") } else { Text("\(names.count) Seen") }
                    Spacer()
                    Image(systemName: "eye").foregroundColor(.white.opacity(0.8))
                }
                .foregroundColor(.white).font(.system(size: 16))
                .padding(.horizontal, 14).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ForEach(names, id: \.self) { n in
                    Text(verbatim: n).font(.system(size: 15)).foregroundColor(.white.opacity(0.85)).lineLimit(1)   // USER-DATA: a reader's name
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

extension MTGroupRight {
    /// The permission's row, in the reference's own words.
    var title: LocalizedStringKey {
        switch self {
        case .text: return "Send Messages"
        case .photos: return "Send Photos"
        case .videos: return "Send Videos"
        case .stickers: return "Send Stickers & GIFs"
        case .music: return "Send Music"
        case .files: return "Send Files"
        case .voice: return "Send Audio Messages"
        case .rounds: return "Send Video Messages"
        case .links: return "Embed Links"
        case .reactions: return "Send Reactions"
        case .pin: return "Pin Messages"
        case .info: return "Change Group Info"
        }
    }
}

/// THE GROUP'S PERMISSIONS, AS THE REFERENCE'S PAGE KEEPS THEM (the checklist's G.5): «What can members of this group do?» -- one
/// switch a right, «Send Media» opening its own under it -- and «Slowmode» below; what the owner leaves goes to every member as the
/// page closes (MTGroup.setRights), one word for all the changes.
struct MTGroupPermissionsPage: View {
    @EnvironmentObject private var store: ChatStore
    let chat: String
    @State private var banned: Set<String> = []
    @State private var slow = 0
    @State private var mediaOpen = false
    @State private var loaded = false
    /// The reference's steps of slow mode: off, ten and thirty seconds, one, five and fifteen minutes, an hour.
    static let steps = [0, 10, 30, 60, 300, 900, 3600]
    /// «n/m», the rights left of all of them, as the editor's row says it.
    static func count(_ chat: String) -> String {
        let banned = Set(MTGroup.shared.state(chat)?.barred ?? [])
        let all = MTGroupRight.shown
        return String(all.filter { r in !banned.contains(r.rawValue) }.count) + "/" + String(all.count)
    }
    var body: some View {
        List {
            Section {
                toggle(.text)
                mediaRow
                if mediaOpen {
                    ForEach(MTGroupRight.media, id: \.self) { r in toggle(r).padding(.leading, 20) }
                }
                toggle(.pin)
                toggle(.info)
            } header: {
                Text("What can members of this group do?")
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { Double(Self.steps.firstIndex(of: slow) ?? 0) },
                                          set: { v in slow = Self.steps[max(0, min(Self.steps.count - 1, Int(v.rounded())))] }),
                           in: 0...Double(Self.steps.count - 1), step: 1)
                        .frame(minHeight: 44)
                    HStack(spacing: 0) {
                        ForEach(Self.steps, id: \.self) { s in
                            Text(Self.word(s)).font(.caption2).foregroundColor(s == slow ? .primary : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } header: {
                Text("Slowmode")
            } footer: {
                Text("Members will be restricted to send one message per this interval.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Permissions").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let g = MTGroup.shared.state(chat) else { return }
            loaded = true
            banned = Set(g.barred ?? [])
            slow = g.slow ?? 0
        }
        .onDisappear { if loaded { MTGroup.shared.setRights(chat, banned: banned, slow: slow, store: store) } }
    }
    private func toggle(_ r: MTGroupRight) -> some View {
        Toggle(isOn: Binding(get: { !banned.contains(r.rawValue) },
                             set: { on in if on { banned.remove(r.rawValue) } else { banned.insert(r.rawValue) } })) {
            Text(r.title)
        }
        .frame(minHeight: 44)
    }
    /// «Send Media» with how many of its own are left; the words open them, the switch turns them all.
    private var mediaRow: some View {
        let left = MTGroupRight.media.filter { r in !banned.contains(r.rawValue) }.count
        return HStack(spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.2)) { mediaOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("Send Media")
                    Text(verbatim: String(left) + "/" + String(MTGroupRight.media.count)).foregroundColor(.secondary)   // USER-DATA: a count
                    Image(systemName: mediaOpen ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { left == MTGroupRight.media.count },
                                     set: { on in for r in MTGroupRight.media { if on { banned.remove(r.rawValue) } else { banned.insert(r.rawValue) } } }))
                .labelsHidden()
        }
    }
    /// A step's word, by the system's own short units in the app's language; «Off» from the catalogue.
    static func word(_ s: Int) -> String {
        guard 0 < s else { return String(localized: "Off", bundle: MTLanguage.bundle) }
        let f = DateComponentsFormatter()
        var cal = Calendar.current
        cal.locale = MTLanguage.locale
        f.calendar = cal
        f.unitsStyle = .abbreviated
        f.allowedUnits = s < 60 ? [.second] : (s < 3600 ? [.minute] : [.hour])
        return f.string(from: TimeInterval(s)) ?? String(s)
    }
}

extension MTAdminRight {
    /// The admin right's row, in the reference's own words.
    var title: LocalizedStringKey {
        switch self {
        case .info: return "Change Group Info"
        case .delete: return "Delete Messages"
        case .ban: return "Ban Users"
        case .invite: return "Invite Users via Link"
        case .pin: return "Pin Messages"
        }
    }
}

/// THE GROUP'S ADMINISTRATORS, AS THE REFERENCE'S PAGE LISTS THEM (the checklist's G.6): the owner first, every administrator with
/// its custom title or its role, each opening its rights; «Add Admin» chooses among the members.
struct MTGroupAdminsPage: View {
    @EnvironmentObject private var store: ChatStore
    let chat: String
    @State private var tick = 0
    var body: some View {
        let g = MTGroup.shared.state(chat)
        let people = MTGroup.shared.pagePeople(chat)
        let admins = people.filter { p in g?.admins?.contains(p.seat) == true }
        let _ = tick
        List {
            Section {
                row(name: MTGroup.clean(E2E.myDisplayName(), MTGroup.nameLimit), seat: MTGroup.ownerSeat, owner: true)
                ForEach(admins, id: \.seat) { p in
                    NavigationLink { MTGroupAdminRightsPage(chat: chat, seat: p.seat, name: p.name, isNew: false) } label: {
                        row(name: p.name, seat: p.seat, owner: false)
                    }
                }
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                NavigationLink { MTGroupAdminPickPage(chat: chat) } label: { Label("Add Admin", systemImage: "person.badge.plus") }
            } footer: {
                Text("You can add admins to help you manage your group.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Administrators").navigationBarTitleDisplayMode(.inline)
        .onAppear { tick += 1 }   // a rights page closed: the list is read again
    }
    private func row(name: String, seat: String, owner: Bool) -> some View {
        HStack {
            Text(verbatim: name).lineLimit(1)   // USER-DATA: a person's name
            Spacer()
            if let r = MTGroup.shared.rank(chat, seat: seat) {
                Text(verbatim: r).foregroundColor(.secondary)   // USER-DATA: the owner's custom title
            } else if owner {
                Text("Owner").foregroundColor(.secondary)
            } else {
                Text("Admin").foregroundColor(.secondary)
            }
        }
        .frame(minHeight: 44)
    }
}

/// «Add Admin»: the members who are none yet, each opening the rights it would have.
struct MTGroupAdminPickPage: View {
    let chat: String
    var body: some View {
        let g = MTGroup.shared.state(chat)
        let people = MTGroup.shared.pagePeople(chat).filter { p in g?.admins?.contains(p.seat) != true && p.seat != MTGroup.ownerSeat }
        List {
            Section {
                ForEach(people, id: \.seat) { p in
                    NavigationLink { MTGroupAdminRightsPage(chat: chat, seat: p.seat, name: p.name, isNew: true) } label: {
                        Text(verbatim: p.name).lineLimit(1).frame(minHeight: 44)   // USER-DATA: a person's name
                    }
                }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Add Admin").navigationBarTitleDisplayMode(.inline)
    }
}

/// AN ADMINISTRATOR'S RIGHTS, AS THE REFERENCE'S PAGE KEEPS THEM (G.6): the custom title, «What can this admin do?» one switch a
/// right, and «Dismiss Admin»; the checkmark names or renews the administrator, carried to every member (MTGroup.setAdmin).
struct MTGroupAdminRightsPage: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let chat: String
    let seat: String
    let name: String
    let isNew: Bool
    @State private var taken: Set<String> = []
    @State private var rank = ""
    @State private var loaded = false
    var body: some View {
        List {
            Section {
                Text(verbatim: name).font(.headline).frame(minHeight: 44)   // USER-DATA: a person's name
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                TextField("admin", text: $rank).textInputAutocapitalization(.never)
            } header: {
                Text("Custom Title")
            } footer: {
                Text("A title that will be shown instead of 'admin'.")
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                ForEach(MTAdminRight.allCases, id: \.self) { r in
                    Toggle(isOn: Binding(get: { !taken.contains(r.rawValue) },
                                         set: { on in if on { taken.remove(r.rawValue) } else { taken.insert(r.rawValue) } })) {
                        Text(r.title)
                    }
                    .frame(minHeight: 44)
                }
            } header: {
                Text("What can this admin do?")
            }
            .listRowBackground(MTGlassRowPlate())
            if !isNew {
                Section {
                    Button(role: .destructive) {
                        MTGroup.shared.setAdmin(chat, seat: seat, on: false, store: store)
                        dismiss()
                    } label: {
                        Text("Dismiss Admin").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                }
                .listRowBackground(MTGlassRowPlate())
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Admin Rights").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                MontanaDoneMark {
                    MTGroup.shared.setAdmin(chat, seat: seat, on: true, taken: taken, rank: rank, store: store)
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            taken = Set(MTGroup.shared.state(chat)?.adminTaken?[seat] ?? [])
            rank = MTGroup.shared.rank(chat, seat: seat) ?? ""
        }
    }
}

/// THE GROUP'S REMOVED USERS, AS THE REFERENCE'S PAGE KEEPS THEM (the checklist's G.7): every person the owner or an administrator
/// took out, who cannot come back by the invite link; a swipe lets one back («Delete»), a hold adds one again («Add To Group»).
struct MTGroupRemovedPage: View {
    @EnvironmentObject private var store: ChatStore
    let key: String
    @State private var tick = 0
    private struct Person: Identifiable { let seat: String; let name: String; let pipe: String; var id: String { seat } }
    var body: some View {
        let _ = tick
        let gid = MTGroup.id(of: key) ?? ""
        let people = MTGroup.shared.bannedPeople(key).map { p in Person(seat: p.seat, name: p.name, pipe: p.pipe) }
        List {
            Section {
                ForEach(people) { p in
                    HStack(spacing: 12) {
                        MTSpeakerFace(ref: MTGroup.speaker(gid, p.seat), name: p.name, side: 40)
                        Text(verbatim: p.name).foregroundColor(.primary).lineLimit(1)   // USER-DATA: a removed person's name
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: montanaTouchTarget)
                    .contentShape(Rectangle())
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { MTGroup.shared.unban(key, seat: p.seat); tick += 1 } label: { Text("Delete") }
                    }
                    .contextMenu {
                        Button {
                            MTGroup.shared.add(key, people: [Chat(name: p.pipe, lastMessage: "", time: "", unread: 0, status: "", convId: p.pipe)],
                                               store: store)
                            tick += 1
                        } label: { Label("Add To Group", systemImage: "person.badge.plus") }
                        Button(role: .destructive) { MTGroup.shared.unban(key, seat: p.seat); tick += 1 } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            } header: {
                Text("REMOVED USERS")
            } footer: {
                Text("Users removed from the group by admins cannot rejoin it via invite links.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Removed Users").navigationBarTitleDisplayMode(.inline)
    }
}

/// THE GROUP'S MEMBER REQUESTS, AS THE REFERENCE'S PAGE KEEPS THEM (the checklist's G.8): who asked to join by the link while it asks
/// the owner first, the newest first -- «Add to Group» adds them by the owner's own road, «Dismiss» lets the request go.
struct MTGroupRequestsPage: View {
    @EnvironmentObject private var store: ChatStore
    let chat: String
    @State private var tick = 0
    var body: some View {
        let _ = tick
        let list = MTGroup.shared.requests(chat)
        List {
            if list.isEmpty {
                VStack(spacing: 8) {
                    Text("No Member Requests").font(.headline)
                    Text("You have no pending requests to join the group.").font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(list, id: \.pipe) { r in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AvatarCircle(photoURL: store.avatarFor(ref: r.pipe), color: MTSpeakerFace.tint(r.pipe),
                                             initial: MontanaAvatar.initial(title: r.name, name: r.pipe), size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: r.name.isEmpty ? MTGroup.memberWord : r.name).lineLimit(1)   // USER-DATA: the asker's name
                                    // USER-DATA: when they asked, by the system's own words for a moment
                                    Text(verbatim: Date(timeIntervalSince1970: r.at).formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            HStack(spacing: 10) {
                                Button { MTGroup.shared.approve(chat, pipe: r.pipe, store: store); tick += 1 } label: {
                                    Text("Add to Group").frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent).tint(.blue)
                                Button { MTGroup.shared.dismiss(chat, pipe: r.pipe); tick += 1 } label: {
                                    Text("Dismiss").frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listRowBackground(MTGlassRowPlate())
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Member Requests").navigationBarTitleDisplayMode(.inline)
    }
}

/// CHAT HISTORY FOR NEW MEMBERS, AS THE REFERENCE'S PAGE ASKS IT (the checklist's G.4): «Visible» -- one added reads the group's newest
/// words; «Hidden» -- they begin where they came in, the reference's default.
struct MTGroupHistoryPage: View {
    let chat: String
    @State private var visible = false
    var body: some View {
        List {
            Section {
                choice(true, "Visible")
                choice(false, "Hidden")
            } header: {
                Text("History for new members")
            } footer: {
                if visible { Text("New members will see messages that were sent before they joined.") }
                else { Text("New members won't see earlier messages.") }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Chat History Settings").navigationBarTitleDisplayMode(.inline)
        .onAppear { visible = MTGroup.shared.state(chat)?.history == true }
    }
    private func choice(_ on: Bool, _ title: LocalizedStringKey) -> some View {
        Button {
            visible = on
            MTGroup.shared.setHistory(chat, visible: on)
        } label: {
            HStack {
                Text(title).foregroundColor(.primary)
                Spacer()
                if visible == on { Image(systemName: "checkmark").foregroundColor(.primary) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// THE GROUP'S TYPE, AS THE REFERENCE'S PAGE SAYS IT (the checklist's G.2): a group here is private -- joined by the owner's hand or
/// by its invite link -- and the page says so in the reference's words, with the link under it. A public group is found by a search
/// of all groups, and this network keeps no list of them: no server holds one, so no switch stands that could not keep its word.
struct MTGroupTypePage: View {
    let chat: String
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Private")
                    Spacer()
                    Image(systemName: "checkmark").foregroundColor(.primary)
                }
                .frame(minHeight: 44)
            } header: {
                Text("Group Type")
            } footer: {
                Text("Private groups can only be joined if you were invited or have an invite link.")
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                NavigationLink { MTGroupInviteLinksPage(chat: chat) } label: { Label("Invite Links", systemImage: "link") }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Group Type").navigationBarTitleDisplayMode(.inline)
    }
}
