import Foundation
import UIKit

// ════════════════════════════════════════════════════════════
// GROUPS AND CHANNELS, CARRIED BY THE PHONES THEMSELVES
// ════════════════════════════════════════════════════════════
//
// The author's words 05.10.2026: «Group (choose Contacts to add to the group)», «Channel», «you build the full working function
// of everything». No server holds a group. The owner's phone holds a pipe with every member -- the members were chosen from its
// own correspondents -- and carries every word to the others over those pipes: a star through the owner (the groups and channels
// checklist). A word of a group rides the one delivery queue, one copy per receiver under a name of its own (the queue keeps one
// item per name), and the row it lands as is witnessed by its receivers: a member's letter by the owner's receipt, the owner's
// letter by the receipt of every member.

/// What a group is to its people: a room where everyone writes, or a channel where only its owner posts. Said once, in the
/// invitation, and read the same way on every phone.
enum MTGroupKind: String, Codable {
    case group = "g"
    case channel = "c"
}

/// One person the owner carries the group's words to: the seat the group knows them by, and the pipe this phone holds with them.
/// The seat rides the wire; the pipe never does.
struct MTGroupMember: Codable, Equatable {
    var seat: String
    var pipe: String
}

/// A group as this phone holds it.
struct MTGroupState: Codable, Equatable {
    var id: String
    var kind: MTGroupKind
    var title: String
    var about: String = ""
    /// The pipe to the owner; empty when this phone owns the group.
    var owner: String
    /// This phone's own seat; the owner sits at MTGroup.ownerSeat.
    var me: String
    /// Whom the owner carries to. A member's phone carries to the owner alone and holds nobody here.
    var members: [MTGroupMember]
    /// The people in the group, the owner included, as the owner counted them.
    var count: Int
    /// The name each seat gave itself in its last word: a person's name reaches the group from that person, never from the owner.
    var names: [String: String]
    var at: Double
    /// This phone left the group or its owner took it out: the rows stay readable, nothing is written or taken into it.
    var left: Bool? = nil
    /// Its owner took this phone out (their «out»), as against a leaving by this phone's own hand: the chat's head says which
    /// (the reference folder: «you were removed from the group» / «you have left the group»).
    var removed: Bool? = nil
    /// The seats the owner of a carried group named its administrators (stage R.6, the reference folder: «Promote»): they take
    /// another's letter away for everyone and ask the owner to take a person out. Named by the owner alone, in its invitation.
    var admins: [String]? = nil
    /// The owner's standing mark of the group's invite link (stage R.6, the reference folder: «Invite Link»): whoever opens the
    /// link meets the owner by its card and asks with this mark; a new mark (reset) ends every link given before. Owner only.
    var invite: String? = nil
    /// The face last taken from an invitation, by its length and its tail: a repeat of the same word lays no second file.
    var faceTag: String? = nil
    /// THE GROUP'S FACE ON THIS PHONE, a file of the avatars folder (17.10.2026): the group is its one owner, so the row, the copy
    /// and the notices read it here -- it used to live on the row alone and left with a row a copy did not carry.
    var face: String? = nil
    /// WHO READ THIS PHONE'S LETTERS, AND HOW FAR (the checklist's B.13): each reader's seat with the birth millisecond of the newest
    /// letter they read. This phone's own record, never on the wire; bounded by the group's people (I-14).
    var readBy: [String: Int64]? = nil
    /// THE OWNER'S POSTS GO WITHOUT SOUND (the reference's «Silent Broadcast», the bell in a channel's field): this phone's own choice
    /// for its channel, never on the wire as a setting -- each post says it (MTGroupWord.sl).
    var silent: Bool? = nil
    /// WHAT THE MEMBERS MAY NOT DO (the checklist's G.5, the reference's «Permissions»): the rights the owner took from them, by their
    /// short words (MTGroupRight); absent -- everything, the reference's default for a new group. Said by the owner alone, in its invitation.
    var barred: [String]? = nil
    /// SLOW MODE (the reference's «Slowmode»): the seconds a member waits between letters; absent or 0 -- off.
    var slow: Int? = nil
    /// WHAT EACH ADMINISTRATOR MAY NOT DO (the checklist's G.6, the reference's «What can this admin do?»): by seat, the admin's
    /// rights the owner left out (MTAdminRight); absent -- all of them. Said by the owner alone, in its invitation.
    var adminTaken: [String: [String]]? = nil
    /// The custom titles the owner gave (the reference's «Custom Title»), by seat: shown instead of «owner» or «admin».
    var ranks: [String: String]? = nil
    /// The group's invite link as the owner hands it to an administrator who may invite by it (MTAdminRight.invite).
    var link: String? = nil
    /// THE LINK ASKS THE OWNER FIRST (the checklist's G.8, the reference's «Request Admin Approval»): who opens it waits in the
    /// requests until the owner adds or dismisses them. The owner's phone alone keeps both; nothing of it rides the wire.
    var approval: Bool? = nil
    /// CHAT HISTORY FOR NEW MEMBERS (the checklist's G.4, the reference's «Visible» / «Hidden»): true -- one added reads the group's
    /// newest words, as everyone was carried them; absent -- hidden, the reference's default. The owner's choice, never on the wire.
    var history: Bool? = nil
    var requests: [MTGroupRequest]? = nil
    /// THE CHANNEL SIGNS ITS POSTS (the reference's «Sign Messages»): the owner's choice, carried to every subscriber in its invitation
    /// (MTGroupWord.sg); each post then wears its writer's name in its stamp.
    var signs: Bool? = nil
    /// THE CHANNEL TAKES NO REACTIONS (the reference's «Allow Reactions» off): false -- its owner turned them off; carried to every
    /// subscriber in its invitation (MTGroupWord.rx). Absent -- every reaction is taken.
    var reacts: Bool? = nil
    /// THE PEOPLE ITS OWNER TOOK OUT OF A CHANNEL (the reference's «Removed Users»): they cannot come back by the invite link until the
    /// owner lets them, or adds them again. The owner's phone alone keeps them; nothing of it rides the wire.
    var banned: [MTGroupMember]? = nil
    /// WHAT WAS DONE IN A CHANNEL (the reference's «Recent Actions»): the owner's phone writes each deed as it does it, by the names it
    /// knew then, and shows the last two days. Never on the wire.
    var acts: [MTChannelAct]? = nil
    /// SUBSCRIBERS COMMENT UNDER THE CHANNEL'S POSTS (the reference's discussion under a post): the owner's choice, carried in its
    /// invitation (MTGroupWord.dc); the comments ride the channel itself (MTChannelComments), no group of their own.
    var talks: Bool? = nil
    /// THE REACTIONS A CHANNEL TAKES (the reference's «Some Reactions»): the owner's list; absent -- every reaction (while it takes
    /// any, MTGroupState.reacts). Carried in its invitation (MTGroupWord.rl).
    var reactList: [String]? = nil
    var mine: Bool { owner.isEmpty }
    var canManage: Bool { mine && left != true }
    /// A group's every person writes; a channel's owner and the administrators it named post (the reference's «Post Messages»).
    var canWrite: Bool {
        left != true && (kind == .group || mine
            || (admins?.contains(me) == true && !(adminTaken?[me] ?? []).contains(MTChannelRight.post.rawValue)))   // «Post Messages»
    }
}

/// One deed of a channel, as its owner's phone wrote it (MTGroupState.acts): what, about whom by the names known then, when.
struct MTChannelAct: Codable, Equatable {
    /// invited, joined, removed, left, title, about, photo, promoted, demoted, signOn, signOff, reactOn, reactOff
    var e: String
    var p: [String]? = nil
    var t: String? = nil
    var at: Double
}

/// A copy of a group's word on its way to one receiver. The queue knows the copy by its own name; the group knows by this record
/// whose row the copy's receipt moves and what to carry again when a hand asks.
struct MTGroupCopy: Codable, Equatable {
    var group: String
    /// The row the copy carries (a bare letter name); empty for an invitation.
    var letter: String
    var to: String
    /// A copy of a letter of mine: its receipt is a witness of my row.
    var own: Bool
    /// How many copies the letter left in: every one of them must be receipted before the row is delivered.
    var of: Int
    var held: Bool
    var failed: Bool
    var text: String
    var at: Double
}

/// The group's word on the wire. «inv» -- the owner to one member: the group, its kind, its title, its words about itself, its face,
/// how many people are in it, the receiver's seat and the owner's own name. «say» -- a letter: its one name, the speaker's seat and
/// the name the speaker gives, the words, the quote. Short keys; a key a reader does not know is skipped by it.
struct MTGroupWord: Codable {
    var t: String
    var g: String
    var k: String? = nil
    var ti: String? = nil
    var ds: String? = nil
    var fc: String? = nil
    var c: Int? = nil
    var me: String? = nil
    var n: String? = nil
    var id: String? = nil
    var s: String? = nil
    var tx: String? = nil
    var qt: String? = nil
    var qm: String? = nil
    /// A room's invitation (MTGroupRoom, 07.10): the seats it is for. It is carried to them alone, and it rings there -- the
    /// notification extension shows it by the group's face though the app is closed.
    var ts: [String]? = nil
    /// 1: the targeted word rings on the seats it is for (an invitation); a room's other targeted word (a key handed to one who came
    /// in) rides silent.
    var rg: Int? = nil
    /// 1 on an «out»: the owner deleted the group for everyone (the reference folder: «Delete for All»). A build that
    /// does not read it takes the word as a taking out -- the group stands there read-only, as the owner's word allows.
    var dl: Int? = nil
    /// The owner's administrators on an «inv» (stage R.6): the seats it named; absent -- none.
    var ad: [String]? = nil
    /// 1 on a channel's post sent without sound (the reference's «Silent Broadcast»): it rides silent and rings nothing where it lands.
    /// A build that does not read it skips the key; the push is silent there too.
    var sl: Int? = nil
    /// 1 on a channel's «inv»: its posts are signed (Sign Messages). A build that does not read it skips the key.
    var sg: Int? = nil
    /// 0 on a channel's «inv»: its posts take no reactions (Allow Reactions off). A build that does not read it skips the key.
    var rx: Int? = nil
    /// The rights the members lack and the slow mode's seconds, on an «inv» (G.5): an older build skips both keys and keeps writing as
    /// before -- the owner, who carries every letter, refuses what they forbid.
    var bn: [String]? = nil
    var sw: Int? = nil
    /// The administrators' rights left out, the custom titles and -- to an administrator who may invite -- the link, on an «inv»
    /// (G.6); an older build skips the keys, and the owner's door holds every right whatever a build shows.
    var ax: [String: [String]]? = nil
    var rk: [String: String]? = nil
    var lk: String? = nil
    /// 1 on a channel's «inv»: its subscribers comment under its posts. A build that does not read it skips the key.
    var dc: Int? = nil
    /// 1 on a letter of the group's past handed to one just added (G.4): it lands silent, at its own moment, with no banner. A build
    /// that does not read it skips the key and shows it as a letter.
    var hs: Int? = nil
    /// The reactions a channel takes, on its «inv» (Some Reactions); absent -- every one. A build that does not read it skips the key.
    var rl: [String]? = nil
    /// THE WORD'S AUTHOR IS THE PERSON (MTGroup.ownTag, 18.10.2026): sixteen bytes only this person's devices make, over the pipe's
    /// secret and the word's own fields. A group's word is too big for the letter's eighth field more often than not (an invitation
    /// with the group's face, a channel's post), so it rode unsigned and the seed's other device judged it as a stranger's. A build
    /// that does not read it skips the key.
    var au: String? = nil
}

/// ONE WHO ASKED TO JOIN BY THE LINK (the reference's «Member Requests»): the pipe the owner met them by, the name they gave and when.
struct MTGroupRequest: Codable, Equatable {
    var pipe: String
    var name: String
    var at: Double
}

/// ONE PERSON OF A GROUP AS A COIN OF THIS PHONE REACHES THEM (MTGroup.coinPeople): their seat and the name this phone shows them by,
/// the pair's chat a transfer to them rides when this phone holds one open to coins, and whether it holds a pipe with them at all.
struct MTGroupPayee {
    let seat: String
    let name: String
    let chat: Chat?
    let held: Bool
}

/// WHAT AN ADMINISTRATOR MAY DO (the checklist's G.6, the reference's «What can this admin do?»), each a short word on the wire --
/// the rights whose deed this phone's group can hold: the owner names the ones an administrator lacks.
enum MTAdminRight: String, CaseIterable {
    case info = "ci", delete = "dm", ban = "bu", invite = "il", pin = "pm"
}

/// WHAT A CHANNEL'S ADMINISTRATOR MAY DO (the reference's channel «Admin Rights»), the rights its owner's phone carries out: the
/// channel's name, words and face asked of the owner; posting through the owner; taking another's post away; handing the channel's
/// link. Each a short word on the wire, three of them a group's own; the owner names the ones an administrator lacks.
enum MTChannelRight: String, CaseIterable {
    case info = "ci", post = "po", delete = "dm", invite = "il"
}

/// WHAT MEMBERS OF A GROUP MAY DO (the checklist's G.5, the reference's «What can members of this group do?»), each a short word on
/// the wire. The owner names the ones its members lack; the owner and the administrators it named keep them all.
enum MTGroupRight: String, CaseIterable {
    case text = "tx", photos = "ph", videos = "vd", stickers = "gf", music = "mu", files = "fl", voice = "vo", rounds = "rv",
         links = "ln", reactions = "re", pin = "pn", info = "ci"
    /// «Send Media» opened, in the reference's order.
    static let media: [MTGroupRight] = [.photos, .videos, .stickers, .music, .files, .voice, .rounds, .links, .reactions]
    /// The rows of the permissions page, the media standing as one row with its own.
    static let shown: [MTGroupRight] = [.text] + media + [.pin, .info]
    /// What the field says when this phone tries what the group took from its members, in the reference's sentence.
    var refusal: String {
        let b = MTLanguage.bundle
        switch self {
        case .text: return String(localized: "Sending messages is not allowed in this group", bundle: b)
        case .photos: return String(localized: "Sending photos is not allowed in this group", bundle: b)
        case .videos: return String(localized: "Sending videos is not allowed in this group", bundle: b)
        case .stickers: return String(localized: "Posting stickers isn’t allowed in this group.", bundle: b)
        case .music: return String(localized: "Sending music is not allowed in this group", bundle: b)
        case .files: return String(localized: "Sending files is not allowed in this group", bundle: b)
        case .voice: return String(localized: "Sending audio messages is not allowed in this group", bundle: b)
        case .rounds: return String(localized: "Sending video messages is not allowed in this group", bundle: b)
        case .links: return String(localized: "Sending links is not allowed in this group", bundle: b)
        case .reactions: return String(localized: "Sending reactions is not allowed in this group", bundle: b)
        case .pin, .info: return String(localized: "You cannot edit this permission.", bundle: b)
        }
    }
}

/// A GROUP'S EVENT, A ROW IN THE MIDDLE OF ITS FEED (stage R, the reference folder's service rows: «X created the group»,
/// «X added Y», «X removed Y», «X left the group», a new name or face, a voice chat begun and ended). The row is this
/// phone's own; the owner's word «ev» names whom an event was about by seat alone -- a person's name reaches the group from
/// that person, never from the owner -- so the row asks the group for the names when it is drawn.
struct MTGroupEvent: Codable {
    static let mark = "\u{200B}\u{200B}GE:"   // COMPAT-LOCAL: this phone's own row, never on the wire
    /// made, added, removed, left, named, face, call, ended
    var e: String
    var g: String
    /// The seat that did it.
    var a: String
    /// The seats it was about.
    var p: [String]? = nil
    /// The group's name (made, named).
    var t: String? = nil
    /// A room's kind (call, ended): call or live; v 1 -- with the camera.
    var k: String? = nil
    var v: Int? = nil
    /// A room's id (call): the row's tap is the way in while the room lives.
    var r: String? = nil
    /// How long the room lived, in seconds (ended).
    var d: Int? = nil
    static func of(_ text: String) -> MTGroupEvent? {
        guard text.hasPrefix(mark), let data = String(text.dropFirst(mark.count)).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MTGroupEvent.self, from: data)
    }
    var row: String? {
        guard let data = try? JSONEncoder().encode(self), let js = String(data: data, encoding: .utf8) else { return nil }
        return Self.mark + js
    }
}

/// THE MESSENGER HOLDS NO ORGANISATION'S CHAT (Montana Business's, carried by nobody): every group here is carried by its owner.
/// Said once, so the rooms, the events and the roles read the same words in both apps (stage R).
extension MTGroupState {
    var bosses: [String]? { nil }
}

/// The one owner of groups and channels on this phone: their state, their words on the wire, the owner's carrying and the
/// receipts of every copy. Read and written on the main thread, where the store lands every letter.
final class MTGroup {
    static let shared = MTGroup()
    /// Whether this phone keeps the group's people (adds, takes out, renames, describes): its owner.
    func manages(_ key: String) -> Bool { state(key)?.canManage == true }
    static let mark = "\u{200B}\u{200B}GR:"
    static let stateKey = "groups.held"
    static let copiesKey = "groups.copies"
    // COMPAT-LOCAL: the feed's key and a speaker's reference name rows of this phone; neither rides the wire.
    static let keyHead = "grp:"
    static let speakerHead = "gm:"
    static let ownerSeat = "0"
    static let titleLimit = 64
    static let aboutLimit = 255
    static let nameLimit = 64
    static let faceSide: CGFloat = 160
    static let faceLimit = 24_000
    /// [I-14]: a group is bounded by the people its owner carries to.
    static let peopleLimit = 200
    /// A copy outlives the queue's own term by a day and is let go with it.
    static let copyLife: Double = 8 * 24 * 3600
    /// A channel's post with its files' posters, at most (MTBoard.thumbLimit a poster, MTBoard.mediaLimit files, the words).
    static let wallPostLimit = 1_000_000
    /// [I-14]: the posts one word of a channel's views names, at most (MTChannelViews).
    static let viewsBatch = 200
    /// [I-14]: a letter's link card on the wire, at most -- the pair's leg (MTLinkPreviewBuilder.fitting), its picture cut to it.
    static let cardLimit = 16_384
    /// [I-15]: how long a card that outran its letter on the road waits for it, by the letter's own birth; a letter refused never lands.
    static let cardWait: Double = 600
    /// [I-14]: a sticker's passport on the wire, at most -- its set, its sticker and the letter it answers.
    static let passportLimit = 4_096

    private(set) var groups: [String: MTGroupState] = [:]
    private var copies: [String: MTGroupCopy] = [:]
    /// The names of the newest answers already applied: a repeat of a copy is applied once, and carried on once.
    private var answersHeard: [String] = []
    /// [I-15] A MEMBER'S ROOM WORDS ARE TAKEN AT A PERSON'S PACE (07.10, the rooms of Montana Business), by the clock of the phone
    /// that takes them -- a clock the speaker does not set. The owner of a group says every member's room word again to everyone
    /// else -- one word is a copy for every member -- so a member who floods would make phones shout without end. Thirty words a
    /// minute per member are taken; a copy past the pace is not taken (no receipt) and knocks again when the minute has room:
    /// nothing is lost, the pace is a person's. Time, not money, is the barrier.
    static let carriedPerMinute = 30
    private var carriedAt: [String: [Double]] = [:]
    /// A STORE THAT WOULD NOT OPEN IS NOT AN EMPTY ONE (the device key not yet at hand, a launch before the first unlock): it is
    /// read again before it is used, nothing is written over it, and a word that needs it waits unanswered -- one group written
    /// over an unread store would write every other group away.
    private var unread = false

    private init() {
        load()
        NotificationCenter.default.addObserver(forName: .montanaSeedForgotten, object: nil, queue: .main) { [weak self] _ in
            self?.load()   // another person's groups are not this one's
        }
    }
    /// The store was laid again under the living (a copy, a seat lifted): the groups are read from it, never written over it.
    func reread() { load() }
    private func load() {
        let held = MontanaLocalVault.getDecrypted(Self.stateKey).flatMap { try? JSONDecoder().decode([String: MTGroupState].self, from: $0) }
        let kept = MontanaLocalVault.getDecrypted(Self.copiesKey).flatMap { try? JSONDecoder().decode([String: MTGroupCopy].self, from: $0) }
        unread = (held == nil && UserDefaults.standard.data(forKey: Self.stateKey) != nil)
            || (kept == nil && UserDefaults.standard.data(forKey: Self.copiesKey) != nil)
        if unread { MontanaTrace.mark("group_unread", "the groups' store did not open -- read again before use") }
        groups = held ?? [:]
        let edge = Date().timeIntervalSince1970 - Self.copyLife
        copies = (kept ?? [:]).filter { edge < $0.value.at }
    }
    /// The store, read again if it would not open before.
    private func ready() -> Bool {
        if unread { load() }
        return !unread
    }
    private func saveGroups() {
        guard !unread, let d = try? JSONEncoder().encode(groups) else { return }
        MontanaLocalVault.setEncrypted(Self.stateKey, d)
    }
    private func saveCopies() {
        guard !unread, let d = try? JSONEncoder().encode(copies) else { return }
        MontanaLocalVault.setEncrypted(Self.copiesKey, d)
    }

    // -- names ---------------------------------------------------------------------------------

