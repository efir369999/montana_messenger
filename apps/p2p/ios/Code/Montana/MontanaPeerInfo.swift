import SwiftUI
import Contacts
import PhotosUI

// ════════════════════════════════════════════════════════════
// PEER INFO — the profile of the person or the group on the other side.
//
// Four files, one prefix. This one owns the model: the kind of counterpart, the resolved data the
// screen draws, and the screen's state. MontanaPeerInfoRows owns the typed rows and their sections,
// MontanaPeerHeader the header shared with our own profile, MontanaPeerInfoScreen the screen.
// ════════════════════════════════════════════════════════════

// Which kind of counterpart is being described. Every branch of the screen asks the kind and never
// the raw fields: a saved-messages chat has no address to show and no fingerprint to compare, and
// reading that off `isGroup` alone is how "Address: Saved Messages" reached the screen.
enum MTPeerKind {
    case person
    case group
    case saved

    init(chat: Chat) {
        if chat.name == savedMessagesKey {
            self = .saved
        } else if chat.isGroup {
            self = .group
        } else {
            self = .person
        }
    }

    var showsRef: Bool { self == .person }
    var showsFingerprint: Bool { self == .person }
    var showsMembers: Bool { self == .group }
    var showsBlock: Bool { self == .person }
    var isEditable: Bool { self != .saved }
}

// ── Media panes ──────────────────────────────────────────────
// One case per pane: the title, the empty-state icon and the selection of messages live together, so
// adding a pane is one case and not four parallel switches.
enum MTMediaTab: Int, CaseIterable, Identifiable {
    case wall, media, video, files, links, music, voice   // the wall first (the author's word 24.09)

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .wall: return "Wall"
        case .media: return "Media"
        case .video: return "Video"
        case .files: return "Files"
        case .links: return "Links"
        case .music: return "Music"
        case .voice: return "Voice"
        }
    }

    /// The word for UIKit's own controls (the segmented strip), from the catalog.
    var name: String {
        switch self {
        case .wall: return String(localized: "Wall", bundle: MTLanguage.bundle)
        case .media: return String(localized: "Media", bundle: MTLanguage.bundle)
        case .video: return String(localized: "Video", bundle: MTLanguage.bundle)
        case .files: return String(localized: "Files", bundle: MTLanguage.bundle)
        case .links: return String(localized: "Links", bundle: MTLanguage.bundle)
        case .music: return String(localized: "Music", bundle: MTLanguage.bundle)
        case .voice: return String(localized: "Voice", bundle: MTLanguage.bundle)
        }
    }

    var icon: String {
        switch self {
        case .wall: return "text.below.photo"
        case .media: return "photo.on.rectangle"
        case .video: return "video.fill"
        case .files: return "doc.fill"
        case .links: return "link"
        case .music: return "music.note"
        case .voice: return "mic.fill"
        }
    }

    var emptyText: LocalizedStringKey {
        switch self {
        case .wall: return "No posts yet"
        case .media: return "Shared media will appear here"
        case .video: return "Shared video will appear here"
        case .files: return "Shared files will appear here"
        case .links: return "Shared links will appear here"
        case .music: return "Shared music will appear here"
        case .voice: return "Shared voice messages will appear here"
        }
    }

    static func isMusic(_ m: Message) -> Bool {
        guard let d = m.docFile else { return false }
        return mtIsAudioName(m.docName ?? "") || mtIsAudioName(d)
    }

    func select(from messages: [Message]) -> [Message] {
        switch self {
        case .wall: return []   // the wall is its owner's posts, not the letters (MTBoardPane)
        case .media: return messages.filter { $0.imageFile != nil }
        case .video: return messages.filter { $0.videoFile != nil }
        case .files: return messages.filter { $0.docFile != nil && !Self.isMusic($0) }
        case .links: return messages.filter { !MTLinks.urls(in: $0.text).isEmpty }
        case .music: return messages.filter { Self.isMusic($0) }
        case .voice: return messages.filter { $0.audioFile != nil }
        }
    }
}

