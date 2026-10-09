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
    var mine: Bool { owner.isEmpty }
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
    var mesh: Bool { false }
    var bosses: [String]? { nil }
}

/// The one owner of groups and channels on this phone: their state, their words on the wire, the owner's carrying and the
/// receipts of every copy. Read and written on the main thread, where the store lands every letter.
final class MTGroup {
    static let shared = MTGroup()
    /// Whether this phone keeps the group's people (adds, takes out, renames, describes): its owner.
    func manages(_ key: String) -> Bool { state(key)?.mine == true }
    /// [P2P-COMPAT] Every older build buries this word unread (mtUnknownServiceWord): a group's word is never their row.
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
        if unread { MontanaP2PTrace.mark("group_unread", "the groups' store did not open -- read again before use") }
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
    /// Whether this phone may write into the group: everyone in a group, the owner alone in a channel.
    func canWrite(_ key: String) -> Bool {
        guard let g = state(key), g.left != true else { return false }
        return g.kind == .group || g.mine
    }
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
        if !g.mine, !g.mesh {
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

    static func speaker(_ id: String, _ seat: String) -> String { speakerHead + id + "/" + seat }
    static func isSpeaker(_ ref: String) -> Bool { ref.hasPrefix(speakerHead) }
    /// The name a speaker's rows wear on this phone: the person as this phone knows them where it holds their pipe, else the name
    /// they gave themselves in their last word.
    func speakerName(_ ref: String) -> String {
        let parts = ref.dropFirst(Self.speakerHead.count).split(separator: "/", maxSplits: 1).map(String.init)
        guard ready(), parts.count == 2, let g = groups[parts[0]] else { return Self.memberWord }
        let seat = parts[1]
        let pipe = (!g.mine && seat == Self.ownerSeat) ? g.owner : g.members.first { $0.seat == seat }?.pipe
        return shownName(pipe: pipe, said: g.names[seat])
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
    /// ride the queue until every one is receipted. Nil when nobody chosen can be carried to.
    @MainActor @discardableResult
    func create(_ kind: MTGroupKind, title: String, about: String = "", face: Data, people: [Chat], store: ChatStore) -> Chat? {
        let name = Self.clean(title, Self.titleLimit)
        var pipes: [String] = []
        for c in people where !c.isGroup {
            let p = MTSamePair.root(c.convRef)
            if MontanaConv.holds(p), !ChatStore.refusesCold(p), !pipes.contains(p) { pipes.append(p) }
        }
        pipes = Array(pipes.prefix(Self.peopleLimit))
        guard ready(), !name.isEmpty, !pipes.isEmpty else {
            MontanaP2PTrace.mark("group_refused", "birth -- title=\(name.isEmpty ? 0 : 1) people=\(pipes.count) store=\(unread ? 0 : 1)")
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
        MontanaP2PTrace.mark("group_born", "kind=\(kind.rawValue) people=\(g.count)")
        return row
    }

    /// The group's row on the list: the one standing or archived, or a new one at the top. A deleted group's row comes back
    /// with its next word, as a deleted conversation does.
    @MainActor @discardableResult
    private func stand(_ g: MTGroupState, face: String?, store: ChatStore) -> Chat {
        let key = Self.key(of: g.id)
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
        let row = Chat(name: key, lastMessage: "", time: nowHHMM(), unread: 0, status: "", photoURL: face,
                       isGroup: true, isAdmin: g.mine, members: [], convId: key, displayName: g.title)
        rows.insert(row, at: 0)
        store.saveStored(chats: rows)
        store.bump(key)
        return row
    }

    // -- the wire ------------------------------------------------------------------------------

    /// One copy to one receiver, under a name of its own. A copy has no row of its own (headless): the row it carries stands in
    /// the group's feed under the letter's name, and the group answers for it (rides) where the mirror law asks. A letter and an
    /// invitation ring (the receiver's phone shows the group's face); an answer, a leaving and a taking out are silent words.
    @MainActor
    private func carry(_ w: MTGroupWord, to pipe: String, letter: String, own: Bool, ring: Bool = false) -> String? {
        guard MontanaConv.holds(pipe), !ChatStore.refusesCold(pipe),
              let d = try? JSONEncoder().encode(w), let js = String(data: d, encoding: .utf8) else { return nil }
        let name = ChatStore.mintMid().mid
        let text = Self.mark + js
        copies[name] = MTGroupCopy(group: w.g, letter: letter, to: pipe, own: own, of: 1, held: false, failed: false,
                                   text: text, at: Date().timeIntervalSince1970)
        saveCopies()
        MontanaDeliveryEngine.shared.enqueue(to: pipe, chat: pipe, mid: name, text: text, silent: !ring && w.t != "say" && w.t != "inv",
                                             headless: true)   // a room's invitation rings where it is carried (07.10)
        MontanaP2PTrace.mark("group_tx", mid: name, "t=\(w.t) to=\(String(pipe.prefix(10)))")
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
            MontanaP2PTrace.mark("group_refused", "send -- group=\(state(key) == nil ? 0 : 1) chat=\(String(key.prefix(12)))")
            return Message(text: "", isFromMe: true, time: nowHHMM(), senderRef: nil)
        }
        let minted = ChatStore.mintMid()
        let row = Message(text: text, isFromMe: true, time: nowHHMM(), replyText: replyText, deliveryStatus: .sending,
                          msgId: "mid:" + minted.mid, senderRef: nil, createdAt: Double(minted.ms) / 1000, replyToId: replyToId)
        store.append(key, row)
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        // The title and the kind ride every letter: the receiver's notification extension holds no group, and names it by these.
        let w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: minted.mid, s: g.me, tx: text,
                            qt: (replyText ?? "").isEmpty ? nil : replyText, qm: (replyWireMid ?? "").isEmpty ? nil : replyWireMid)
        if spread(w, in: g, except: nil, own: true) == 0, let i = store.messages[key]?.firstIndex(where: { $0.mid == row.mid }) {
            store.putOut(key, i, because: .nobodyToCarry)   // nobody to carry to: honest red, a hand may try again
        }
        return row
    }

    /// A MEDIA LETTER OF MINE INTO A GROUP (ChatStore.sendMediaToPeer, the author's words 06.10.2026 14:2x-14:3x MSK: «groups and channels with the whole of a chat, every kind of data»): its row
    /// stands in the feed already under its one name, its file's sealed pieces lie on the nodes for every receiver -- the node's term
    /// keeps them, no single receipt takes them away -- and its manifest leaves to everyone this phone carries to, as a word does.
    @MainActor
    func carryMedia(_ letter: String, mid: String, in key: String, store: ChatStore) -> Bool {
        guard let g = state(key), canWrite(key), Self.carries(letter), letter.hasPrefix(mediaMark), Self.isLetterName(mid) else {
            MontanaP2PTrace.mark("group_refused", "media -- group=\(state(key) == nil ? 0 : 1) chat=\(String(key.prefix(12)))")
            return false
        }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        let w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: mid, s: g.me, tx: letter)
        return spread(w, in: g, except: nil, own: true) > 0
    }