    static func isKey(_ chat: String) -> Bool { chat.hasPrefix(keyHead) }
    static func key(of id: String) -> String { keyHead + id }
    static func id(of key: String) -> String? { isKey(key) ? String(key.dropFirst(keyHead.count)) : nil }
    func state(_ key: String) -> MTGroupState? {
        guard Self.isKey(key), ready() else { return nil }
        return Self.id(of: key).flatMap { groups[$0] }
    }
    func kind(_ key: String) -> MTGroupKind? { state(key)?.kind }
    /// The people in the group, the owner included -- the head of the group's chat and its page say this number.
    func people(_ key: String) -> Int? { state(key)?.count }
    /// The conversations this phone holds with people of the group, by their roots -- the owner's phone with everyone it carries
    /// to, a member's phone with the owner alone: whom it may see online at all. Nothing is asked of anyone here.
    func heldConversations(_ key: String) -> [String] {
        guard let g = state(key) else { return [] }
        return g.mine ? g.members.map { MTSamePair.root($0.pipe) } : [MTSamePair.root(g.owner)]
    }
    /// Whether this phone may write into the group: everyone in a group, the owner alone in a channel.
    func canWrite(_ key: String) -> Bool {
        state(key)?.canWrite == true
    }
    /// WHETHER THE FIELD OF THIS GROUP HOLDS THE COIN (the author's word 17.10.2026 21:14 UTC): a group's every person who writes;
    /// never a channel -- its owner alone posts and its subscribers have no field.
    func takesCoins(_ key: String) -> Bool { state(key).map { g in g.kind == .group && g.canWrite } == true }
    /// Whether this phone is out of the group -- it left, or the owner took it out (the chat says so instead of a field).
    func isOut(_ key: String) -> Bool { state(key)?.left == true }
    /// Whether the owner's phone already carries the group to this person (the page's «add» lists the others only).
    func carries(to pipe: String, in key: String) -> Bool {
        let p = MTSamePair.root(pipe)
        return state(key)?.members.contains { MTSamePair.root($0.pipe) == p } == true
    }
    /// The people of the group's page with their seats: the owner's phone lists everyone it carries to, a member's the owner.
    func shownSeats(_ key: String) -> [(seat: String, name: String)] {
        guard let g = state(key) else { return [] }
        if g.mine { return g.members.map { ($0.seat, shownName(pipe: $0.pipe, said: g.names[$0.seat])) } }
        return [(Self.ownerSeat, shownName(pipe: g.owner, said: g.names[Self.ownerSeat]))]
    }
    /// THE PEOPLE OF A GROUP'S PAGE (stage R, the reference folder lists every member): the owner's phone everyone it carries to;
    /// a member's phone the owner first, then everyone who spoke -- the owner names nobody, the others come by their own words.
    func pagePeople(_ key: String) -> [(seat: String, name: String)] {
        guard let g = state(key) else { return [] }
        var out = shownSeats(key)
        if !g.mine {
            let spoke = g.names.filter { e in e.key != Self.ownerSeat && e.key != g.me && !out.contains(where: { o in o.seat == e.key }) }
            for (seat, n) in spoke.sorted(by: { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }) { out.append((seat, n)) }
        }
        return out
    }
    /// The names of the people this phone sees in the group, for its page: the owner's phone names everyone it carries to, a
    /// member's phone names the owner -- the others give their names by their own words.
    func shownPeople(_ key: String) -> [String] {
        guard let g = state(key) else { return [] }
        if g.mine { return g.members.map { shownName(pipe: $0.pipe, said: g.names[$0.seat]) } }
        return [shownName(pipe: g.owner, said: g.names[Self.ownerSeat])]
    }

    /// WHOM A COIN OF THE GROUP REACHES FROM THIS PHONE (the author's word 17.10.2026 21:14 UTC, asked whether a coin in a group is a
    /// transfer to one chosen member or no coin at all: «yes, with a choice by check marks among the members, as on the Send page of
    /// the time coin»). A transfer is one record on the nodes for one receiver, named by the pair's tag under the pipe's secret
    /// (MTCoinTx.pairTag, send3) and found by the receiver through its own pipes' tags alone -- so a person is reached only through a
    /// pipe this phone holds with them: the owner's phone every member it carries to, a member's phone the owner. The others are known
    /// here by their seat and the name they gave (the seat rides the wire, the pipe never does): a transfer to them would need the
    /// owner to hand one member's pipe to another, which a group never does. The pair's own door decides the rest (MTCoinSend.canPay).
    @MainActor
    func coinPeople(_ key: String, store: ChatStore) -> [MTGroupPayee] {
        guard takesCoins(key), let g = state(key) else { return [] }
        let rows = store.listChats().filter { c in !c.isGroup && !Self.isKey(c.name) && MTSamePair.root(c.name) == c.name }
        return pagePeople(key).filter { p in p.seat != g.me }.map { p -> MTGroupPayee in
            guard let pipe = speakerPipe(Self.speaker(g.id, p.seat)), !pipe.isEmpty else {
                return MTGroupPayee(seat: p.seat, name: p.name, chat: nil, held: false)
            }
            let root = MTSamePair.root(pipe)
            var chat = rows.first { c in MTSamePair.root(c.convId ?? c.name) == root }
                ?? Chat(name: root, lastMessage: "", time: "", unread: 0, convId: root)
            if chat.convId == nil { chat.convId = chat.name }
            return MTGroupPayee(seat: p.seat, name: p.name, chat: MTCoinSend.canPay(chat, store: store) ? chat : nil, held: true)
        }
    }
    /// THE GROUP IS TOLD, IT IS NEVER PAID (the author's word 17.10.2026 21:14 UTC): the coins went to each person picked by the pair's
    /// own transfer (MTCoinSendSheet, MTCoinSend.transfer); the group's feed gets the sender's plain words of how many were paid -- no
    /// sum, no name, no transfer's link and no coin letter's machine line, so no phone of the group credits anything by it (carries
    /// refuses a coin letter in a group, and ChatStore credits a coin letter only outside one). A right the group took from its
    /// members, or slow mode's wait, leaves the words unsaid: the transfers stand in the pairs' chats all the same.
    @MainActor
    func tellCoins(_ people: Int, in key: String, store: ChatStore) {
        guard 0 < people, takesCoins(key) else { return }
        let words = "🪙 " + String(localized: "Sent coins to \(people) members", bundle: MTLanguage.bundle)
        guard Self.carries(words), refusal(words, in: key, letter: true, store: store) == nil else {
            MontanaTrace.mark("group_coin", "told=0 people=\(people)")
            return
        }
        _ = store.send(text: words, chat: key)
        MontanaTrace.mark("group_coin", "told=1 people=\(people)")
    }

    static func speaker(_ id: String, _ seat: String) -> String { speakerHead + id + "/" + seat }
    static func isSpeaker(_ ref: String) -> Bool { ref.hasPrefix(speakerHead) }
    /// The name a speaker's rows wear on this phone: the person as this phone knows them where it holds their pipe, else the name
    /// they gave themselves in their last word.
    func speakerName(_ ref: String) -> String {
        guard let at = seatOf(ref) else { return Self.memberWord }
        return shownName(pipe: speakerPipe(ref), said: at.g.names[at.seat])
    }
    /// The pipe this phone holds to a speaker of a group, when it holds one: the owner's phone to every member it carries to, a
    /// member's phone to the owner -- the others are known by their own words alone.
    func speakerPipe(_ ref: String) -> String? {
        guard let at = seatOf(ref) else { return nil }
        return (!at.g.mine && at.seat == Self.ownerSeat) ? at.g.owner : at.g.members.first { m in m.seat == at.seat }?.pipe
    }
    private func seatOf(_ ref: String) -> (g: MTGroupState, seat: String)? {
        let parts = ref.dropFirst(Self.speakerHead.count).split(separator: "/", maxSplits: 1).map(String.init)
        guard ready(), parts.count == 2, let g = groups[parts[0]] else { return nil }
        return (g, parts[1])
    }
    /// The line above a speaker's bubble: in a group, every letter of another says who wrote it; a channel speaks as itself.
    func speakerLine(_ m: Message, in chat: String) -> String? {
        guard !m.isFromMe, let ref = m.senderRef, Self.isSpeaker(ref), state(chat)?.kind == .group else { return nil }
        return speakerName(ref)
    }
    private func shownName(pipe: String?, said: String?) -> String {
        let neutral = String(localized: "Correspondent", bundle: MTLanguage.bundle)
        if let pipe, !pipe.isEmpty {
            let book = MTNameBook.display(conv: pipe)
            if book != neutral, !book.isEmpty { return book }
        }
        let own = said ?? ""
        return own.isEmpty ? Self.memberWord : own
    }
    static var memberWord: String { String(localized: "Member", bundle: MTLanguage.bundle) }

    // -- birth ---------------------------------------------------------------------------------

    /// A GROUP OR A CHANNEL IS BORN ON THIS PHONE: its owner's phone. The people are the correspondents chosen, each by the pipe
    /// this phone holds with them; each is told by an invitation of their own. The row stands in the list at once; the invitations
    /// ride the queue until every one is receipted. A channel may start before it has subscribers.
    @MainActor @discardableResult
    func create(_ kind: MTGroupKind, title: String, about: String = "", face: Data, people: [Chat], store: ChatStore) -> Chat? {
        let name = Self.clean(title, Self.titleLimit)
        var pipes: [String] = []
        for c in people where !c.isGroup {
            let p = MTSamePair.root(c.convRef)
            if MontanaConv.holds(p), !ChatStore.refusesCold(p), !pipes.contains(p) { pipes.append(p) }
        }
        pipes = Array(pipes.prefix(Self.peopleLimit))
        // A GROUP MAY BEGIN WITH NOBODY YET, as the reference's does (the checklist's A.2): its owner adds people from its page
        guard ready(), !name.isEmpty else {
            MontanaTrace.mark("group_refused", "birth -- title=\(name.isEmpty ? 0 : 1) people=\(pipes.count) store=\(unread ? 0 : 1)")
            return nil
        }
        let id = Self.mintId()
        var taken: Set<String> = [Self.ownerSeat]
        var members: [MTGroupMember] = []
        for p in pipes {
            var seat = Self.mintSeat()
            while taken.contains(seat) { seat = Self.mintSeat() }
            taken.insert(seat)
            members.append(MTGroupMember(seat: seat, pipe: p))
        }
        let g = MTGroupState(id: id, kind: kind, title: name, about: Self.clean(about, Self.aboutLimit), owner: "", me: Self.ownerSeat,
                             members: members, count: members.count + 1, names: [:], at: Date().timeIntervalSince1970)
        groups[id] = g
        saveGroups()
        let row = stand(g, face: face.isEmpty ? nil : saveChatAvatar(face), store: store)
        lay(MTGroupEvent(e: "made", g: id, a: Self.ownerSeat, t: name), store: store)   // «You created the group»
        let thumb = Self.thumb(face)
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        for m in members {
            let w = MTGroupWord(t: "inv", g: id, k: kind.rawValue, ti: name, ds: g.about.isEmpty ? nil : g.about, fc: thumb,
                                c: g.count, me: m.seat, n: me.isEmpty ? nil : me)
            _ = carry(w, to: m.pipe, letter: "", own: false)
        }
        MontanaTrace.mark("group_born", "kind=\(kind.rawValue) people=\(g.count)")
        return row
    }

    /// ONE MEMBER'S INVITATION AS THE GROUP'S ROAD CARRIES IT (a call of two growing into a room, MTGroupRoom.grow, the author's word
    /// 18.10.2026 10:3x UTC: «adding to a call must not interrupt it»): the same word, handed to the call's own road, so the peer
    /// stands the group the moment the call says so instead of the minutes the box takes. The word is the owner's alone.
    func invitationText(_ key: String, seat: String) -> String? {
        guard let g = state(key), g.mine, g.members.contains(where: { m in m.seat == seat }) else { return nil }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        let w = MTGroupWord(t: "inv", g: g.id, k: g.kind.rawValue, ti: g.title, ds: g.about.isEmpty ? nil : g.about, fc: nil,
                            c: g.count, me: seat, n: me.isEmpty ? nil : me)
        guard let d = try? JSONEncoder().encode(w), let js = String(data: d, encoding: .utf8) else { return nil }
        return Self.mark + js
    }

    /// The group's row on the list: the one standing or archived, or a new one at the top. A deleted group's row comes back
    /// with its next word, as a deleted conversation does.
    /// `fresh` -- a word of the group raised it now; a row stood back by standAll keeps its place by its newest letter.
    @MainActor @discardableResult
    private func stand(_ g: MTGroupState, face: String?, store: ChatStore, fresh: Bool = true) -> Chat {
        let key = Self.key(of: g.id)
        // THE GROUP OWNS ITS FACE (17.10.2026): a new face is written into the group's state first; the row and the notices'
        // mirror follow it -- a row lost to a copy or a shelf comes back wearing it, and a banner wears it while the app sleeps.
        if let face, groups[g.id] != nil, groups[g.id]?.face != face {
            groups[g.id]?.face = face
            saveGroups()
            store.mirrorFaceToShared(key)
        }
        if store.deletedChats.contains(key) { store.deletedChats.remove(key) }
        var rows = store.storedChats()
        if let i = rows.firstIndex(where: { $0.id == key }) {
            if rows[i].displayName != g.title || (face != nil && rows[i].photoURL != face) {
                rows[i].displayName = g.title
                if let face { rows[i].photoURL = face }
                store.saveStored(chats: rows)
            }
            return rows[i]
        }
        if let held = store.storedArchived().first(where: { $0.id == key }) { return held }
        let row = Chat(name: key, lastMessage: "", time: nowHHMM(), unread: 0, status: "", photoURL: face ?? groups[g.id]?.face,
                       isGroup: true, isAdmin: g.mine, members: [], convId: key, displayName: g.title)
        rows.insert(row, at: 0)
        store.saveStored(chats: rows)
        if fresh { store.bump(key) }
        return row
    }

    /// EVERY GROUP THIS PHONE HOLDS STANDS ON A SHELF (the author's word 17.10.2026 13:0x UTC: «groups and channels did not come
    /// back»). A group has no pipe, so no builder derives its row from the feed: the row lived on the saved shelf alone, and a
    /// copy that did not carry the shelf -- or a shelf written over -- left the group's state and its feed on the phone with no
    /// row to open them by (the Mac 17.10 13:03 UTC: feed_no_row=grp:9cf40d,grp:3d8826). The group is its row's owner: at every
    /// load and after every copy laid, a held group with no row on either shelf stands one, in its place by its newest letter,
    /// unless the person deleted it; a face only the old row knew is taken into the group once.
    @MainActor
    func standAll(store: ChatStore) {
        guard ready(), !groups.isEmpty else { return }
        let rows = store.storedChats(), archived = store.storedArchived()
        var stood = 0, faces = 0
        for id in groups.keys.sorted() {
            guard let g = groups[id] else { continue }
            let key = Self.key(of: id)
            let row = rows.first { $0.id == key } ?? archived.first { $0.id == key }
            if g.face == nil, let f = row?.photoURL, !f.isEmpty {
                groups[id]?.face = f
                faces += 1
            }
            guard row == nil, !store.deletedChats.contains(key) else { continue }
            stand(groups[id] ?? g, face: nil, store: store, fresh: false)
            stood += 1
        }
        if faces > 0 { saveGroups() }
        if stood + faces > 0 { MontanaTrace.mark("group_stood", "rows=\(stood) faces=\(faces) held=\(groups.count)") }
        mirrorHeld(store: store)
    }