/// The links a letter carries — found by the system detector, service words excluded (15.49) — and every Montana link.
///
/// EVERY LINK MONTANA BUILDS ANSWERS THE FINGER (the author's word 02.10 19:26: «share the chain from a post -- the link
/// arrives crooked and cannot be tapped; every link built into Montana must be tappable»). A Montana link holds no dot, so
/// the host gate below never showed it to the system's finder, and the finder's answer kept only the web's schemes: a post's
/// short link (montana://wall/@name/12) rode a letter, a comment and a post as dead words. It is found here by its own
/// scheme, up to the first space, the punctuation a sentence glues on left outside it. A game's letter is the board's card,
/// not a link (MTChessLetter.link). This is the one finder: the letter's bubble, the letter's page, a post's words, a
/// comment, a person's words about themselves and the chat's list of links all read it.
enum MTLinks {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let montana = try? NSRegularExpression(pattern: "montana://[^\\s]+", options: [.caseInsensitive])
    /// The schemes the system's finder is believed for: the web and a mail address.
    private static let webSchemes: Set<String> = ["http", "https", "mailto"]
    /// The cheap gate before the finder ([C-1], read by the letter's words and by this list alike): a
    /// letter can hold a host only if it holds a dot with a letter or a digit on either side of it,
    /// and a Montana link only if it holds the scheme.
    /// The old gate demanded «://» or «www.» and hid every bare «montana.quest» from the finder.
    static func mayHold(_ s: String) -> Bool {
        if s.range(of: "montana://", options: .caseInsensitive) != nil { return true }
        let c = Array(s)
        guard c.count >= 3 else { return false }
        for i in 1..<(c.count - 1) where c[i] == "." {
            if c[i - 1].isLetter || c[i - 1].isNumber, c[i + 1].isLetter { return true }
        }
        return false
    }
    /// THE FINDER'S ANSWER IS KEPT BY THE WORDS (28.09): a letter's bubble asks it at every pass of its body -- and every bubble
    /// in view passes at every tick of a transfer, of the player, of an answer -- so the system's detector walked every visible
    /// letter again and again (a long letter's cell stood 160-290 ms on T1's scroll of the long chat). The same words hold the same
    /// links; the answer is kept under them, in the platform's own cache, safe from any thread.
    /// One link where it lies in the words (UTF-16, as the text views count).
    struct Hit { let range: NSRange; let url: URL }
    private final class Found { let hits: [Hit]; init(_ hits: [Hit]) { self.hits = hits } }
    private static let found: NSCache<NSString, Found> = { let c = NSCache<NSString, Found>(); c.countLimit = 2048; return c }()
    /// The web's links of a letter (the chat's list of links and the bubble's gate): a letter past 20 000 bytes is not asked.
    static func urls(in text: String) -> [URL] {
        text.utf8.count < 20_000 ? hits(in: text).map { $0.url } : []
    }
    /// Every link of the words and where it lies; a long text is found anew rather than kept.
    static func hits(in text: String) -> [Hit] {
        if text.isEmpty || MontanaNotify.isService(text) { return [] }
        let key = text as NSString
        let keep = text.utf8.count < 20_000
        if keep, let kept = found.object(forKey: key) { return kept.hits }
        let out = mayHold(text) ? find(text) : []
        if keep { found.setObject(Found(out), forKey: key) }
        return out
    }
    private static func find(_ text: String) -> [Hit] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var out: [Hit] = []
        for m in montana?.matches(in: text, range: all) ?? [] {
            var r = m.range
            while r.length > 0, let last = ns.substring(with: NSRange(location: NSMaxRange(r) - 1, length: 1)).first,
                  ".,;:!?)]}>»›\"'’”…".contains(last) {
                r.length -= 1
            }
            let s = ns.substring(with: r)
            if s.lowercased().hasPrefix(MTChessLetter.link) { continue }
            if let u = URL(string: s) { out.append(Hit(range: r, url: u)) }
        }
        for m in detector?.matches(in: text, range: all) ?? [] {
            if let u = m.url, let sch = u.scheme?.lowercased(), webSchemes.contains(sch),
               !out.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) {
                out.append(Hit(range: m.range, url: u))
            }
        }
        return out.sorted { $0.range.location < $1.range.location }
    }
    /// The words with their links marked, for a platform text view (a letter, a letter's page, a post's words).
    static func marked(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let a = NSMutableAttributedString(string: text, attributes: attributes)
        for h in hits(in: text) where NSMaxRange(h.range) <= a.length {
            a.addAttribute(.link, value: h.url, range: h.range)
        }
        return a
    }
    /// The same links for SwiftUI's own text (a comment, a person's words about themselves, a code's line).
    static func linked(_ text: String, color: Color, underline: Bool = false) -> AttributedString {
        var a = AttributedString(text)
        for h in hits(in: text) {
            if let r = Range(h.range, in: text), let ar = Range(r, in: a) {
                a[ar].link = h.url
                a[ar].foregroundColor = color
                if underline { a[ar].underlineStyle = .single }
            }
        }
        return a
    }
    /// A Montana link as a person reads it: the letters of a name stand as letters, not as the bytes a URL carries
    /// (montana://wall/@%D0%9A... was the crooked link of 02.10). Any other link keeps its own spelling.
    static func readable(_ u: URL) -> String {
        guard u.scheme?.lowercased() == "montana", let words = u.absoluteString.removingPercentEncoding else { return u.absoluteString }
        return words
    }
}