    /// A CHANNEL'S POST LEAVES TO EVERY SUBSCRIBER (the author's words 06.10.2026 14:2x-14:4x MSK: «in channels posts as on the Wall of Thoughts; everything the wall publishes is published in a channel», MTBoard.lay): the wall's own word «cpost» with the post as the channel's page
    /// shows it, carried as the channel's letter; no row of the feed is born of it (ChatStore.append hands a wall's word to MTBoard).
    @MainActor
    func carryWallPost(_ post: MTBoardSeen, in key: String) {
        guard let g = state(key), g.mine, g.kind == .channel,
              let d = try? JSONEncoder().encode(MTBoardWord(t: "cpost", ps: [post])), let js = String(data: d, encoding: .utf8) else { return }   // COMPAT-GATED: a channel's carrier alone
        let text = MTBoard.mark + js
        guard Self.carries(text) else { MontanaP2PTrace.mark("group_refused", "wall post bytes=\(text.utf8.count)"); return }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        let w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: ChatStore.mintMid().mid, s: g.me, tx: text)
        let n = spread(w, in: g, except: nil, own: false)
        MontanaP2PTrace.mark("group_tx", "wall post copies=\(n)")
    }

    /// A HAND ASKED AGAIN (the red mark's retry): every copy of the letter that has not been receipted rides again under its own
    /// name; a letter with no copy left leaves anew to everyone. The row goes back to the clock by the one road back.
    @MainActor
    func resend(_ m: Message, in key: String, store: ChatStore) {
        guard let g = state(key), let i = store.messages[key]?.firstIndex(where: { $0.mid == m.mid }) else { return }
        let letter = m.mid.hasPrefix("mid:") ? String(m.mid.dropFirst(4)) : m.mid
        store.restartSend(key, i)
        let waiting = copies.filter { $0.value.own && $0.value.group == g.id && $0.value.letter == letter }
        if waiting.isEmpty {
            let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
            let w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: letter, s: g.me, tx: m.text,
                                qt: (m.replyText ?? "").isEmpty ? nil : m.replyText)
            if spread(w, in: g, except: nil, own: true) == 0 { store.putOut(key, i, because: .nobodyToCarry) }
            MontanaP2PTrace.mark("group_resend", mid: letter, "anew")
            return
        }
        for (name, c) in waiting {
            copies[name]?.failed = false
            MontanaDeliveryEngine.shared.enqueue(to: c.to, chat: c.to, mid: name, text: c.text, silent: false, headless: true)
        }
        saveCopies()
        MontanaDeliveryEngine.shared.drainAll()
        MontanaP2PTrace.mark("group_resend", mid: letter, "copies=\(waiting.count)")
    }

    /// AN ANSWER TO A LETTER -- a reaction, an edit of one's own words, a deletion of one's own letter for everyone: carried to
    /// every phone of the group like a letter and applied by the same road in the group's feed (ChatStore.append), where it is
    /// never a row. Everyone in a group or a channel may react; only a letter's own speaker changes or takes it away (answered).
    @MainActor
    func signal(_ text: String, in key: String, store: ChatStore) {
        guard let g = state(key), g.left != true, Self.answers(text) else {
            MontanaP2PTrace.mark("group_refused", "answer -- group=\(state(key) == nil ? 0 : 1)")
            return
        }
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        let w = MTGroupWord(t: "sig", g: g.id, n: me.isEmpty ? nil : me, id: ChatStore.mintMid().mid, s: g.me, tx: text)
        spread(w, in: g, except: nil, own: false)
    }

    /// A ROOM'S WORD INTO THE GROUP (MTGroupRoom, the author's word 07.10.2026 00:2x MSK: calls of up to 13 in a group): carried like
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

    /// Whether a seat is an administrator the owner of a carried group named.
    func isAdmin(_ key: String, seat: String) -> Bool { state(key)?.admins?.contains(seat) == true }
    /// Whether this phone moderates the group: its owner, an administrator the owner named, or -- in an organisation's chat -- an
    /// administrator of the core. A moderator takes another's letter away for everyone.
    func moderates(_ key: String) -> Bool {
        guard let g = state(key), g.left != true, g.kind == .group else { return false }
        if g.mesh { return g.bosses?.contains(g.me) == true }
        return g.mine || g.admins?.contains(g.me) == true
    }
    /// THE OWNER NAMES OR DISMISSES AN ADMINISTRATOR: every member hears the list by the invitation's word again.
    @MainActor
    func setAdmin(_ key: String, seat: String, on: Bool, store: ChatStore) {
        guard var g = state(key), g.mine, !g.mesh, g.kind == .group, g.members.contains(where: { $0.seat == seat }) else { return }
        var list = Set(g.admins ?? [])
        if on { list.insert(seat) } else { list.remove(seat) }
        g.admins = Array(list).sorted().nilIfEmpty
        groups[g.id] = g
        saveGroups()
        tellAll(g, face: nil)
        MontanaP2PTrace.mark("group_admin", on ? "named" : "dismissed")
    }
    /// AN ADMINISTRATOR TAKES A PERSON OUT: the owner's phone carries the group, so the word goes to the owner, who takes the person
    /// out as by its own hand -- never the owner, never another administrator. The owner's phone is the one that can.
    @MainActor
    func kick(_ key: String, seat: String, store: ChatStore) {
        guard let g = state(key), !g.mesh, g.left != true else { return }
        if g.mine { remove(key, seat: seat, store: store); return }
        guard g.admins?.contains(g.me) == true, seat != Self.ownerSeat, seat != g.me, g.admins?.contains(seat) != true else { return }
        _ = carry(MTGroupWord(t: "kk", g: g.id, id: ChatStore.mintMid().mid, s: seat), to: g.owner, letter: "", own: false)   // COMPAT-GATED
        MontanaP2PTrace.mark("group_admin", "asked the owner to take a person out")
    }
    /// An administrator's «take out» at the owner's phone: the asker must be an administrator, the person a member who is none.
    @MainActor
    private func kicked(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g], g.mine, !g.mesh, g.left != true else { return .refused }
        let from = MTSamePair.root(pipe)
        guard let asker = g.members.first(where: { MTSamePair.root($0.pipe) == from }), g.admins?.contains(asker.seat) == true,
              let target = w.s, target != asker.seat, g.admins?.contains(target) != true,
              g.members.contains(where: { $0.seat == target }) else { return .refused }
        remove(Self.key(of: g.id), seat: target, by: asker.seat, store: store)
        return .held
    }

    // -- the group's invite link (stage R.6, the reference folder: «Invite Link», «joined the group via invite link») -------------

    /// The link the owner hands out: its own card (whoever opens it meets the owner, the one road of a link) and the group's mark
    /// after it (jg). Nil -- no card stands yet, or this phone is no owner of the group.
    @MainActor
    func inviteLink(_ key: String) -> URL? {
        guard var g = state(key), g.mine, !g.mesh, g.kind == .group, g.left != true,
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
        guard var g = state(key), g.mine, !g.mesh else { return }
        g.invite = Self.mintId()
        groups[g.id] = g
        saveGroups()
        MontanaP2PTrace.mark("group_link", "reset")
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
        MontanaP2PTrace.mark("group_link", "a join waits for its meeting")
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
            MontanaP2PTrace.mark("group_link", "join asked sent=\(sent ? 1 : 0)")
        }
    }
    /// One who opened the group's link asks at the owner's phone: the mark must be the group's standing one; then the person is
    /// added by the owner's own road, and everyone reads that they joined by the link.
    @MainActor
    private func joined(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g], g.mine, !g.mesh, g.kind == .group, g.left != true,
              let mark = w.tx, let held = g.invite, mark == held else { return .refused }
        let from = MTSamePair.root(pipe)
        if g.members.contains(where: { MTSamePair.root($0.pipe) == from }) { return .held }   // already in: nothing more
        add(Self.key(of: g.id), people: [Chat(name: from, lastMessage: "", time: "", unread: 0, status: "", convId: from)],
            viaLink: true, store: store)
        MontanaP2PTrace.mark("group_link", "joined by the link")
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
        guard !g.mesh || e.e == "call" || e.e == "ended" else { return }
        st.appendGroupEvent(Self.key(of: g.id), row)
    }
    /// The owner tells everyone else who came, who was taken out, who left -- by seat, never by a name of the owner's.
    @MainActor
    private func tellEvent(_ e: MTGroupEvent, in g: MTGroupState) {
        guard g.mine, !g.mesh, g.kind == .group, let d = try? JSONEncoder().encode(e), let js = String(data: d, encoding: .utf8) else { return }
        let w = MTGroupWord(t: "ev", g: g.id, id: ChatStore.mintMid().mid, s: Self.ownerSeat, tx: js)   // COMPAT-GATED: an older build buries «ev»
        let about = Set(e.p ?? [])
        for m in g.members where !about.contains(m.seat) { _ = carry(w, to: m.pipe, letter: "", own: false) }
    }
    /// AN EVENT FROM THE OWNER (its «ev»): taken from the owner's pipe alone, about seats alone, once by its name.
    @MainActor
    private func evented(_ w: MTGroupWord, from pipe: String, store: ChatStore) -> Verdict {
        guard let g = groups[w.g] else { return .wait }
        guard g.left != true, !g.mine, !g.mesh, MTSamePair.root(g.owner) == MTSamePair.root(pipe) else { return .refused }
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
        MontanaP2PTrace.mark("group_erased", "out=\(g.removed == true ? "removed" : "left")")
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
        guard var g = state(key), g.mine, !g.mesh, g.left != true else { return }
        var w = MTGroupWord(t: "out", g: g.id)
        w.dl = 1
        for m in g.members { _ = carry(w, to: m.pipe, letter: "", own: false) }
        g.left = true
        g.members = []
        groups[g.id] = g
        saveGroups()
        erase(key, store: store)
        MontanaP2PTrace.mark("group_dissolved", "by its owner")
    }

    // -- the group's life: its name and face, its people, leaving ---------------------------------

    /// THE OWNER RENAMES THE GROUP OR GIVES IT A NEW FACE (its page): every member is told by the invitation's own word again --
    /// the same group, the same seat, the new title and face -- so every phone shows what the owner's shows.
    @MainActor
    func renew(_ key: String, title: String, faceFile: String?, about: String? = nil, store: ChatStore) {
        guard var g = state(key), g.mine else { return }
        let name = Self.clean(title, Self.titleLimit)
        let face = faceFile.flatMap { try? Data(contentsOf: avatarsDirURL().appendingPathComponent($0)) }
        // the description, the owner's words about the group (stage R): carried in the invitation's ds, as at the group's birth
        let words = about.map { Self.clean($0, Self.aboutLimit) }
        let described = words.map { $0 != g.about } ?? false
        guard !name.isEmpty, name != g.title || face != nil || described else { return }
        let renamed = name != g.title
        g.title = name
        if let words { g.about = words }
        groups[g.id] = g
        saveGroups()
        // The owner's own row is the page's to write (ChatsListView.updateChat): a second writer of the shelf here would lay the
        // shelf back over the page's fresh copy.
        tellAll(g, face: face.flatMap { Self.thumb($0) })
        if renamed { lay(MTGroupEvent(e: "named", g: g.id, a: Self.ownerSeat, t: name), store: store) }
        if face != nil { lay(MTGroupEvent(e: "face", g: g.id, a: Self.ownerSeat), store: store) }
        MontanaP2PTrace.mark("group_renewed", "face=\(face == nil ? 0 : 1)")
    }

    /// THE OWNER ADDS PEOPLE (its page): each new one is invited with a seat of their own, and everyone learns the new count.
    @MainActor
    func add(_ key: String, people: [Chat], viaLink: Bool = false, store: ChatStore) {
        guard var g = state(key), g.mine else { return }
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
        groups[g.id] = g
        saveGroups()
        let face = store.storedChats().first(where: { $0.id == key })?.photoURL.flatMap { try? Data(contentsOf: avatarsDirURL().appendingPathComponent($0)) }
        tellAll(g, face: face.flatMap { Self.thumb($0) }, only: Set(fresh.map(\.seat)))
        // one who came by the group's link joined by their own hand (the reference: «%@ joined the group via invite link»)
        let came = viaLink ? MTGroupEvent(e: "joined", g: g.id, a: fresh[0].seat)
                           : MTGroupEvent(e: "added", g: g.id, a: Self.ownerSeat, p: fresh.map(\.seat))
        lay(came, store: store)
        tellEvent(came, in: g)
        // A SUBSCRIBER ADDED LATER SEES THE CHANNEL'S PAGE (06.10): its newest posts, each as every subscriber was carried it.
        if g.kind == .channel {
            let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
            for p in MTBoard.shared.channelPosts(key, newest: 10).reversed() {
                guard let d = try? JSONEncoder().encode(MTBoardWord(t: "cpost", ps: [p])), let js = String(data: d, encoding: .utf8) else { continue }   // COMPAT-GATED
                let text = MTBoard.mark + js
                guard Self.carries(text) else { continue }
                let w = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: me.isEmpty ? nil : me, id: ChatStore.mintMid().mid, s: g.me, tx: text)
                for m in fresh { _ = carry(w, to: m.pipe, letter: w.id ?? "", own: false) }
            }
        }
        MontanaP2PTrace.mark("group_added", "people=\(fresh.count) count=\(g.count)")
    }

    /// THE OWNER TAKES A PERSON OUT (its page): they are told by their own word and stop being carried to; everyone left learns
    /// the new count. Their letters already in the group stay where they stand.
    @MainActor
    func remove(_ key: String, seat: String, by actor: String = MTGroup.ownerSeat, store: ChatStore) {
        guard var g = state(key), g.mine, let m = g.members.first(where: { $0.seat == seat }) else { return }
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
        MontanaP2PTrace.mark("group_removed", "count=\(g.count)")
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
        MontanaP2PTrace.mark("group_left", "by this phone")
    }

    /// The invitation's word again to every member: the title, the words about the group, the count, and a new face when one is
    /// given. Each member keeps their seat.
    /// `only` -- the seats the face goes to (the people just added); everyone else learns the count without it.
    @MainActor
    private func tellAll(_ g: MTGroupState, face: String?, only: Set<String>? = nil) {
        let me = Self.clean(E2E.myDisplayName(), Self.nameLimit)
        for m in g.members {
            let fc = (only == nil || only?.contains(m.seat) == true) ? face : nil
            var w = MTGroupWord(t: "inv", g: g.id, k: g.kind.rawValue, ti: g.title, ds: g.about.isEmpty ? nil : g.about, fc: fc,
                                c: g.count, me: m.seat, n: me.isEmpty ? nil : me)
            w.ad = g.admins   // the administrators the owner named (stage R.6)
            _ = carry(w, to: m.pipe, letter: "", own: false)
        }
    }

    // -- the receipts of the copies ------------------------------------------------------------

    /// A copy was receipted (ChatStore.markDelivered, after the queue let it go). True when the name was a group's copy.
    @MainActor
    func copyDelivered(_ name: String, store: ChatStore) -> Bool {
        guard ready(), let c = copies.removeValue(forKey: name) else { return false }
        saveCopies()
        MontanaP2PTrace.mark("group_rcpt", mid: name, "own=\(c.own ? 1 : 0)")
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

    // -- arrival -------------------------------------------------------------------------------

    enum Verdict { case held, refused, wait }

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
            verdict = shared.take(w, from: pipe, copy: sid ?? "", store: store)
        } else {
            MontanaP2PTrace.mark("group_refused", "unreadable from=\(String(pipe.prefix(10)))")
        }
        if verdict != .wait {
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
        default:
            MontanaP2PTrace.mark("group_refused", "kind=\(String(w.t.prefix(8)))")   // a newer build's word: its road ends here
            return .refused
        }
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
                MontanaP2PTrace.mark("group_refused", "invitation of a group held by another owner")
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
            let tag = w.fc.map { String($0.count) + "-" + String($0.suffix(16)) }
            let newFace = tag != nil && tag != g.faceTag
            if newFace { g.faceTag = tag }
            groups[w.g] = g
            saveGroups()
            stand(g, face: newFace ? Self.face(w.fc) : nil, store: store)
            // the reference folder's rows: added again, a new name, a new face -- each the owner's deed
            if back { lay(MTGroupEvent(e: "added", g: g.id, a: Self.ownerSeat, p: [seat]), store: store) }
            if renamed { lay(MTGroupEvent(e: "named", g: g.id, a: Self.ownerSeat, t: title), store: store) }
            if newFace, hadFace, !back { lay(MTGroupEvent(e: "face", g: g.id, a: Self.ownerSeat), store: store) }
            return .held
        }
        var g = MTGroupState(id: w.g, kind: kind, title: title, about: Self.clean(w.ds ?? "", Self.aboutLimit), owner: owner, me: seat,
                             members: [], count: count, names: ownerName.isEmpty ? [:] : [Self.ownerSeat: ownerName],
                             at: Date().timeIntervalSince1970)
        g.faceTag = w.fc.map { String($0.count) + "-" + String($0.suffix(16)) }
        groups[w.g] = g
        saveGroups()
        stand(g, face: Self.face(w.fc), store: store)
        lay(MTGroupEvent(e: "added", g: g.id, a: Self.ownerSeat, p: [seat]), store: store)   // «X added you»
        MontanaP2PTrace.mark("group_rx", "invitation kind=\(kind.rawValue) people=\(count) from=\(String(pipe.prefix(10)))")
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
            guard g.kind == .group else {
                MontanaP2PTrace.mark("group_refused", "a member's letter in a channel is not carried")
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
        stand(g, face: nil, store: store)
        let born = MontanaDeliveryEngine.letterMoment(mid: sid, sentAt: nil)
        let quote = (w.qt ?? "").isEmpty ? nil : w.qt
        let row = Message(text: words, isFromMe: false, time: hhmm(at: born), replyText: quote, deliveryStatus: .delivered,
                          msgId: sid, senderRef: Self.speaker(g.id, seat), createdAt: born,
                          replyToId: store.localId(forMid: w.qm, chat: key))
        let landed = store.append(key, row)   // a channel's post lands on its wall, never as a row (MTBoard.handle)
        MontanaP2PTrace.mark("group_rx", mid: id, "letter landed=\(landed ? 1 : 0) owner=\(g.mine ? 1 : 0) post=\(post ? 1 : 0)")
        if post {
            MontanaNotify.presentGroup(title: g.title, body: String(localized: "New message", bundle: MTLanguage.bundle), chat: key, copy: copy)
            return .held
        }
        if landed {
            // The banner a running app owes its person: the group's title over who wrote and what (a channel speaks as itself).
            let shown = MontanaNotify.body(for: words) ?? String(localized: "New message", bundle: MTLanguage.bundle)
            let who = g.kind == .group ? speakerName(Self.speaker(g.id, seat)) : ""
            MontanaNotify.presentGroup(title: g.title, body: who.isEmpty ? shown : who + ": " + shown, chat: key, copy: copy,
                                       mentioned: g.kind == .group && Self.mentionsMe(words))   // a mention rings through the mute
        }
        if landed, g.mine {
            let on = MTGroupWord(t: "say", g: g.id, k: g.kind.rawValue, ti: g.title, n: name.isEmpty ? nil : name, id: id, s: seat,
                                 tx: words, qt: quote, qm: w.qm)
            spread(on, in: g, except: seat, own: false)
        }
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
        let key = Self.key(of: g.id)
        // AN EDIT OR A DELETION IS THE SPEAKER'S OWN (applyEditFromPeer and deleteEverywhere ask only whose phone wrote a row):
        // the owner answers for every member, so it takes one only for a letter standing here under that member's seat; a member
        // takes the owner's word, and a deletion of a letter not landed yet buries it before it comes.
        if let target = Self.target(words) {
            if let row = store.messages[key]?.first(where: { $0.mid == target }) {
                // The owner and the administrators it named take another's letter away (stage R.6, as the reference's admins
                // delete messages); the owner's word alone names them. An edit stays the speaker's own.
                let boss = words.hasPrefix(deleteMark) && (seat == Self.ownerSeat || g.admins?.contains(seat) == true)
                guard Self.author(row, in: g) == seat || boss else {
                    MontanaP2PTrace.mark("group_refused", "an answer to another's letter seat=\(seat)")
                    return .refused
                }
            } else if store.deletedMids.contains(target) {
                return .held   // the letter is gone here already
            } else if g.mine {
                return .wait   // the letter has not landed at the owner yet: the copy knocks again
            } else if words.hasPrefix(deleteMark) {
                store.deletedMids.insert(target)
                answersHeard.append(id)
                return .held
            }
        }
        answersHeard.append(id)
        if 512 < answersHeard.count { answersHeard.removeFirst(answersHeard.count - 512) }
        let born = MontanaDeliveryEngine.letterMoment(mid: "mid:" + id, sentAt: nil)
        store.append(key, Message(text: words, isFromMe: false, time: "", msgId: "mid:" + id, senderRef: Self.speaker(g.id, seat), createdAt: born))
        if g.mine { spread(MTGroupWord(t: "sig", g: g.id, n: w.n, id: id, s: seat, tx: words), in: g, except: seat, own: false) }
        return .held
    }

    /// A WORD OF A CHANNEL'S WALL (the author's words 06.10.2026 14:2x-14:4x MSK: «in channels posts as on the Wall of Thoughts»): a subscriber's mark -- a like, the posts
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
            MontanaP2PTrace.markFolded("group_paced", "a member past thirty room words a minute -- the copy knocks again", window: 60, key: key)
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
        g.members.removeAll { $0.seat == m.seat }
        g.count = g.members.count + 1
        groups[w.g] = g
        saveGroups()
        tellAll(g, face: nil)
        let gone = MTGroupEvent(e: "left", g: g.id, a: m.seat)
        lay(gone, store: store)
        tellEvent(gone, in: g)
        MontanaP2PTrace.mark("group_rx", "a member left count=\(g.count)")
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
            if !ended { lay(MTGroupEvent(e: "removed", g: g.id, a: Self.ownerSeat, p: [g.me]), store: store) }
            MontanaP2PTrace.mark("group_rx", "taken out by the owner")
        }
        if ended {
            erase(Self.key(of: g.id), store: store)
            MontanaP2PTrace.mark("group_rx", "the owner deleted the group for everyone")
        }
        return .held
    }

    // -- measures ------------------------------------------------------------------------------

    /// WHAT AN ANSWER MAY BE IN A GROUP: an emoji put on a letter or taken off it -- a coin rides a reaction between two people
    /// only, in a group it would be credited from nobody --, a letter's new words, or a letter taken away for everyone.
    static func answers(_ text: String) -> Bool {
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
    /// round note, a voice or a file, whose sealed pieces lie on the nodes for every receiver (the author's words 06.10.2026 14:2x-14:3x MSK: «groups and channels with the whole of a chat, every kind of data»). Never another service word, a long letter's reference, a coin, a game's letter or a row of a
    /// phone's own -- a coin landing in a group would be credited from nobody.
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

/// One person of a group a @ may name.
struct MTRoomPerson: Identifiable, Equatable {
    let seat: String
    let name: String
    var id: String { seat }
}

extension Array {
    /// Nil for an empty list: a field that names nobody is not written at all.
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
