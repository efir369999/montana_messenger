import SwiftUI
import PhotosUI

/// THE CHANNEL IS BORN IN THREE STEPS (the author's words 05.10.2026 16:0x UTC: «3. Channel -- see the mechanics in the reference
/// tree»; 16:1x «real delivery to a channel from the phone»): what a channel is, then its face, name and description, then the
/// subscribers, each chosen by a tick. A channel is a group whose owner alone posts; its posts ride the pipe of each subscriber
/// from this phone, so only a person this phone holds a pipe with can subscribe (MTGroupPickStep.reachable).
struct MTChannelIntroStep: View {
    @Environment(\.dismiss) private var dismiss
    var onCreate: (String, String, Data, [Chat]) -> Void
    @State private var naming = false

    var body: some View {
        NavigationStack {
            // THE REFERENCE'S INTRODUCTION (the author's words 17.10.2026 15:4x UTC: «1 to 1»): the picture, «What is a Channel?», its
            // one sentence, and «Create Channel» at the foot.
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "megaphone.fill").font(.system(size: 64)).foregroundColor(.primary)
                Text("What is a Channel?").font(.title2.bold())
                Text("Channels are a new tool for broadcasting your messages to large audiences.")
                    .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)
                Spacer()
                Spacer()
                Button { naming = true } label: {
                    Text("Create Channel").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent).tint(.blue)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
            .montanaPageGround()
            .navigationTitle("New Channel").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } }
            }
            .navigationDestination(isPresented: $naming) {
                MTChannelInfoStep { title, about, face, subscribers in
                    onCreate(title, about, face, subscribers)
                    dismiss()
                }
            }
        }
    }
}

/// The second step: the channel's face, name and description.
struct MTChannelInfoStep: View {
    var onCreate: (String, String, Data, [Chat]) -> Void
    @State private var name = ""
    @State private var about = ""
    @State private var face = Data()
    @State private var choosing = false
    @FocusState private var typing: Bool

    private var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    MTFacePicker(face: $face)
                    TextField("Channel Name", text: $name).focused($typing)
                }
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                TextField("Description (Optional)", text: $about, axis: .vertical).lineLimit(1...6)
            } footer: {
                Text("You can provide an optional description for your channel.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("New Channel").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                MontanaDoneMark { choosing = true }.disabled(title.isEmpty).opacity(title.isEmpty ? 0.4 : 1)
            }
        }
        .onAppear { typing = true }
        .navigationDestination(isPresented: $choosing) {
            MTChannelSubscribersStep { subscribers in
                onCreate(title, about.trimmingCharacters(in: .whitespacesAndNewlines), face, subscribers)
            }
        }
    }
}

/// The third step: the subscribers, each chosen by a tick among the people this phone holds a pipe with.
struct MTChannelSubscribersStep: View {
    @EnvironmentObject private var store: ChatStore
    var onCreate: ([Chat]) -> Void
    @State private var chosen: [String] = []
    @State private var query = ""

    private var people: [Chat] { MTGroupPickStep.reachable(store) }
    private var shown: [Chat] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? people : people.filter { store.title(for: $0).localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            Section {
                ForEach(shown) { c in
                    Button { toggle(c.convRef) } label: { MTPickRow(chat: c, on: chosen.contains(c.convRef)) }
                }
            } footer: {
                Text("A post rides the pipe of each person, so only the people you write with are listed.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Add Subscribers").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                MontanaDoneMark { onCreate(chosen.compactMap { ref in people.first { $0.convRef == ref } }) }
            }
        }
    }

    private func toggle(_ ref: String) {
        if let i = chosen.firstIndex(of: ref) { chosen.remove(at: i) } else { chosen.append(ref) }
    }
}

/// A person in a list of choice -- the face, the name, the tick; the whole row is the target, not only its words (22.09).
struct MTPickRow: View {
    @EnvironmentObject private var store: ChatStore
    let chat: Chat
    let on: Bool

    var body: some View {
        HStack(spacing: 12) {
            MTChatAvatar(chat: chat, size: 40)
            Text(verbatim: store.title(for: chat)).foregroundColor(.primary)   // USER-DATA: a person's name
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(on ? .white : .secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The face of a group or a channel: the platform's photo picker in a circle, the picture brought to the avatar's size.
struct MTFacePicker: View {
    @Binding var face: Data
    @State private var pick: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pick, matching: .images) {
            Group {
                if let ui = UIImage(data: face) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    Circle().fill(Color(.tertiarySystemFill))
                        .overlay(Image(systemName: "camera.fill").font(.title3).foregroundColor(.primary))
                }
            }
            .frame(width: 60, height: 60).clipShape(Circle())
        }
        .onChange(of: pick) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    face = ui.avatarResized(1080).jpegData(compressionQuality: 0.85) ?? data
                }
            }
        }
    }
}

// ════════════════════════════════════════════════════════════
// A CHANNEL'S FEED, AS THE REFERENCE DRAWS IT
// ════════════════════════════════════════════════════════════
//
// The author's words 17.10.2026 15:4x UTC: «channels and groups entirely as in the reference folder, 1 to 1», «and the posts too,
// everything exactly as there», «we do not need our own kinds of pages inside groups and channels». A channel is a chat's feed:
// its posts stand one under another as letters do, every post drawn as one received -- the owner's own included -- with the
// channel's name at the head of a run, the eye and its number in the stamp and a round beside it that hands the post on.