// ── Header actions ───────────────────────────────────────────
// The buttons under the header as data, not as layout: what is offered comes from the kind, so
// connecting a button later changes one case and leaves the row untouched.
enum MTPeerAction: Int, CaseIterable, Identifiable {
    case message, audioCall, videoCall, more   // «More» (the author's word 22.09): the chat's wallpaper lives behind it

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .message: return "Message"
        case .audioCall: return "Voice Call"   // named as the chat's own menu names them (the author's word 18.09)
        case .videoCall: return "Video Call"
        case .more: return "More"
        }
    }

    var icon: String {
        switch self {
        case .message: return "message.fill"
        case .audioCall: return "phone.fill"
        case .videoCall: return "video.fill"
        case .more: return "ellipsis"
        }
    }

    static func available(for kind: MTPeerKind, blocked: Bool = false) -> [MTPeerAction] {
        switch kind {
        case .person: return blocked ? [.message, .more] : allCases   // a blocked person is not called
        case .group: return [.message, .more]
        case .saved: return [.message]
        }
    }
}

// ── Resolved data ────────────────────────────────────────────
// Everything the screen draws, resolved from the stores in one place. It is computed inside `body`,
// so a name, an avatar or a message arriving over the mesh redraws the profile the moment the store
// publishes it. The screen keeps no copy of any of it — the drafts of the edit mode are the only
// values it owns, and they live in MTPeerInfoState.
struct MTPeerInfoData {
    let kind: MTPeerKind
    let conv: String
    let title: String
    let initial: String
    let avatarFile: String?
    let color: Color
    let subtitle: LocalizedStringKey
    let subtitleIsActive: Bool
    let note: String
    let members: [String]
    let canEdit: Bool
    let hasFingerprint: Bool
    let messages: [Message]

    var memberCount: Int { members.count + 1 }

    func pane(_ tab: MTMediaTab) -> [Message] { tab.select(from: messages) }