    /// THE GROUPS THIS DEVICE HELD BEFORE THE MIRROR, ONCE A DEVICE (the twin mirror, 18.10.2026): each rides to the seed's other
    /// devices as the words that made it here -- the owner's invitation of every member, a member's invitation from its owner -- and
    /// with it the person's own letters of the box's term, so a group born on one device before the mirror stands on every device
    /// of the seed by the same replay a new one takes (MTGroup.handleOwn). A media letter's cargo is not on this device to give.
    @MainActor
    private func mirrorHeld(store: ChatStore) {
        let flag = "mt.group.mirrored.1"   // NOT-UI: this device gave its groups to the seed's other devices
        guard ready(), !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let edge = Date().timeIntervalSince1970 - 7 * 86_400
        var words = 0, letters = 0
        func note(_ w: MTGroupWord, on pipe: String, own: Bool) {
            guard !pipe.isEmpty, let d = try? JSONEncoder().encode(w), let js = String(data: d, encoding: .utf8) else { return }
            MontanaArchive.mirrorNote(.init(c: pipe, m: ChatStore.mintMid().mid, x: Self.mark + js, o: own ? 1 : nil))
            words += 1
        }
        for id in groups.keys.sorted() {
            guard let g = groups[id], g.left != true else { continue }
            func invitation(_ seat: String) -> MTGroupWord {
                var w = MTGroupWord(t: "inv", g: g.id, k: g.kind.rawValue, ti: g.title, ds: g.about.isEmpty ? nil : g.about, fc: nil,
                                    c: g.count, me: seat, n: g.mine ? nil : g.names[Self.ownerSeat])
                w.ad = g.admins
                w.bn = g.barred
                w.sw = g.slow
                w.ax = g.adminTaken
                w.rk = g.ranks
                w.sg = g.kind == .channel && g.signs == true ? 1 : nil
                w.rx = g.kind == .channel && g.reacts == false ? 0 : nil
                w.dc = g.kind == .channel && g.talks == true ? 1 : nil
                w.rl = g.kind == .channel ? g.reactList : nil
                return w
            }
            if g.mine {
                for m in g.members { note(invitation(m.seat), on: m.pipe, own: true) }
            } else {
                note(invitation(g.me), on: g.owner, own: false)
            }
            // the person's own letters of the box's term, by their names: the other device lands each once (replayLetter)
            let carrier = g.mine ? g.members.first?.pipe ?? "" : g.owner
            for r in (store.messages[Self.key(of: id)] ?? []).suffix(300) where r.isFromMe && edge < r.createdAt {
                guard r.mid.hasPrefix("mid:"), r.imageFile == nil, r.videoFile == nil, r.audioFile == nil, r.docFile == nil,
                      Self.carries(r.text) else { continue }
                let name = String(r.mid.dropFirst(4))
                guard Self.isLetterName(name) else { continue }
                note(MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, id: name, s: g.me, tx: r.text, qt: r.replyText),
                     on: carrier, own: true)
                letters += 1
            }
        }
        MontanaTrace.mark("group_mirrored", "words=\(words) letters=\(letters) groups=\(groups.count)")
    }

    // -- the wire ------------------------------------------------------------------------------

    /// One copy to one receiver, under a name of its own. A copy has no row of its own (headless): the row it carries stands in
    /// the group's feed under the letter's name, and the group answers for it (rides) where the mirror law asks. A letter and an
    /// invitation ring (the receiver's phone shows the group's face); an answer, a leaving and a taking out are silent words.
    @MainActor
    private func carry(_ w: MTGroupWord, to pipe: String, letter: String, own: Bool, ring: Bool = false) -> String? {
        var w = w
        w.au = Self.ownTag(w, pipe: pipe)   // signed by the person: the seed's other devices know the word as their own
        guard MontanaConv.holds(pipe), !ChatStore.refusesCold(pipe),
              let d = try? JSONEncoder().encode(w), let js = String(data: d, encoding: .utf8) else { return nil }
        let name = ChatStore.mintMid().mid
        let text = Self.mark + js
        copies[name] = MTGroupCopy(group: w.g, letter: letter, to: pipe, own: own, of: 1, held: false, failed: false,
                                   text: text, at: Date().timeIntervalSince1970)
        saveCopies()
        // A DELETION WAKES THE EXTENSION OF A BUILD THAT PROVED IT TAKES IT QUIETLY (E2E.deletionQuiet, 16.10.2026): the deleted letter's
        // notice leaves that screen at once; the copy waits for its receipt as every group word does.
        let wakes = w.t == "sig" && (w.tx ?? "").hasPrefix(deleteMark) && E2E.deletionQuiet(pipe)
        MontanaDeliveryEngine.shared.enqueue(to: pipe, chat: pipe, mid: name, text: text,
                                             silent: (!ring && w.t != "say" && w.t != "inv" && !wakes) || w.sl == 1 || w.hs == 1,   // a silent post, and the past (G.4), ring nothing
                                             headless: true)   // a room's invitation rings where it is carried (07.10)
        MontanaTrace.mark("group_tx", mid: name, "t=\(w.t) to=\(String(pipe.prefix(10)))")
        return name
    }

    /// A letter to everyone this phone carries to in the group: the owner to every member but the speaker, a member to the owner.
    @MainActor @discardableResult
    private func spread(_ w: MTGroupWord, in g: MTGroupState, except seat: String?, own: Bool) -> Int {
        let targets = g.mine ? g.members.filter { $0.seat != seat }.map(\.pipe) : [g.owner]
        let names = targets.compactMap { carry(w, to: $0, letter: w.id ?? "", own: own) }
        for n in names { copies[n]?.of = names.count }
        if !names.isEmpty { saveCopies() }
        return names.count
    }

    /// A LETTER OF MINE INTO A GROUP (ChatStore.send): the row is born in the group's feed under its one name, on the clock, and a
    /// copy leaves for every receiver; the receipts raise the row (follow). A channel takes the owner's letters alone.
    @MainActor
    func send(_ text: String, in key: String, replyText: String?, replyToId: MID?, replyWireMid: String?, store: ChatStore) -> Message {
        guard let g = state(key), canWrite(key), Self.carries(text) else {
            MontanaTrace.mark("group_refused", "send -- group=\(state(key) == nil ? 0 : 1) chat=\(String(key.prefix(12)))")
            return Message(text: "", isFromMe: true, time: nowHHMM(), senderRef: nil)
        }
        let minted = ChatStore.mintMid()
        let row = Message(text: text, isFromMe: true, time: nowHHMM(), replyText: replyText, deliveryStatus: .sending,
                          msgId: "mid:" + minted.mid, senderRef: nil, createdAt: Double(minted.ms) / 1000, replyToId: replyToId)
        store.append(key, row)
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        // The title and the kind ride every letter: the receiver's notification extension holds no group, and names it by these.
        var w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: minted.mid, s: g.me, tx: text,
                            qt: (replyText ?? "").isEmpty ? nil : replyText, qm: (replyWireMid ?? "").isEmpty ? nil : replyWireMid)
        w.sl = g.kind == .channel && g.silent == true ? 1 : nil   // the bell in the owner's field (Silent Broadcast)
        if spread(w, in: g, except: nil, own: true) == 0, let i = store.messages[key]?.firstIndex(where: { $0.mid == row.mid }) {
            // a group of its owner alone holds the letter here, as the reference's does (A.2); else nobody to carry to: honest red
            if Self.alone(g) { store.advance(key, i, to: .delivered) } else { store.putOut(key, i, because: .nobodyToCarry) }
        }
        return row
    }

    /// A MEDIA LETTER OF MINE INTO A GROUP (ChatStore.sendMediaToPeer, the author's words 06.10.2026 11:2x-11:3x UTC: «groups and channels with the whole of a chat, every kind of data»): its row
    /// stands in the feed already under its one name, its file's sealed pieces lie on the nodes for every receiver -- the node's term
    /// keeps them, no single receipt takes them away -- and its manifest leaves to everyone this phone carries to, as a word does.
    @MainActor
    func carryMedia(_ letter: String, mid: String, in key: String, store: ChatStore) -> Bool {
        guard let g = state(key), canWrite(key), Self.carries(letter), letter.hasPrefix(mediaMark), Self.isLetterName(mid) else {
            MontanaTrace.mark("group_refused", "media -- group=\(state(key) == nil ? 0 : 1) chat=\(String(key.prefix(12)))")
            return false
        }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        var w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: mid, s: g.me, tx: letter)
        w.sl = g.kind == .channel && g.silent == true ? 1 : nil   // the bell in the owner's field (Silent Broadcast)
        let n = spread(w, in: g, except: nil, own: true)
        if n == 0, Self.alone(g), let i = store.messages[key]?.firstIndex(where: { r in r.isFromMe && r.mid == "mid:" + mid }) {
            store.advance(key, i, to: .delivered)   // a group of its owner alone holds the letter here (A.2)
            return true
        }
        return n > 0
    }
    /// A group of its owner alone (A.2): nobody to carry to, so a letter is held where it was written, never red.
    static func alone(_ g: MTGroupState) -> Bool { g.mine && g.kind == .group && g.members.isEmpty }

    /// THE CARD OF A LETTER OF MINE, TO EVERYONE THIS PHONE CARRIES TO (the author's word 17.10.2026 19:3x UTC: «everything as in chats,
    /// one to one»): the card the person saw above the field, and its picture when it catches up (MTLinkCards), ride as the group's own
    /// word «lp» under the letter's name -- the pair's same-name copy that carries the card (MontanaDeliveryEngine.attachPreview), said
    /// the group's way. An older build buries a word of a kind it does not know.
    @MainActor
    func carryCard(_ card: String, letter: String, in key: String, store: ChatStore) {
        guard let g = state(key), canWrite(key), Self.isLetterName(letter),
              store.messages[key]?.contains(where: { r in r.isFromMe && r.mid == "mid:" + letter }) == true,
              let fitted = MTLinkPreviewBuilder.fitting(card), fitted.utf8.count <= Self.cardLimit else { return }
        let w = MTGroupWord(t: "lp", g: g.id, id: letter, s: g.me, tx: fitted)   // COMPAT-GATED: a letter's card (17.10.2026), an older build buries it
        let n = spread(w, in: g, except: nil, own: false)   // no copy of a card is a witness of the letter's row
        MontanaTrace.mark("group_tx", mid: letter, "card copies=\(n) bytes=\(fitted.utf8.count)")
    }

    /// A STICKER'S PASSPORT INTO A GROUP (MontanaStickerWire.sendPassport): the set the sticker is of and the letter it answers ride as
    /// the group's own word «sp» under the sticker letter's name, to everyone this phone carries to. An older build buries it.
    @MainActor
    func carryPassport(_ body: String, letter: String, in key: String) {
        guard let g = state(key), canWrite(key), Self.isLetterName(letter), body.utf8.count <= Self.passportLimit else { return }
        let w = MTGroupWord(t: "sp", g: g.id, id: letter, s: g.me, tx: body)   // COMPAT-GATED: a sticker's passport (17.10.2026), an older build buries it
        let n = spread(w, in: g, except: nil, own: false)   // no copy of a passport is a witness of the sticker's row
        MontanaTrace.mark("group_tx", mid: letter, "passport copies=\(n)")
    }

    /// A CHANNEL'S POST LEAVES TO EVERY SUBSCRIBER (the author's words 06.10.2026 11:2x-11:4x UTC: «in channels posts as on the Wall of Thoughts; everything the wall publishes is published in a channel», MTBoard.lay): the wall's own word «cpost» with the post as the channel's page
    /// shows it, carried as the channel's letter; no row of the feed is born of it (ChatStore.append hands a wall's word to MTBoard).
    @MainActor
    func carryWallPost(_ post: MTBoardSeen, in key: String) {
        guard let g = state(key), g.canManage, g.kind == .channel,
              let d = try? JSONEncoder().encode(MTBoardWord(t: "cpost", ps: [post])), let js = String(data: d, encoding: .utf8) else { return }   // COMPAT-GATED: a channel's carrier alone
        let text = MTBoard.mark + js
        guard Self.carries(text) else { MontanaTrace.mark("group_refused", "wall post bytes=\(text.utf8.count)"); return }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        let w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: ChatStore.mintMid().mid, s: g.me, tx: text)
        let n = spread(w, in: g, except: nil, own: false)
        MontanaTrace.mark("group_tx", "wall post copies=\(n)")
    }

    /// A HAND ASKED AGAIN (the red mark's retry): every copy of the letter that has not been receipted rides again under its own
    /// name; a letter with no copy left leaves anew to everyone. The row goes back to the clock by the one road back.
    @MainActor
    func resend(_ m: Message, in key: String, store: ChatStore) {
        guard let g = state(key), g.canWrite, m.isFromMe,
              let i = store.messages[key]?.firstIndex(where: { $0.mid == m.mid }) else { return }
        let letter = m.mid.hasPrefix("mid:") ? String(m.mid.dropFirst(4)) : m.mid
        store.restartSend(key, i)
        let waiting = copies.filter { $0.value.own && $0.value.group == g.id && $0.value.letter == letter }
        if waiting.isEmpty {
            let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
            let w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: letter, s: g.me, tx: m.text,
                                qt: (m.replyText ?? "").isEmpty ? nil : m.replyText)
            if spread(w, in: g, except: nil, own: true) == 0 {
                if Self.alone(g) { store.advance(key, i, to: .delivered) } else { store.putOut(key, i, because: .nobodyToCarry) }   // A.2
            }
            MontanaTrace.mark("group_resend", mid: letter, "anew")
            return
        }
        for (name, c) in waiting {
            copies[name]?.failed = false
            MontanaDeliveryEngine.shared.enqueue(to: c.to, chat: c.to, mid: name, text: c.text, silent: false, headless: true)
        }
        saveCopies()
        MontanaDeliveryEngine.shared.drainAll()
        MontanaTrace.mark("group_resend", mid: letter, "copies=\(waiting.count)")
    }

    /// AN ANSWER TO A LETTER -- a reaction, an edit of one's own words, a deletion of one's own letter for everyone: carried to
    /// every phone of the group like a letter and applied by the same road in the group's feed (ChatStore.append), where it is
    /// never a row. Everyone in a group or a channel may react; only a letter's own speaker changes or takes it away (answered).
    @MainActor
    func signal(_ text: String, in key: String, store: ChatStore) {
        guard let g = state(key), g.left != true, Self.answers(text) else {
            MontanaTrace.mark("group_refused", "answer -- group=\(state(key) == nil ? 0 : 1)")
            return
        }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        let w = MTGroupWord(t: "sig", g: g.id, n: me.isEmpty ? nil : me, id: ChatStore.mintMid().mid, s: g.me, tx: text)
        spread(w, in: g, except: nil, own: false)
    }

    /// A LETTER TAKEN AWAY FOR EVERYONE STAYS ON THIS PHONE (MTLevelAccess.keepDeleted, 16.10.2026 No.72): its speaker alone is told, by
    /// the keeper's own word «kp» -- the owner carries it to that seat; in a channel the speaker is its owner. An older build refuses the
    /// word and receipts it (take's default): its speaker is not told there.
    @MainActor
    func tellKept(_ sid: String, speaker ref: String?, in key: String) {
        guard let g = state(key), g.left != true else { return }
        let head = Self.speaker(g.id, "")
        let seat = ref.flatMap { r in r.hasPrefix(head) ? String(r.dropFirst(head.count)) : nil } ?? Self.ownerSeat
        guard seat != g.me else { return }
        var w = MTGroupWord(t: "kp", g: g.id, id: ChatStore.mintMid().mid, s: g.me, tx: deleteKeptMark + sid)   // COMPAT-GATED: refused by older builds
        w.ts = [seat]
        if g.mine {
            if let m = g.members.first(where: { m in m.seat == seat }) { _ = carry(w, to: m.pipe, letter: "", own: false) }
        } else {
            _ = carry(w, to: g.owner, letter: "", own: false)
        }
        MontanaTrace.mark("delete_kept", "group word to seat=\(seat)")
    }
    /// The keeper's word reached the group: the owner carries it on to the speaker's seat; the speaker is told.
    @MainActor
    private func keptHeard(_ w: MTGroupWord, from pipe: String) -> Verdict {
        guard let g = groups[w.g], g.left != true, let to = w.ts?.first, (w.tx ?? "").hasPrefix(deleteKeptMark) else { return .refused }
        let from = MTSamePair.root(pipe)
        if g.mine {
            guard g.members.contains(where: { m in MTSamePair.root(m.pipe) == from }) else { return .refused }   // a member's word alone
            if to != g.me {
                if let m = g.members.first(where: { m in m.seat == to }) { _ = carry(w, to: m.pipe, letter: "", own: false) }
                return .held
            }
        } else {
            guard MTSamePair.root(g.owner) == from, to == g.me else { return .refused }
        }
        let key = Self.key(of: g.id)
        MontanaNotify.presentKept(from: key, chat: key)
        return .held
    }

    /// A ROOM'S WORD INTO THE GROUP (MTGroupRoom, the author's word 06.10.2026 21:2x UTC: calls of up to 13 in a group): carried like
    /// an answer -- to everyone this phone carries to, the owner passing it on -- and never a row.
    /// An invitation (ask) goes to the seats chosen alone and rings there; the owner of a group it carries passes it on to them only.
    @MainActor
    func room(_ text: String, in key: String, ask seats: [String]? = nil, ring: Bool = true) {
        guard let g = state(key), g.left != true, text.utf8.count <= 4096 else { return }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        // the title and the kind ride the word: the receiver's notification extension holds no group, and names it by these
        var w = MTGroupWord(t: "room", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: ChatStore.mintMid().mid,
                            s: g.me, tx: text)
        guard let seats, !seats.isEmpty else { spread(w, in: g, except: nil, own: false); return }
        w.ts = Array(seats.prefix(32))
        w.rg = ring ? 1 : 0   // said either way: a word naming no ring is read as an invitation of build 52-54
        if g.mine {
            for m in g.members where seats.contains(m.seat) { _ = carry(w, to: m.pipe, letter: "", own: false, ring: ring) }
        } else {
            _ = carry(w, to: g.owner, letter: "", own: false, ring: ring && seats.contains(Self.ownerSeat))
        }
    }

    // -- administrators (stage R.6, the reference folder: «Promote», «Dismiss Admin») ---------------------------------

    /// WHETHER THE OWNER'S NEXT POSTS GO WITHOUT SOUND (the bell in a channel's field): its owner's choice, kept on its state.
    func silent(_ key: String) -> Bool { state(key)?.silent == true }
    func setSilent(_ key: String, on: Bool) {
        guard var g = state(key), g.canManage, g.kind == .channel else { return }
        g.silent = on ? true : nil
        groups[g.id] = g
        saveGroups()
        MontanaTrace.mark("channel_silent", on ? "on" : "off")
    }
    /// [I-14]: the deeds a channel's owner keeps for its Recent Actions.
    static let actsKept = 100
    /// A DEED OF A CHANNEL, WRITTEN ON ITS OWNER'S PHONE (MTGroupState.acts): a group keeps its events in its feed instead.
    private func act(_ g: inout MTGroupState, _ e: String, p: [String]? = nil, t: String? = nil) {
        guard g.kind == .channel, g.mine else { return }
        var list = g.acts ?? []
        list.append(MTChannelAct(e: e, p: p, t: t, at: Date().timeIntervalSince1970))
        if Self.actsKept < list.count { list.removeFirst(list.count - Self.actsKept) }
        g.acts = list
    }
    /// The name a seat of a group is known by on this phone, as the page lists it.
    func seatName(_ g: MTGroupState, _ seat: String) -> String {
        if let m = g.members.first(where: { m in m.seat == seat }) { return shownName(pipe: m.pipe, said: g.names[seat]) }
        if let b = g.banned?.first(where: { b in b.seat == seat }) { return shownName(pipe: b.pipe, said: g.names[seat]) }
        return shownName(pipe: nil, said: g.names[seat])
    }
    /// THE OWNER LETS A REMOVED PERSON BACK BY THE LINK (the reference's «Removed Users», Delete): they are no longer kept out.
    @MainActor
    func unban(_ key: String, seat: String) {
        guard var g = state(key), g.canManage, g.banned?.contains(where: { b in b.seat == seat }) == true else { return }
        g.banned = g.banned?.filter { b in b.seat != seat }.nilIfEmpty
        groups[g.id] = g
        saveGroups()
        MontanaTrace.mark("channel_banned", "let back")
    }
    /// The people its owner took out of a channel, by the names they were known by, for its Removed Users.
    func bannedPeople(_ key: String) -> [(seat: String, name: String, pipe: String)] {
        guard let g = state(key) else { return [] }
        return (g.banned ?? []).map { b in (b.seat, seatName(g, b.seat), b.pipe) }
    }
    // -- a channel's comments (the reference's discussion under a post; MTChannelComments) ---------------------------------

    /// [I-14]: a comment's words, at most.
    static let commentLimit = 4096
    /// [I-15] ONE COMMENT FROM ONE PERSON IN THIS MANY SECONDS (the critic's note on c59776c7; the reference's slowmode): a person who
    /// floods would push everyone else's comments out of a post's five hundred. Time, not money: the owner takes one comment from a
    /// seat in this span and refuses the rest with a receipt; a subscriber's own phone keeps the same span and its field says what is
    /// left. The owner's own comments wait for nobody.
    static let commentGap: Double = 30
    private var commentAt: [String: Double] = [:]
    private var myCommentAt: [String: Double] = [:]
    /// The seconds this phone waits before its next comment in a channel: 0 when it may comment now.
    func commentWait(_ key: String) -> Int {
        guard let g = state(key), !g.mine, let last = myCommentAt[g.id] else { return 0 }
        return max(0, Int((Self.commentGap - (Date().timeIntervalSince1970 - last)).rounded(.up)))
    }
    /// Whether a channel's subscribers comment under its posts (Allow Comments).
    func talks(_ key: String) -> Bool { state(key)?.talks == true && state(key)?.kind == .channel }
    /// THE OWNER LETS ITS SUBSCRIBERS COMMENT OR STOPS IT: every subscriber hears it by the invitation's word again.
    @MainActor
    func setTalks(_ key: String, on: Bool) {
        guard var g = state(key), g.canManage, g.kind == .channel else { return }
        g.talks = on ? true : nil
        act(&g, on ? "talkOn" : "talkOff")
        groups[g.id] = g
        saveGroups()
        tellAll(g, face: nil)
        MontanaTrace.mark("channel_comments", on ? "on" : "off")
    }
    /// A COMMENT OF MINE UNDER A CHANNEL'S POST: kept here at once and carried as the channel's word -- a subscriber's to the owner,
    /// the owner's to everyone. False -- not carried (comments off, no pipe, an empty or overlong word).
    @MainActor @discardableResult
    func comment(_ text: String, on post: String, in key: String) -> Bool {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let g = state(key), g.kind == .channel, g.talks == true, g.left != true, Self.isLetterName(post),
              !words.isEmpty, words.count <= Self.commentLimit, commentWait(key) == 0 else { return false }
        if !g.mine { myCommentAt[g.id] = Date().timeIntervalSince1970 }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        let id = ChatStore.mintMid().mid
        let w = MTGroupWord(t: "cm", g: g.id, n: me.isEmpty ? nil : me, id: id, s: g.me, tx: words, qm: post)   // COMPAT-GATED: older builds refuse «cm»
        MTChannelComments.shared.put(MTChannelComment(id: id, seat: g.me, name: me, text: words, at: Date().timeIntervalSince1970, mine: true),
                                     on: post, in: key)
        return 0 < spread(w, in: g, except: nil, own: false) || (g.mine && g.members.isEmpty)
    }
    /// A COMMENT ARRIVED: the owner takes one only under a post of its feed, from a subscriber it carries to, while comments are on,
    /// and carries it on to everyone else; a subscriber takes the owner's word alone. Each comment once, by its name.
    @MainActor
    private func commented(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard g.kind == .channel, g.left != true, let id = w.id, Self.isLetterName(id), let post = w.qm, Self.isLetterName(post),
              let tx = w.tx, !tx.isEmpty, tx.count <= Self.commentLimit else { return .refused }
        let from = MTSamePair.root(pipe)
        let key = Self.key(of: g.id)
        let seat: String
        if g.mine {
            guard g.talks == true, let m = g.members.first(where: { m in MTSamePair.root(m.pipe) == from }),
                  store.messages[key]?.contains(where: { r in r.mid == "mid:" + post }) == true else { return .refused }
            seat = m.seat
        } else {
            guard MTSamePair.root(g.owner) == from, let s = w.s, Self.isSeat(s), s != g.me else { return .refused }
            seat = s
        }
        if MTChannelComments.shared.has(id, on: post, in: key) { return .held }   // a repeat: taken already
        if g.mine {
            let now = Date().timeIntervalSince1970, pace = g.id + "/" + seat
            guard Self.commentGap <= now - (commentAt[pace] ?? 0) else {
                MontanaTrace.markFolded("channel_comment_paced", "one comment from a seat in thirty seconds -- refused", window: 60, key: pace)
                return .refused
            }
            commentAt[pace] = now
        }
        let name = Self.clean(w.n ?? "", Self.nameLimit)
        let born = MontanaDeliveryEngine.letterMoment(mid: "mid:" + id, sentAt: nil)
        let fresh = MTChannelComments.shared.put(MTChannelComment(id: id, seat: seat, name: name, text: tx, at: born, mine: false), on: post, in: key)
        if fresh, g.mine {
            spread(MTGroupWord(t: "cm", g: g.id, n: name.isEmpty ? nil : name, id: id, s: seat, tx: tx, qm: post), in: g, except: seat, own: false)
        }
        return .held
    }
    /// [I-14]: the reactions a channel's list names, at most, each a glyph of a few letters.
    static let reactListLimit = 80
    /// A list of reactions as it came: glyphs alone, each once, bounded; nil for none or for every one.
    static func reactionList(_ l: [String]?) -> [String]? {
        guard let l else { return nil }
        var seen = Set<String>()
        let out = l.filter { e in !e.isEmpty && e.count <= 4 && e.unicodeScalars.count <= 16 && seen.insert(e).inserted }
        return out.isEmpty ? nil : Array(out.prefix(Self.reactListLimit))
    }
    /// The reactions a channel takes: its owner's list, or nil for every one.
    func reactionList(_ key: String) -> [String]? { state(key)?.kind == .channel ? state(key)?.reactList : nil }
    /// THE OWNER CHOOSES THE REACTIONS ITS CHANNEL TAKES (Some Reactions), or every one (nil): every subscriber hears it by the
    /// invitation's word again.
    @MainActor
    func setReactionList(_ key: String, _ list: [String]?) {
        guard var g = state(key), g.canManage, g.kind == .channel else { return }
        let next = Self.reactionList(list)
        guard next != g.reactList else { return }
        g.reactList = next
        act(&g, next == nil ? "reactOn" : "reactSome")
        groups[g.id] = g
        saveGroups()
        tellAll(g, face: nil)
        MontanaTrace.mark("channel_reactions", "list=\(next?.count ?? 0)")
    }
    /// Whether a channel's posts take reactions (Allow Reactions): on unless its owner turned them off.
    func reactionsOn(_ key: String) -> Bool { state(key)?.reacts != false }
    /// THE OWNER ALLOWS REACTIONS OR TURNS THEM OFF: every subscriber hears it by the invitation's word again.
    @MainActor
    func setReactions(_ key: String, on: Bool) {
        guard var g = state(key), g.canManage, g.kind == .channel else { return }
        g.reacts = on ? nil : false
        act(&g, on ? "reactOn" : "reactOff")
        groups[g.id] = g
        saveGroups()
        tellAll(g, face: nil)
        MontanaTrace.mark("channel_reactions", on ? "on" : "off")
    }
    /// THE OWNER SIGNS THE CHANNEL'S POSTS OR STOPS (Sign Messages): every subscriber hears it by the invitation's word again.
    @MainActor
    func setSigns(_ key: String, on: Bool) {
        guard var g = state(key), g.canManage, g.kind == .channel else { return }
        g.signs = on ? true : nil
        act(&g, on ? "signOn" : "signOff")
        groups[g.id] = g
        saveGroups()
        tellAll(g, face: nil)
        MontanaTrace.mark("channel_signs", on ? "on" : "off")
    }
    /// The name a signed channel's post wears in its stamp: its writer's -- this phone's own name on its own posts, the speaker's
    /// on another's. Nil where the channel does not sign.
    func signature(_ m: Message, in key: String) -> String? {
        guard let g = state(key), g.kind == .channel, g.signs == true else { return nil }
        if m.isFromMe { let me = Self.clean(E2E.myDisplayName(), Self.nameLimit); return me.isEmpty ? nil : me }
        guard let ref = m.senderRef, Self.isSpeaker(ref) else { return nil }
        let name = speakerName(ref)
        return name == Self.memberWord ? nil : name
    }
    /// Whether a seat is an administrator the owner of a carried group named.
    func isAdmin(_ key: String, seat: String) -> Bool { state(key)?.admins?.contains(seat) == true }
    /// Whether this phone moderates the group: its owner, an administrator the owner named, or -- in an organisation's chat -- an
    /// administrator of the core. A moderator takes another's letter away for everyone.
    func moderates(_ key: String) -> Bool {
        guard let g = state(key), g.left != true else { return false }   // a channel's administrators delete posts too (the reference's)
        return Self.adminCan(g, seat: g.me, .delete)   // a group's and a channel's by the right (G.6; a channel's «Delete Messages of Others»)
    }
    /// WHETHER A SEAT HOLDS AN ADMINISTRATOR'S RIGHT (G.6): the owner every one; an administrator the ones the owner did not take.
    static func adminCan(_ g: MTGroupState, seat: String, _ r: MTAdminRight) -> Bool {
        if seat == ownerSeat { return true }
        guard g.admins?.contains(seat) == true else { return false }
        return !(g.adminTaken?[seat] ?? []).contains(r.rawValue)
    }
    /// The owner's word about its administrators, taken as it stands: the rights left out (known ones alone), the custom titles,
    /// and the link -- an https link of the owner's card, kept only while this phone is an administrator who may invite.
    static func takeAdmins(_ w: MTGroupWord, into g: inout MTGroupState) {
        var taken: [String: [String]] = [:]
        for (seat, rights) in w.ax ?? [:] where isSeat(seat) {
            let known = rights.filter { r in MTAdminRight(rawValue: r) != nil || MTChannelRight(rawValue: r) != nil }   // a channel's too
            if !known.isEmpty { taken[seat] = known }
        }
        g.adminTaken = taken.isEmpty ? nil : taken
        var ranks: [String: String] = [:]
        for (seat, r) in w.rk ?? [:] where isSeat(seat) {
            let t = String(clean(r, 16))
            if !t.isEmpty { ranks[seat] = t }
        }
        g.ranks = ranks.isEmpty ? nil : ranks
        let mine = adminCan(g, seat: g.me, .invite) && g.me != ownerSeat
        g.link = mine ? w.lk.flatMap { s in s.count <= 2048 && s.hasPrefix("https://") ? s : nil } : nil
    }
    /// The words a seat wears beside its name: the custom title the owner gave, else nil (the role's own word stands).
    func rank(_ key: String, seat: String) -> String? { state(key)?.ranks?[seat].flatMap { r in r.isEmpty ? nil : r } }
    /// THE OWNER NAMES OR DISMISSES AN ADMINISTRATOR: every member hears the list by the invitation's word again.
    @MainActor
    func setAdmin(_ key: String, seat: String, on: Bool, taken: Set<String> = [], rank: String? = nil, store: ChatStore) {
        guard var g = state(key), g.canManage, g.members.contains(where: { $0.seat == seat }) else { return }   // a group's or a channel's
        var list = Set(g.admins ?? [])
        if on { list.insert(seat) } else { list.remove(seat) }
        g.admins = Array(list).sorted().nilIfEmpty
        // the admin's rights left out and its custom title (G.6): kept while it is one, gone with its dismissal
        var takenBy = g.adminTaken ?? [:]
        var ranks = g.ranks ?? [:]
        let words = g.kind == .channel ? MTChannelRight.allCases.map(\.rawValue) : MTAdminRight.allCases.map(\.rawValue)
        let left = words.filter { x in taken.contains(x) }   // a channel's rights are its own (MTChannelRight)
        takenBy[seat] = on && !left.isEmpty ? left : nil
        let title = String(Self.clean(rank ?? "", 16))
        ranks[seat] = on && !title.isEmpty ? title : nil
        g.adminTaken = takenBy.isEmpty ? nil : takenBy
        g.ranks = ranks.isEmpty ? nil : ranks
        act(&g, on ? "promoted" : "demoted", p: [seatName(g, seat)])   // a channel's recent actions (its owner's phone alone)
        groups[g.id] = g
        saveGroups()
        tellAll(g, face: nil)
        MontanaTrace.mark("group_admin", on ? "named" : "dismissed")
    }
    /// AN ADMINISTRATOR TAKES A PERSON OUT: the owner's phone carries the group, so the word goes to the owner, who takes the person
    /// out as by its own hand -- never the owner, never another administrator. The owner's phone is the one that can.
    @MainActor
    func kick(_ key: String, seat: String, store: ChatStore) {
        guard let g = state(key), g.left != true else { return }
        if g.mine { remove(key, seat: seat, store: store); return }
        guard Self.adminCan(g, seat: g.me, .ban), seat != Self.ownerSeat, seat != g.me, g.admins?.contains(seat) != true else { return }
        _ = carry(MTGroupWord(t: "kk", g: g.id, id: ChatStore.mintMid().mid, s: seat), to: g.owner, letter: "", own: false)   // COMPAT-GATED
        MontanaTrace.mark("group_admin", "asked the owner to take a person out")
    }
    /// An administrator's «take out» at the owner's phone: the asker must be an administrator, the person a member who is none.
    @MainActor
    private func kicked(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g], g.mine, g.left != true else { return .refused }
        let from = MTSamePair.root(pipe)
        guard let asker = g.members.first(where: { MTSamePair.root($0.pipe) == from }), Self.adminCan(g, seat: asker.seat, .ban),
              let target = w.s, target != asker.seat, g.admins?.contains(target) != true,
              g.members.contains(where: { $0.seat == target }) else { return .refused }
        remove(Self.key(of: g.id), seat: target, by: asker.seat, store: store)
        return .held
    }

    // -- typing (the checklist's B.12, the reference's «X is typing» in a group's head) ------------------------------------------

    /// A GROUP'S TYPING WORD LIVES AN INSTANT: thrown at the pipes this phone holds for the group (E2E.signalNow) -- the owner's phone
    /// at every member, a member's at the owner -- never queued, never receipted, never written; the owner throws a member's word on.
    /// TYPING IS PRESENCE (the critic's K-G1): a phone that hides its presence says none, and none to a person it blocked
    /// (MontanaPresencePrivacy.saysTyping). A person blocks only whom they hold a pipe with -- in a group, the owner for a member and
    /// the members for the owner -- so the check at the sender covers every block there is; the owner, carrying another's word on,
    /// passes it to nobody it blocked itself and takes none from a person it blocked.
    @MainActor
    func typing(in key: String) {
        guard MontanaPresencePrivacy.sharing, let g = state(key), g.canWrite, g.kind == .group else { return }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        throwTyping(MTGroupWord(t: "ty", g: g.id, n: me.isEmpty ? nil : me, s: g.me), to: g.mine ? g.members.map(\.pipe) : [g.owner], own: true)
    }
    private func throwTyping(_ w: MTGroupWord, to pipes: [String], own: Bool) {
        guard let d = try? JSONEncoder().encode(w), let js = String(data: d, encoding: .utf8) else { return }
        let text = Self.mark + js
        for p in pipes where MontanaConv.holds(p) && !ChatStore.refusesCold(p) {
            guard own ? MontanaPresencePrivacy.saysTyping(to: p) : !E2E.shared.silenced(p) else { continue }
            Task { _ = await E2E.shared.signalNow(to: p, text) }
        }
    }
    /// The moment the owner last threw a member's typing on: once in two seconds a member, whatever it sends (I-15).
    private var typingThrown: [String: Date] = [:]
    /// A TYPING WORD LANDED: its seat proven by the pipe it came by, as every word's is; the head shows it for the store's typing life.
    @MainActor
    private func typed(_ w: MTGroupWord, from pipe: String) -> Verdict {
        guard var g = groups[w.g], g.left != true, g.kind == .group else { return .instant }
        let from = MTSamePair.root(pipe)
        let seat: String
        if g.mine {
            guard let m = g.members.first(where: { x in MTSamePair.root(x.pipe) == from }), !E2E.shared.silenced(m.pipe) else { return .instant }
            seat = m.seat
            let k = g.id + "/" + seat
            if Date().timeIntervalSince(typingThrown[k] ?? .distantPast) >= 2 {
                typingThrown[k] = Date()
                var on = w
                on.s = seat
                throwTyping(on, to: g.members.filter { x in x.seat != seat }.map(\.pipe), own: false)
            }
        } else {
            guard MTSamePair.root(g.owner) == from, let s = w.s, Self.isSeat(s), s != g.me else { return .instant }
            seat = s
        }
        let name = Self.clean(w.n ?? "", Self.nameLimit)
        if !name.isEmpty, g.names[seat] != name {   // a person's name reaches the group from that person, as their letters bring it
            g.names[seat] = name
            groups[w.g] = g
            saveGroups()
        }
        MTGroupTyping.shared.heard(Self.key(of: g.id), seat: seat)
        return .instant
    }

    // -- read (the checklist's B.13, the reference's small group: a letter read, and who saw it) -------------------------------

    /// How far this phone told each group it read: one word a moment, and only when the mark moved. Held in memory: a launch tells once.
    private var readTold: [String: Int64] = [:]
    /// How far the owner told the speakers each reader read, by group and reader: a speaker hears of a reader once for each new reach.
    private var readSpread: [String: Int64] = [:]
    /// THIS PHONE READ THE GROUP (ChatStore.sendReadMark, on the chat's own terms: on screen, the app active): the birth millisecond of
    /// the newest letter of another before its eyes, told as its own word «rd» to the owner, who tells each speaker it covers; the
    /// owner's own reading goes to them straight. Never with «Read receipts» off -- the switch is the person's word about themselves.
    @MainActor
    func tellRead(_ key: String, store: ChatStore) {
        guard ChatStore.readReceiptsOn, let g = state(key), g.kind == .group, g.left != true,
              let newest = (store.messages[key] ?? []).compactMap({ r in r.isFromMe ? nil : r.msgId.flatMap(ChatStore.birthMs(fromMid:)) }).max()
        else { return }
        let ms = Int64(newest * 1000)
        guard (readTold[g.id] ?? 0) < ms else { return }
        readTold[g.id] = ms
        if g.mine {
            spreadRead(g, reader: g.me, upTo: ms, store: store)
        } else {
            _ = carry(MTGroupWord(t: "rd", g: g.id, id: ChatStore.mintMid().mid, s: g.me, tx: String(ms)), to: g.owner, letter: "", own: false)
        }
        MontanaTrace.mark("read_tx", "group upto=\(MontanaTrace.shortMs(ms))")
    }
    /// THE OWNER TELLS EACH SPEAKER A READER REACHED: the seats of the letters born after the reader's last mark and up to the new one,
    /// each told by a word of its own (ts names it); the owner's own letters are read here.
    @MainActor
    private func spreadRead(_ g: MTGroupState, reader: String, upTo ms: Int64, store: ChatStore) {
        let key = Self.key(of: g.id)
        let head = Self.speaker(g.id, "")
        let k = g.id + "/" + reader
        let since = readSpread[k] ?? 0
        guard since < ms else { return }
        readSpread[k] = ms
        var speakers = Set<String>()
        for r in store.messages[key] ?? [] {
            guard let b = r.msgId.flatMap(ChatStore.birthMs(fromMid:)) else { continue }
            let born = Int64(b * 1000)
            guard since < born, born <= ms else { continue }
            let seat = r.isFromMe ? g.me : (r.senderRef.flatMap { x in x.hasPrefix(head) ? String(x.dropFirst(head.count)) : nil } ?? "")
            if !seat.isEmpty, seat != reader { speakers.insert(seat) }
        }
        if speakers.contains(g.me) { readMine(g.id, reader: reader, upTo: ms, store: store) }
        for m in g.members where speakers.contains(m.seat) {
            var w = MTGroupWord(t: "rd", g: g.id, id: ChatStore.mintMid().mid, s: reader, tx: String(ms))
            w.ts = [m.seat]
            _ = carry(w, to: m.pipe, letter: "", own: false)
        }
    }
    /// A READER REACHED MY LETTERS: their mark kept, and every letter of mine born up to it raised to read through the ladder's one
    /// door (delivered first, as everywhere).
    @MainActor
    private func readMine(_ gid: String, reader: String, upTo ms: Int64, store: ChatStore) {
        guard var g = groups[gid], reader != g.me else { return }
        var by = g.readBy ?? [:]
        guard (by[reader] ?? 0) < ms else { return }
        by[reader] = ms
        g.readBy = by
        groups[gid] = g
        saveGroups()
        let key = Self.key(of: gid)
        var raised = 0
        for (i, r) in (store.messages[key] ?? []).enumerated() where r.isFromMe {
            if let b = r.msgId.flatMap(ChatStore.birthMs(fromMid:)), Int64(b * 1000) <= ms, store.advance(key, i, to: .read) { raised += 1 }
        }
        MontanaTrace.mark("read_rx", "group upto=\(MontanaTrace.shortMs(ms)) raised=\(raised)")
    }
    /// A READER'S WORD: at the owner, the reader's seat is the pipe's own, never the word's; at a member, the owner's word for a
    /// reader of this phone's letters.
    @MainActor
    private func readWord(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard g.left != true, g.kind == .group, let tx = w.tx, let ms = Int64(tx), 0 < ms else { return .refused }
        let from = MTSamePair.root(pipe)
        if g.mine {
            guard let m = g.members.first(where: { x in MTSamePair.root(x.pipe) == from }) else { return .refused }
            spreadRead(g, reader: m.seat, upTo: ms, store: store)
        } else {
            guard MTSamePair.root(g.owner) == from, let s = w.s, Self.isSeat(s), s != g.me, w.ts?.contains(g.me) != false else { return .refused }
            readMine(g.id, reader: s, upTo: ms, store: store)
        }
        return .held
    }
    /// THE READERS OF A LETTER OF MINE, BY NAME (the reference's «N Seen» over the letter's menu): the seats whose mark covers its birth.
    func seenBy(_ m: Message, in key: String) -> [String]? {
        guard let g = state(key), g.kind == .group, m.isFromMe, let b = m.msgId.flatMap(ChatStore.birthMs(fromMid:)) else { return nil }
        let ms = Int64(b * 1000)
        return (g.readBy ?? [:]).filter { e in ms <= e.value }.map { e in speakerName(Self.speaker(g.id, e.key)) }
            .sorted { a, b in a.localizedCaseInsensitiveCompare(b) == .orderedAscending }
    }

    // -- permissions and slow mode (the checklist's G.5, the reference's «Permissions» and «Slowmode») -------------------------------

    /// THE RIGHTS A LETTER ASKS OF ITS SPEAKER: a reaction, a pin, a sticker, each kind of media by its manifest, and words -- with
    /// «Embed Links» where they carry a link. A deletion of one's own asks none.
    static func rightsAsked(by words: String) -> [MTGroupRight] {
        if words.hasPrefix(reactionMark) { return [.reactions] }
        if words.hasPrefix(pinMark) { return [.pin] }
        if words.hasPrefix(deleteMark) || MTBoard.isChannelPost(words) { return [] }
        if words.hasPrefix(stickerMark) { return [.stickers] }
        if words.hasPrefix(mediaMark) {
            let o = json(String(words.dropFirst(mediaMark.count))) ?? [:]
            let name = (o["n"] as? String) ?? (o["name"] as? String) ?? ""
            var out = [mediaRight(kind: (o["k"] as? String) ?? "", round: (o["r"] as? Bool) ?? false, name: name)]
            if !MTLinks.urls(in: (o["cap"] as? String) ?? "").isEmpty { out.append(.links) }
            return out
        }
        let text = words.hasPrefix(editMark) ? ((json(String(words.dropFirst(editMark.count)))?["tx"] as? String) ?? "") : words
        return MTLinks.urls(in: text).isEmpty ? [.text] : [.text, .links]
    }
    /// The right one media letter asks, by its kind, its roundness and its file's name.
    static func mediaRight(kind: String, round: Bool, name: String) -> MTGroupRight {
        switch kind {
        case "img": return name == MontanaCardPlate.stickerName ? .stickers : .photos
        case "vid", "video": return round ? .rounds : .videos
        case "aud": return .voice
        default: return mtIsAudioName(name) ? .music : (MontanaGif.isGif(name) ? .stickers : .files)
        }
    }
    /// WHETHER A SEAT MAY SAY THESE WORDS INTO THE GROUP: the owner and its administrators always; a member by the rights left them.
    static func allows(_ g: MTGroupState, seat: String, _ words: String) -> Bool {
        if seat == ownerSeat || g.admins?.contains(seat) == true { return true }
        let banned = Set(g.barred ?? [])
        return !rightsAsked(by: words).contains { r in banned.contains(r.rawValue) }
    }
    /// The moment the owner last took a letter of each member while slow mode stands, by group and seat (I-15: time, not money).
    private var slowAt: [String: Double] = [:]
    /// A MEMBER'S LETTER IN SLOW MODE: taken once an interval; a letter before it is held unanswered and knocks again -- delayed,
    /// never lost. The owner and its administrators are not paced, as in the reference.
    private func paceSlow(_ g: MTGroupState, seat: String) -> Bool {
        guard let s = g.slow, 0 < s, seat != Self.ownerSeat, g.admins?.contains(seat) != true else { return true }
        let k = g.id + "/" + seat, now = Date().timeIntervalSince1970
        guard Double(s) <= now - (slowAt[k] ?? 0) else { return false }
        slowAt[k] = now
        return true
    }
    /// WHY THIS PHONE MAY NOT SEND THESE WORDS NOW, in the reference's sentence -- a right the group took, or slow mode's wait;
    /// nil when it may. The field asks before it empties itself, so nothing typed is lost to a refusal.
    @MainActor
    func refusal(_ words: String, in key: String, letter: Bool, store: ChatStore) -> String? {
        guard let g = state(key), g.kind == .group, !g.mine, g.left != true, g.admins?.contains(g.me) != true else { return nil }
        let banned = Set(g.barred ?? [])
        if let r = Self.rightsAsked(by: words).first(where: { x in banned.contains(x.rawValue) }) { return r.refusal }
        return letter ? slowRefusal(g, key: key, store: store) : nil
    }
    /// The same for a media letter not yet made, by its kind, roundness, file name and caption.
    @MainActor
    func mediaRefusal(kind: String, round: Bool, name: String, caption: String, in key: String, store: ChatStore, except files: Set<String> = []) -> String? {
        guard let g = state(key), g.kind == .group, !g.mine, g.left != true, g.admins?.contains(g.me) != true else { return nil }
        let banned = Set(g.barred ?? [])
        var asked = [Self.mediaRight(kind: kind, round: round, name: name)]
        if !MTLinks.urls(in: caption).isEmpty { asked.append(.links) }
        if let r = asked.first(where: { x in banned.contains(x.rawValue) }) { return r.refusal }
        return slowRefusal(g, key: key, store: store, except: files)
    }
    /// The slow mode's wait from this phone's last letter in the group -- the rows just laid for `files` are not that letter.
    /// A TRAY SENT AT ONCE IS ONE LETTER TO SLOW MODE (the author's word 25.10.2026 17:40 UTC, council link 8089: «only one file
    /// is added»): each file of a batch was asked alone, so the first one's row stood as «the last letter» of the second, and
    /// in a member's slow group every file after the first was refused and taken off the feed. The batch names all its rows.
    @MainActor
    private func slowRefusal(_ g: MTGroupState, key: String, store: ChatStore, except files: Set<String> = []) -> String? {
        guard let s = g.slow, 0 < s,
              let last = (store.messages[key] ?? []).last(where: { r in
                  r.isFromMe && MTGroupEvent.of(r.text) == nil
                      && Set([r.imageFile, r.videoFile, r.audioFile, r.docFile].compactMap { $0 }).isDisjoint(with: files)
              })?.createdAt else { return nil }
        let left = Double(s) - (Date().timeIntervalSince1970 - last)
        guard 0 < left else { return nil }
        return String(localized: "Slowmode is enabled. You can send your next message in \(Self.span(Int(left.rounded(.up)))).", bundle: MTLanguage.bundle)
    }
    /// Whether the group took every way of writing from this phone: words and every kind of media (G.5) -- the field gives way.
    func mutes(_ key: String) -> Bool {
        guard let g = state(key), g.kind == .group, !g.mine, g.left != true, g.admins?.contains(g.me) != true else { return false }
        let banned = Set(g.barred ?? [])
        return banned.contains(MTGroupRight.text.rawValue) && MTGroupRight.media.filter { r in r != .reactions }.allSatisfy { r in banned.contains(r.rawValue) }
    }
    /// Whether this phone may change the group's name, words and face: its owner, an administrator, or a member the group lets.
    func mayChangeInfo(_ key: String) -> Bool {
        guard let g = state(key), g.left != true else { return false }
        if g.kind == .channel { return Self.adminCan(g, seat: g.me, .info) }   // its owner, or an administrator with «Change Channel Info»
        return Self.adminCan(g, seat: g.me, .info) || !(g.barred ?? []).contains(MTGroupRight.info.rawValue)
    }
    /// THE OWNER SETS WHAT THE MEMBERS MAY DO AND THE SLOW MODE: every member hears it by the invitation's word again.
    @MainActor
    func setRights(_ key: String, banned: Set<String>, slow: Int, store: ChatStore) {
        guard var g = state(key), g.canManage, g.kind == .group else { return }
        let list = MTGroupRight.allCases.map(\.rawValue).filter { x in banned.contains(x) }
        let s = max(0, min(slow, 3600))
        guard list != (g.barred ?? []) || s != (g.slow ?? 0) else { return }
        g.barred = list.nilIfEmpty
        g.slow = 0 < s ? s : nil
        groups[g.id] = g
        saveGroups()
        tellAll(g, face: nil)
        MontanaTrace.mark("group_rights", "banned=\(list.count) slow=\(s)")
    }
    /// A member's renewal asked of the owner: the new name, words and face, small, as an invitation carries them.
    @MainActor
    private func askRenew(_ g: MTGroupState, title: String, faceFile: String?, about: String?) {
        guard mayChangeInfo(Self.key(of: g.id)) else { return }
        let face = faceFile.flatMap { f in try? Data(contentsOf: avatarsDirURL().appendingPathComponent(f)) }.flatMap { d in Self.thumb(d) }
        let w = MTGroupWord(t: "ci", g: g.id, ti: Self.clean(title, Self.titleLimit), ds: about.map { a in Self.clean(a, Self.aboutLimit) },
                            fc: face, id: ChatStore.mintMid().mid, s: g.me)
        _ = carry(w, to: g.owner, letter: "", own: false)
        MontanaTrace.mark("group_renewed", "asked of the owner face=\(face == nil ? 0 : 1)")
    }
    /// A MEMBER'S RENEWAL AT THE OWNER'S PHONE: the seat is the pipe's; the right is the group's «Change Group Info».
    @MainActor
    private func infoAsked(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g], g.mine, g.left != true else { return .refused }
        let from = MTSamePair.root(pipe)
        guard let m = g.members.first(where: { x in MTSamePair.root(x.pipe) == from }),
              Self.adminCan(g, seat: m.seat, .info)
                || (g.kind == .group && !(g.barred ?? []).contains(MTGroupRight.info.rawValue)) else { return .refused }   // a channel's: the admin's right alone
        let key = Self.key(of: g.id)
        let file = Self.face(w.fc)
        renew(key, title: w.ti ?? g.title, faceFile: file, about: w.ds, by: m.seat, store: store)
        if let held = groups[g.id] { stand(held, face: file, store: store, fresh: false) }   // the owner's own row follows the group
        return .held
    }

    // -- chat history for new members (the checklist's G.4) ---------------------------------------------------------------------

    /// The letters of the past one added may read (I-14: bounded, as the reference's own first page is).
    static let historyLimit = 50
    /// THE OWNER SHOWS OR HIDES THE GROUP'S PAST TO NEW MEMBERS (the reference's «Chat History For New Members»).
    @MainActor
    func setHistory(_ key: String, visible: Bool) {
        guard var g = state(key), g.canManage, g.kind == .group, (g.history == true) != visible else { return }
        g.history = visible ? true : nil
        groups[g.id] = g
        saveGroups()
        MontanaTrace.mark("group_history", visible ? "visible" : "hidden")
    }

    // -- member requests (the checklist's G.8, the reference's «Request Admin Approval» and «Member Requests») ----------------------

    /// The owner turns the link's approval on or off; the requests already waiting stay until they are answered.
    @MainActor
    func setApproval(_ key: String, on: Bool) {
        guard var g = state(key), g.canManage, (g.approval == true) != on else { return }
        g.approval = on ? true : nil
        groups[g.id] = g
        saveGroups()
        MontanaTrace.mark("group_link", "approval=\(on ? 1 : 0)")
    }
    /// The people waiting to join, the newest first.
    func requests(_ key: String) -> [MTGroupRequest] { (state(key)?.requests ?? []).sorted { a, b in b.at < a.at } }
    /// THE OWNER ADDS ONE WHO ASKED: by the owner's own road, as by the link (they joined by it).
    @MainActor
    func approve(_ key: String, pipe: String, store: ChatStore) {
        guard state(key)?.canManage == true else { return }
        drop(key, pipe: pipe)
        add(key, people: [Chat(name: pipe, lastMessage: "", time: "", unread: 0, status: "", convId: pipe)], viaLink: true, store: store)
    }
    /// THE OWNER DISMISSES ONE WHO ASKED: they are told nothing; the link may bring them again.
    @MainActor
    func dismiss(_ key: String, pipe: String) {
        guard state(key)?.canManage == true else { return }
        drop(key, pipe: pipe)
    }
    @MainActor
    private func drop(_ key: String, pipe: String) {
        guard var g = state(key) else { return }
        let root = MTSamePair.root(pipe)
        g.requests = g.requests?.filter { r in MTSamePair.root(r.pipe) != root }.nilIfEmpty
        groups[g.id] = g
        saveGroups()
    }

    // -- the pin for everyone (the checklist's B.11, the reference: «Pin this message and notify all members of the group?») ------

    /// WHO PINS FOR EVERYONE: the owner, the administrators it named, and every member while the group lets its members pin -- the
    /// reference's own default for a new group. The one gate of a pin, asked where it is sent and wherever it lands.
    static func pins(_ g: MTGroupState, seat: String) -> Bool {
        guard g.kind == .group else { return false }
        return adminCan(g, seat: seat, .pin) || !(g.barred ?? []).contains(MTGroupRight.pin.rawValue)
    }
    /// Whether this phone pins a letter of the group for everyone.
    func mayPin(_ key: String) -> Bool {
        guard let g = state(key), g.left != true else { return false }
        return Self.pins(g, seat: g.me)
    }
    /// A LETTER PINNED OR UNPINNED FOR EVERYONE: here at once, and its word carried to every phone of the group by the answers' road
    /// (signal); a pin lays the reference's service row. `notify` -- «Pin and notify all members» against «Only Pin».
    @MainActor
    func pin(_ m: Message, pin: Bool, notify: Bool, in key: String, store: ChatStore) {
        guard let g = state(key), g.left != true, Self.pins(g, seat: g.me), let sid = m.msgId, sid.hasPrefix("mid:") else { return }
        if pin { store.pin(key, m.id) } else { store.unpin(key, m.id) }
        var o: [String: Any] = ["sid": sid, "op": pin ? "pin" : "unpin"]
        if !notify { o["n"] = 0 }
        guard let d = try? JSONSerialization.data(withJSONObject: o), let body = String(data: d, encoding: .utf8) else { return }
        signal(pinMark + body, in: key, store: store)
        if pin { lay(MTGroupEvent(e: "pinned", g: g.id, a: g.me, t: Self.pinWords(m)), store: store) }
        MontanaTrace.mark("pin_tx", "group \(pin ? "pin" : "unpin") notify=\(notify ? 1 : 0)")
    }
    /// The pinned letter's words as its service row quotes them: the list's own preview, cut at forty letters.
    static func pinWords(_ m: Message) -> String {
        let w = ChatStore.listPreview(m)
        return w.count <= 40 ? w : String(w.prefix(40)) + "…"
    }

    // -- a channel's views (the reference's eye under a post; MTChannelViews) ---------------------------------

    /// A SUBSCRIBER'S SCREEN SHOWED POSTS: their names go to the owner alone, silent, for its count. False -- no pipe to the owner
    /// now, and the posts wait. It is a read receipt: with the person's «Read receipts» off the word never leaves (the critic's K-1).
    @MainActor
    func tellSeen(_ letters: [String], in key: String) -> Bool {
        guard ChatStore.readReceiptsOn, let g = state(key), g.kind == .channel, !g.mine, g.left != true, !letters.isEmpty else { return false }
        let w = MTGroupWord(t: "vw", g: g.id, id: ChatStore.mintMid().mid, s: g.me,
                            tx: letters.prefix(Self.viewsBatch).joined(separator: ","))   // COMPAT-GATED: an older owner refuses «vw»
        return carry(w, to: g.owner, letter: "", own: false) != nil
    }
    /// THE OWNER TELLS THE NUMBERS THAT MOVED: one silent word to every subscriber.
    @MainActor
    func tellCounts(_ numbers: [String: Int], in key: String) {
        guard let g = state(key), g.kind == .channel, g.canManage, !numbers.isEmpty,
              let d = try? JSONEncoder().encode(numbers), let js = String(data: d, encoding: .utf8) else { return }
        let w = MTGroupWord(t: "vc", g: g.id, id: ChatStore.mintMid().mid, s: Self.ownerSeat, tx: js)   // COMPAT-GATED: an older subscriber refuses «vc»
        for m in g.members { _ = carry(w, to: m.pipe, letter: "", own: false) }
    }
    /// A subscriber's posts shown, at the owner's phone: the seat is the pipe's, and only posts of this channel's feed count.
    @MainActor
    private func seen(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        let from = MTSamePair.root(pipe)
        guard g.mine, g.kind == .channel, g.left != true, let tx = w.tx, tx.utf8.count <= 16_384,
              let m = g.members.first(where: { MTSamePair.root($0.pipe) == from }) else { return .refused }
        let key = Self.key(of: g.id)
        let posts = Set((store.messages[key] ?? []).filter { m in MTGroupEvent.of(m.text) == nil }.map(\.mid))   // the owner's posts and its administrators'
        let letters = tx.split(separator: ",").prefix(Self.viewsBatch).map(String.init)
            .filter { Self.isLetterName($0) && posts.contains("mid:" + $0) }
        MTChannelViews.shared.saw(letters, by: m.seat, in: key)
        return .held
    }
    /// The owner's numbers, at a subscriber's phone: from the owner's pipe alone.
    @MainActor
    private func counted(_ w: MTGroupWord, from pipe: String) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard !g.mine, g.kind == .channel, g.left != true, MTSamePair.root(g.owner) == MTSamePair.root(pipe),
              let tx = w.tx, tx.utf8.count <= 16_384, let d = tx.data(using: .utf8),
              let numbers = try? JSONDecoder().decode([String: Int].self, from: d) else { return .refused }
        MTChannelViews.shared.told(numbers.filter { Self.isLetterName($0.key) }, in: Self.key(of: g.id))
        return .held
    }

    // -- the group's invite link (stage R.6, the reference folder: «Invite Link», «joined the group via invite link») -------------

    /// The link the owner hands out: its own card (whoever opens it meets the owner, the one road of a link) and the group's mark
    /// after it (jg). Nil -- no card stands yet, or this phone is no owner of the group.
    @MainActor
    func inviteLink(_ key: String) -> URL? {
        guard var g = state(key), g.canManage,
              let card = MontanaCard.offerStanding(), var parts = URLComponents(string: card) else { return nil }
        if g.invite == nil {
            g.invite = Self.mintId()
            groups[g.id] = g
            saveGroups()
        }
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: Self.joinParam, value: g.id + "." + (g.invite ?? ""))]
        return parts.url
    }
    /// A new mark: every link given before opens nothing more (the reference's «Reset Link»).
    @MainActor
    func resetInvite(_ key: String) {
        guard var g = state(key), g.canManage else { return }
        g.invite = Self.mintId()
        groups[g.id] = g
        saveGroups()
        // an administrator who invites holds the new link at once (G.6); the old one opens nothing more
        if (g.admins ?? []).contains(where: { s in Self.adminCan(g, seat: s, .invite) }) { tellAll(g, face: nil) }
        MontanaTrace.mark("group_link", "reset")
    }
    static let joinParam = "jg"
    /// A group's id or a link's mark: 32 lowercase hex, the form mintId makes.
    nonisolated static func isMark(_ s: String) -> Bool { s.count == 32 && s.allSatisfy { $0.isHexDigit && !$0.isUppercase } }
    /// A JOIN THAT WAITS FOR ITS MEETING: the link's group and mark, taken off the link before the card is met (MontanaMeeting.handleLink)
    /// and asked of the owner the moment the meeting opens its conversation; ten minutes at most.
    private var waitingJoin: (g: String, mark: String, at: Date)?
    /// The link's group mark, if it carries one, and the link without it -- which goes on to the meeting. Read on any thread.
    nonisolated static func joinMark(in url: URL) -> (url: URL, g: String, mark: String)? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let v = parts.queryItems?.first(where: { $0.name == joinParam })?.value else { return nil }
        let bits = v.split(separator: ".", maxSplits: 1).map(String.init)
        guard bits.count == 2, isMark(bits[0]), isMark(bits[1]) else { return nil }
        parts.queryItems = parts.queryItems?.filter { $0.name != joinParam }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        guard let bare = parts.url else { return nil }
        return (bare, bits[0], bits[1])
    }
    /// The join waits for its meeting.
    @MainActor
    func waitJoin(_ g: String, _ mark: String) {
        waitingJoin = (g, mark, Date())
        MontanaTrace.mark("group_link", "a join waits for its meeting")
    }
    /// The meeting opened its conversation: the waiting join is asked of the owner over it -- at once when the pipe holds, else
    /// a few seconds later, a minute at most.
    @MainActor
    func askJoin(through pipe: String) {
        guard let j = waitingJoin, Date().timeIntervalSince(j.at) < 600 else { return }
        waitingJoin = nil
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        let w = MTGroupWord(t: "jn", g: j.g, n: me.isEmpty ? nil : me, id: ChatStore.mintMid().mid, tx: j.mark)   // COMPAT-GATED
        Task { @MainActor in
            for _ in 0..<30 {
                if MontanaConv.holds(pipe) { break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            let sent = self.carry(w, to: pipe, letter: "", own: false) != nil
            MontanaTrace.mark("group_link", "join asked sent=\(sent ? 1 : 0)")
        }
    }
    /// One who opened the group's link asks at the owner's phone: the mark must be the group's standing one; then the person is
    /// added by the owner's own road, and everyone reads that they joined by the link.
    @MainActor
    private func joined(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g], g.canManage,
              let mark = w.tx, let held = g.invite, mark == held else { return .refused }
        let from = MTSamePair.root(pipe)
        if g.members.contains(where: { MTSamePair.root($0.pipe) == from }) { return .held }   // already in: nothing more
        // ONE THE OWNER TOOK OUT DOES NOT COME BACK BY THE LINK (the reference's «Removed Users»): the owner lets them, or adds them
        if g.banned?.contains(where: { MTSamePair.root($0.pipe) == from }) == true {
            MontanaTrace.mark("group_link", "a removed person asked by the link -- refused")
            return .refused
        }
        // THE LINK ASKS THE OWNER FIRST (G.8): the asker waits among the requests, once, until the owner adds or dismisses them
        if g.approval == true {
            var g2 = g
            var list = (g2.requests ?? []).filter { r in MTSamePair.root(r.pipe) != from }
            list.append(MTGroupRequest(pipe: from, name: Self.clean(w.n ?? "", Self.nameLimit), at: Date().timeIntervalSince1970))
            g2.requests = Array(list.suffix(Self.peopleLimit))
            groups[g2.id] = g2
            saveGroups()
            store.objectWillChange.send()   // the owner's page counts the requests at once
            MontanaTrace.mark("group_link", "a join waits for approval")
            return .held
        }
        add(Self.key(of: g.id), people: [Chat(name: from, lastMessage: "", time: "", unread: 0, status: "", convId: from)],
            viaLink: true, store: store)
        MontanaTrace.mark("group_link", "joined by the link")
        return .held
    }

    // -- mentions (stage R, the reference folder: «@» names a person of the group) ---------------------------------

    /// The people a «@» may name in a group: everyone this phone knows by name in it -- the owner's phone everyone it carries to,
    /// a member's phone the owner and whoever spoke -- this phone aside, and nobody known only as «Member».
    func mentionable(_ key: String) -> [MTRoomPerson] {
        guard let g = state(key), g.kind == .group else { return [] }
        var out = shownSeats(key)
        if !g.mine {
            for (seat, n) in g.names where seat != Self.ownerSeat && !out.contains(where: { $0.seat == seat }) { out.append((seat, n)) }
        }
        return out.filter { $0.seat != g.me && $0.name != Self.memberWord }.map { MTRoomPerson(seat: $0.seat, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// A LETTER THAT NAMES ME (the reference folder's mention): «@» and the name I go by -- my own name or my nick. It rings even in
    /// a chat whose sound is off, as the reference rings a mention.
    static func mentionsMe(_ words: String) -> Bool {
        let low = words.lowercased()
        let names = [E2E.myDisplayName(), MontanaNames.heldName ?? ""]
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        // the name must end where a word ends: «@Al» is not a mention of a person named «Al» inside «@Alex»
        return names.contains { name in
            var from = low.startIndex
            while let r = low.range(of: "@" + name, range: from..<low.endIndex) {
                if r.upperBound == low.endIndex || !(low[r.upperBound].isLetter || low[r.upperBound].isNumber) { return true }
                from = r.upperBound
            }
            return false
        }
    }

    // -- the group's events: rows in the middle of its feed (stage R) ---------------------------------

    /// AN EVENT OF THE GROUP STANDS IN ITS FEED (MTGroupEvent): laid on this phone, in the middle of the feed as the day is. An
    /// organisation's chat takes its people from the core and lays only its calls.
    @MainActor
    func lay(_ e: MTGroupEvent, store: ChatStore? = nil) {
        guard let st = store ?? ChatStore.live, let g = groups[e.g], g.kind == .group, let row = e.row else { return }
        st.appendGroupEvent(Self.key(of: g.id), row)
    }
    /// The owner tells everyone else who came, who was taken out, who left -- by seat, never by a name of the owner's.
    @MainActor
    private func tellEvent(_ e: MTGroupEvent, in g: MTGroupState) {
        guard g.mine, g.kind == .group, let d = try? JSONEncoder().encode(e), let js = String(data: d, encoding: .utf8) else { return }
        let w = MTGroupWord(t: "ev", g: g.id, id: ChatStore.mintMid().mid, s: Self.ownerSeat, tx: js)   // COMPAT-GATED: an older build buries «ev»
        let about = Set(e.p ?? [])
        for m in g.members where !about.contains(m.seat) { _ = carry(w, to: m.pipe, letter: "", own: false) }
    }
    /// AN EVENT FROM THE OWNER (its «ev»): taken from the owner's pipe alone, about seats alone, once by its name.
    @MainActor
    private func evented(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard g.left != true, !g.mine, MTSamePair.root(g.owner) == MTSamePair.root(pipe) else { return .refused }
        guard let id = w.id, Self.isLetterName(id), let tx = w.tx, tx.utf8.count <= 4096, let d = tx.data(using: .utf8),
              let e = try? JSONDecoder().decode(MTGroupEvent.self, from: d), ["added", "removed", "left", "joined"].contains(e.e),
              Self.isSeat(e.a) else { return .refused }
        guard !answersHeard.contains(id) else { return .held }
        answersHeard.append(id)
        if 512 < answersHeard.count { answersHeard.removeFirst(answersHeard.count - 512) }
        let about = Array((e.p ?? []).filter { Self.isSeat($0) }.prefix(Self.peopleLimit))
        lay(MTGroupEvent(e: e.e, g: g.id, a: e.a, p: about.isEmpty ? nil : about), store: store)
        return .held
    }
    /// The sentence an event's row says on this phone: the people by the names this group knows them by, «you» for this phone.
    func eventWords(_ text: String) -> String? {
        guard let e = MTGroupEvent.of(text) else { return nil }
        let me = groups[e.g]?.me
        let mine = e.a == me
        let who = mine ? "" : speakerName(Self.speaker(e.g, e.a))
        let about = e.p ?? []
        let you = me.map { about.contains($0) } ?? false
        let names = about.filter { $0 != me }.map { speakerName(Self.speaker(e.g, $0)) }.joined(separator: ", ")
        let title = e.t ?? ""
        let b = MTLanguage.bundle
        switch e.e {
        case "made":
            return mine ? String(localized: "You created the group \"\(title)\"", bundle: b) : String(localized: "\(who) created the group \"\(title)\"", bundle: b)
        case "added":
            if mine { return String(localized: "You added \(names)", bundle: b) }
            return you ? String(localized: "\(who) added you", bundle: b) : String(localized: "\(who) added \(names)", bundle: b)
        case "removed":
            if mine { return String(localized: "You removed \(names)", bundle: b) }
            return you ? String(localized: "\(who) removed you", bundle: b) : String(localized: "\(who) removed \(names)", bundle: b)
        case "left":
            return mine ? String(localized: "You left the group", bundle: b) : String(localized: "\(who) left the group", bundle: b)
        case "joined":
            return mine ? String(localized: "You joined the group via invite link", bundle: b)
                        : String(localized: "\(who) joined the group via invite link", bundle: b)
        case "named":
            return mine ? String(localized: "You changed the group name to \"\(title)\"", bundle: b)
                        : String(localized: "\(who) changed the group name to \"\(title)\"", bundle: b)
        case "face":
            return mine ? String(localized: "You changed the group photo", bundle: b) : String(localized: "\(who) changed the group photo", bundle: b)
        case "pinned":
            return mine ? String(localized: "You pinned \"\(title)\"", bundle: b) : String(localized: "\(who) pinned \"\(title)\"", bundle: b)
        case "call":
            if e.k == "live" { return mine ? String(localized: "You started a live stream", bundle: b) : String(localized: "\(who) started a live stream", bundle: b) }
            if e.v == 1 { return mine ? String(localized: "You started a video chat", bundle: b) : String(localized: "\(who) started a video chat", bundle: b) }
            return mine ? String(localized: "You started a voice chat", bundle: b) : String(localized: "\(who) started a voice chat", bundle: b)
        case "ended":
            let span = Self.span(e.d ?? 0)
            if e.k == "live" { return String(localized: "Live stream ended (\(span))", bundle: b) }
            if e.v == 1 { return String(localized: "Video chat ended (\(span))", bundle: b) }
            return String(localized: "Voice chat ended (\(span))", bundle: b)
        default:
            return nil
        }
    }
    /// A room's length as the reference's row says it: minutes and seconds, hours when it ran past one.
    static func span(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return 3600 <= s ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
    /// What the head of a group's chat says once this phone is out of it (the reference folder: «you were removed from the group»,
    /// «you have left the group»).
    func outWords(_ key: String) -> String? {
        guard let g = state(key), g.left == true else { return nil }
        let channel = g.kind == .channel
        if g.removed == true {
            return channel ? String(localized: "you were removed from the channel", bundle: MTLanguage.bundle)
                           : String(localized: "you were removed from the group", bundle: MTLanguage.bundle)
        }
        return channel ? String(localized: "you have left the channel", bundle: MTLanguage.bundle)
                       : String(localized: "you have left the group", bundle: MTLanguage.bundle)
    }

    /// DELETE AND EXIT (the reference folder: the button standing in the field's place once a person is out): the chat and its rows
    /// leave this phone; the group stays known as one this phone is out of, so a word still on its way finds its road over and brings
    /// nothing back -- only the owner adding this phone again stands it anew.
    @MainActor
    func erase(_ key: String, store: ChatStore) {
        guard let g = state(key), g.left == true else { return }
        let row = store.storedChats().first { $0.id == key } ?? store.storedArchived().first { $0.id == key }
            ?? Chat(name: key, lastMessage: "", time: nowHHMM(), unread: 0, status: "", photoURL: nil,
                    isGroup: true, isAdmin: g.mine, members: [], convId: key, displayName: g.title)
        store.deleteChat(row, forBoth: false)
        MontanaTrace.mark("group_erased", "out=\(g.removed == true ? "removed" : "left")")
    }
    /// LEAVE GROUP (the reference folder: «Are you sure you want to leave and delete %@?»): the owner is told, and the chat goes.
    @MainActor
    func leaveAndErase(_ key: String, store: ChatStore) {
        leave(key, store: store)
        erase(key, store: store)
    }
    /// DELETE FOR ALL (the reference folder: the owner's «Delete Group» -- «delete the group and all of its messages for all
    /// members»): every member is told by the owner's own «out», marked as the group's end -- a build that reads the mark erases the
    /// chat, an older one stands it read-only, as a taking out -- and the chat leaves this phone, the group known as ended here.
    @MainActor
    func dissolve(_ key: String, store: ChatStore) {
        guard var g = state(key), g.mine, g.left != true else { return }
        var w = MTGroupWord(t: "out", g: g.id)
        w.dl = 1
        for m in g.members { _ = carry(w, to: m.pipe, letter: "", own: false) }
        MTGroupRoom.shared.groupGone(g.id)
        g.left = true
        g.members = []
        groups[g.id] = g
        saveGroups()
        erase(key, store: store)
        MontanaTrace.mark("group_dissolved", "by its owner")
    }

    // -- the group's life: its name and face, its people, leaving ---------------------------------

    /// THE OWNER RENAMES THE GROUP OR GIVES IT A NEW FACE (its page): every member is told by the invitation's own word again --
    /// the same group, the same seat, the new title and face -- so every phone shows what the owner's shows.
    @MainActor
    func renew(_ key: String, title: String, faceFile: String?, about: String? = nil, by actor: String = MTGroup.ownerSeat, store: ChatStore) {
        // A MEMBER WITH «CHANGE GROUP INFO» (G.5) asks the owner, whose phone carries the group; the owner's own hand renews here.
        if let m = state(key), !m.mine, m.left != true { askRenew(m, title: title, faceFile: faceFile, about: about); return }
        guard var g = state(key), g.canManage else { return }
        let name = Self.clean(title, Self.titleLimit)
        let face = faceFile.flatMap { try? Data(contentsOf: avatarsDirURL().appendingPathComponent($0)) }
        // the description, the owner's words about the group (stage R): carried in the invitation's ds, as at the group's birth
        let words = about.map { Self.clean($0, Self.aboutLimit) }
        let described = words.map { $0 != g.about } ?? false
        guard !name.isEmpty, name != g.title || face != nil || described else { return }
        let renamed = name != g.title
        if renamed { act(&g, "title", t: name) }
        if described { act(&g, "about") }
        if face != nil { act(&g, "photo") }
        g.title = name
        if let words { g.about = words }
        if face != nil, let faceFile { g.face = faceFile }   // the group owns its face (stand)
        groups[g.id] = g
        saveGroups()
        if face != nil { store.mirrorFaceToShared(key) }
        // The owner's own row is the page's to write (ChatsListView.updateChat): a second writer of the shelf here would lay the
        // shelf back over the page's fresh copy.
        tellAll(g, face: face.flatMap { Self.thumb($0) }, by: actor)
        if renamed { lay(MTGroupEvent(e: "named", g: g.id, a: actor, t: name), store: store) }
        if face != nil { lay(MTGroupEvent(e: "face", g: g.id, a: actor), store: store) }
        MontanaTrace.mark("group_renewed", "face=\(face == nil ? 0 : 1)")
    }

    /// THE OWNER ADDS PEOPLE (its page): each new one is invited with a seat of their own, and everyone learns the new count.
    @MainActor
    func add(_ key: String, people: [Chat], viaLink: Bool = false, store: ChatStore) {
        guard var g = state(key), g.canManage else { return }
        let held = Set(g.members.map { MTSamePair.root($0.pipe) })
        var taken = Set(g.members.map(\.seat) + [Self.ownerSeat])
        var fresh: [MTGroupMember] = []
        for c in people where !c.isGroup {
            let p = MTSamePair.root(c.convRef)
            guard MontanaConv.holds(p), !ChatStore.refusesCold(p), !held.contains(p), !fresh.contains(where: { $0.pipe == p }),
                  g.members.count + fresh.count < Self.peopleLimit else { continue }
            var seat = Self.mintSeat()
            while taken.contains(seat) { seat = Self.mintSeat() }
            taken.insert(seat)
            fresh.append(MTGroupMember(seat: seat, pipe: p))
        }
        guard !fresh.isEmpty else { return }
        g.members += fresh
        g.count = g.members.count + 1
        // one taken out and added again by the owner's own hand is let back (the reference's «Add To Channel»)
        g.banned = g.banned?.filter { b in !fresh.contains { f in f.pipe == MTSamePair.root(b.pipe) } }.nilIfEmpty
        act(&g, viaLink ? "joined" : "invited", p: fresh.map { f in seatName(g, f.seat) })
        groups[g.id] = g
        saveGroups()
        let face = store.storedChats().first(where: { $0.id == key })?.photoURL.flatMap { try? Data(contentsOf: avatarsDirURL().appendingPathComponent($0)) }
        tellAll(g, face: face.flatMap { Self.thumb($0) }, only: Set(fresh.map(\.seat)))
        // one who came by the group's link joined by their own hand (the reference: «%@ joined the group via invite link»)
        let came = viaLink ? MTGroupEvent(e: "joined", g: g.id, a: fresh[0].seat)
                           : MTGroupEvent(e: "added", g: g.id, a: Self.ownerSeat, p: fresh.map(\.seat))
        lay(came, store: store)
        tellEvent(came, in: g)
        // A SUBSCRIBER ADDED LATER READS THE CHANNEL'S NEWEST POSTS (the reference shows a channel's history to whoever comes in;
        // the author's words 17.10.2026 15:4x UTC: «channels ... 1 to 1»): the newest ten posts of words, each under its own one name
        // and so at its own moment, as every subscriber was carried it. A post with a file stays: its sealed pieces were laid for
        // the receivers of its day.
        // CHAT HISTORY FOR NEW MEMBERS (G.4, the reference's «Visible»): one added reads the group's newest words -- fifty letters of
        // words, each under its own one name and so at its own moment, by its own speaker, silent; a letter with a file stays, its
        // sealed pieces laid for the receivers of its day.
        if g.kind == .group, g.history == true {
            let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
            let past = (store.messages[key] ?? []).filter { m in
                m.imageFile == nil && m.videoFile == nil && m.audioFile == nil && m.docFile == nil
                    && MTGroupEvent.of(m.text) == nil && Self.carries(m.text) && !m.text.hasPrefix(mediaMark)
            }
            let head = Self.speaker(g.id, "")
            for p in past.suffix(Self.historyLimit) {
                let letter = p.mid.hasPrefix("mid:") ? String(p.mid.dropFirst(4)) : p.mid
                let seat = p.isFromMe ? g.me : (p.senderRef.flatMap { r in r.hasPrefix(head) ? String(r.dropFirst(head.count)) : nil } ?? "")
                guard Self.isLetterName(letter), Self.isSeat(seat), !fresh.contains(where: { f in f.seat == seat }) else { continue }
                let name = seat == g.me ? me : (g.names[seat] ?? "")
                var w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: name.isEmpty ? nil : name, id: letter, s: seat, tx: p.text,
                                    qt: (p.replyText ?? "").isEmpty ? nil : p.replyText)
                w.hs = 1
                for m in fresh { _ = carry(w, to: m.pipe, letter: "", own: false) }
            }
        }
        if g.kind == .channel {
            let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
            let posts = (store.messages[key] ?? []).filter { m in
                m.isFromMe && m.imageFile == nil && m.videoFile == nil && m.audioFile == nil && m.docFile == nil
                    && MTGroupEvent.of(m.text) == nil && Self.carries(m.text)
            }
            for p in posts.suffix(10) {
                let letter = p.mid.hasPrefix("mid:") ? String(p.mid.dropFirst(4)) : p.mid
                guard Self.isLetterName(letter) else { continue }
                let w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: letter, s: g.me, tx: p.text,
                                    qt: (p.replyText ?? "").isEmpty ? nil : p.replyText)
                for m in fresh { _ = carry(w, to: m.pipe, letter: "", own: false) }
            }
        }
        MontanaTrace.mark("group_added", "people=\(fresh.count) count=\(g.count)")
    }

    /// THE OWNER TAKES A PERSON OUT (its page): they are told by their own word and stop being carried to; everyone left learns
    /// the new count. Their letters already in the group stay where they stand.
    @MainActor
    func remove(_ key: String, seat: String, by actor: String = MTGroup.ownerSeat, store: ChatStore) {
        guard var g = state(key), g.canManage, let m = g.members.first(where: { $0.seat == seat }) else { return }
        // ONE TAKEN OUT IS KEPT OUT (the reference's «Removed Users»): a channel's and -- the groups checklist's G.7 and E.4 -- a group's;
        // the link opens nothing for them until the owner lets them back or adds them again
        g.banned = Array(((g.banned ?? []).filter { b in b.seat != seat } + [m]).suffix(Self.peopleLimit))
        act(&g, "removed", p: [seatName(g, seat)])
        g.members.removeAll { $0.seat == seat }
        g.admins = g.admins?.filter { $0 != seat }.nilIfEmpty   // a person taken out is nobody's administrator
        g.count = g.members.count + 1
        groups[g.id] = g
        saveGroups()
        _ = carry(MTGroupWord(t: "out", g: g.id), to: m.pipe, letter: "", own: false)
        tellAll(g, face: nil)
        let out = MTGroupEvent(e: "removed", g: g.id, a: actor, p: [seat])   // an administrator's deed says its own name
        lay(out, store: store)
        tellEvent(out, in: g)
        MontanaTrace.mark("group_removed", "count=\(g.count)")
    }

    /// A MEMBER LEAVES (its page): the owner is told and carries nothing more to this phone; the group's rows stay readable here,
    /// and a word of the group still on its way is answered as one whose road is over.
    @MainActor
    func leave(_ key: String, store: ChatStore) {
        guard var g = state(key), !g.mine, g.left != true else { return }
        g.left = true
        groups[g.id] = g
        saveGroups()
        _ = carry(MTGroupWord(t: "bye", g: g.id), to: g.owner, letter: "", own: false)
        MTGroupRoom.shared.groupGone(g.id)   // its room goes with the group
        MontanaTrace.mark("group_left", "by this phone")
    }

    /// The invitation's word again to every member: the title, the words about the group, the count, and a new face when one is
    /// given. Each member keeps their seat.
    /// `only` -- the seats the face goes to (the people just added); everyone else learns the count without it.
    @MainActor
    private func tellAll(_ g: MTGroupState, face: String?, only: Set<String>? = nil, by actor: String = MTGroup.ownerSeat) {
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        // the group's link, minted once, for the administrators who may invite by it (G.6)
        let link = (g.admins ?? []).contains(where: { s in Self.adminCan(g, seat: s, .invite) }) ? inviteLink(Self.key(of: g.id))?.absoluteString : nil
        for m in g.members {
            let fc = (only == nil || only?.contains(m.seat) == true) ? face : nil
            var w = MTGroupWord(t: "inv", g: g.id, k: g.kind.rawValue, ti: g.title, ds: g.about.isEmpty ? nil : g.about, fc: fc,
                                c: g.count, me: m.seat, n: me.isEmpty ? nil : me)
            w.ad = g.admins   // the administrators the owner named (stage R.6)
            w.bn = g.barred   // what the members may not do, and the slow mode (G.5)
            w.sw = g.slow
            w.ax = g.adminTaken   // the administrators' rights left out and the custom titles (G.6)
            w.rk = g.ranks
            if g.admins?.contains(m.seat) == true, Self.adminCan(g, seat: m.seat, .invite) { w.lk = link }   // the link, to an admin who invites
            if actor != Self.ownerSeat { w.s = actor }   // a member's renewal names its own hand (G.5)
            w.sg = g.kind == .channel && g.signs == true ? 1 : nil   // a channel signs its posts (Sign Messages)
            w.rx = g.kind == .channel && g.reacts == false ? 0 : nil   // a channel takes no reactions (Allow Reactions off)
            w.dc = g.kind == .channel && g.talks == true ? 1 : nil   // a channel's subscribers comment (Allow Comments)
            w.rl = g.kind == .channel ? g.reactList : nil   // the reactions a channel takes (Some Reactions)
            _ = carry(w, to: m.pipe, letter: "", own: false)
        }
    }

    // -- the receipts of the copies ------------------------------------------------------------

    /// A copy was receipted (ChatStore.markDelivered, after the queue let it go). True when the name was a group's copy.
    @MainActor
    func copyDelivered(_ name: String, store: ChatStore) -> Bool {
        guard ready(), let c = copies.removeValue(forKey: name) else { return false }
        saveCopies()
        MontanaTrace.mark("group_rcpt", mid: name, "own=\(c.own ? 1 : 0)")
        if c.own { follow(c, store: store) }
        return true
    }
    /// The node holds a copy (ChatStore.markSentByNode): my row has left this phone.
    @MainActor
    func copyHeld(_ name: String, store: ChatStore) -> Bool {
        guard ready(), let c = copies[name] else { return false }
        if !c.held { copies[name]?.held = true; saveCopies() }
        if c.own { follow(c, store: store) }
        return true
    }
    /// The queue settled a copy (ChatStore.settleByMid): my row follows its copies.
    @MainActor
    func copySettled(_ name: String, store: ChatStore) -> Bool {
        guard ready(), let c = copies[name] else { return false }
        if c.own { follow(c, store: store) }
        return true
    }
    /// The queue refused a copy by a word (ChatStore.settleRefused, MTRefusal) -- my row says so.
    @MainActor
    func copyRefused(_ name: String, store: ChatStore) -> Bool {
        guard ready(), let c = copies[name] else { return false }
        if !c.failed { copies[name]?.failed = true; saveCopies() }
        if c.own { follow(c, store: store) }
        return true
    }
    /// MY ROW STANDS WHERE ITS RECEIVERS SAY (the groups checklist): delivered when every copy is receipted, red while a copy has
    /// failed, sent once the node holds one or one is receipted. Through the ladder's one door: forward only, red only from below.
    @MainActor
    private func follow(_ c: MTGroupCopy, store: ChatStore) {
        guard !c.letter.isEmpty else { return }
        let key = Self.key(of: c.group)
        guard let i = store.messages[key]?.firstIndex(where: { $0.isFromMe && $0.mid == "mid:" + c.letter }) else { return }
        let left = copies.values.filter { $0.own && $0.group == c.group && $0.letter == c.letter }
        if left.isEmpty {
            store.advance(key, i, to: .delivered)
        } else if left.contains(where: { $0.failed }) {
            store.putOut(key, i, because: .copyRefused)
        } else if left.count < c.of || left.contains(where: { $0.held }) {
            store.advance(key, i, to: .sent)
        }
    }
    /// Whether a row of mine still has a copy in the queue (ChatStore.paintOrphanSending): a clock with nothing behind it is a lie.
    func rides(_ letter: String, queued: Set<String>) -> Bool {
        guard ready() else { return true }   // an unread store says nothing is lost: the clock waits for the store
        return copies.contains { $0.value.own && $0.value.letter == letter && queued.contains($0.key) }
    }
    /// A ROW OF MINE STANDS WHERE ITS COPIES SAY, ASKED AGAIN AT THE COLD SWEEP (the author's words 27.10.2026 09:15 UTC and 09:44 UTC,
    /// council links 9561, 9597: after a relaunch a channel's files wore red and «retry» though they stood in the channel). A group's
    /// media rides on its copies, under names of their own and never under the letter's (carry): the sweep asked the queue for the
    /// letter's name, found none, and painted red a row whose copies were carried (T1, 2314: «TX stale -> failed chat=grp:...» at
    /// every launch after «upload END group carried=1»). True when the row is the group's to answer -- a copy of mine names the letter,
    /// or the store is not read yet; the row is moved by `follow`, the ladder's one door, as its receipts would move it.
    @MainActor
    func answersFor(_ letter: String, store: ChatStore) -> Bool {
        guard ready() else { return true }   // an unread store says nothing is lost: the clock waits for the store
        guard let c = copies.values.first(where: { $0.own && $0.letter == letter }) else { return false }
        follow(c, store: store)
        return true
    }

    // -- arrival -------------------------------------------------------------------------------

    /// `instant` -- a word that lived an instant (a typing word): it rode no queue, so nothing is receipted and nothing knocks again.
    enum Verdict { case held, refused, wait, instant }

    /// A group's word arrived on a pipe (ChatStore.append). True when it was ours to read: it is never a row of the pipe. Every
    /// copy is answered by the one receipt door on the pipe it came by -- held, or with its road over here; a letter of a group
    /// whose invitation has not landed yet is not answered, and its copy knocks again.
    @MainActor
    static func handle(_ text: String, from pipe: String, isFromMe: Bool, sid: String?, store: ChatStore) -> Bool {
        guard text.hasPrefix(mark) else { return false }
        guard !isFromMe else { return true }
        var verdict = Verdict.refused
        if let d = String(text.dropFirst(mark.count)).data(using: .utf8),
           let w = try? JSONDecoder().decode(MTGroupWord.self, from: d), MontanaArchive.isLabel(w.g) {
            // THE PERSON'S OWN WORD, HEARD ON A PIPE ITS DEVICES SHARE (the author's word 18.10.2026 10:3x UTC: «check what the errors of
            // sending into channels on T1 are, and fix everything»). Measured: T1 and the Mac refused each other's group words without
            // end -- 292 «a member's letter in a channel is not carried» and 219 «invitation of a group held by another owner» on T1
            // from 17.10 16:18 on: the Mac, the same person, carried its channel's posts and invitations to a member, and T1, holding the
            // same end of that member's pipe, heard them as the member's. A word this person signed is done here as the hand did it
            // there (replay) -- never judged as a stranger's, never answered: the device that spoke carries it.
            if shared.ownWord(w, pipe: pipe) {
                MainActor.assumeIsolated { shared.replay(w, to: pipe, store: store) }
                return true
            }
            verdict = shared.take(w, from: pipe, copy: sid ?? "", store: store)
        } else {
            MontanaTrace.mark("group_refused", "unreadable from=\(String(pipe.prefix(10)))")
        }
        if verdict != .wait, verdict != .instant {
            store.sendDeliveryReceipt(pipe, msgId: sid, isFromMe: false, text: text, buried: verdict == .refused)
        }
        return true
    }

    @MainActor
    private func take(_ w: MTGroupWord, from pipe: String, copy: String, store: ChatStore) -> Verdict {
        guard ready() else { return .wait }   // the copy knocks again once the store opens
        switch w.t {
        case "inv": return invited(w, by: pipe, store: store)
        case "say": return heard(w, from: pipe, copy: copy, store: store)
        case "sig": return answered(w, from: pipe, store: store)
        case "bye": return parted(w, from: pipe, store: store)
        case "out": return dropped(w, by: pipe, store: store)
        case "wl": return wallWord(w, from: pipe, store: store)   // COMPAT-GATED: a channel's wall word (06.10)
        case "room": return roomed(w, from: pipe, copy: copy)   // COMPAT-GATED: a group room's word (07.10)
        case "ev": return evented(w, from: pipe, store: store)
        case "kk": return kicked(w, from: pipe, store: store)   // COMPAT-GATED: an administrator's «take out», to the owner
        case "jn": return joined(w, from: pipe, store: store)   // COMPAT-GATED: a person who opened the group's invite link
        case "kp": return keptHeard(w, from: pipe)   // COMPAT-GATED: a keeper's word to a deleted letter's speaker (16.10)
        case "ty": return typed(w, from: pipe)   // COMPAT-GATED: a member typing, an instant word an older build buries (B.12)
        case "rd": return readWord(w, from: pipe, store: store)   // COMPAT-GATED: a reader's mark, an older build buries it (B.13)
        case "ci": return infoAsked(w, from: pipe, store: store)   // COMPAT-GATED: a member's renewal, to the owner (G.5)
        case "vw": return seen(w, from: pipe, store: store)   // COMPAT-GATED: a subscriber's posts shown, to a channel's owner (17.10)
        case "vc": return counted(w, from: pipe)   // COMPAT-GATED: a channel owner's view counts, to its subscribers (17.10)
        case "cm": return commented(w, from: pipe, store: store)   // COMPAT-GATED: a comment under a channel's post (17.10)
        case "lp": return carded(w, from: pipe, store: store)   // COMPAT-GATED: a letter's link card (17.10), an older build buries it
        case "sp": return passported(w, from: pipe, store: store)   // COMPAT-GATED: a sticker's passport (17.10), an older build buries it
        default:
            MontanaTrace.mark("group_refused", "kind=\(String(w.t.prefix(8)))")   // a newer build's word: its road ends here
            return .refused
        }
    }

    // -- the seed's own words from its other devices (the twin mirror, 18.10.2026) --------------------------------------

    /// A group's word rides to the seed's other devices unless it lived an instant: a typing word would be stale where it landed
    /// (MontanaDeliveryEngine.mirrors).
    nonisolated static func mirrors(_ text: String) -> Bool {
        guard let d = String(text.dropFirst(mark.count)).data(using: .utf8),
              let w = try? JSONDecoder().decode(MTGroupWord.self, from: d) else { return false }
        return w.t != "ty"
    }

    /// THE SEED'S OWN GROUP WORD FROM ANOTHER OF ITS DEVICES (the author's words 18.10.2026 07:3x-07:4x UTC: «on the Mac, in my own
    /// groups and channels, what I posted from the phone is not seen -- it does not sync as the chats do»; «on T1 and on the Mac one
    /// and the same person»). A group was its owner's PHONE: a seed's second device stood in no group the first made, heard none of
    /// its letters (handle buries a word of the person's own), and judged a member's letter by another state -- T1 18.10.2026
    /// 07:07:00Z refused four channel letters the Mac took. What that device said is what this person said, so it is done here as
    /// the hand did it there: an invitation stands the group and its member, a letter its row, a taking out and a leaving their
    /// state -- and nothing is said to anyone again: the device that spoke already carried it.
    @MainActor
    static func handleOwn(_ text: String, from pipe: String, store: ChatStore) {
        guard let d = String(text.dropFirst(mark.count)).data(using: .utf8),
              let w = try? JSONDecoder().decode(MTGroupWord.self, from: d), MontanaArchive.isLabel(w.g) else { return }
        shared.replay(w, to: pipe, store: store)
    }

    /// The fields the person's tag is made over: the group, the kind, the letter's name, the seats and the words -- what a member
    /// could alter to pass another's word off.
    private static func tagText(_ w: MTGroupWord) -> String {
        [w.t, w.id ?? "", w.me ?? "", w.s ?? "", w.ti ?? "", w.tx ?? ""].joined(separator: "\u{0}")
    }
    /// The person's tag on a word carried on one pipe: the letter author's key (MTLetterAuthor) over that pipe's secret.
    static func ownTag(_ w: MTGroupWord, pipe: String) -> String? {
        guard let key = MTLetterAuthor.key, let held = MTPipeBook.key(for: pipe) else { return nil }
        return held.authorTag(person: key, mid: w.g, text: tagText(w))
    }
    /// Whether a word heard on a pipe was signed by this person -- on another of its devices.
    func ownWord(_ w: MTGroupWord, pipe: String) -> Bool {
        guard let tag = w.au, let held = MTPipeBook.key(for: pipe) else { return false }
        return held.authorHolds(tag, person: MTLetterAuthor.key, mid: w.g, text: Self.tagText(w))
    }

    @MainActor
    private func replay(_ w: MTGroupWord, to pipe: String, store: ChatStore) {
        guard ready() else { return }
        switch w.t {
        case "inv": replayInvitation(w, to: pipe, store: store)
        case "say": replayLetter(w, store: store)
        case "out":
            let gone = MTSamePair.root(pipe)
            guard var g = groups[w.g], g.mine, let m = g.members.first(where: { x in MTSamePair.root(x.pipe) == gone }) else { return }
            g.banned = Array(((g.banned ?? []).filter { b in b.seat != m.seat } + [m]).suffix(Self.peopleLimit))
            g.members.removeAll { x in x.seat == m.seat }
            g.admins = g.admins?.filter { a in a != m.seat }.nilIfEmpty
            g.count = g.members.count + 1
            groups[g.id] = g
            saveGroups()
            lay(MTGroupEvent(e: "removed", g: g.id, a: Self.ownerSeat, p: [m.seat]), store: store)
        case "bye":
            guard var g = groups[w.g], !g.mine, g.left != true else { return }
            g.left = true
            groups[g.id] = g
            saveGroups()
            MTGroupRoom.shared.groupGone(g.id)
        default:
            MontanaTrace.markFolded("group_own", "kind=\(String(w.t.prefix(8))) -- the other device's word, applied to nobody", window: 30, key: w.t)
            return
        }
        MontanaTrace.mark("group_own", "kind=\(w.t) group=\(String(w.g.prefix(6)))")
    }

    /// The sibling invited a person into a group of this seed -- its birth, an addition, a renewal: the group stands here as its
    /// owner's, with that person at the seat the word gave them, by the pipe the word rode (the pipes of one seed are one book).
    @MainActor
    private func replayInvitation(_ w: MTGroupWord, to pipe: String, store: ChatStore) {
        let title = Self.clean(w.ti ?? "", Self.titleLimit)
        guard let kind = MTGroupKind(rawValue: w.k ?? ""), !title.isEmpty,
              let seat = w.me, Self.isSeat(seat), seat != Self.ownerSeat else { return }
        let member = MTSamePair.root(pipe)
        let fresh = groups[w.g] == nil
        var g = groups[w.g] ?? MTGroupState(id: w.g, kind: kind, title: title, owner: "", me: Self.ownerSeat, members: [], count: 2,
                                           names: [:], at: Date().timeIntervalSince1970)
        guard g.mine else { return MontanaTrace.mark("group_refused", "an own invitation of a group this device holds as a member") }
        let renamed = !fresh && g.title != title
        g.title = title
        g.about = Self.clean(w.ds ?? "", Self.aboutLimit)
        g.members.removeAll { m in m.seat == seat || MTSamePair.root(m.pipe) == member }
        g.members.append(MTGroupMember(seat: seat, pipe: member))
        g.banned = g.banned?.filter { b in MTSamePair.root(b.pipe) != member }.nilIfEmpty
        g.count = max(g.members.count + 1, min(w.c ?? 2, Self.peopleLimit + 1))
        g.admins = w.ad.map { a in a.filter(Self.isSeat) }.flatMap { a in a.isEmpty ? nil : a }
        g.barred = w.bn.map { b in b.filter { x in MTGroupRight(rawValue: x) != nil } }.flatMap { b in b.isEmpty ? nil : b }
        g.slow = w.sw.flatMap { x in 0 < x ? min(x, 3600) : nil }
        Self.takeAdmins(w, into: &g)
        g.signs = w.sg == 1 ? true : nil
        g.reacts = w.rx == 0 ? false : nil
        g.talks = w.dc == 1 ? true : nil
        g.reactList = Self.reactionList(w.rl)
        let tag = w.fc.map { f in String(f.count) + "-" + String(f.suffix(16)) }
        let newFace = tag != nil && tag != g.faceTag
        if newFace { g.faceTag = tag }
        groups[w.g] = g
        saveGroups()
        stand(g, face: newFace ? Self.face(w.fc) : nil, store: store)
        if fresh { lay(MTGroupEvent(e: "made", g: g.id, a: Self.ownerSeat, t: title), store: store) }
        if renamed { lay(MTGroupEvent(e: "named", g: g.id, a: Self.ownerSeat, t: title), store: store) }
    }

    /// A letter the sibling wrote into a group of this seed, or carried there for a member: its row stands here under its one name,
    /// as the person's own when its seat is this person's, never a second time and never over its tombstone.
    @MainActor
    private func replayLetter(_ w: MTGroupWord, store: ChatStore) {
        guard let g = groups[w.g], g.left != true, let id = w.id, Self.isLetterName(id), let words = w.tx, Self.carries(words),
              let seat = w.s, Self.isSeat(seat) else { return }
        let key = Self.key(of: g.id)
        let sid = "mid:" + id
        guard store.messages[key]?.contains(where: { r in r.mid == sid }) != true, !store.buried(sid, in: key) else { return }
        let mine = seat == g.me
        stand(g, face: nil, store: store)
        let born = MontanaDeliveryEngine.letterMoment(mid: sid, sentAt: nil, own: mine)
        let quote = (w.qt ?? "").isEmpty ? nil : w.qt
        let row = Message(text: words, isFromMe: mine, time: hhmm(at: born), replyText: quote, deliveryStatus: mine ? .sent : .delivered,
                          msgId: sid, senderRef: mine ? nil : Self.speaker(g.id, seat), createdAt: born,
                          replyToId: store.localId(forMid: w.qm, chat: key))
        let landed = store.append(key, row)
        MontanaTrace.mark("group_own", mid: id, "letter landed=\(landed ? 1 : 0) mine=\(mine ? 1 : 0)")
    }

    /// AN INVITATION: the group stands on this phone, owned by the pipe the word came by. A second invitation of the same owner
    /// renews the title and the count; another pipe naming a group this phone already holds is refused.
    @MainActor
    private func invited(_ w: MTGroupWord, by pipe: String, store: ChatStore) -> Verdict {
        let owner = MTSamePair.root(pipe)
        let title = Self.clean(w.ti ?? "", Self.titleLimit)
        guard let kind = MTGroupKind(rawValue: w.k ?? ""), !title.isEmpty,
              let seat = w.me, Self.isSeat(seat), seat != Self.ownerSeat else { return .refused }
        let count = max(2, min(w.c ?? 2, Self.peopleLimit + 1))
        let ownerName = Self.clean(w.n ?? "", Self.nameLimit)
        if var g = groups[w.g] {
            guard !g.mine, MTSamePair.root(g.owner) == owner else {
                MontanaTrace.mark("group_refused", "invitation of a group held by another owner")
                return .refused
            }
            // Out of the group, a word of the old seat is one that was on its way; the owner adding this phone again gives a new seat.
            let back = g.left == true
            if back {
                guard seat != g.me else { return .refused }
                g.left = nil
                g.removed = nil
            }
            let renamed = !back && g.title != title
            let hadFace = g.faceTag != nil
            g.title = title
            g.about = Self.clean(w.ds ?? "", Self.aboutLimit)
            g.count = count
            g.me = seat
            if !ownerName.isEmpty { g.names[Self.ownerSeat] = ownerName }
            g.admins = w.ad.map { $0.filter(Self.isSeat) }.flatMap { $0.isEmpty ? nil : $0 }   // the owner's word alone names them
            g.barred = w.bn.map { b in b.filter { x in MTGroupRight(rawValue: x) != nil } }.flatMap { b in b.isEmpty ? nil : b }
            g.slow = w.sw.flatMap { s in 0 < s ? min(s, 3600) : nil }
            Self.takeAdmins(w, into: &g)
            g.signs = w.sg == 1 ? true : nil
            g.reacts = w.rx == 0 ? false : nil
            g.talks = w.dc == 1 ? true : nil
            g.reactList = Self.reactionList(w.rl)
            let tag = w.fc.map { String($0.count) + "-" + String($0.suffix(16)) }
            let newFace = tag != nil && tag != g.faceTag
            if newFace { g.faceTag = tag }
            groups[w.g] = g
            saveGroups()
            stand(g, face: newFace ? Self.face(w.fc) : nil, store: store)
            // the reference folder's rows: added again, a new name, a new face -- each the owner's deed
            if back { lay(MTGroupEvent(e: "added", g: g.id, a: Self.ownerSeat, p: [seat]), store: store) }
            let actor = w.s.flatMap { s in Self.isSeat(s) ? s : nil } ?? Self.ownerSeat   // a member's renewal, named by the owner (G.5)
            if renamed { lay(MTGroupEvent(e: "named", g: g.id, a: actor, t: title), store: store) }
            if newFace, hadFace, !back { lay(MTGroupEvent(e: "face", g: g.id, a: actor), store: store) }
            return .held
        }
        var g = MTGroupState(id: w.g, kind: kind, title: title, about: Self.clean(w.ds ?? "", Self.aboutLimit), owner: owner, me: seat,
                             members: [], count: count, names: ownerName.isEmpty ? [:] : [Self.ownerSeat: ownerName],
                             at: Date().timeIntervalSince1970)
        g.admins = w.ad.map { $0.filter(Self.isSeat) }.flatMap { $0.isEmpty ? nil : $0 }
        g.barred = w.bn.map { b in b.filter { x in MTGroupRight(rawValue: x) != nil } }.flatMap { b in b.isEmpty ? nil : b }
        g.slow = w.sw.flatMap { s in 0 < s ? min(s, 3600) : nil }
        Self.takeAdmins(w, into: &g)
        g.signs = w.sg == 1 ? true : nil
        g.reacts = w.rx == 0 ? false : nil
        g.talks = w.dc == 1 ? true : nil
        g.reactList = Self.reactionList(w.rl)
        g.faceTag = w.fc.map { String($0.count) + "-" + String($0.suffix(16)) }
        groups[w.g] = g
        saveGroups()
        stand(g, face: Self.face(w.fc), store: store)
        lay(MTGroupEvent(e: "added", g: g.id, a: Self.ownerSeat, p: [seat]), store: store)   // «X added you»
        MontanaTrace.mark("group_rx", "invitation kind=\(kind.rawValue) people=\(count) from=\(String(pipe.prefix(10)))")
        return .held
    }

    /// A LETTER: it lands in the group's feed by the one landing road (ChatStore.append). The owner takes a letter only from a
    /// member it carries to -- in a group, never in a channel -- and carries it on to every other member; a member takes letters
    /// from the owner's pipe alone.
    @MainActor
    private func heard(_ w: MTGroupWord, from pipe: String, copy: String, store: ChatStore) -> Verdict {
        guard var g = groups[w.g] else { return .wait }
        guard g.left != true else { return .refused }   // out of the group: the word's road ends here
        guard let id = w.id, Self.isLetterName(id), let words = w.tx, Self.carries(words) else { return .refused }
        let post = MTBoard.isChannelPost(words)
        if post, g.kind != .channel || g.mine { return .refused }   // a wall's post rides a channel alone, from its owner
        let from = MTSamePair.root(pipe)
        let seat: String
        if g.mine {
            guard let m = g.members.first(where: { MTSamePair.root($0.pipe) == from }) else { return .refused }
            // A CHANNEL CARRIES ITS ADMINISTRATORS' POSTS (the reference's «Post Messages» right): the owner named them; anyone else
            // only reads.
            guard g.kind == .group || (g.admins?.contains(m.seat) == true
                                          && !(g.adminTaken?[m.seat] ?? []).contains(MTChannelRight.post.rawValue)) else {   // «Post Messages»
                MontanaTrace.mark("group_refused", "a member's letter in a channel is not carried")
                return .refused
            }
            seat = m.seat
        } else {
            guard MTSamePair.root(g.owner) == from, let s = w.s, Self.isSeat(s), s != g.me else { return .refused }
            seat = s
        }
        let name = Self.clean(w.n ?? "", Self.nameLimit)
        if !name.isEmpty, g.names[seat] != name {
            g.names[seat] = name
            groups[w.g] = g
            saveGroups()
        }
        let key = Self.key(of: g.id)
        let sid = "mid:" + id
        guard store.messages[key]?.contains(where: { $0.mid == sid }) != true else { return .held }   // a repeat: the row stands
        if g.mine {
            // THE GROUP'S PERMISSIONS AT THE DOOR (G.5): the owner carries every letter, so the owner refuses what the members may not
            // send -- whatever a member's build shows -- and holds a letter that came before its slow mode's interval: it knocks again.
            guard Self.allows(g, seat: seat, words) else { MontanaTrace.mark("group_refused", "a letter past the group's permissions"); return .refused }
            guard paceSlow(g, seat: seat) else { return .wait }
        }
        stand(g, face: nil, store: store)
        let born = MontanaDeliveryEngine.letterMoment(mid: sid, sentAt: nil)
        let quote = (w.qt ?? "").isEmpty ? nil : w.qt
        let row = Message(text: words, isFromMe: false, time: hhmm(at: born), replyText: quote, deliveryStatus: .delivered,
                          msgId: sid, senderRef: Self.speaker(g.id, seat), createdAt: born,
                          replyToId: store.localId(forMid: w.qm, chat: key))
        let landed = store.append(key, row)   // a channel's post lands on its wall, never as a row (MTBoard.handle)
        MTGroupTyping.shared.stopped(key, seat: seat)   // the letter came: its speaker types no more (the reference's head)
        MontanaTrace.mark("group_rx", mid: id, "letter landed=\(landed ? 1 : 0) owner=\(g.mine ? 1 : 0) post=\(post ? 1 : 0)")
        if post {
            if w.sl != 1 { MontanaNotify.presentGroup(title: g.title, body: String(localized: "New message", bundle: MTLanguage.bundle), chat: key, copy: copy) }
            return .held
        }
        if landed, w.sl != 1, w.hs != 1 {   // a channel's silent post, and a group's past handed to one just added (G.4), show no banner
            // The banner a running app owes its person: the group's title over who wrote and what (a channel speaks as itself).
            let shown = MontanaNotify.body(for: words) ?? String(localized: "New message", bundle: MTLanguage.bundle)
            let who = g.kind == .group ? speakerName(Self.speaker(g.id, seat)) : ""
            MontanaNotify.presentGroup(title: g.title, body: shown, speaker: who, chat: key, copy: copy,
                                       mentioned: g.kind == .group && Self.mentionsMe(words))   // a mention rings through the mute
        }
        if landed, g.mine {
            let on = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: name.isEmpty ? nil : name, id: id, s: seat,
                                 tx: words, qt: quote, qm: w.qm)
            spread(on, in: g, except: seat, own: false)
        }
        return .held
    }

    /// A LETTER'S CARD (MTGroup.carryCard): it lands on its letter's row by the pair's one rule of a late card (ChatStore.enrichLinkPreview
    /// -- the words, then the picture once), and the owner carries it on. Only the letter's speaker names its card, and only for a link
    /// the letter's own words carry; a card that outran its letter waits for it a while (cardWait).
    @MainActor
    private func carded(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard g.left != true else { return .refused }
        guard let id = w.id, Self.isLetterName(id), let lp = w.tx, lp.utf8.count <= Self.cardLimit,
              let card = MTLinkPreview.parse(lp) else { return .refused }
        let from = MTSamePair.root(pipe)
        let seat: String
        if g.mine {
            guard let m = g.members.first(where: { MTSamePair.root($0.pipe) == from }) else { return .refused }
            seat = m.seat
        } else {
            guard MTSamePair.root(g.owner) == from, let s = w.s, Self.isSeat(s), s != g.me else { return .refused }
            seat = s
        }
        let key = Self.key(of: g.id)
        let sid = "mid:" + id
        guard let row = store.messages[key]?.first(where: { r in r.mid == sid }) else {
            if store.buried(sid, in: key) { return .held }   // the letter is gone here already
            let born = MontanaDeliveryEngine.letterMoment(mid: sid, sentAt: nil)
            return Date().timeIntervalSince1970 - born < Self.cardWait ? .wait : .refused
        }
        guard !row.isFromMe, Self.author(row, in: g) == seat,
              MTLinkPreviewBuilder.webURLs(in: row.text).contains(where: { u in u.absoluteString == card.u }) else {
            MontanaTrace.mark("group_refused", "a card past its letter's speaker or its words")
            return .refused
        }
        store.enrichLinkPreview(key, sid: sid, lp: lp)
        if g.mine { spread(MTGroupWord(t: "lp", g: g.id, id: id, s: seat, tx: lp), in: g, except: seat, own: false) }
        MontanaTrace.mark("group_rx", mid: id, "card owner=\(g.mine ? 1 : 0)")
        return .held
    }

    /// A STICKER'S PASSPORT (MTGroup.carryPassport): read by the pair's one reader of a passport (MontanaStickerWire.handle) in the group's
    /// feed -- the set the sticker is of, and the quote its row grows, now or when the picture lands -- and carried on by the owner. Only
    /// the sticker's speaker names it; it names no address, so the set is asked of the pipe it came by (a member holds the owner's).
    @MainActor
    private func passported(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard g.left != true else { return .refused }
        guard let id = w.id, Self.isLetterName(id), let body = w.tx, body.utf8.count <= Self.passportLimit,
              var o = Self.json(body), (o["t"] as? String) == "id",
              let named = o["m"] as? String, MontanaStickerBook.bare(named) == id else { return .refused }
        let from = MTSamePair.root(pipe)
        let seat: String
        if g.mine {
            guard let m = g.members.first(where: { MTSamePair.root($0.pipe) == from }) else { return .refused }
            seat = m.seat
        } else {
            guard MTSamePair.root(g.owner) == from, let s = w.s, Self.isSeat(s), s != g.me else { return .refused }
            seat = s
        }
        let key = Self.key(of: g.id)
        if let row = store.messages[key]?.first(where: { r in r.mid == "mid:" + id }), row.isFromMe || Self.author(row, in: g) != seat {
            MontanaTrace.mark("group_refused", "a passport past its sticker's speaker")
            return .refused
        }
        o["o"] = nil   // no address rides a group: the giver is the pipe this word came by
        guard let d = try? JSONSerialization.data(withJSONObject: o), let clean = String(data: d, encoding: .utf8) else { return .refused }
        MontanaStickerWire.handle(MontanaStickerWire.mark + clean, from: pipe, chat: key, store: store)
        if g.mine { spread(MTGroupWord(t: "sp", g: g.id, id: id, s: seat, tx: clean), in: g, except: seat, own: false) }
        MontanaTrace.mark("group_rx", mid: id, "passport owner=\(g.mine ? 1 : 0)")
        return .held
    }

    /// AN ANSWER: applied in the group's feed by the reaction's own road (ChatStore.append), once by its name, and carried on by
    /// the owner to every other member.
    @MainActor
    private func answered(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard g.left != true else { return .refused }
        guard let id = w.id, Self.isLetterName(id), let words = w.tx, Self.answers(words) else { return .refused }
        let from = MTSamePair.root(pipe)
        let seat: String
        if g.mine {
            guard let m = g.members.first(where: { MTSamePair.root($0.pipe) == from }) else { return .refused }
            seat = m.seat
        } else {
            guard MTSamePair.root(g.owner) == from, let s = w.s, Self.isSeat(s), s != g.me else { return .refused }
            seat = s
        }
        guard !answersHeard.contains(id) else { return .held }
        // A CHANNEL WHOSE OWNER TURNED REACTIONS OFF TAKES NONE (the reference's «Allow Reactions»): a subscriber's reaction ends here
        if words.hasPrefix(reactionMark), g.kind == .channel, g.reacts == false, seat != Self.ownerSeat, g.admins?.contains(seat) != true {
            return .refused
        }
        // A CHANNEL THAT TAKES SOME REACTIONS TAKES THOSE ALONE (the reference's «Some Reactions»): another added is refused here
        if words.hasPrefix(reactionMark), g.kind == .channel, let list = g.reactList, seat != Self.ownerSeat, g.admins?.contains(seat) != true,
           let o = Self.json(String(words.dropFirst(reactionMark.count))), (o["op"] as? String) == "add", let e = o["e"] as? String,
           !list.contains(e) {
            MontanaTrace.mark("group_refused", "a reaction outside the channel's list")
            return .refused
        }
        let key = Self.key(of: g.id)
        if words.hasPrefix(pinMark), !Self.pins(g, seat: seat) {
            MontanaTrace.mark("group_refused", "a pin by a seat without the right seat=\(seat)")
            return .refused
        }
        if g.mine, !Self.allows(g, seat: seat, words) {   // a reaction or an edit past the group's permissions (G.5)
            MontanaTrace.mark("group_refused", "an answer past the group's permissions")
            return .refused
        }
        // AN EDIT OR A DELETION IS THE SPEAKER'S OWN (applyEditFromPeer and deleteEverywhere ask only whose phone wrote a row):
        // the owner answers for every member, so it takes one only for a letter standing here under that member's seat; a member
        // takes the owner's word, and a deletion of a letter not landed yet buries it before it comes.
        if let target = Self.target(words) {
            if let row = store.messages[key]?.first(where: { $0.mid == target }) {
                // The owner and the administrators it named take another's letter away (stage R.6, as the reference's admins
                // delete messages); the owner's word alone names them. An edit stays the speaker's own.
                let boss = words.hasPrefix(deleteMark) && Self.adminCan(g, seat: seat, .delete)   // G.6: «Delete Messages»
                guard Self.author(row, in: g) == seat || boss else {
                    MontanaTrace.mark("group_refused", "an answer to another's letter seat=\(seat)")
                    return .refused
                }
            } else if store.buried(target, in: key) {
                return .held   // the letter is gone here already
            } else if g.mine {
                return .wait   // the letter has not landed at the owner yet: the copy knocks again
            } else if words.hasPrefix(deleteMark) {
                store.bury([target], in: key)   // in this group alone: a speaker's notice reaches no other conversation
                answersHeard.append(id)
                return .held
            }
        }
        answersHeard.append(id)
        if 512 < answersHeard.count { answersHeard.removeFirst(answersHeard.count - 512) }
        let born = MontanaDeliveryEngine.letterMoment(mid: "mid:" + id, sentAt: nil)
        store.append(key, Message(text: words, isFromMe: false, time: "", msgId: "mid:" + id, senderRef: Self.speaker(g.id, seat), createdAt: born))
        // the reference's service row of a pin: «X pinned "..."», laid on this phone under the pinned letter's own words
        if words.hasPrefix(pinMark), let o = Self.json(String(words.dropFirst(pinMark.count))), (o["op"] as? String) == "pin",
           let sid = o["sid"] as? String, let row = store.messages[key]?.first(where: { r in r.msgId == sid }) {
            lay(MTGroupEvent(e: "pinned", g: g.id, a: seat, t: Self.pinWords(row)), store: store)
        }
        if g.mine { spread(MTGroupWord(t: "sig", g: g.id, n: w.n, id: id, s: seat, tx: words), in: g, except: seat, own: false) }
        return .held
    }

    /// A WORD OF A CHANNEL'S WALL (the author's words 06.10.2026 11:2x-11:4x UTC: «in channels posts as on the Wall of Thoughts»): a subscriber's mark -- a like, the posts
    /// seen, a comment -- reaches the owner, who applies it by the subscriber's seat (MTBoard.applyChannel); the owner's counts and
    /// deletions reach a subscriber, who lays them on the channel's page (MTBoard.handle).
    @MainActor
    private func wallWord(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard g.left != true, g.kind == .channel, let words = w.tx, words.hasPrefix(MTBoard.mark),
              words.utf8.count <= Self.wallPostLimit,
              let bw = try? JSONDecoder().decode(MTBoardWord.self, from: Data(words.dropFirst(MTBoard.mark.count).utf8)) else { return .refused }
        let from = MTSamePair.root(pipe)
        let key = Self.key(of: g.id)
        if g.mine {
            guard let m = g.members.first(where: { MTSamePair.root($0.pipe) == from }) else { return .refused }
            MTBoard.shared.applyChannel(bw, from: Self.speaker(g.id, m.seat), in: key)
        } else {
            guard MTSamePair.root(g.owner) == from else { return .refused }
            MTBoard.handle(words, from: key, isFromMe: false)
        }
        return .held
    }

    /// A WORD OF A CHANNEL'S WALL LEAVES (MTBoard.send, tellChannel): the owner's to every subscriber, a subscriber's to the owner.
    @MainActor @discardableResult
    func carryWallWord(_ bw: MTBoardWord, in key: String) -> Bool {
        guard let g = state(key), g.kind == .channel, g.left != true,
              let d = try? JSONEncoder().encode(bw), let js = String(data: d, encoding: .utf8) else { return false }
        let w = MTGroupWord(t: "wl", g: g.id, id: ChatStore.mintMid().mid, s: g.me, tx: MTBoard.mark + js)   // COMPAT-GATED: a channel's wall word
        return spread(w, in: g, except: nil, own: false) > 0
    }

    /// A ROOM'S WORD (MTGroupRoom): its seat is proven by the pipe it came by, as an answer's is; the room reads it once by its name,
    /// and the owner of the group passes it on to everyone else -- a targeted word to the seats it names alone.
    @MainActor
    private func roomed(_ w: MTGroupWord, from pipe: String, copy: String) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard g.left != true else { return .refused }
        guard let id = w.id, Self.isLetterName(id), let words = w.tx, words.utf8.count <= 4096 else { return .refused }
        let from = MTSamePair.root(pipe)
        let seat: String
        if g.mine {
            guard let m = g.members.first(where: { MTSamePair.root($0.pipe) == from }) else { return .refused }
            seat = m.seat
        } else {
            guard MTSamePair.root(g.owner) == from, let s = w.s, Self.isSeat(s), s != g.me else { return .refused }
            seat = s
        }
        guard !answersHeard.contains(id) else { return .held }
        guard paced(g, seat: seat) else { return .wait }
        answersHeard.append(id)
        if 512 < answersHeard.count { answersHeard.removeFirst(answersHeard.count - 512) }
        MTGroupRoom.shared.heard(words, group: g.id, chat: Self.key(of: g.id), seat: seat, name: w.n.map { Self.clean($0, Self.nameLimit) },
                                 copy: copy)
        if g.mine {
            var on = MTGroupWord(t: "room", g: g.id, k: g.kind.rawValue, ti: g.title, n: w.n, id: id, s: seat, tx: words)
            if let ts = w.ts, ts.count <= 32 {
                // a targeted word: to the seats it names alone -- ringing there if it is an invitation (a word naming no ring is one)
                let ring = w.rg == 1 || w.rg == nil
                on.ts = ts
                on.rg = ring ? 1 : 0
                for m in g.members where ts.contains(m.seat) && m.seat != seat { _ = carry(on, to: m.pipe, letter: "", own: false, ring: ring) }
            } else {
                spread(on, in: g, except: seat, own: false)
            }
        }
        return .held
    }

    /// The pace of one member's room words the owner takes and carries on (carriedPerMinute). A member hears its owner alone, who
    /// paced them already.
    private func paced(_ g: MTGroupState, seat: String) -> Bool {
        guard g.mine else { return true }
        let now = Date().timeIntervalSince1970
        let key = g.id + "/" + seat
        var moments = (carriedAt[key] ?? []).filter { now - $0 < 60 }
        guard moments.count < Self.carriedPerMinute else {
            carriedAt[key] = moments
            MontanaTrace.markFolded("group_paced", "a member past thirty room words a minute -- the copy knocks again", window: 60, key: key)
            return false
        }
        moments.append(now)
        carriedAt[key] = moments
        return true
    }

    /// A MEMBER LEFT (their «bye»): the owner carries nothing more to them, and everyone left learns the new count.
    @MainActor
    private func parted(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard var g = groups[w.g] else { return .refused }
        let from = MTSamePair.root(pipe)
        guard g.mine, let m = g.members.first(where: { MTSamePair.root($0.pipe) == from }) else { return .refused }
        act(&g, "left", p: [seatName(g, m.seat)])
        g.members.removeAll { $0.seat == m.seat }
        g.admins = g.admins?.filter { $0 != m.seat }.nilIfEmpty
        g.count = g.members.count + 1
        groups[w.g] = g
        saveGroups()
        tellAll(g, face: nil)
        let gone = MTGroupEvent(e: "left", g: g.id, a: m.seat)
        lay(gone, store: store)
        tellEvent(gone, in: g)
        MontanaTrace.mark("group_rx", "a member left count=\(g.count)")
        return .held
    }
    /// THE OWNER TOOK THIS PHONE OUT (its «out»): the rows stay readable, and the chat says so instead of a field.
    @MainActor
    private func dropped(_ w: MTGroupWord, by pipe: String, store: ChatStore) -> Verdict {
        guard var g = groups[w.g], !g.mine, MTSamePair.root(g.owner) == MTSamePair.root(pipe) else { return .refused }
        let ended = w.dl == 1   // the owner deleted the group for everyone
        if g.left != true {
            g.left = true
            g.removed = true
            groups[w.g] = g
            saveGroups()
            store.objectWillChange.send()   // the open chat trades its field for the button at once
            MTGroupRoom.shared.groupGone(g.id)   // its room goes with the group
            if !ended { lay(MTGroupEvent(e: "removed", g: g.id, a: Self.ownerSeat, p: [g.me]), store: store) }
            MontanaTrace.mark("group_rx", "taken out by the owner")
        }
        if ended {
            erase(Self.key(of: g.id), store: store)
            MontanaTrace.mark("group_rx", "the owner deleted the group for everyone")
        }
        return .held
    }

    // -- measures ------------------------------------------------------------------------------

    static func answers(_ text: String) -> Bool {
        // A PIN FOR EVERYONE (the checklist's B.11): the letter by its one name, pinned or unpinned; an older build refuses it here
        // and buries it (COMPAT-GATED: the word «sig» is known, its pin is not).
        if text.hasPrefix(pinMark) {
            guard text.utf8.count <= 1024, let o = json(String(text.dropFirst(pinMark.count))), let op = o["op"] as? String,
                  op == "pin" || op == "unpin", let sid = o["sid"] as? String, sid.hasPrefix("mid:") else { return false }
            return isLetterName(String(sid.dropFirst(4)))
        }
        if text.hasPrefix(reactionMark) {
            guard text.count <= 2048, let o = json(String(text.dropFirst(reactionMark.count))), let op = o["op"] as? String else { return false }
            return op == "add" || op == "del"
        }
        if text.hasPrefix(editMark) {
            guard let o = json(String(text.dropFirst(editMark.count))), let tx = o["tx"] as? String else { return false }
            return target(text) != nil && carries(tx)
        }
        return text.hasPrefix(deleteMark) && target(text) != nil
    }
    /// The letter an edit or a deletion speaks of, by its one name; nil for a reaction.
    static func target(_ text: String) -> String? {
        var sid = ""
        if text.hasPrefix(editMark) { sid = (json(String(text.dropFirst(editMark.count)))?["sid"] as? String) ?? "" }
        else if text.hasPrefix(deleteMark) { sid = String(text.dropFirst(deleteMark.count)) }
        let bare = sid.hasPrefix("mid:") ? String(sid.dropFirst(4)) : sid
        return isLetterName(bare) ? "mid:" + bare : nil
    }
    /// The seat whose letter a row is: mine is this phone's seat, another's is named by its speaker's reference.
    static func author(_ row: Message, in g: MTGroupState) -> String? {
        if row.isFromMe { return g.me }
        guard let ref = row.senderRef, ref.hasPrefix(speaker(g.id, "")) else { return nil }
        return String(ref.dropFirst(speaker(g.id, "").count))
    }
    private static func json(_ s: String) -> [String: Any]? {
        s.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// WHAT A GROUP CARRIES IN THIS BUILD: a person's words, a sticker, and a media letter -- the manifest of a picture, a video, a
    /// round note, a voice or a file, whose sealed pieces lie on the nodes for every receiver (the author's words 06.10.2026 11:2x-11:3x UTC: «groups and channels with the whole of a chat, every kind of data»). Never another service word, a long letter's reference, a coin, a game's letter or a row of a
    /// phone's own -- a coin landing in a group would be credited from nobody. A GROUP'S COIN (18.10.2026) is no letter of the group:
    /// each person picked gets the pair's own transfer, and the group gets plain words of how many were paid (tellCoins).
    static func carries(_ text: String) -> Bool {
        // A CHANNEL'S POST (MTBoard.isChannelPost): the wall's own word, its pictures' posters within the wall's own bounds.
        if MTBoard.isChannelPost(text) { return text.utf8.count <= Self.wallPostLimit }
        guard !text.isEmpty, text.count <= ChatStore.sendPieceChars else { return false }
        if MontanaNotify.isService(text), !text.hasPrefix(stickerMark), !text.hasPrefix(mediaMark) { return false }
        return MTCoinLetter.parse(text) == nil && MTChessLetter.parse(text) == nil && !MTRowLetter.ownRow(text)
    }
    static func clean(_ s: String, _ limit: Int) -> String {
        String(MTCrown.plain(s.trimmingCharacters(in: .whitespacesAndNewlines)).prefix(limit))
    }
    static func isSeat(_ s: String) -> Bool { !s.isEmpty && s.count <= 16 && s.allSatisfy { $0.isHexDigit } }
    static func isLetterName(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 80 && !s.hasPrefix("mid:") && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
    private static func mintId() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    private static func mintSeat() -> String { String(mintId().prefix(8)) }
    /// The face an invitation carries: small, so the word stays a letter and not a file.
    private static func thumb(_ face: Data) -> String? {
        guard !face.isEmpty, let ui = UIImage(data: face),
              let d = ui.avatarResized(faceSide).jpegData(compressionQuality: 0.7) else { return nil }
        let b64 = d.base64EncodedString()
        return b64.count <= faceLimit ? b64 : nil
    }
    private static func face(_ b64: String?) -> String? {
        guard let b64, b64.count <= faceLimit, let d = Data(base64Encoded: b64), UIImage(data: d) != nil else { return nil }
        return saveChatAvatar(d)
    }
}


/// THE PLATE OF «@» ABOVE A GROUP'S FIELD (stage R, the reference folder's mention list): it follows the word typed after «@»,
/// a holder of its own, as the link's plate is -- typing redraws the plate, never the feed.
final class MTMentionCompose: ObservableObject {
    static let shared = MTMentionCompose()
    @Published private(set) var query: String?
    @Published private(set) var chat = ""
    func look(at text: String, in key: String) {
        let held = MTGroup.isKey(key) && MTGroup.shared.kind(key) == .group ? Self.tail(text) : nil
        if held != query { query = held }
        if chat != key { chat = key }
    }
    /// The word after the last «@» at the text's end: «@» at the start or after a space, then no space, 32 letters at most.
    static func tail(_ text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at != text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let rest = text[text.index(after: at)...]
        guard rest.count <= 32, !rest.contains(where: { $0.isWhitespace }) else { return nil }
        return String(rest)
    }
    /// The people whose name, by any of its words, begins with what is typed -- five at most.
    func people() -> [MTRoomPerson] {
        guard let q = query?.lowercased() else { return [] }
        let all = MTGroup.shared.mentionable(chat)
        let hit = q.isEmpty ? all : all.filter { p in p.name.lowercased().split(separator: " ").contains { $0.hasPrefix(q) } }
        return Array(hit.prefix(5))
    }
}

extension Array {
    /// Nil for an empty list: a field that names nobody is not written at all.
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

/// WHO TYPES IN A GROUP NOW (the checklist's B.12): seats by the moment their word landed, each alive the store's typing life, and
/// the head's line in the reference's words -- one name, two names, a name and how many others.
final class MTGroupTyping: ObservableObject {
    static let shared = MTGroupTyping()
    @Published private(set) var seats: [String: [String: Date]] = [:]
    @MainActor
    func heard(_ key: String, seat: String) {
        seats[key, default: [:]][seat] = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + ChatStore.typingLife + 0.1) { [weak self] in self?.sweep(key) }
    }
    @MainActor
    func stopped(_ key: String, seat: String) {
        if seats[key]?[seat] != nil { seats[key]?[seat] = nil }
    }
    @MainActor
    private func sweep(_ key: String) {
        let now = Date()
        let alive = (seats[key] ?? [:]).filter { e in now.timeIntervalSince(e.value) < ChatStore.typingLife }
        if alive.count != seats[key]?.count { seats[key] = alive.isEmpty ? nil : alive }
    }
    /// The head's line while someone types, nil when nobody does.
    @MainActor
    func line(_ key: String) -> String? {
        guard let gid = MTGroup.id(of: key) else { return nil }
        let now = Date()
        let names = (seats[key] ?? [:]).filter { e in now.timeIntervalSince(e.value) < ChatStore.typingLife }
            .sorted { a, b in a.value < b.value }
            .map { e in MTGroup.shared.speakerName(MTGroup.speaker(gid, e.key)) }
        let b = MTLanguage.bundle
        switch names.count {
        case 0: return nil
        case 1: return String(localized: "\(names[0]) is typing…", bundle: b)
        case 2: return String(localized: "\(names[0]) and \(names[1]) are typing…", bundle: b)
        default: return String(localized: "\(names[0]) and \(String(names.count - 1)) others are typing…", bundle: b)
        }
    }
}