/// How a channel's post is drawn (MessageBubble.post): a value the bubble compares and the feed hashes, so a moved number redraws the row.
struct MTChannelPostLook: Hashable {
    /// The channel's name over the words at the head of a run; nil inside a run.
    var head: String?
    /// The name's colour: the same on every phone, from the channel's key.
    var tint: Color
    /// How many people saw the post, as its owner counted them (MTChannelViews).
    var views: Int
    /// Its writer's name, before the time, where the channel signs its posts (the reference's «Sign Messages»).
    var signature: String? = nil
    /// The comments under it where the channel takes comments (the reference's footer «Leave a Comment» / «N Comments»); nil -- none.
    var comments: Int? = nil
    /// The reference's short count: «999», «1.2K», «3M» -- the tenth shown only where it is not a zero.
    static func count(_ n: Int) -> String {
        let dot = Locale.current.decimalSeparator ?? "."
        func short(_ unit: Int, _ mark: String) -> String {
            let tenth = (n % unit) / (unit / 10)
            return String(n / unit) + (tenth == 0 ? "" : dot + String(tenth)) + mark
        }
        if 1_000_000 <= n { return short(1_000_000, "M") }
        if 1_000 <= n { return short(1_000, "K") }
        return String(n)
    }
}

/// THE EYE UNDER A CHANNEL'S POST (the reference's view counter: a post is born with one view, its author's, and every person
/// whose screen showed it adds one). No server counts. A subscriber's phone tells the owner which posts its screen showed
/// (MTGroup.tellSeen); the owner counts each subscriber's seat once per post and carries the numbers that moved to every
/// subscriber (MTGroup.tellCounts). The number is people, never openings: a seat is counted once, and a number only grows.
final class MTChannelViews: ObservableObject {
    static let shared = MTChannelViews()
    static let storeKey = "channels.views"
    /// [I-14]: the newest posts a channel keeps numbers for, and the posts a subscriber remembers having told.
    static let postsKept = 400
    static let saidKept = 1_000
    /// Moves when a number shown moves: the open channel's feed reads its rows again.
    @Published private(set) var rev = 0
    private struct Book: Codable {
        /// The owner's: a channel's post and the seats that showed it.
        var seen: [String: [String: [String]]] = [:]
        /// A subscriber's: a channel's post and the number its owner told.
        var told: [String: [String: Int]] = [:]
        /// A subscriber's: the posts already told as shown.
        var said: [String: [String]] = [:]
    }
    private var book = Book()
    private var waiting: [String: Set<String>] = [:]
    private var moved: [String: Set<String>] = [:]
    private var telling = false
    private var counting = false

    private init() {
        load()
        NotificationCenter.default.addObserver(forName: .montanaSeedForgotten, object: nil, queue: .main) { [weak self] _ in
            self?.load()   // another person's channels are not this one's
        }
    }
    /// The store was laid again under the living (a copy, a seat lifted): the numbers are read from it.
    func reread() { load() }
    private func load() {
        book = MontanaLocalVault.getDecrypted(Self.storeKey).flatMap { try? JSONDecoder().decode(Book.self, from: $0) } ?? Book()
        waiting = [:]
        moved = [:]
    }
    private func save() {
        guard let d = try? JSONEncoder().encode(book) else { return }
        MontanaLocalVault.setEncrypted(Self.storeKey, d)
    }
    /// A post's one name without its wire head: the same on the owner's phone and on every subscriber's.
    static func letter(_ m: Message) -> String? {
        let bare = m.mid.hasPrefix("mid:") ? String(m.mid.dropFirst(4)) : m.mid
        return MTGroup.isLetterName(bare) ? bare : nil
    }
    private static func trimmed<V>(_ page: [String: V]) -> [String: V] {
        guard postsKept < page.count else { return page }
        var out = page
        for old in page.keys.sorted().prefix(page.count - postsKept) { out[old] = nil }   // a name begins with its birth moment
        return out
    }

    /// The number under a post: on the owner's phone its own count -- one, the author, and every seat that showed it; on a
    /// subscriber's phone what the owner told, one until it is told.
    func views(_ m: Message, in key: String) -> Int {
        guard let l = Self.letter(m) else { return 1 }
        if MTGroup.shared.state(key)?.mine == true { return 1 + (book.seen[key]?[l]?.count ?? 0) }
        return max(1, book.told[key]?[l] ?? 1)
    }