    @MainActor
    static func resolve(chat: Chat, store: ChatStore, state: MTPeerInfoState) -> MTPeerInfoData {
        let kind = MTPeerKind(chat: chat)
        let conv = chat.convId ?? ""

        let title: String
        switch kind {
        case .saved:
            title = chat.title
        case .group:
            title = MTNameBook.display(conv: conv, localFirst: state.draftFirst, localLast: state.draftLast)
        case .person:
            title = MTNameBook.display(conv: conv)
        }

        let subtitle: LocalizedStringKey
        let isActive: Bool
        switch kind {
        case .group:
            subtitle = "\(MTGroup.shared.people(chat.name) ?? chat.members.count + 1) members"   // the owner's count (MTGroup)
            isActive = false
        case .saved:
            subtitle = LocalizedStringKey(chat.status)
            isActive = false
        case .person:
            // Presence is resolved live ([C-1]) — the stored string never carries it.
            let w = store.presenceWord(conv.isEmpty ? chat.name : conv)
            subtitle = LocalizedStringKey(w?.text ?? "")
            isActive = (w?.tier ?? 0) > 0
        }

        return MTPeerInfoData(
            kind: kind,
            conv: conv,
            title: title,
            initial: store.initial(for: chat),   // the one door ([C-1], 20.09)
            // Live truth on every pass (the screen's own header comment): a face arriving over
            // the wire shows up at once. The draft wins only under the author's hands.
            avatarFile: state.editing ? state.draftPhoto : store.avatarFor(chat),
            color: chat.color,
            subtitle: subtitle,
            subtitleIsActive: isActive,
            note: state.draftNote,
            // A GROUP'S PEOPLE ARE THE GROUP'S BOOK (MTGroup): its name, face and people change by the owner's word to every phone
            // (MTGroup.renew, add, remove), never on one phone alone -- so only the owner's page edits a group.
            members: kind == .group ? MTGroup.shared.shownPeople(chat.name) : state.draftMembers,
            canEdit: kind.isEditable && (kind == .person || (kind == .group && chat.isAdmin && MTGroup.shared.state(chat.name)?.mine == true)),
            hasFingerprint: kind.showsFingerprint && MontanaConv.holds(conv),
            messages: state.conversation   // read once per change (MTPeerInfoState.refreshConversation), never per pass
        )
    }

    // The conversation under every key this chat has ever been filed under, de-duplicated by message
    // id: a chat renamed from address to name keeps both keys in the store, and a pane that reads one
    // of them shows half the media.
    static func conversation(chat: Chat, store: ChatStore) -> [Message] {
        var keys = Set([chat.name, chat.name.lowercased()])
        if let s = chat.convId { keys.insert(s); keys.insert(s.lowercased()) }
        var all: [Message] = []
        for k in keys { all += store.messages[k] ?? [] }
        var seen = Set<MID>()
        return all.filter { seen.insert($0.id).inserted }.sorted(by: ChatStore.before)
    }
}

// ── Screen state ─────────────────────────────────────────────
// One type for everything the screen owns: the edit-mode drafts, the open pane, the presented sheet.
// The three flags at the bottom are seeded from stores that publish nothing, so they are held here and
// written through; everything else about the peer is resolved live and never copied.
@MainActor
final class MTPeerInfoState: ObservableObject {
    @Published var editing = false
    @Published var tab: MTMediaTab = .wall   // a page opens on its wall (the author's word 24.09)
    /// THE CONVERSATION, READ ONCE PER CHANGE (the author's word 18.09: the profile must open at
    /// once): merging and sorting every letter under every key on every pass of the body made the
    /// push wait; the screen refreshes it when the store's counts change, and the data reads it.
    @Published var conversation: [Message] = []
    func refreshConversation(chat: Chat, store: ChatStore) { conversation = MTPeerInfoData.conversation(chat: chat, store: store) }
    @Published var modal: MTPeerInfoModal?
    @Published var showFingerprint = false
    @Published var pickerItem: PhotosPickerItem?

    @Published var draftFirst = ""
    @Published var draftLast = ""
    @Published var draftNote = ""
    @Published var draftPhoto: String?
    @Published var draftMembers: [String] = []

    @Published var isMuted = false
    @Published var isBlocked = false
    @Published var isVerified = false

    private var boundConv: String?