    /// A post stood on this subscriber's screen (its row appeared in the feed): told to the owner once, a moment later together
    /// with the others that appeared. «I saw your words» is a read receipt: with the person's «Read receipts» off nothing is told
    /// and nothing is kept to tell later (the critic's K-1, 17.10.2026).
    @MainActor
    func shown(_ m: Message, in key: String) {
        guard ChatStore.readReceiptsOn, !m.isFromMe, let g = MTGroup.shared.state(key), g.kind == .channel, !g.mine, g.left != true,
              let l = Self.letter(m), book.said[key]?.contains(l) != true else { return }
        waiting[key, default: []].insert(l)
        guard !telling else { return }
        telling = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.tell()
        }
    }
    @MainActor
    private func tell() {
        telling = false
        guard ChatStore.readReceiptsOn else { waiting = [:]; return }   // turned off while they waited: they are let go untold
        var told = false
        for (key, letters) in waiting {
            let list = Array(letters).sorted()
            guard MTGroup.shared.tellSeen(list, in: key) else { continue }   // no pipe to the owner now: they wait for the next post shown
            var said = (book.said[key] ?? []) + list
            if Self.saidKept < said.count { said.removeFirst(said.count - Self.saidKept) }
            book.said[key] = said
            waiting[key] = nil
            told = true
        }
        if told { save() }
    }

    /// A subscriber's seat showed these posts of mine (their «vw»): each seat counted once; the numbers that moved leave to every
    /// subscriber a few seconds later, in one word.
    @MainActor
    func saw(_ letters: [String], by seat: String, in key: String) {
        var page = book.seen[key] ?? [:]
        var grew = false
        for l in letters {
            var seats = page[l] ?? []
            guard !seats.contains(seat), seats.count < MTGroup.peopleLimit else { continue }
            seats.append(seat)
            page[l] = seats
            moved[key, default: []].insert(l)
            grew = true
        }
        guard grew else { return }
        book.seen[key] = Self.trimmed(page)
        save()
        rev += 1
        guard !counting else { return }
        counting = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.count()
        }
    }
    @MainActor
    private func count() {
        counting = false
        for (key, letters) in moved {
            let page = book.seen[key] ?? [:]
            var numbers: [String: Int] = [:]
            for l in letters.sorted().suffix(MTGroup.viewsBatch) { numbers[l] = 1 + (page[l]?.count ?? 0) }
            MTGroup.shared.tellCounts(numbers, in: key)
        }
        moved = [:]
    }
    /// The owner told the numbers (their «vc»): a number only grows, so a word that came late changes nothing.
    @MainActor
    func told(_ numbers: [String: Int], in key: String) {
        var page = book.told[key] ?? [:]
        var grew = false
        for (l, n) in numbers where (page[l] ?? 0) < n {
            page[l] = min(n, MTGroup.peopleLimit + 1)
            grew = true
        }
        guard grew else { return }
        book.told[key] = Self.trimmed(page)
        save()
        rev += 1
    }
}

/// THE ROUND BESIDE A CHANNEL'S POST (the reference: a round of glass thirty points across beside the post, its foot at the post's
/// foot, eight points away): it hands the post on by the menu's own «Forward». The finger keeps its 44 around the 30 drawn.
struct MTChannelShareRound: View {
    let action: () -> Void
    private static let side: CGFloat = 30
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrowshape.turn.up.right.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
                .frame(width: Self.side, height: Self.side)
                .background { MTChannelGlass(shape: Circle()) }
                .frame(width: montanaTouchTarget, height: montanaTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-(montanaTouchTarget - Self.side) / 2)   // the finger keeps its 44; the row keeps the round's 30
        .padding(.bottom, 1)
        .accessibilityLabel(Text("Share"))
    }
}

/// The round stands beside a channel's post alone; every other letter is drawn as it was.
struct MTShareBeside: ViewModifier {
    let on: Bool
    let action: () -> Void
    func body(content: Content) -> some View {
        if on {
            HStack(alignment: .bottom, spacing: 8) {
                content
                MTChannelShareRound(action: action)
            }
        } else {
            content
        }
    }
}

/// The platform's glass where it has one, its thin material before.
struct MTChannelGlass<S: Shape>: View {
    let shape: S
    var body: some View {
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            MTGlassPlate(shape: shape)
        } else {
            shape.fill(MontanaOctagon.barMaterial)
        }
    }
}

/// A SUBSCRIBER'S PANEL IN THE FIELD'S PLACE (the reference's channel panel): one wide round of glass across the middle saying
/// «Mute» or «Unmute» -- the channel's sound, the same switch as the list's swipe -- and a round of glass with the magnifier on
/// the right, the chat's own search. A room as wide as the right round stands on the left, so the word stays in the middle.
struct MTChannelSubscriberBar: View {
    let muted: Bool
    let onMute: () -> Void
    let onSearch: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: montanaTouchTarget, height: montanaTouchTarget)
            Button(action: onMute) {
                Text(muted ? "Unmute" : "Mute")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.primary)
                    .frame(maxWidth: .infinity, minHeight: montanaTouchTarget)
                    .background { MTChannelGlass(shape: Capsule()) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold)).foregroundColor(.primary)
                    .frame(width: montanaTouchTarget, height: montanaTouchTarget)
                    .background { MTChannelGlass(shape: Circle()) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Search"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, MTInputField.barPad)
    }
}

/// THE CHANNEL'S OLD POSTS COME INTO ITS FEED (the critic's K-2, 17.10.2026; the author's words 17.10: «we do not need our own kinds
/// of pages inside channels»). Until 2233 a channel was a wall, and its posts lie in the wall's store on every phone -- the owner's
/// own, a subscriber's page. Each is laid once into the channel's feed on this phone alone; nothing goes to the network. Its row's
/// name is made of its moment and its wall name, the same on every phone, so a word of the channel about it -- a reaction, an
/// edit, a deletion -- finds the same row everywhere. Its words come, and its first picture or video: the file when this phone
/// holds it, else the poster the wall carried, as a picture.
enum MTChannelWallFold {
    /// The row's one name for a wall post: «t», its moment in milliseconds, «-», its wall name.
    static func name(_ p: MTBoardSeen) -> String? {
        let pid = String(p.id.filter { c in c.isASCII && (c.isLetter || c.isNumber) }.prefix(40))
        guard !pid.isEmpty, p.at.isFinite, 0 < p.at else { return nil }
        let bare = "t" + String(Int64(p.at * 1000)) + "-" + pid
        return MTGroup.isLetterName(bare) ? "mid:" + bare : nil
    }
    @MainActor
    static func fold(_ key: String, store: ChatStore) {
        guard let g = MTGroup.shared.state(key), g.kind == .channel else { return }
        let posts = MTBoard.shared.posts(on: key)
        guard !posts.isEmpty else { return }
        let held = Set((store.messages[key] ?? []).map(\.mid))
        var laid = 0
        for p in posts.sorted(by: { a, b in a.at < b.at }) {
            guard let mid = name(p), !held.contains(mid), !store.buried(mid, in: key) else { continue }
            var row = Message(text: p.text, isFromMe: g.mine, time: hhmm(at: p.at), deliveryStatus: .delivered, msgId: mid,
                              senderRef: g.mine ? nil : MTGroup.speaker(g.id, MTGroup.ownerSeat), createdAt: p.at)
            if let f = file(p) {
                if f.video { row.videoFile = f.name } else { row.imageFile = f.name }
            }
            guard !row.text.isEmpty || row.imageFile != nil || row.videoFile != nil else { continue }
            MTRowJournal.put(key, store.placeRow(key, row))
            laid += 1
        }
        guard 0 < laid else { return }
        store.noteListState(key, last: store.lastLetter(key))
        MontanaTrace.mark("channel_fold", "posts=\(laid)")
    }
    /// The post's first picture or video on this phone: the file the wall brought when it is whole here, else the poster the
    /// post carried, laid once in the store as a picture of its own name.
    private static func file(_ p: MTBoardSeen) -> (name: String, video: Bool)? {
        guard let i = p.media.firstIndex(where: { m in m.kind == "img" || m.kind == "vid" }) else { return nil }
        let m = p.media[i]
        let whole = MTBoard.fileName(p.id, i, m.ext)
        if MontanaMediaStore.exists(whole) { return (whole, m.kind == "vid") }
        guard let b64 = m.thumb, b64.count <= MTBoard.thumbLimit, let data = Data(base64Encoded: b64), UIImage(data: data) != nil else { return nil }
        let poster = "wallposter_" + p.id + "_" + String(i) + ".jpg"
        guard MontanaMediaStore.exists(poster) || MontanaMediaStore.put(poster, data: data) else { return nil }
        return (poster, false)
    }
}

/// A CHANNEL'S PAGE, AS THE REFERENCE LAYS IT (the author's words 17.10.2026 15:4x-15:5x UTC: «channels ... 1 to 1», «we do not need our
/// own kinds of pages inside channels»): the head's count and the buttons, said once here; the page (MontanaPeerInfoScreen) asks it
/// for a channel alone, as it asks MTGroupPage for a group.
enum MTChannelPage {
    /// «N subscribers» under the channel's name, the owner counted among them -- the chat's top and the page say this one line.
    static func head(_ key: String) -> String {
        String(localized: "\(MTGroup.shared.people(key) ?? 1) subscribers", bundle: MTLanguage.bundle)
    }
    /// The page's buttons, as the reference's channel page has them: the owner's live stream, the sound and the search; a subscriber's
    /// sound, search, the way out and more. A channel this phone is out of keeps the sound and the search.
    @MainActor
    static func actions(_ key: String, muted: Bool) -> [MTPeerAction] {
        let g = MTGroup.shared.state(key)
        let sound: MTPeerAction = muted ? .unmute : .mute
        if g?.canManage == true {
            return (MTGroupRoom.shared.kinds(for: key).contains(.live) ? [.liveStream] : []) + [sound, .search]
        }
        if g == nil || g?.left == true { return [sound, .search] }
        return [sound, .search, .leave, .more]
    }
}

/// THE CHANNEL'S SUBSCRIBERS (the reference's «Subscribers» page, its owner's alone): «Add Subscribers» first, then every person the
/// owner's phone carries the channel to, a hold or a swipe to take one out -- asked first, as the reference asks.
struct MTChannelPeoplePage: View {
    @EnvironmentObject private var store: ChatStore
    let key: String
    @State private var adding = false
    @State private var removing: String? = nil

    private struct Person: Identifiable { let seat: String; let name: String; var id: String { seat } }

    var body: some View {
        let gid = MTGroup.id(of: key) ?? ""
        let people = MTGroup.shared.pagePeople(key).map { Person(seat: $0.seat, name: $0.name) }
        List {
            if MTGroup.shared.manages(key) {
                Section {
                    Button { adding = true } label: {
                        Label("Add Subscribers", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: montanaTouchTarget, alignment: .leading).contentShape(Rectangle())
                    }
                }
                .listRowBackground(MTGlassRowPlate())
            }
            Section {
                ForEach(people) { p in
                    HStack(spacing: 12) {
                        MTSpeakerFace(ref: MTGroup.speaker(gid, p.seat), name: p.name, side: 40)
                        Text(verbatim: p.name).foregroundColor(.primary).lineLimit(1)   // USER-DATA: a subscriber's name
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: montanaTouchTarget)
                    .contentShape(Rectangle())
                    .swipeActions(edge: .trailing) {
                        if MTGroup.shared.manages(key) {
                            Button(role: .destructive) { removing = p.seat } label: { Label("Remove", systemImage: "person.fill.xmark") }
                        }
                    }
                    .contextMenu {
                        if MTGroup.shared.manages(key) {
                            Button(role: .destructive) { removing = p.seat } label: { Label("Remove", systemImage: "person.fill.xmark") }
                        }
                    }
                }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Subscribers").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove from the channel?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let seat = removing { MTGroup.shared.remove(key, seat: seat, store: store) }
                removing = nil
            }
        }
        .sheet(isPresented: $adding) {
            MTGroupPickStep(adding: key) { _, _, people in MTGroup.shared.add(key, people: people, store: store) }
                .environmentObject(store)
        }
    }
}