    func bind(chat: Chat, store: ChatStore) {
        guard boundConv != chat.convId ?? "" else { return }
        boundConv = chat.convId ?? ""
        let kind = MTPeerKind(chat: chat)
        if kind == .group {
            draftFirst = chat.displayName ?? ""
            draftLast = chat.lastName ?? ""
            draftNote = MTGroup.shared.state(chat.name)?.about ?? ""   // a group's note is its description, the owner's to write (stage R)
        } else {
            let shown = MTNameBook.display(conv: chat.convId ?? "")
            let manual = MTNameBook.manualName(chat.convId ?? "") ?? ""
            let source = manual.isEmpty ? shown : manual
            let parts = source.split(separator: " ", maxSplits: 1).map(String.init)
            draftFirst = parts.first ?? ""
            draftLast = parts.count > 1 ? parts[1] : ""
        }
        draftNote = chat.note ?? ""
        draftPhoto = store.avatarFor(chat)
        draftMembers = chat.members
        isMuted = ChatStore.chatFlag("mute", chat.name)
        isBlocked = ChatStore.chatFlag("block", chat.name) || ChatStore.legacyBlocked().contains(chat.name)
        isVerified = SafetyStore.isVerified(chat.convId ?? "")
    }

    func refreshVerified(_ conv: String) { isVerified = SafetyStore.isVerified(conv) }

    // Contacts are created by hand only, and always the same way: the entry goes into the app list
    // AND into the phone's address book through the contacts tab's own save path, so the person
    // shows up on the Contacts tab and in the phone at once.
    func isInContacts(_ conv: String) -> Bool {
        guard let data = (MontanaLocalVault.getString("mtContacts") ?? "").data(using: .utf8),
              let arr = try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: data) else { return false }
        return arr.contains { $0.ref == conv }
    }
    // Attach the Montana address to a card that already exists in the phone, then mirror that card
    // as our contact — the same single save path, just starting from the phone side.
    func attachToExistingCard(_ card: CNContact, conv: String) {
        // A nickname does not exist in a profile; nothing is appended to the phone contact card --
        // the card is only mirrored into our contact list by the same single path.
        // THE PHONE CARD'S NAME IS THE PERSON'S OWN WORD for this correspondent: it enters the rename
        // book — the one place that means «named by me» (18.09); the card fields are a mirror only.
        let given = card.givenName.trimmingCharacters(in: .whitespaces)
        let family = card.familyName.trimmingCharacters(in: .whitespaces)
        if !(given + family).isEmpty { MTNameBook.setManual(conv: conv, first: given, last: family) }
        addToContacts(conv: conv,
                      title: [card.givenName, card.familyName].filter { !$0.isEmpty }.joined(separator: " "))
    }

    func addToContacts(conv: String, title: String) {
        let raw = MontanaLocalVault.getString("mtContacts") ?? ""
        var arr: [ContactsTabView.MTContact] = []
        if let d = raw.data(using: .utf8),
           let x = try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: d) { arr = x }
        guard !arr.contains(where: { $0.ref == conv }) else { return }
        let parts = title.split(separator: " ", maxSplits: 1).map(String.init)
        // The card name is what the person sees; the address does not get into it (N-1 of the address inventory).
        let first = parts.first ?? MTNameBook.display(conv: conv)
        let last = parts.count > 1 ? parts[1] : ""

        let c = ContactsTabView.MTContact(firstName: first, lastName: last, ref: conv,
                                          name: "",   // a nick does not exist in the profile
                                          addedAt: Date().timeIntervalSince1970)
        arr.append(c)
        if let d = try? JSONEncoder().encode(arr), let js = String(data: d, encoding: .utf8) {
            MontanaLocalVault.setString("mtContacts", js)
            MTNameBook.invalidateContacts()
        }
        ContactsTabView.MTContact.upsertSystemCard(c)   // the card in the phone's address book
        objectWillChange.send()
    }

    func toggleBlocked(_ chat: Chat, store: ChatStore) {
        store.toggleBlocked(chat.name)   // ONE owner of the block (MontanaSafety): the set every road obeys
        isBlocked = store.isBlocked(chat.name)
    }
}

// Full-screen presentation of one picture, one video or the avatar — a single modifier, so two
// viewers can never be on screen at once.
enum MTPeerInfoModal: Identifiable {
    case avatar
    case video(String)

    var id: String {
        switch self {
        case .avatar: return "avatar"
        case .video(let f): return "video:\(f)"
        }
    }
}