/// THE CHANNEL'S INVITE LINK, WHERE THE REFERENCE'S CHANNEL SETTINGS KEEP IT: the link, «Copy» and «Share» under it, and «Revoke Link»
/// -- a new mark that ends every link given before (MTGroup.resetInvite), asked first. Whoever opens the link meets the owner by its
/// card and asks with the mark; the owner's phone adds them as a subscriber.
struct MTChannelInviteLinksPage: View {
    let chat: String
    @State private var link: URL?
    @State private var askRevoke = false
    var body: some View {
        List {
            Section {
                if let link {
                    Text(verbatim: link.absoluteString).foregroundColor(.primary).lineLimit(1).truncationMode(.middle)   // USER-DATA: the channel's link
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
                Text("Anyone who follows this link will be able to join your channel.")
            }
            .listRowBackground(MTGlassRowPlate())
            if MTGroup.shared.manages(chat) {   // the owner alone ends the links it gave
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
        // an administrator with «Add Subscribers» hands the owner's link as the owner gave it (MTGroupState.link)
        .onAppear { link = MTGroup.shared.inviteLink(chat) ?? MTGroup.shared.state(chat)?.link.flatMap { s in URL(string: s) } }
        .confirmationDialog(Text("Are you sure you want to revoke this link? Once you do, no one will be able to join the channel using it."),
                            isPresented: $askRevoke, titleVisibility: .visible) {
            Button("Revoke", role: .destructive) {
                MTGroup.shared.resetInvite(chat)
                link = MTGroup.shared.inviteLink(chat)
            }
        }
    }
}

/// THE CHANNEL'S ADMINISTRATORS (the reference's «Administrators» page of a channel): «CHANNEL ADMINS» -- the owner first, then every
/// administrator it named, a swipe or a hold to dismiss one -- «Add Admin» from the channel's subscribers, and «Sign Messages». An
/// administrator posts into the channel and takes a post away (MTGroup: the owner carries their posts on, MTGroup.answered takes
/// their deletions); the owner alone names them, by its invitation's word, so every phone reads the same list.
struct MTChannelAdminsPage: View {
    @EnvironmentObject private var store: ChatStore
    let key: String
    @State private var picking = false
    @State private var tick = 0   // the owner's choice moved: the page reads the channel again

    private struct Person: Identifiable { let seat: String; let name: String; var id: String { seat } }

    var body: some View {
        let _ = tick
        let g = MTGroup.shared.state(key)
        let gid = g?.id ?? ""
        let owns = g?.canManage == true
        let admins = Set(g?.admins ?? [])
        let people = MTGroup.shared.pagePeople(key).map { Person(seat: $0.seat, name: $0.name) }
        let ownerName = g?.mine == true ? String(localized: "You", bundle: MTLanguage.bundle)
            : (people.first { $0.seat == MTGroup.ownerSeat }?.name ?? MTGroup.memberWord)
        List {
            Section {
                HStack(spacing: 12) {
                    MTSpeakerFace(ref: MTGroup.speaker(gid, MTGroup.ownerSeat), name: ownerName, side: 40)
                    Text(verbatim: ownerName).foregroundColor(.primary).lineLimit(1)   // USER-DATA: the owner's name
                    Spacer(minLength: 0)
                    Text("Owner").font(.subheadline).foregroundColor(.secondary)
                }
                .frame(minHeight: montanaTouchTarget)
                ForEach(people.filter { admins.contains($0.seat) }) { p in
                    NavigationLink {   // the owner opens an administrator's rights (the reference's «Admin Rights»)
                        MTChannelAdminRightsPage(key: key, seat: p.seat, name: p.name, isNew: false) { tick += 1 }
                    } label: {
                        HStack(spacing: 12) {
                            MTSpeakerFace(ref: MTGroup.speaker(gid, p.seat), name: p.name, side: 40)
                            Text(verbatim: p.name).foregroundColor(.primary).lineLimit(1)   // USER-DATA: an administrator's name
                            Spacer(minLength: 0)
                            Text("Admin").font(.subheadline).foregroundColor(.secondary)
                        }
                        .frame(minHeight: montanaTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .disabled(!owns)
                    .swipeActions(edge: .trailing) {
                        if owns { Button(role: .destructive) { set(p.seat, on: false) } label: { Text("Dismiss Admin") } }
                    }
                    .contextMenu {
                        if owns { Button(role: .destructive) { set(p.seat, on: false) } label: { Label("Dismiss Admin", systemImage: "person.badge.minus") } }
                    }
                }
                if owns {
                    Button { picking = true } label: {
                        Label("Add Admin", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: montanaTouchTarget, alignment: .leading).contentShape(Rectangle())
                    }
                }
            } header: {
                Text("CHANNEL ADMINS")
            } footer: {
                Text("You can add admins to help you manage your channel.")
            }
            .listRowBackground(MTGlassRowPlate())
            if owns {
                Section {
                    Toggle(isOn: Binding(get: { g?.signs == true }, set: { on in MTGroup.shared.setSigns(key, on: on); tick += 1 })) {
                        Text("Sign Messages")
                    }
                    .frame(minHeight: montanaTouchTarget)
                } footer: {
                    Text("Add names of the admins to the messages they post.")
                }
                .listRowBackground(MTGlassRowPlate())
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Administrators").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) {
            NavigationStack {
                List {
                    ForEach(people.filter { !admins.contains($0.seat) && $0.seat != MTGroup.ownerSeat }) { p in
                        NavigationLink {   // the rights first, then the naming (the reference's «Admin Rights» of a new admin)
                            MTChannelAdminRightsPage(key: key, seat: p.seat, name: p.name, isNew: true) { tick += 1; picking = false }
                        } label: {
                            HStack(spacing: 12) {
                                MTSpeakerFace(ref: MTGroup.speaker(gid, p.seat), name: p.name, side: 40)
                                Text(verbatim: p.name).foregroundColor(.primary).lineLimit(1)   // USER-DATA: a subscriber's name
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: montanaTouchTarget).contentShape(Rectangle())
                        }
                    }
                    .listRowBackground(MTGlassRowPlate())
                }
                .scrollContentBackground(.hidden).montanaPageGround()
                .navigationTitle("Add Admin").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { picking = false } } }
            }
            .environmentObject(store)
        }
    }

    private func set(_ seat: String, on: Bool) {
        MTGroup.shared.setAdmin(key, seat: seat, on: on, store: store)
        tick += 1
    }
}

/// THE CHANNEL'S REACTIONS (the reference's «Reactions» page of a channel): «Allow Reactions» and its caption; on, «AVAILABLE
/// REACTIONS» -- every reaction a tap in or out, every one taken while all stand chosen. Off, the post's menu on every subscriber's
/// phone stands without its strip; a list, the strip offers it alone; the owner takes nothing else (MTGroup.answered).
struct MTChannelReactionsPage: View {
    let key: String
    @State private var on = true
    @State private var chosen: Set<String> = []
    /// The reactions the owner chooses among: the common ones first, then the emoji panel's own, each once.
    static var choice: [String] {
        var seen = Set<String>()
        return Array((MTReactions.common + emojiCategories.flatMap(\.emojis)).filter { e in seen.insert(e).inserted }.prefix(MTGroup.reactListLimit))
    }
    var body: some View {
        let all = Self.choice
        List {
            Section {
                Toggle(isOn: Binding(get: { on }, set: { v in on = v; MTGroup.shared.setReactions(key, on: v) })) {
                    Text("Allow Reactions")
                }
                .frame(minHeight: montanaTouchTarget)
            } footer: {
                Text("Allow subscribers to react to channel posts.")
            }
            .listRowBackground(MTGlassRowPlate())
            if on {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(all, id: \.self) { e in
                            Button { flip(e, all) } label: {
                                Text(e).font(.system(size: 28))
                                    .frame(width: montanaTouchTarget, height: montanaTouchTarget)
                                    .opacity(chosen.contains(e) ? 1 : 0.3)
                                    .overlay(alignment: .bottomTrailing) {
                                        if chosen.contains(e) {
                                            Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(.white)
                                        }
                                    }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: e))   // USER-DATA: a reaction's glyph
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("AVAILABLE REACTIONS")
                }
                .listRowBackground(MTGlassRowPlate())
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Reactions").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            on = MTGroup.shared.reactionsOn(key)
            chosen = Set(MTGroup.shared.reactionList(key) ?? all)
        }
    }
    /// One reaction in or out: every one chosen is the whole choice (nil), any fewer the owner's list in the choice's order.
    private func flip(_ e: String, _ all: [String]) {
        if chosen.contains(e) { chosen.remove(e) } else { chosen.insert(e) }
        guard !chosen.isEmpty else { chosen.insert(e); return }   // at least one: none at all is «Allow Reactions» off
        MTGroup.shared.setReactionList(key, chosen.count == all.count ? nil : all.filter { x in chosen.contains(x) })
    }
}

/// THE CHANNEL'S REMOVED USERS (the reference's page): every person its owner took out, who cannot come back by the invite link; a
/// swipe lets one back («Delete»), a hold adds one again («Add to Channel»).
struct MTChannelRemovedPage: View {
    @EnvironmentObject private var store: ChatStore
    let key: String
    @State private var tick = 0
    private struct Person: Identifiable { let seat: String; let name: String; let pipe: String; var id: String { seat } }
    var body: some View {
        let _ = tick
        let gid = MTGroup.id(of: key) ?? ""
        let people = MTGroup.shared.bannedPeople(key).map { Person(seat: $0.seat, name: $0.name, pipe: $0.pipe) }
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
                        } label: { Label("Add to Channel", systemImage: "person.badge.plus") }
                        Button(role: .destructive) { MTGroup.shared.unban(key, seat: p.seat); tick += 1 } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            } header: {
                Text("REMOVED USERS")
            } footer: {
                Text("Users removed from the channel by admins cannot rejoin it via invite links.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Removed Users").navigationBarTitleDisplayMode(.inline)
    }
}

/// THE CHANNEL'S RECENT ACTIONS (the reference's event log of a channel): the deeds of the last two days, the newest first, each a
/// sentence by the names known when it was done, and its moment. Its owner's phone writes them (MTGroupState.acts).
struct MTChannelActionsPage: View {
    let key: String
    static let span: Double = 48 * 3600
    var body: some View {
        let now = Date().timeIntervalSince1970
        let acts = (MTGroup.shared.state(key)?.acts ?? []).filter { a in now - a.at < Self.span }.reversed()
        List {
            if acts.isEmpty {
                VStack(spacing: 8) {
                    Text("No actions here yet").font(.headline)
                    Text("No service actions were taken by the channel's subscribers and admins in the last 48 hours.")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 36)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(Array(acts.enumerated()), id: \.offset) { _, a in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: Self.words(a)).foregroundColor(.primary)   // USER-DATA: the people's names inside the catalogue's sentence
                            Text(verbatim: Date(timeIntervalSince1970: a.at).formatted(date: .abbreviated, time: .shortened))   // USER-DATA: the deed's moment
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(MTGlassRowPlate())
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Recent Actions").navigationBarTitleDisplayMode(.inline)
    }
    /// The deed in the reference's words, its doer this phone's owner.
    static func words(_ a: MTChannelAct) -> String {
        let names = (a.p ?? []).joined(separator: ", ")
        let b = MTLanguage.bundle
        switch a.e {
        case "invited": return String(localized: "You added \(names)", bundle: b)
        case "joined": return String(localized: "\(names) joined via invite link", bundle: b)
        case "removed": return String(localized: "You removed \(names)", bundle: b)
        case "left": return String(localized: "\(names) left the channel", bundle: b)
        case "title": return String(localized: "You changed the channel name to \"\(a.t ?? "")\"", bundle: b)
        case "about": return String(localized: "You edited channel description", bundle: b)
        case "photo": return String(localized: "You changed the channel photo", bundle: b)
        case "promoted": return String(localized: "You promoted \(names)", bundle: b)
        case "demoted": return String(localized: "You demoted \(names)", bundle: b)
        case "signOn": return String(localized: "You enabled signatures", bundle: b)
        case "signOff": return String(localized: "You disabled signatures", bundle: b)
        case "reactOn": return String(localized: "You enabled all reactions", bundle: b)
        case "reactSome": return String(localized: "You updated the list of allowed reactions", bundle: b)
        case "talkOn": return String(localized: "You enabled comments", bundle: b)
        case "talkOff": return String(localized: "You disabled comments", bundle: b)
        default: return String(localized: "You disabled reactions", bundle: b)
        }
    }
}

/// ONE COMMENT UNDER A CHANNEL'S POST: its one name, its speaker's seat and the name they gave, its words, its moment.
struct MTChannelComment: Codable, Equatable, Identifiable {
    var id: String
    var seat: String
    var name: String
    var text: String
    var at: Double
    var mine: Bool
}

/// THE COMMENTS OF A CHANNEL'S POSTS ON THIS PHONE (the reference's discussion under a post): each post's comments by their one
/// names, in their order; the channel's carrier brings them (MTGroup.comment, commented). The person's own content, as letters are.
final class MTChannelComments: ObservableObject {
    static let shared = MTChannelComments()
    static let storeKey = "channels.comments"
    /// [I-14]: the comments a post keeps, and the posts a channel keeps comments for.
    static let perPost = 500
    static let postsKept = 300
    @Published private(set) var rev = 0
    private var book: [String: [String: [MTChannelComment]]] = [:]

    private init() {
        load()
        NotificationCenter.default.addObserver(forName: .montanaSeedForgotten, object: nil, queue: .main) { [weak self] _ in
            self?.load()   // another person's comments are not this one's
        }
    }
    /// The store was laid again under the living (a copy, a seat lifted): the comments are read from it.
    func reread() { load() }
    private func load() {
        book = MontanaLocalVault.getDecrypted(Self.storeKey).flatMap { try? JSONDecoder().decode([String: [String: [MTChannelComment]]].self, from: $0) } ?? [:]
        rev += 1
    }
    private func save() {
        guard let d = try? JSONEncoder().encode(book) else { return }
        MontanaLocalVault.setEncrypted(Self.storeKey, d)
    }
    func comments(on post: String, in key: String) -> [MTChannelComment] { book[key]?[post] ?? [] }
    func count(on post: String, in key: String) -> Int { book[key]?[post]?.count ?? 0 }
    func has(_ id: String, on post: String, in key: String) -> Bool { book[key]?[post]?.contains { c in c.id == id } == true }
    /// A comment comes: kept once by its name, in the order of its moment. False when it was here already.
    @discardableResult
    func put(_ c: MTChannelComment, on post: String, in key: String) -> Bool {
        var page = book[key] ?? [:]
        var list = page[post] ?? []
        guard !list.contains(where: { x in x.id == c.id }) else { return false }
        list.append(c)
        list.sort { a, b in a.at < b.at }
        if Self.perPost < list.count { list.removeFirst(list.count - Self.perPost) }
        page[post] = list
        if Self.postsKept < page.count {
            for old in page.keys.sorted().prefix(page.count - Self.postsKept) { page[old] = nil }   // a post's name begins with its birth
        }
        book[key] = page
        save()
        rev += 1
        return true
    }
}

/// THE COMMENTS OF A POST (the reference's thread of a channel's post): the post's words over the comments, each with its speaker's
/// name in the speaker's colour, and the field «Comment» at the foot where the channel takes comments.
struct MTChannelCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var board = MTChannelComments.shared
    let key: String
    let post: Message
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        let letter = MTChannelViews.letter(post) ?? ""
        let list = board.comments(on: letter, in: key)
        let gid = MTGroup.id(of: key) ?? ""
        NavigationStack {
            List {
                if !post.text.isEmpty {
                    Section {
                        Text(verbatim: MTRowLetter.words(post.text)).lineLimit(8).foregroundColor(.primary)   // USER-DATA: the post's words
                    }
                    .listRowBackground(MTGlassRowPlate())
                }
                Section {
                    if list.isEmpty {
                        Text("No comments here yet...").foregroundColor(.secondary).frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    ForEach(list) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(verbatim: c.mine ? E2E.myDisplayName() : (c.name.isEmpty ? MTGroup.memberWord : c.name))   // USER-DATA: the speaker's name
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(MTSpeakerFace.tint(MTGroup.speaker(gid, c.seat)))
                                Spacer(minLength: 0)
                                Text(verbatim: hhmm(at: c.at)).font(.caption2).foregroundColor(.secondary)   // USER-DATA: the comment's moment
                            }
                            Text(verbatim: c.text).foregroundColor(.primary)   // USER-DATA: the comment's words
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(MTGlassRowPlate())
            }
            .scrollContentBackground(.hidden).montanaPageGround()
            .navigationTitle(list.isEmpty ? Text("Comments") : Text("\(list.count) Comments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if MTGroup.shared.talks(key), !MTGroup.shared.isOut(key) { VStack(spacing: 4) {
                    // THE FIELD SAYS WHAT IS LEFT (the reference's slowmode words): one comment in thirty seconds (MTGroup.commentGap)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let wait = MTGroup.shared.commentWait(key)
                        if 0 < wait {
                            Text("Slowmode is enabled. You can send your next message in \(String(format: "0:%02d", wait)).")
                                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity).padding(.horizontal, 16)
                        }
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Comment", text: $draft, axis: .vertical)
                            .lineLimit(1...5).focused($typing)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background { MTChannelGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)) }
                        Button {
                            if MTGroup.shared.comment(draft, on: letter, in: key) { draft = "" }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundColor(.white)
                                .frame(width: montanaTouchTarget, height: montanaTouchTarget)
                        }
                        .buttonStyle(.plain)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(Text("Send"))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                } }
            }
        }
    }
}

/// THE CHANNEL'S DISCUSSION (the reference's «Discussion» of a channel's settings): «Allow Comments» -- every post then wears its
/// comments' footer on every subscriber's phone. The comments ride the channel itself; no group hosts them.
struct MTChannelDiscussionPage: View {
    let key: String
    @State private var on = false
    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { on }, set: { v in on = v; MTGroup.shared.setTalks(key, on: v) })) { Text("Allow Comments") }
                    .frame(minHeight: montanaTouchTarget)
            } footer: {
                Text("Subscribers comment under every post. The comments ride the channel itself, phone to phone.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Discussion").navigationBarTitleDisplayMode(.inline)
        .onAppear { on = MTGroup.shared.talks(key) }
    }
}

/// AN ADMINISTRATOR'S RIGHTS IN A CHANNEL (the reference's «Admin Rights»): «WHAT CAN THIS ADMIN DO?» -- the rights the owner's
/// phone carries out (MTChannelRight), each a switch; «Dismiss Admin» for one named before. Done names the administrator with the
/// rights left on; every subscriber hears it by the invitation's word.
struct MTChannelAdminRightsPage: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let key: String
    let seat: String
    let name: String
    let isNew: Bool
    var done: () -> Void = {}
    @State private var taken: Set<String> = []
    @State private var loaded = false
    var body: some View {
        List {
            Section {
                Text(verbatim: name).font(.headline).frame(minHeight: montanaTouchTarget)   // USER-DATA: a person's name
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                ForEach(MTChannelRight.allCases, id: \.self) { r in
                    Toggle(isOn: Binding(get: { !taken.contains(r.rawValue) },
                                         set: { on in if on { taken.remove(r.rawValue) } else { taken.insert(r.rawValue) } })) {
                        Text(r.title)
                    }
                    .frame(minHeight: montanaTouchTarget)
                }
            } header: {
                Text("WHAT CAN THIS ADMIN DO?")
            }
            .listRowBackground(MTGlassRowPlate())
            if !isNew {
                Section {
                    Button(role: .destructive) {
                        MTGroup.shared.setAdmin(key, seat: seat, on: false, store: store)
                        done()
                        dismiss()
                    } label: {
                        Text("Dismiss Admin").frame(maxWidth: .infinity, minHeight: montanaTouchTarget, alignment: .leading).contentShape(Rectangle())
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
                    MTGroup.shared.setAdmin(key, seat: seat, on: true, taken: taken, store: store)
                    done()
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            taken = Set(MTGroup.shared.state(key)?.adminTaken?[seat] ?? [])
        }
    }
}

/// A channel's administrator's right in the reference's words (MTChannelAdminRightsPage).
extension MTChannelRight {
    var title: LocalizedStringKey {
        switch self {
        case .info: return "Change Channel Info"
        case .post: return "Post Messages"
        case .delete: return "Delete Messages of Others"
        case .invite: return "Add Subscribers"
        }
    }
}
