import Foundation
import CryptoKit
import SwiftUI
import UIKit
import AVFoundation
import ImageIO

// ════════════════════════════════════════════════════════════ THE WALL (the author's word 24.09): on a person's
// page the people they allow write posts — words, pictures, videos, tracks and files with their captions — and a
// post lives with those who keep it. The one who wrote it keeps it first; the wall's owner who presses «Save» keeps
// it too, and so may anyone who sees it: every keeper is a peer of the post, and the post stands on the wall while
// one keeper holds its files. Under every post: its keepers, its likes, its comments, its downloads, its reposts.
//
// NO THIRD PARTY HOLDS A WORD OF IT. The words travel as the service word «WL:» in the one pipe between two people,
// the files as sealed chunks on the node's blind store under keys that ride only inside the pipes — the node sees
// the chunks' names and sizes, never a picture, a caption or a writer. The wall's owner answers for their wall: a
// post is sent to them, its counts are kept by them, and a visitor asks them for the page. A visitor never learns
// who the other visitors are — only how many.
//
// «Board» in the code, «Wall» on the screen: a chat's ground is already called its wall (MTWallpaper, chatWall.*).

/// What a rule of my wall is about (the author's word 24.09): who may write on it, and who may see it.
enum MTBoardAct: String { case write, see }

/// Who may write on my wall, and who may see it (the author's word 24.09): only me, everyone, my contacts (the author's
/// word 25.09), some — chosen — or everyone but some. One rule over two acts, each kept under its own keys; both start
/// at «Everyone».
enum MTBoardRule: String, CaseIterable, Identifiable {
    case onlyMe, everyone, contacts, some, except
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .onlyMe: return "Only me"
        case .everyone: return "Everyone"
        case .contacts: return "Only contacts"
        case .some: return "Some people"
        case .except: return "Everyone except"
        }
    }
    static let key = "boardRule"
    static let allowKey = "boardAllow"
    static let denyKey = "boardDeny"
    static let sightKey = "boardSight"
    static let sightAllowKey = "boardSightAllow"
    static let sightDenyKey = "boardSightDeny"
    private static func keys(_ a: MTBoardAct) -> (rule: String, allow: String, deny: String) {
        switch a {
        case .write: return (key, allowKey, denyKey)
        case .see: return (sightKey, sightAllowKey, sightDenyKey)
        }
    }
    /// A rule moved: the wall carries its page again -- the posts' wall renews its version.
    private static func renewed(_ a: MTBoardAct) {
        MTBoard.shared.renewVersion(own: true)
    }
    static func current(_ a: MTBoardAct) -> MTBoardRule {
        MTBoardRule(rawValue: UserDefaults.standard.string(forKey: keys(a).rule) ?? "") ?? .everyone
    }
    static func allowed(_ a: MTBoardAct) -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: keys(a).allow) ?? []) }
    static func denied(_ a: MTBoardAct) -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: keys(a).deny) ?? []) }
    static func choose(_ r: MTBoardRule, for a: MTBoardAct) {
        UserDefaults.standard.set(r.rawValue, forKey: keys(a).rule); renewed(a)
    }
    static func setAllowed(_ s: Set<String>, for a: MTBoardAct) {
        UserDefaults.standard.set(Array(s).sorted(), forKey: keys(a).allow); renewed(a)
    }
    static func setDenied(_ s: Set<String>, for a: MTBoardAct) {
        UserDefaults.standard.set(Array(s).sorted(), forKey: keys(a).deny); renewed(a)
    }
    /// May this correspondent write on my wall, or see it? A blocked person never may.
    static func admits(_ conv: String, to a: MTBoardAct) -> Bool {
        if conv.isEmpty || ChatStore.refusesCold(conv) { return false }
        return byRule(conv, to: a)
    }
    /// The rule alone, without the block list — for the presence word, which is built for every word and never
    /// reaches a blocked person anyway (the critic's P8: the block list is a keychain read).
    static func byRule(_ conv: String, to a: MTBoardAct) -> Bool {
        if conv.isEmpty { return false }
        switch current(a) {
        case .onlyMe: return false
        case .everyone: return true
        case .contacts: return MTNameBook.isContact(conv)
        case .some: return allowed(a).contains(conv)
        case .except: return !denied(a).contains(conv)
        }
    }
}

struct MTBoardChunk: Codable, Hashable { var bid: String; var cs: Int }

/// One file of a post: what a keeper needs to fetch it, and what a page needs to draw it before it is fetched.
struct MTBoardMedia: Codable, Hashable {
    var kind: String            // "img", "vid", "aud" or "doc"
    var name: String            // the name shown for a track or a file
    var ext: String
    var size: Int
    var key: String             // the chunks' key, base64 — it rides only inside the pipes
    var chunks: [MTBoardChunk]
    var thumb: String? = nil    // a small poster, base64 JPEG, for a picture and a video — cut to its frame
    var dur: Double? = nil
    var fr: MTBoardFrame? = nil // a picture's or a video's frame in the post: its shape and the part it shows
}

/// THE PICTURE'S FRAME IN ITS POST (the author's word 24.09: «a preview with the editing of the photo — its size, the
/// field of it the post shows»): the tile's shape, width over height, and the part of the picture the tile shows, in the
/// picture's own proportions (0…1, the picture upright). The poster a post carries is cut to it, so a build that does
/// not read the frame draws the same part; «fr» is a new name, unknown keys are skipped by every build's decoder.
struct MTBoardFrame: Codable, Hashable {
    var a: Double
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    /// The shapes a picture takes in a post: from 9:16 upright to 16:9 wide — a panorama shows its middle.
    static let least = MTPostMeasure.narrowest
    static let most = MTPostMeasure.widest
    static let shapes: [Double] = [1, 4.0 / 5.0, 3.0 / 4.0, 9.0 / 16.0, 4.0 / 3.0, 16.0 / 9.0]
    static func held(_ a: Double) -> Double { a.isFinite && 0 < a ? min(max(a, least), most) : 1 }
    /// The largest part of a picture of this size in the shape a, around a centre (0…1), inside the picture.
    static func around(_ cx: Double, _ cy: Double, shape: Double, of size: CGSize) -> MTBoardFrame {
        let a = held(shape)
        let own = 0 < size.height ? Double(size.width / size.height) : 1
        var w = 1.0, h = 1.0
        if a < own { w = a / own } else { h = own / a }
        return MTBoardFrame(a: a, x: min(max(cx - w / 2, 0), 1 - w), y: min(max(cy - h / 2, 0), 1 - h), w: w, h: h)
    }
    /// A picture's own shape, whole — or, past the shapes a post takes, its middle.
    static func own(_ size: CGSize) -> MTBoardFrame {
        around(0.5, 0.5, shape: 0 < size.height ? Double(size.width / size.height) : 1, of: size)
    }
    /// A frame from another phone held to what a frame can be; nil when it cannot be one.
    var valid: MTBoardFrame? {
        guard [a, x, y, w, h].allSatisfy({ $0.isFinite }), Self.least - 0.01 <= a, a <= Self.most + 0.01,
              0 <= x, 0 <= y, 0.01 <= w, 0.01 <= h, x + w <= 1.0001, y + h <= 1.0001 else { return nil }
        return self
    }
}

struct MTBoardComment: Codable, Hashable, Identifiable {
    var id: String
    var by: String
    var glyph: String
    var text: String
    var at: Double
    var ref: String? = nil      // who wrote it, on the wall owner's phone only — never on a page
    var fc: String? = nil       // the commenter's small face, base64 JPEG, as the commenter sent it (25.09)
    var m: Bool? = nil          // on a page: written by the visitor it is carried to (25.09)
    var o: Bool? = nil
    var h: String? = nil
    var pv: String? = nil
    var hid: Bool? = nil          // on a page: written by the wall's owner (25.09)
}

/// A post as its wall's owner keeps it. The references are the owner's own and never leave the owner's phone: a
/// visitor gets the counts and their own marks (MTBoardSeen).
struct MTBoardPost: Codable, Identifiable, Hashable {
    var id: String
    var author: String          // the writer's reference on the owner's phone; "" = the owner
    var byName: String
    var byGlyph: String
    var at: Double
    var text: String
    var media: [MTBoardMedia]
    var pinned: Bool
    var keepers: [String]       // "" = the owner
    var likes: [String]
    var downloads: [String]
    var reposts: [String]
    var comments: [MTBoardComment]
    var from: String?           // a repost: the name of the wall it was taken from
    var face: String? = nil     // the writer's small face, base64 JPEG, as a writer on another's wall sent it
    var src: String? = nil      // a repost: the wall it was taken from, by reference on this phone — never on a page
    var srcBy: String? = nil    // a repost: its writer by reference, when this phone knows them — never on a page
    var ed: Double? = nil       // the moment its writer last changed the words — never on a page; it moves the wall's version
    var lp: String? = nil       // the link card its writer read; a visitor draws these bytes and opens nothing
    var n: Int? = nil           // its number on its wall, given once at its birth; the short link names it (02.10)
    var views: [String]? = nil  // who saw it, on the owner's phone only, each person once -- never on a page, never shown (06.10)
}

/// A post as a visitor sees it: the counts and the visitor's own marks, no reference of anybody.
struct MTBoardSeen: Codable, Identifiable, Hashable {
    var id: String
    var byName: String
    var byGlyph: String
    var at: Double
    var text: String
    var media: [MTBoardMedia]
    var pinned: Bool
    var keepers: Int
    var likes: Int
    var downloads: Int
    var reposts: Int
    var comments: [MTBoardComment]
    var commentCount: Int
    var liked: Bool
    var kept: Bool
    var reposted: Bool
    var mine: Bool
    var from: String?
    var face: String? = nil     // the writer's small face, when the wall's owner holds one (never the owner's own)
    var own: Bool? = nil        // written by the wall's owner: the visitor knows whose page it is
    var lp: String? = nil       // the link card its writer read; a visitor draws these bytes and opens nothing
    var n: Int? = nil           // its number on its wall, given once at its birth; the short link names it (02.10)
    var views: Int? = nil       // how many people saw it, by its wall owner's count; nil -- the owner's build counts none (06.10)
}

struct MTBoardPage: Codable, Hashable {
    var canWrite: Bool
    var posts: [MTBoardSeen]
    var at: Double
    var version: String? = nil  // the owner's wall version the page was built from (its presence word names it)
}

/// A post whose files this phone keeps: my own on another wall, or one I saved from a wall.
struct MTBoardKept: Codable, Hashable {
    var post: MTBoardSeen
    var wall: String            // the wall's owner by reference; "" = my own wall
    var files: [String]
    var dl: Bool? = nil         // this phone's download of the post is counted on its wall
}

struct MTBoardWord: Codable {
    var t: String
    var id: String? = nil
    var at: Double? = nil
    var tx: String? = nil
    var md: [MTBoardMedia]? = nil
    var bn: String? = nil
    var bg: String? = nil
    var on: Bool? = nil
    var cid: String? = nil
    var w: Bool? = nil
    var ps: [MTBoardSeen]? = nil
    var v: String? = nil
    var fc: String? = nil       // a post's writer's small face
    var lp: String? = nil       // the link card its writer read; a visitor draws these bytes and opens nothing
    var hh: String? = nil
    var pv: String? = nil
    var vs: [String]? = nil     // «view»: the posts seen, a few at once (06.10)
}

/// Whose post it is, as far as this phone knows them: me, a correspondent by reference, or nobody it knows.
enum MTBoardWriter: Equatable { case me, peer(String), unknown }

/// A POST ON ITS WAY (the author's word 24.09: «the system's progress bar at the top of the new post's page, as the
/// backup to iCloud shows it — the blue line with its share and its bytes — and the new post shows at once as it will
/// be published»): the post as it will stand, and each file's pieces THE NODE HAS CONFIRMED — the keeper's own count
/// (MontanaWakePush.uploadChunks), never what was handed to it.
struct MTBoardOutgoing: Identifiable, Codable {
    let id: String
    let wall: String?
    var post: MTBoardSeen
    let sizes: [Int]
    var confirmed: [Int]
    var failed = false
    /// The row a post on its way stands in beside the wall's posts: never the post's own name, which the published post takes.
    var row: String { "out#" + id }
    var total: Int { sizes.reduce(0, +) }
    var done: Int {
        var n = 0
        for (i, s) in sizes.enumerated() { n += min(s, (i < confirmed.count ? confirmed[i] : 0) * MontanaMedia.chunkSize) }
        return n
    }
    var share: Double { total == 0 ? 1 : min(1, Double(done) / Double(total)) }
}

/// A FILE OF A POST BEING WRITTEN, KEPT ON THIS PHONE (25.09): copied into the wall's own drafts folder the moment it is picked,
/// under a name of its own, with what the post shows of it — its size, a track's or a video's length, a picture's frame.
struct MTBoardDraftFile: Codable, Hashable, Identifiable {
    var id: String              // the file's name in the drafts folder
    var kind: String
    var name: String
    var ext: String
    var size: Int
    var dur: Double? = nil
    var fr: MTBoardFrame? = nil
    var url: URL { MTBoardDrafts.url(id) }
}

/// A POST BEING WRITTEN, KEPT (the author's word 25.09: «drafts are permanent — nothing is reset, even after a leave to another
/// app; the wall keeps a draft not published, against failures, the network and every other turn»): its words, its files and
/// the moment it was begun, one per wall, laid into the wall's store as it changes (MTBoard.lay) and read back by the page that
/// writes it — after a leave to another app, a death of the run, a restart. It stands on its wall as itself (MTBoardDraftCell)
/// until it is posted or thrown away.
struct MTBoardDraft: Codable, Hashable {
    var text: String
    var files: [MTBoardDraftFile]
    var at: Double
    var lp: String? = nil
    var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && files.isEmpty }
    /// The post as its wall will draw it, one to one (MTBoard.fresh) — on the page that writes it and on the wall alike.
    func seen(on wall: String?) -> MTBoardSeen {
        let media = files.map { MTBoardMedia(kind: $0.kind, name: $0.name, ext: $0.ext, size: $0.size, key: "", chunks: [], dur: $0.dur, fr: $0.fr) }
        return MTBoard.fresh("draft", on: wall, text: text, media: media, at: at, card: lp)
    }
}

final class MTBoard: ObservableObject {
    static let shared = MTBoard()
    static let mark = "\u{200B}\u{200B}WL:"
    static let mineKey = "board.mine"
    static let keptKey = "board.held"
    static let pagesKey = "board.pages"
    static let capKey = "board.cap"      // the correspondents whose build speaks the wall — told by their own words
    static let sentKey = "board.sent"    // the version of my wall each of them was last carried
    static let draftsKey = "board.drafts" // a post being written, one per wall (25.09)
    static let goingKey = "board.going"   // the posts on their way, until the node holds their files whole (25.09)
    static let ownedKey = "board.owned"   // the posts of the channels this person owns, as an owner keeps them (06.10)
    static let firstKey = "board.first"   // the moment this phone first held each post of another's wall (07.10, held)
    /// The viewer a channel's page is drawn for: nobody's reference, so no subscriber reads another's marks as their own.
    static let subscriber = "#"
    static let pushTo = 128              // the owner carries the wall to the latest correspondents this many at most (25.09: thirty-two left «Everyone» short)
    static let pageSize = 30
    static let commentsShown = 20
    static let commentsKept = 200
    static let textLimit = 4000
    static let commentLimit = 1000
    static let mediaLimit = MTPostMeasure.files
    static let postsPerWriter = 100   // [I-14]-bound: a writer let in cannot fill a wall
    static let wallLimit = 500
    static let walls = 64             // the walls of others kept on this phone, the latest seen
    static let firstKept = 2000       // [I-14] the first sights of posts no page holds any more, the newest kept (held)
    static let thumbLimit = 60_000    // a poster's base64: a tile's picture, never a file
    static let faceLimit = 16_000     // a writer's small face, base64

    @Published private(set) var mine: [MTBoardPost] = []
    /// THE CHANNELS I OWN ARE WALLS OF MINE (the author's words 06.10.2026 14:2x-14:4x MSK: «in channels posts as on the Wall of Thoughts»): each channel's posts as an
    /// owner keeps them -- who liked, who saw, the comments by their writers -- and every subscriber is carried the counts.
    @Published private(set) var owned: [String: [MTBoardPost]] = [:]
    @Published private(set) var pages: [String: MTBoardPage] = [:]
    @Published private(set) var kept: [String: MTBoardKept] = [:]
    @Published private(set) var asking: Set<String> = []
    @Published private(set) var fetching: Set<String> = []
    @Published private(set) var outgoing: [String: MTBoardOutgoing] = [:]
    @Published private(set) var reposting: [String: MTBoardOutgoing] = [:]   // a repost on its way: its files coming here (25.09)
    /// A POST BEING WRITTEN, ONE PER WALL (25.09): written to the vault as it changes; the wall's pages hear of its birth and its
    /// end, never of every letter typed (the page that writes it shows the words itself).
    private(set) var drafts: [String: MTBoardDraft] = [:]
    private var publishing: Set<String> = []   // the posts whose files are being laid this moment: one lay a post at a time
    private var askedAt: [String: Date] = [:]
    private var goneSaid: Set<String> = []
    private var countedDownload: Set<String> = []
    private var heard: [String: String] = [:]   // the wall version each correspondent's presence word named
    private var cap: Set<String> = []
    private var sent: [String: String] = [:]
    private var firstSeen: [String: Double] = [:]   // a post's id: the moment this phone first held it (held)
    private var answeredAt: [String: Date] = [:]
    private var pushing: Set<String> = []
    private var inFlight: [String: (v: String, at: Date)] = [:]   // the page handed to the queue, until its receipt
    private var hiSaid: Set<String> = []
    private var pushWork: DispatchWorkItem?
    private var dirty: Set<String> = []
    private var saveWork: DispatchWorkItem?

    private init() {
        load()
        NotificationCenter.default.addObserver(forName: .montanaSeedForgotten, object: nil, queue: .main) { [weak self] _ in
            self?.load()   // another person's wall is not this one's
        }
    }
    /// A person was lifted into the seat (MTSeats, the second identity checklist): the wall reads that person's values,
    /// or the memory of the moment before writes itself over them.
    func reread() { load() }
    private func load() {
        mine = Self.read(Self.mineKey) ?? []
        owned = Self.read(Self.ownedKey) ?? [:]
        let numbered = Self.numberMissing(&mine)
        let sealedChain = Self.sealMissing(&mine) || numbered
        kept = Self.read(Self.keptKey) ?? [:]
        firstSeen = Self.read(Self.firstKey) ?? [:]
        let stored: [String: MTBoardPage] = Self.read(Self.pagesKey) ?? [:]
        pages = stored.filter { !Self.isEcho($0.value.posts, of: mine) }
        if pages.count != stored.count { MontanaTrace.mark("wall_echo", "let go at the load n=\(stored.count - pages.count)") }
        cap = Self.read(Self.capKey) ?? []
        sent = Self.read(Self.sentKey) ?? [:]
        // A DRAFT AND A POST ON ITS WAY OUTLIVE THE RUN (the author's word 25.09: «drafts are permanent — nothing is reset; against
        // failures, the network and other turns»): a draft comes back with the files its folder still holds (a copy laid on another
        // phone carries the words, not the files); a post on its way comes back as one the node did not take whole — the bar says
        // so, with its try-again — and is laid again by itself the moment the app is on the screen (roadBack); its files lie in
        // the media store under the post's own names. What no draft names in the drafts folder is let go.
        var held: [String: MTBoardDraft] = Self.read(Self.draftsKey) ?? [:]
        for k in held.keys {
            held[k]?.files.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
            if held[k]?.empty == true { held.removeValue(forKey: k) }
        }
        drafts = held
        var going: [String: MTBoardOutgoing] = Self.read(Self.goingKey) ?? [:]
        for k in going.keys {
            let pieces = going[k]?.sizes.count ?? 0   // read before the write: one access to the map at a time
            going[k]?.failed = true
            going[k]?.confirmed = Array(repeating: 0, count: pieces)
        }
        outgoing = going
        if !going.isEmpty || !held.isEmpty { MontanaTrace.mark("wall_kept", "going=\(going.count) drafts=\(held.count)") }
        let named = Set(held.values.flatMap { $0.files.map { $0.id } })
        DispatchQueue.global(qos: .utility).async { MTBoardDrafts.sweep(keeping: named) }
        DispatchQueue.global(qos: .utility).async { _ = MTBoardLook.folder() }   // the folder's birth and its one-time move out of Caches, off the main thread (29.09)
        renewVersion()
        if sealedChain { saveMine() }
        DispatchQueue.main.async { [weak self] in self?.lendMissingFaces(); self?.watchMint() }   // the wall may be read first from any thread
    }
    private static func read<T: Decodable>(_ key: String) -> T? {
        guard let d = MontanaLocalVault.getDecrypted(key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private static func write<T: Encodable>(_ value: T, _ key: String) {
        if let d = try? JSONEncoder().encode(value) { _ = MontanaLocalVault.setEncrypted(key, d) }
    }
    // ONE WRITE A MOMENT (the critic 24.09): a like wrote the whole wall — its posters with it — sealed, on the main
    // thread, at every touch. The writes gather for a moment and leave as one.
    private func saveMine(own: Bool = false) {
        _ = Self.numberMissing(&mine); renewVersion(own: own); scheduleSave(Self.mineKey)
    }
    private func saveKept() { scheduleSave(Self.keptKey) }
    private func saveOwned() { scheduleSave(Self.ownedKey) }
    private func savePages() { scheduleSave(Self.pagesKey) }
    private func saveCap() { scheduleSave(Self.capKey) }
    private func saveSent() { scheduleSave(Self.sentKey) }
    private func saveDrafts() { scheduleSave(Self.draftsKey) }
    private func saveGoing() { scheduleSave(Self.goingKey) }
    private func scheduleSave(_ key: String) {
        dirty.insert(key)
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    func flush() {
        if dirty.contains(Self.mineKey) { Self.write(mine, Self.mineKey) }
        if dirty.contains(Self.ownedKey) { Self.write(owned, Self.ownedKey) }
        if dirty.contains(Self.keptKey) { Self.write(kept, Self.keptKey) }
        if dirty.contains(Self.pagesKey) {
            if Self.walls < pages.count {
                let keep = Set(pages.sorted { $0.value.at > $1.value.at }.prefix(Self.walls).map { $0.key })
                pages = pages.filter { keep.contains($0.key) }
            }
            Self.write(pages, Self.pagesKey)
        }
        if dirty.contains(Self.capKey) { Self.write(cap, Self.capKey) }
        if dirty.contains(Self.sentKey) { Self.write(sent, Self.sentKey) }
        if dirty.contains(Self.draftsKey) { Self.write(drafts, Self.draftsKey) }
        if dirty.contains(Self.goingKey) { Self.write(outgoing, Self.goingKey) }
        if dirty.contains(Self.firstKey) {
            // [I-14] bound: a moment is kept while its post stands on a page here, or for thirty days after it was first held.
            let standing = Set(pages.values.flatMap { pg in pg.posts.map(\.id) })
            let since = Date().timeIntervalSince1970 - 30 * 86400
            firstSeen = firstSeen.filter { e in standing.contains(e.key) || since < e.value }
            let gone = firstSeen.filter { e in !standing.contains(e.key) }
            if Self.firstKept < gone.count {
                let keep = Set(gone.sorted { a, b in b.value < a.value }.prefix(Self.firstKept).map(\.key))
                firstSeen = firstSeen.filter { e in standing.contains(e.key) || keep.contains(e.key) }
            }
            Self.write(firstSeen, Self.firstKey)
        }
        dirty.removeAll()
    }

    // -- names ----------------------------------------------------------------------------------

    /// A post's file in the media store: its name is the post's and the file's place in it, so a file fetched twice
    /// lands once and a keeper finds it by the post alone.
    static func fileName(_ pid: String, _ i: Int, _ ext: String) -> String {
        "wall_" + pid + "_" + String(i) + (ext.isEmpty ? "" : "." + ext)
    }
    /// A post's photos on this phone, in the post's order: what a tapped picture of the post pages through
    /// (PhotoPresenter.present(_:among:), the one road for a picture).
    static func pictures(_ p: MTBoardSeen) -> [MTMoment] {
        p.media.indices.compactMap { j in
            let m = p.media[j], f = fileName(p.id, j, m.ext)
            guard m.kind == "img", MontanaMediaStore.exists(f) else { return nil }
            return MTMoment(id: f, url: MontanaMediaStore.url(f), caption: p.byName, own: false, at: Double(j), chat: "", mid: nil, photo: true)
        }
    }
    /// THE WALL NAMES ITS FILES TO THE SWEEP (the pattern of the sticker book): no letter names them, and the sweep
    /// carries off what no letter names — a kept post's files, and my own wall's files I keep.
    var allFiles: Set<String> {
        var s = Set<String>()
        for k in kept.values { for f in k.files where !f.isEmpty { s.insert(f) } }
        for p in mine where p.keepers.contains("") {
            for i in p.media.indices { s.insert(Self.fileName(p.id, i, p.media[i].ext)) }
        }
        for o in outgoing.values {   // a post on its way: its files are laid from here
            for i in o.post.media.indices { s.insert(Self.fileName(o.id, i, o.post.media[i].ext)) }
        }
        return s
    }
    /// MY WALL'S VERSION, IN EVERY PRESENCE WORD (the critic 24.09): a visitor fetches the page when the version they
    /// hear differs from the page they hold — never at a look: opening a person's page used to ask them for it, and so
    /// told them, at that moment, who was looking. Digits only («W», uppercase and digits, invisible to every frozen
    /// build); «0» — the wall is empty, or not the visitor's to see.
    private static let versionLock = NSLock()
    private static var versionKept = "0"
    /// ONE VERSION PER VISITOR (the critic's P5): the posts' part, kept beside the wall, and that visitor's own right to
    /// write — so a change of anybody else's rights moves nobody's version, and two visitors comparing notes learn
    /// nothing of each other. A VISITOR THE RULE OF SIGHT LEAVES OUT HEARS WHAT AN EMPTY WALL SAYS (the critic's N3):
    /// the version and the page of an empty wall they may not write on — so the refusal itself says nothing. «0» is
    /// only read, from the builds of 1923–1925.
    static let refusedVersion = MontanaDeliveryEngine.Announced.wireTag(Data("0r".utf8))
    static func spokenVersion(for peer: String) -> String {
        _ = shared   // the wall is read before its version is spoken: an unread wall is not an empty one
        guard MTBoardRule.byRule(peer, to: .see) else { return refusedVersion }
        versionLock.lock(); let base = versionKept; versionLock.unlock()
        let bit = MTBoardRule.byRule(peer, to: .write) ? "w" : "r"
        return MontanaDeliveryEngine.Announced.wireTag(Data((base + bit).utf8))
    }
    /// One who hides their presence carries the wall only right after an act of their own (the critic's N6): a carry at
    /// a return of the app, or after marks that came while it was closed, would say when they came back.
    func renewVersion(own: Bool = false) {
        let v = postsTag
        Self.versionLock.lock(); Self.versionKept = v; Self.versionLock.unlock()
        if own || MontanaPresencePrivacy.sharing { schedulePush() }
    }
    /// THE PAGE'S SHAPE IS PART OF ITS VERSION (the critic 25.09): a build whose page says more — which comments are the
    /// visitor's own, which the owner's — carries every page again once, when the phone that holds the wall takes it; the
    /// pages its visitors hold were drawn in the older shape and would wait for the wall's next change.
    static let pageShape = "c4"   // c4 (06.10): a page carries its posts' views
    private var postsTag: String {
        let shown = ordered(mine).prefix(Self.pageSize)
        guard !shown.isEmpty else { return "0" }
        var s = Self.pageShape + ";"
        for p in shown {
            let faces = p.comments.filter { $0.fc != nil }.count + (p.face == nil ? 0 : 1)   // a face lent moves the page (lent)
            s += p.id + (p.pinned ? "p" : "") + String(p.keepers.count) + "." + String(p.likes.count) + "." + String(p.downloads.count)
                + "." + String(p.reposts.count) + "." + String(p.comments.count) + "." + String(faces)
                + "." + String(Self.viewStep(p.views?.count ?? 0))
            let hid = p.comments.filter { $0.hid == true }.count
            s += (p.ed.map { "e" + String(Int($0 * 1000)) } ?? "") + "z" + String(hid) + ";"   // an edit moves only its own wall's version
        }
        return MontanaDeliveryEngine.Announced.wireTag(Data(s.utf8))
    }
    /// THE VIEWS MOVE THE WALL'S VERSION AT EVERY DOUBLING (06.10): a moved version carries the page to every correspondent, so a
    /// count that moved it at every viewer would carry the whole wall a hundred times for a hundred viewers; at 1, 2, 4, 8 ... it
    /// travels a handful of times, and a visitor's ask brings it exact.
    static func viewStep(_ n: Int) -> Int { n == 0 ? 0 : Int.bitWidth - n.leadingZeroBitCount }
    /// A correspondent's presence word named their wall's version — and so said their build speaks the wall.
    func heard(version v: String, from conv: String) {
        heard[conv] = v
        learnCap(conv)
        if v == "0" {
            // A build of 1923–1925 says «0» for an empty wall and for one not ours to see alike, and carries nothing: a
            // wall never held is asked (the critic's N7 — else no first post could be written on it), an empty page
            // it may write on is asked again after an hour (a refusal since reads the same «0»), and posts held from
            // it are taken down.
            guard let pg = pages[conv] else { ask(conv); return }
            if !pg.posts.isEmpty {
                pages[conv] = MTBoardPage(canWrite: false, posts: [], at: Date().timeIntervalSince1970, version: "0")
                savePages()
            } else if pg.canWrite, 3600 < Date().timeIntervalSince1970 - pg.at {
                ask(conv)
            }
            return
        }
        guard pages[conv]?.version != v else { return }
        ask(conv)
    }
    /// EVERY WALL NEVER SEEN IS ASKED AT ONCE (the author's word 25.09: «with “Everyone” everything must show at once»): a wall
    /// this phone knows speaks the wall and never came is asked for when my app comes back — every one of them, a third of a
    /// second apart. Three at a time with waits of 5–45 s (24.09) left a person with ten walls waiting four returns of the app.
    func sweep() {
        // A WALL WHOSE PAGE NEVER CAME FROM ITS OWNER IS A WALL NOT YET SEEN (the author's word 25.09: «from T3 I must see the
        // iPhone 15's wall when she shows it to everyone»): a post of mine on it made a page of one post here, and that page
        // stood for the wall for ever — no ask ever went, and an owner who carries nothing never sent the wall itself.
        let unknown = cap.filter { MontanaConv.holds($0) && pages[$0]?.version == nil }
        for (n, conv) in unknown.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * Double(n)) { [weak self] in self?.ask(conv) }
        }
    }
    /// THE LOOK ASKS (the author's word 25.09: «if the person shows the wall to everyone, entering the page must show it to
    /// everyone, at once»): a person's page and the feed ask for every wall they draw that this phone does not hold, or holds
    /// from more than ten minutes ago. What is held is drawn at once; the owner's fresh page takes its place when it comes.
    /// The critic's P1 of 24.09 (a look tells the owner who looked) yields to the author's word: a wall shown to everyone
    /// hides its lookers from no one. The ask keeps its minute of silence per wall (ask).
    static let lookStale: TimeInterval = 600
    func look(_ wall: String?) {
        guard let wall, !wall.isEmpty, MontanaConv.holds(wall) else { return }
        if let pg = pages[wall], Date().timeIntervalSince1970 - pg.at < Self.lookStale { return }
        ask(wall)
    }
    func lookFeed() {
        var n = 0
        for conv in cap where MontanaConv.holds(conv) {
            if let pg = pages[conv], Date().timeIntervalSince1970 - pg.at < Self.lookStale { continue }
            let wait = 0.3 * Double(n); n += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.ask(conv) }
        }
    }

    // -- the owner carries the wall ----------------------------------------------------------------

    private func learnCap(_ conv: String) {
        guard !conv.isEmpty, !cap.contains(conv) else { return }
        cap.insert(conv)
        saveCap()
        if MontanaPresencePrivacy.sharing { schedulePush() }   // one who hides carries at their own next act (N6)
    }
    /// THE OWNER CARRIES THE WALL (the critic 24.09, P1: the ask at a look told the owner who was looking, and a person
    /// who hid their presence never saw a wall). After a change of the wall or of its rules and at every return of the app,
    /// the page goes to each of the latest correspondents whose build speaks the wall and whose version of it moved — IN
    /// THE SAME SECOND (the author's word 25.09: «everything at once»): half a second to fold a burst of edits into one page,
    /// then every correspondent a few frames apart (the twenty seconds of gathering and the 3–45 s of chance for each, 24.09,
    /// left a visitor's page a minute stale). One page on its way per correspondent; every build with the wall takes a page
    /// it did not ask for. A correspondent the rule of sight leaves out is carried the empty page once, and then nothing.
    func schedulePush() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pushWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.pushDue() }
            self.pushWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }
    func pushDue() {
        let latest = (ChatStore.live?.listChats() ?? []).compactMap { $0.convId }.filter { cap.contains($0) }
        // A WITHDRAWN SIGHT REACHES EVERYONE WHO SAW (the critic's N4): whoever was carried a wall they may no longer
        // see gets the empty page — beyond the latest few, and out of the archive too — so no old post stays with them.
        let withdrawn = sent.filter { $0.value != Self.refusedVersion && !MTBoardRule.byRule($0.key, to: .see) }.map { $0.key }
        var due = Array(latest.prefix(Self.pushTo))
        for c in withdrawn where !due.contains(c) { due.append(c) }
        var n = 0
        for conv in due where MontanaConv.holds(conv) && !pushing.contains(conv) {
            let v = Self.spokenVersion(for: conv)
            guard sent[conv] != v, !onItsWay(conv, v) else { continue }
            pushing.insert(conv)
            let wait = 0.15 * Double(n); n += 1   // the same second for everyone, a few frames apart (25.09)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self else { return }
                self.pushing.remove(conv)
                let v = Self.spokenVersion(for: conv)
                guard self.sent[conv] != v, !self.onItsWay(conv, v) else { return }
                self.sendPage(to: conv, version: v)
            }
        }
    }
    /// The same page already stands in the queue for them, handed less than half an hour ago (a letter the queue gave
    /// up on is carried again after that).
    private func onItsWay(_ conv: String, _ v: String) -> Bool {
        guard let f = inFlight[conv], f.v == v else { return false }
        return Date().timeIntervalSince(f.at) < 1800
    }
    /// The one page this owner sends — carried, or answering an ask. Only one who may see may write (the critic's
    /// P2): a writer who cannot see the wall would watch their own post vanish and learn they were left out. THE PAGE
    /// IS «SENT» AT ITS RECEIPT (the critic's N5; the law of Announced.recordDelivered): the version a visitor holds is
    /// written by the receipt of the very letter that carried it (delivered); a page the queue refused or retired
    /// writes nothing and is carried again. A newer page takes the queued one's place (MontanaDeliveryEngine.enqueue,
    /// the critic's N1), and a carried page holds no more posters than a page draws.
    private func sendPage(to conv: String, version v: String) {
        let sees = MTBoardRule.admits(conv, to: .see)
        let ps: [MTBoardSeen] = sees ? ordered(mine).prefix(Self.pageSize).map { Self.clean(seen($0, by: conv, conceal: true)) } : []
        guard send(MTBoardWord(t: "page", w: sees && MTBoardRule.admits(conv, to: .write), ps: ps, v: v), to: conv) else { return }
        inFlight[conv] = (v, Date())
        answeredAt[conv] = Date()   // an ask that crosses the carried page is not answered twice
        MontanaTrace.mark("wall_page", "posts=\(ps.count)")
    }
    /// The receipt of a page letter: the version it carried is the one that visitor now holds.
    static func delivered(text: String, to conv: String) {
        guard isPage(text), let d = String(text.dropFirst(mark.count)).data(using: .utf8),
              let w = try? JSONDecoder().decode(MTBoardWord.self, from: d), let v = w.v else { return }
        DispatchQueue.main.async {
            let b = shared
            b.sent[conv] = v
            if b.inFlight[conv]?.v == v { b.inFlight[conv] = nil }
            b.saveSent()
        }
    }
    /// A page of a wall, told from any other word of it — for the queue, which keeps one per person.
    static func isPage(_ text: String) -> Bool { text.hasPrefix(mark) && text.contains("\"t\":\"page\"") }
    static func nameOf(_ conv: String) -> String {
        let n = ChatStore.live?.displayName(for: conv) ?? ""
        return n.isEmpty ? String(localized: "Someone", bundle: MTLanguage.bundle) : n
    }
    /// THE NAME A REPOST SAYS IT CAME FROM (the critic 25.09): the name that wall's owner gave themselves — never the name
    /// this phone keeps for them (nameOf), which is this phone's own word, a rename or a card, and leaves with no post —
    /// or their public @name when they gave none.
    static func publicName(of conv: String) -> String {
        if let d = MTNameBook.declared[conv], !d.isEmpty { return String(d.prefix(64)) }
        if let n = MTNameBook.name(conv), !n.isEmpty { return "@" + n }
        return String(localized: "Someone", bundle: MTLanguage.bundle)
    }

    // -- what a wall shows ------------------------------------------------------------------------

    /// What a wall shows here: mine as its owner sees it, another's as its owner last sent it.
    func posts(on wall: String?) -> [MTBoardSeen] {
        guard let wall else { return ordered(mine).map { seen($0, by: "") } }
        if let ps = owned[wall] { return ordered(ps).map { seen($0, by: "") } }   // a channel of mine: its owner's own page
        return (pages[wall]?.posts ?? []).sorted { a, b in a.pinned != b.pinned ? a.pinned : Self.lastAt(a) > Self.lastAt(b) }
    }
    /// THE FEED (the author's words 25.09: «every post of all my contacts, by time, and the reposts too»): every post of my
    /// own wall — my reposts among them, and what I write from the feed — and of every wall of my people this phone holds,
    /// each once by its wall and its name, the most seen first (06.10). A wall whose correspondence this phone no longer
    /// holds, or whose owner is blocked or barred, stands out of it; at most the newest three hundred.
    static let feedSize = 300
    func feed() -> [MTBoardFeedItem] {
        let blocked = ChatStore.live?.blockedChats ?? [], barred = MontanaSafety.barred
        var all = mine.map { MTBoardFeedItem(wall: "", post: seen($0, by: "")) }
        for (wall, pg) in pages where !wall.isEmpty && !blocked.contains(wall) && !barred.contains(wall) && MontanaConv.holds(wall) {
            for p in pg.posts { all.append(MTBoardFeedItem(wall: wall, post: p)) }
        }
        var once = Set<String>()
        all = all.filter { once.insert($0.id).inserted }
        // THE FEED STANDS BY TIME, THE NEWEST ON TOP (the author's word 06.10.2026 15:0x MSK: «the Wall of Thoughts strictly by time,
        // the newest on top, the common one» -- it replaces the rank by views of 00:4x): every post by the moment it was published,
        // the newest first; a comment moves nothing. Every reader of the feed -- its page, its pictures' pager, its playlist -- reads
        // this one order.
        return Array(all.sorted { a, b in a.post.at == b.post.at ? a.id > b.id : b.post.at < a.post.at }.prefix(Self.feedSize))
    }
    func canWrite(on wall: String?) -> Bool {
        guard let wall else { return true }
        // A CHANNEL IS A WALL (the author's words 06.10.2026 14:2x-14:4x MSK: «in channels posts as on the Wall of Thoughts; everything the wall publishes is published in a channel»): its owner alone writes on it; a subscriber reads.
        if MTGroup.isKey(wall) { return MTGroup.shared.kind(wall) == .channel && MTGroup.shared.state(wall)?.mine == true }
        return pages[wall]?.canWrite ?? false
    }
    func isAsking(_ wall: String?) -> Bool { wall.map { asking.contains($0) } ?? false }
    /// A channel's page stands from its birth: its posts come by its owner's carrier, never by an ask (MTGroup.carryWallPost).
    func hasPage(_ wall: String?) -> Bool { wall.map { MTGroup.isKey($0) || pages[$0] != nil } ?? true }
    /// A channel's post on the wire (MTGroup.carryWallPost): the wall's own word «cpost».
    static func isChannelPost(_ text: String) -> Bool { text.hasPrefix(mark) && text.contains("\"t\":\"cpost\"") }   // COMPAT-GATED: rides a channel's carrier alone (MTGroup.carries)
    private func ordered(_ ps: [MTBoardPost]) -> [MTBoardPost] {
        ps.sorted { a, b in a.pinned != b.pinned ? a.pinned : Self.lastAt(a) > Self.lastAt(b) }
    }
    private func seen(_ p: MTBoardPost, by v: String, conceal: Bool = false) -> MTBoardSeen {
        MTBoardSeen(id: p.id, byName: p.byName, byGlyph: p.byGlyph, at: p.at, text: p.text, media: p.media, pinned: p.pinned,
                    keepers: p.keepers.count, likes: p.likes.count, downloads: p.downloads.count, reposts: p.reposts.count,
                    comments: (conceal ? Array(p.comments.suffix(Self.commentsShown)) : Array(p.comments)).map { Self.shown($0, to: v, conceal: conceal) },
                    commentCount: p.comments.count,
                    liked: p.likes.contains(v), kept: p.keepers.contains(v), reposted: p.reposts.contains(v),
                    mine: p.author == v, from: p.from,
                    face: p.author.isEmpty && p.from == nil ? nil : p.face,
                    // A REPOST OF THE OWNER'S OWN POST IS THE OWNER'S TOO (the author's word 25.09: «on a reposted post everything
                    // works as on an ordinary one — its writer clickable»): the visitor is told its writer is the page's owner.
                    own: p.author.isEmpty && (p.from == nil || p.srcBy == ""), lp: p.lp, n: p.n, views: p.views?.count ?? 0)
    }
    /// A COMMENT AS A PAGE CARRIES IT TO ONE VISITOR (the author's word 25.09: «the commenters' faces are still not seen»):
    /// nobody's reference — only the two marks that visitor may read: the comment is their own, or the wall owner's. Those
    /// two wear the faces the visitor's phone holds; the rest wear the small face their writers sent.
    private static func shown(_ c: MTBoardComment, to v: String, conceal: Bool = false) -> MTBoardComment {
        var x = c
        x.m = !v.isEmpty && c.ref == v ? true : nil
        x.o = c.ref == "" ? true : nil
        x.ref = nil
        if conceal, x.hid == true { x.text = "" }
        return x
    }

    // -- the wire -------------------------------------------------------------------------------

    @discardableResult
    private func send(_ w: MTBoardWord, to conv: String) -> Bool {
        // A CHANNEL'S WALL TALKS BY THE CHANNEL'S CARRIER (MTGroup.carryWallWord): a subscriber's mark goes to the owner.
        if MTGroup.isKey(conv) {
            if Thread.isMainThread { return MainActor.assumeIsolated { MTGroup.shared.carryWallWord(w, in: conv) } }
            DispatchQueue.main.async { MainActor.assumeIsolated { _ = MTGroup.shared.carryWallWord(w, in: conv) } }
            return true
        }
        guard MontanaConv.holds(conv), !ChatStore.refusesCold(conv),
              let d = try? JSONEncoder().encode(w), let js = String(data: d, encoding: .utf8) else { return false }
        MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: UUID().uuidString, text: Self.mark + js, silent: true)
        MontanaTrace.mark("wall_tx", "t=\(w.t) to=\(String(conv.prefix(10)))")   // named as the presence lines name (25.09): whose page did not come is then a fact
        return true
    }

    /// A word of the wall arrived. True when it was ours to read: the letter is service and never becomes a row.
    @discardableResult
    static func handle(_ text: String, from conv: String, isFromMe: Bool) -> Bool {
        guard text.hasPrefix(mark) else { return false }
        guard !isFromMe, !ChatStore.refusesCold(conv),
              let d = String(text.dropFirst(mark.count)).data(using: .utf8),
              let w = try? JSONDecoder().decode(MTBoardWord.self, from: d) else { return true }
        if Thread.isMainThread { shared.apply(w, from: conv) } else { DispatchQueue.main.async { shared.apply(w, from: conv) } }
        return true
    }

    private func apply(_ w: MTBoardWord, from conv: String) {
        MontanaTrace.mark("wall_rx", "t=\(w.t) from=\(String(conv.prefix(10)))")
        if !MTGroup.isKey(conv) { learnCap(conv) }   // a word of the wall is the proof its build speaks it; a channel has no wall of mine to carry
        let now = Date().timeIntervalSince1970
        switch w.t {
        case "post":
            guard let id = w.id, !id.isEmpty else { return }
            guard MTBoardRule.admits(conv, to: .write), MTBoardRule.admits(conv, to: .see) else {
                send(MTBoardWord(t: "no", id: id), to: conv)
                MontanaTrace.mark("wall_refused", "rule=\(MTBoardRule.current(.write).rawValue)")
                return
            }
            guard !mine.contains(where: { $0.id == id }) else { return }
            guard mine.filter({ $0.author == conv }).count < Self.postsPerWriter, mine.count < Self.wallLimit else {
                send(MTBoardWord(t: "no", id: id), to: conv)
                MontanaTrace.mark("wall_refused", "full")
                return
            }
            let name = (w.bn ?? "").isEmpty ? Self.nameOf(conv) : String((w.bn ?? "").prefix(64))
            let glyph = (w.bg ?? "").isEmpty ? MontanaAvatar.initial(title: name, name: "") : String((w.bg ?? "").prefix(8))
            mine.append(MTBoardPost(id: id, author: conv, byName: name, byGlyph: glyph, at: min(w.at ?? now, now),
                                    text: String((w.tx ?? "").prefix(Self.textLimit)), media: Self.clean(w.md ?? []),
                                    pinned: false, keepers: [conv], likes: [], downloads: [], reposts: [], comments: [], from: nil,
                                    face: (w.fc ?? "").isEmpty || Self.faceLimit < (w.fc ?? "").count ? nil : w.fc, lp: Self.fitCard(w.lp)))
            saveMine()
            // The owner's row is born here, as the post is taken onto the wall -- once, for a post the wall holds is refused above.
            ChatStore.live?.appendWallPost(peer: conv, card: MTWallCard(id: id, text: w.tx ?? "", kind: w.md?.first?.kind), mine: false)
            if (w.fc ?? "").isEmpty { lendFaces([conv]) }   // a build that sent no face: the face they published here
        case "no":
            guard let id = w.id else { return }
            forgetKept(id)
            ChatStore.live?.dropWallPost(peer: conv, id: id)   // the owner said no: the post's row leaves the chat (30.09)
            patchPage(conv) { pg in pg.posts.removeAll { $0.id == id } }
        case "ask":
            // WHO MAY SEE (the author's word 24.09): a correspondent the rule leaves out is answered with an empty page
            // and the empty wall's version — the same answer an empty wall gives, so the refusal itself says nothing.
            // One answer to one correspondent in thirty seconds (the critic's P6): asks piled up in a queue cost the
            // owner one page, not one page each.
            if let t = answeredAt[conv], Date().timeIntervalSince(t) < 30 { return }
            answeredAt[conv] = Date()
            sendPage(to: conv, version: Self.spokenVersion(for: conv))
        case "page":
            asking.remove(conv)
            let fresh = MTBoardPage(canWrite: w.w ?? false, posts: (w.ps ?? []).prefix(Self.pageSize).map { Self.clean($0) },
                                    at: now, version: w.v)
            if Self.isEcho(fresh.posts, of: mine) {
                MontanaTrace.mark("wall_echo", "a page of my own posts came back from=\(String(conv.prefix(10))) — refused")
                return
            }
            var page = fresh
            page.posts = held(fresh.posts, now: now)   // an echo refused above leaves no first sight behind
            pages[conv] = pages[conv].map { Self.keepMine($0, into: page, now: now) } ?? page
            savePages()
        // A CHANNEL'S POST (MTGroup.carryWallPost): its owner's post joins the channel's page here, once by its name, the newest
        // first; the group's carrier took it only from the channel's owner (MTGroup.heard).
        case "cpost" where MTGroup.isKey(conv):   // COMPAT-GATED: rides a channel's carrier alone (MTGroup.carries)
            guard let c = w.ps?.first, let p = held([Self.clean(c)], now: now).first else { return }
            var pg = pages[conv] ?? MTBoardPage(canWrite: false, posts: [], at: now)
            pg.posts.removeAll { $0.id == p.id }
            pg.posts.insert(p, at: pg.posts.firstIndex(where: { !$0.pinned }) ?? pg.posts.count)
            if Self.wallLimit < pg.posts.count { pg.posts.removeLast(pg.posts.count - Self.wallLimit) }
            pg.canWrite = false
            pg.at = now
            pages[conv] = pg
            savePages()
        case "cpost": break
        // A CHANNEL'S COUNTS (tellChannel): the likes, the views, the comments and the pin its owner holds; the files stay as they came.
        case "ccount" where MTGroup.isKey(conv):   // COMPAT-GATED: rides a channel's carrier alone
            guard let q = w.ps?.first.map({ Self.clean($0) }) else { return }
            patchPost(conv, q.id) { s in
                s.likes = q.likes; s.views = q.views; s.comments = q.comments; s.commentCount = q.commentCount
                s.pinned = q.pinned; s.text = q.text; s.lp = q.lp
            }
        case "ccount": break
        case "cdel" where MTGroup.isKey(conv):   // COMPAT-GATED: rides a channel's carrier alone
            guard let id = w.id else { return }
            forgetKept(id)
            patchPage(conv) { pg in pg.posts.removeAll { $0.id == id } }
        case "cdel": break
        case "drop":
            guard let id = w.id else { return }
            forgetKept(id)
            patchPage(conv) { pg in pg.posts.removeAll { $0.id == id } }
        // A mark and a comment come from one who sees the wall; a comment is writing on it (the critic's noticed point 4).
        case "like" where MTBoardRule.admits(conv, to: .see): mutate(w.id) { p in Self.toggle(&p.likes, conv, w.on ?? true) }
        case "keep" where MTBoardRule.admits(conv, to: .see): mutate(w.id) { p in Self.toggle(&p.keepers, conv, w.on ?? true) }
        case "dl" where MTBoardRule.admits(conv, to: .see): mutate(w.id) { p in Self.toggle(&p.downloads, conv, true) }
        case "rp" where MTBoardRule.admits(conv, to: .see): mutate(w.id) { p in Self.toggle(&p.reposts, conv, true) }
        case "like", "keep", "dl", "rp": break
        // A POST SEEN (the author's words 06.10.2026 00:4x MSK: «an eye and how many views», «people, only the number»): one who
        // sees the wall names the posts they saw; a person counts once on a post, its writer never, and nobody is shown who.
        case "view" where MTBoardRule.admits(conv, to: .see):
            var moved = false
            for id in (w.vs ?? []).prefix(Self.pageSize) {
                guard let i = mine.firstIndex(where: { $0.id == id }), mine[i].author != conv,
                      !(mine[i].views ?? []).contains(conv) else { continue }
                mine[i].views = (mine[i].views ?? []) + [conv]
                moved = true
            }
            if moved { saveMine() }
        case "view": break
        case let w where MTRetired.word(w): break   // an older build's op of a kind this app no longer has moves nothing here
        case "cmt":
            guard MTBoardRule.admits(conv, to: .see), MTBoardRule.admits(conv, to: .write) else { return }
            let text = (w.tx ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let name = (w.bn ?? "").isEmpty ? Self.nameOf(conv) : String((w.bn ?? "").prefix(64))
            let face = (w.fc ?? "").isEmpty || Self.faceLimit < (w.fc ?? "").count ? nil : w.fc
            var c = MTBoardComment(id: w.cid ?? UUID().uuidString, by: name,
                                   glyph: (w.bg ?? "").isEmpty ? MontanaAvatar.initial(title: name, name: "") : String((w.bg ?? "").prefix(8)),
                                   text: String(text.prefix(Self.commentLimit)), at: min(w.at ?? now, now), ref: conv, fc: face)
            c.h = w.hh
            c.pv = w.pv
            mutate(w.id) { p in
                guard !p.comments.contains(where: { $0.id == c.id }) else { return }
                if c.h == nil {
                    c.pv = p.comments.last?.h ?? Self.zeroHash
                    c.h = Self.seal(c)
                }
                p.comments.append(c)
            }
            if face == nil { lendFaces([conv]) }   // a build that sent no face: the face they published here
            // THE COMMENTER SEES EVERY COMMENT (the author's word 25.09: «comments must come from everyone who commented»):
            // a comment is an act of its writer's, as an ask is, and is answered as an ask is — with the page as it stands.
            if let t = answeredAt[conv], Date().timeIntervalSince(t) < 30 { return }
            answeredAt[conv] = Date()
            sendPage(to: conv, version: Self.spokenVersion(for: conv))
        case "cpay": break
        case "del":
            // ONLY THE WALL'S OWNER TAKES A POST OFF THEIR WALL (the author's word 24.09: «only the owner deletes a post
            // on their own page»): a writer's «del» — the builds before the rule still send it — takes nothing down; it
            // says only that the writer's phone no longer keeps the post's files.
            guard let id = w.id, let i = mine.firstIndex(where: { $0.id == id }), mine[i].keepers.contains(conv) else { return }
            mine[i].keepers.removeAll { $0 == conv }
            saveMine()
        case "gone":
            guard let id = w.id else { return }
            reseed(id)
        case "seed":
            guard let id = w.id, let k = kept[id] else { return }
            Task { await Self.seedFiles(id, k.post.media) }
        case "hi":
            break   // its whole word is learnCap above: this build reads the wall, and the owner may carry it
        default:
            break   // a shape from a newer build: buried in silence
        }
    }
    /// WHAT I WROTE STAYS UNTIL THE OWNER'S PAGE SAYS IT (the author's word 25.09: «from T1 I see another's comment and not
    /// mine»): a page the owner built before my comment or my post reached them — or a build that answers a comment with
    /// nothing — took my own words off my own screen. My comments and my posts not yet on the owner's page stay as I sent them
    /// for half an hour: the owner's next page carries them, and a «no» or a «drop» takes a post down as ever.
    /// MY OWN WALL NEVER STANDS AS ANOTHER'S (07.10, the author's word «on T1 the second account duplicates the posts»): a page
    /// that holds nothing but the posts of my own wall is my wall come back to me -- an echo through a pipe whose both ends are
    /// this phone (MTShelfPost.wakePairs) -- never the wall of the person it came from; it is refused at its arrival and let go
    /// at the load, so a feed that took one shows every post once again.
    static func isEcho(_ posts: [MTBoardSeen], of mine: [MTBoardPost]) -> Bool {
        !posts.isEmpty && Set(posts.map(\.id)).isSubset(of: Set(mine.map(\.id)))
    }
    static func keepMine(_ old: MTBoardPage, into new: MTBoardPage, now: Double) -> MTBoardPage {
        var out = new
        let since = now - 1800
        for o in old.posts {
            if let i = out.posts.firstIndex(where: { $0.id == o.id }) {
                let have = Set(out.posts[i].comments.map { $0.id })
                let mine = o.comments.filter { $0.m == true && !have.contains($0.id) && since < $0.at }
                if !mine.isEmpty {
                    out.posts[i].comments = (out.posts[i].comments + mine).sorted { $0.at < $1.at }   // in the order written
                    out.posts[i].commentCount += mine.count
                }
            } else if o.mine, since < o.at {
                out.posts.insert(o, at: out.posts.firstIndex(where: { !$0.pinned }) ?? out.posts.count)
            }
        }
        return out
    }
    /// WHAT ARRIVES IS HELD TO ITS BOUNDS (the critic 24.09): a page or a post from another phone is cut to the sizes
    /// this phone draws — a hostile page cannot fill the store with posters, words or comments.
    static func clean(_ media: [MTBoardMedia]) -> [MTBoardMedia] {
        media.prefix(mediaLimit).enumerated().map { i, m in
            var x = m
            x.name = String(x.name.prefix(120))
            x.ext = String(String(x.ext.prefix(8)).filter { $0.isLetter || $0.isNumber })
            if 4 <= i || thumbLimit < (x.thumb?.count ?? 0) { x.thumb = nil }
            x.fr = x.kind == "img" || x.kind == "vid" ? x.fr?.valid : nil
            return x
        }
    }
    /// A card that arrived too large keeps its words and loses the picture.
    static func fitCard(_ raw: String?) -> String? {
        guard let raw, raw.count > 2, let card = MTLinkPreview.parse(raw) else { return nil }
        if raw.utf8.count < 80001 { return raw }
        return card.withoutImage.json
    }

    /// A RECEIVED POST STANDS NO LATER THAN THE MOMENT THIS PHONE FIRST HELD IT (07.10, the finding of the Business's critic, the
    /// author's «collect everything»): the feed stands by time, and a post dated in the future stood on top of every feed for good;
    /// a cap drawn from the clock at every page (min(at, now + 300)) gives it «five minutes from now» again at every ask. The cap is
    /// anchored to the first sight of the post's id, kept on this phone: five minutes past it at most, for the clocks' difference;
    /// an earlier own moment stands.
    private func held(_ posts: [MTBoardSeen], now: Double) -> [MTBoardSeen] {
        var grew = false
        let out = posts.map { p -> MTBoardSeen in
            var x = p
            let first: Double
            if let f = firstSeen[p.id] { first = f } else { first = now; firstSeen[p.id] = now; grew = true }
            x.at = min(x.at, first + 300)
            return x
        }
        if grew { scheduleSave(Self.firstKey) }
        return out
    }
    static func clean(_ s: MTBoardSeen) -> MTBoardSeen {
        var x = s
        x.byName = String(x.byName.prefix(64))
        x.byGlyph = String(x.byGlyph.prefix(8))
        x.text = String(x.text.prefix(textLimit))
        x.lp = Self.fitCard(x.lp)
        x.media = clean(x.media)
        x.from = x.from.map { String($0.prefix(64)) }
        if faceLimit < (x.face?.count ?? 0) { x.face = nil }
        x.views = x.views.map { max(0, $0) }
        x.comments = x.comments.suffix(commentsShown).map { c in
            var y = c
            y.by = String(y.by.prefix(64)); y.glyph = String(y.glyph.prefix(8)); y.text = String(y.text.prefix(commentLimit)); y.ref = nil
            if faceLimit < (y.fc?.count ?? 0) { y.fc = nil }
            return y
        }
        return x
    }
    private static func toggle(_ set: inout [String], _ who: String, _ on: Bool) {
        if on { if !set.contains(who) { set.append(who) } } else { set.removeAll { $0 == who } }
    }
    /// A post of a channel I own changed: kept, and its counts carried to every subscriber a moment later (tellChannel).
    private func mutateOwned(_ key: String, _ id: String?, _ change: (inout MTBoardPost) -> Void) {
        guard let id, var ps = owned[key], let i = ps.firstIndex(where: { $0.id == id }) else { return }
        change(&ps[i])
        owned[key] = ps
        saveOwned()
        tellChannel(key, id)
    }
    /// THE COUNTS OF A CHANNEL'S POSTS GO OUT ONCE A MOMENT: the marks of two seconds ride one word a post, without the files.
    private var channelDue: [String: Set<String>] = [:]
    private func tellChannel(_ key: String, _ id: String) {
        let first = channelDue[key] == nil
        channelDue[key, default: []].insert(id)
        guard first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let ids = self.channelDue.removeValue(forKey: key) else { return }
            for id in ids {
                guard let p = self.owned[key]?.first(where: { $0.id == id }) else { continue }
                var light = self.seen(p, by: Self.subscriber, conceal: true)
                light.media = []
                MainActor.assumeIsolated { _ = MTGroup.shared.carryWallWord(MTBoardWord(t: "ccount", ps: [light]), in: key) }   // COMPAT-GATED
            }
        }
    }
    /// A CHANNEL'S POSTS FOR A SUBSCRIBER JUST ADDED (MTGroup.add): the newest, as every subscriber was carried them.
    func channelPosts(_ key: String, newest n: Int) -> [MTBoardSeen] {
        guard let ps = owned[key] else { return [] }
        return ordered(ps).prefix(n).map { seen($0, by: Self.subscriber, conceal: true) }
    }
    /// A SUBSCRIBER'S MARK ON A CHANNEL I OWN (MTGroup.wallWord): a like, the posts seen, a comment -- each person once, by the
    /// seat the channel knows them by; the counts go out to everyone after it.
    func applyChannel(_ w: MTBoardWord, from ref: String, in key: String) {
        guard owned[key] != nil else { return }
        let now = Date().timeIntervalSince1970
        switch w.t {
        case "like": mutateOwned(key, w.id) { p in Self.toggle(&p.likes, ref, w.on ?? true) }
        case "view":
            for id in (w.vs ?? []).prefix(Self.pageSize) {
                mutateOwned(key, id) { p in if !(p.views ?? []).contains(ref) { p.views = (p.views ?? []) + [ref] } }
            }
        case "cmt":
            let text = (w.tx ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let name = String((w.bn ?? "").prefix(64))
            let face = (w.fc ?? "").isEmpty || Self.faceLimit < (w.fc ?? "").count ? nil : w.fc
            var c = MTBoardComment(id: w.cid ?? UUID().uuidString, by: name,
                                   glyph: (w.bg ?? "").isEmpty ? MontanaAvatar.initial(title: name, name: "") : String((w.bg ?? "").prefix(8)),
                                   text: String(text.prefix(Self.commentLimit)), at: min(w.at ?? now, now), ref: ref, fc: face)
            c.h = w.hh
            c.pv = w.pv
            mutateOwned(key, w.id) { p in
                guard !p.comments.contains(where: { $0.id == c.id }) else { return }
                if c.h == nil {
                    c.pv = p.comments.last?.h ?? Self.zeroHash
                    c.h = Self.seal(c)
                }
                p.comments.append(c)
                if Self.commentsKept < p.comments.count { p.comments.removeFirst(p.comments.count - Self.commentsKept) }
            }
        default: break
        }
    }
    private func mutate(_ id: String?, own: Bool = false, _ change: (inout MTBoardPost) -> Void) {
        guard let id, let i = mine.firstIndex(where: { $0.id == id }) else { return }
        change(&mine[i])
        saveMine(own: own)
    }
    private func patchPage(_ wall: String, _ change: (inout MTBoardPage) -> Void) {
        guard var pg = pages[wall] else { return }
        change(&pg)
        pages[wall] = pg
        savePages()
    }
    private func patchPost(_ wall: String, _ id: String, _ change: (inout MTBoardSeen) -> Void) {
        patchPage(wall) { pg in
            guard let i = pg.posts.firstIndex(where: { $0.id == id }) else { return }
            change(&pg.posts[i])
        }
    }

    // -- a visitor's hand -------------------------------------------------------------------------

    /// MY OWN ACT ASKS FOR THE PAGE (the author's word 25.09: «from T3 I must see her wall»): a post or a comment I just wrote
    /// on another's wall is a moment its owner learns anyway, so an ask right behind it tells them nothing more — and an owner
    /// who hides their presence and carries nothing, or a build that answers a comment with nothing, still gives me the wall
    /// as it stands, my words on it.
    private func askAfterAct(_ wall: String) {
        guard MontanaConv.holds(wall) else { return }
        askedAt[wall] = Date()
        asking.insert(wall)
        send(MTBoardWord(t: "ask"), to: wall)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.asking.remove(wall) }
    }
    /// The page of a correspondent's wall, asked of its owner; answered when their phone is reachable.
    func ask(_ wall: String) {
        // AN ASK SAYS NOTHING A LETTER WOULD NOT (the author's word 25.09: «with “Everyone” the wall must show at the very entry
        // of the page — to everyone, at once»): the wall's word is a machine word (ChatStore.machineWord) and stamps no presence
        // on the owner's phone, so one who hides their presence asks like anyone else. The critic's N2 of 24.09 (an ask says
        // «I am here») kept a door the machine word had already closed at the root.
        guard MontanaConv.holds(wall) else { return }
        if let t = askedAt[wall], Date().timeIntervalSince(t) < 60 { return }
        askedAt[wall] = Date()
        asking.insert(wall)
        send(MTBoardWord(t: "ask"), to: wall)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.asking.remove(wall) }
    }
    func like(_ p: MTBoardSeen, on wall: String?) {
        let on = !p.liked
        guard let wall else { mutate(p.id, own: true) { q in Self.toggle(&q.likes, "", on) }; return }
        if owned[wall] != nil { mutateOwned(wall, p.id) { q in Self.toggle(&q.likes, "", on) }; return }   // a channel of mine
        send(MTBoardWord(t: "like", id: p.id, on: on), to: wall)
        patchPost(wall, p.id) { s in s.liked = on; s.likes = max(0, s.likes + (on ? 1 : -1)) }
    }

    /// THE POSTS I SAW ARE NAMED TO THEIR WALL, EACH ONCE (the author's words 06.10.2026 00:4x MSK: «under the posts, bottom right,
    /// an eye and how many views»): a post drawn on the screen -- in the feed, on a person's page, on its own page -- joins its
    /// wall's list of the moment, and two seconds later the list leaves as one word. A wall whose owner's build counts no views (its
    /// page carries none) is told nothing. The word leaves when the wall is looked at, as the ask does, and says nothing an ask
    /// would not. The number shown is the owner's alone, as their page carries it: nothing is added here before they say it.
    static let viewedKey = "board.viewed"
    private static let viewedKept = 4000
    private lazy var viewed: [String] = UserDefaults.standard.stringArray(forKey: Self.viewedKey) ?? []
    private var seenDue: [String: [String]] = [:]
    func view(_ p: MTBoardSeen, on wall: String?) {
        guard let wall, !p.mine, p.views != nil, !viewed.contains(wall + "#" + p.id),
              !(seenDue[wall] ?? []).contains(p.id) else { return }
        let first = seenDue[wall] == nil
        seenDue[wall, default: []].append(p.id)
        guard first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.tellSeen(wall) }
    }
    private func tellSeen(_ wall: String) {
        guard let ids = seenDue.removeValue(forKey: wall), !ids.isEmpty,
              send(MTBoardWord(t: "view", vs: ids), to: wall) else { return }
        viewed += ids.map { wall + "#" + $0 }
        if Self.viewedKept < viewed.count { viewed.removeFirst(viewed.count - Self.viewedKept) }
        UserDefaults.standard.set(viewed, forKey: Self.viewedKey)
    }


    static let zeroHash = "0000000000000000000000000000000000000000000000000000000000000000"
    static func seal(_ c: MTBoardComment) -> String {
        let prev = c.pv ?? zeroHash
        return digest(c.id + "\n" + stamp(c.at) + "\n" + prev + "\n" + c.text)
    }
    static func digest(_ body: String) -> String {
        SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func stamp(_ at: Double) -> String {
        var sec = Int(at)
        var ms = Int((at - Double(sec)) * 1000 + 0.5)
        if ms == 1000 { ms = 0; sec += 1 }
        if ms < 0 { ms = 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: Double(sec)))
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, ms)
    }
    /// A MOMENT ON THIS PHONE'S CLOCK, IN ITS OWN ZONE (the author's word 02.10); the seal itself stays in UTC (stamp).
    static func local(_ at: Double) -> String {
        var sec = Int(at) + TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: at))
        var ms = Int((at - Double(Int(at))) * 1000 + 0.5)
        if ms == 1000 { ms = 0; sec += 1 }
        if ms < 0 { ms = 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: Double(sec)))
        return String(format: "%02d.%02d.%04d %02d:%02d:%02d.%03d", c.day ?? 0, c.month ?? 0, c.year ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, ms)
    }
    static func gematria(_ hex: String) -> Int {
        let primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109]
        var chars = Array(hex.lowercased())
        if chars.isEmpty { return primes[0] }
        var total = 0
        while true {
            var rem = 0
            var next: [Character] = []
            var started = false
            for ch in chars {
                guard let v = Int(String(ch), radix: 16) else { return total }
                let cur = rem * 16 + v
                let q = cur / 29
                rem = cur % 29
                if q != 0 || started {
                    next.append(contentsOf: String(q, radix: 16))
                    started = true
                }
            }
            total += primes[rem]
            if next.isEmpty { break }
            chars = next
        }
        return total
    }
    static func sealLine(_ c: MTBoardComment) -> String {
        let hash = String((c.h ?? "").prefix(16))
        let prev = String((c.pv ?? "").prefix(16))
        return local(c.at) + " · " + hash + " · " + prev + " · gematria " + String(gematria(c.h ?? ""))
    }
    /// A COMMENT'S NUMBER IN ITS CHAIN, ITS MOMENT, THEN ITS GEMATRIA (the author's words 02.10: «313 · 02.10.2026 13:05:07.624»,
    /// and the gematria after the time as the TimeChain's confirmation): the prime sum of the comment's own seal.
    static func numberLine(_ n: Int, _ c: MTBoardComment) -> String {
        let line = String(n) + " · " + local(c.at)
        guard let h = c.h, !h.isEmpty else { return line }
        return line + " · gematria " + String(gematria(h))
    }
    /// THE WALL, NEWEST FIRST (the author's word 02.10): a post stands at the moment of the newest record of its chain -- its
    /// own birth or its latest comment.
    static func lastAt(_ p: MTBoardPost) -> Double { max(p.at, p.comments.map { $0.at }.max() ?? 0) }
    static func lastAt(_ p: MTBoardSeen) -> Double { max(p.at, p.comments.map { $0.at }.max() ?? 0) }
    /// THE POST'S NUMBER ON ITS WALL (the author's word 02.10: «montana://wall/@nick/12»): given once, the next after the
    /// highest the wall holds, in the order the posts were born.
    private static func numberMissing(_ mine: inout [MTBoardPost]) -> Bool {
        var top = mine.compactMap { $0.n }.max() ?? 0
        var changed = false
        let order = mine.indices.sorted { mine[$0].at < mine[$1].at }
        for i in order where mine[i].n == nil {
            top += 1
            mine[i].n = top
            changed = true
        }
        return changed
    }
    private static func sealMissing(_ mine: inout [MTBoardPost]) -> Bool {
        var changed = false
        for i in mine.indices {
            var prev = zeroHash
            for j in mine[i].comments.indices {
                if mine[i].comments[j].h == nil {
                    mine[i].comments[j].pv = prev
                    mine[i].comments[j].h = seal(mine[i].comments[j])
                    changed = true
                }
                prev = mine[i].comments[j].h ?? prev
            }
        }
        return changed
    }
    private func lastSeal(_ id: String, on wall: String?) -> String {
        let list: [MTBoardComment]
        if let wall {
            list = pages[wall]?.posts.first(where: { $0.id == id })?.comments ?? []
        } else {
            list = mine.first(where: { $0.id == id })?.comments ?? []
        }
        return list.last?.h ?? Self.zeroHash
    }


typealias MTChainBody = [String: Any]
typealias MTWallWindowList = [MTWallWindow]
typealias MTChainRows = [MTChainBody]

struct MTWallWindow: Identifiable {
    let id: String
    let title: String
    let share: Int
    let open: Bool
    let span: String
    let to: Double
    let marks: [String]
}

    /// THE ONE TIMECHAIN FOLDER (Files, On My iPhone, Montana, TimeChain -- 04.10): the comment chains stand there.
    static func chainDir() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let root = docs.appendingPathComponent(MontanaPaths.root).appendingPathComponent("TimeChain", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return root
    }
    static func chainFile(_ post: MTBoardSeen) -> URL? {
        let safe = String(post.id.filter { $0.isLetter || $0.isNumber }.prefix(64))
        // THE COMMENTER KEEPS THE CHAIN, OPEN, BESIDE THE DIARY (the author's word 02.10 15:09): Files, On My iPhone, Montana, TimeChain
        // -- the one TimeChain folder (chainDir, 04.10).
        guard !safe.isEmpty, let dir = chainDir() else { return nil }
        let url = dir.appendingPathComponent(safe + ".md")
        let records = chainRecords(post)
        var lines: [String] = ["# Comment chain", "", "```json"]
        for rec in records {
            guard let data = try? JSONSerialization.data(withJSONObject: rec, options: [.sortedKeys, .withoutEscapingSlashes]),
                  let line = String(data: data, encoding: .utf8) else { return nil }
            lines.append(line)
        }
        lines.append("```")
        lines.append("")
        lines.append(linkPost(post.id))
        for c in post.comments { lines.append(linkComment(post.id, c.id)) }
        do { try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return url
    }

    private var mintTick: Timer?
    private func watchMint() {
        guard mintTick == nil else { return }
        mintTick = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
    static let windowSilence: Double = 60
    static func chainBody(n: Int, time: String, master: String, prev: String, thread: [String], text: String) -> MTChainBody {
        ["n": n, "time": time, "master": master, "kind": "word", "prev": prev, "thread": thread, "text": text]
    }
    static func chainDigest(_ body: MTChainBody) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]),
              let line = String(data: data, encoding: .utf8) else { return zeroHash }
        return digest(line)
    }
    static func chainRecords(_ post: MTBoardSeen) -> MTChainRows {
        var out = MTChainRows()
        var prev = zeroHash
        let head = chainBody(n: 0, time: stamp(post.at), master: post.byName, prev: prev, thread: [], text: post.text)
        let headHash = chainDigest(head)
        var first = head
        first["hash"] = headHash
        out.append(first)
        prev = headHash
        let cs = post.comments.sorted { $0.at < $1.at }
        for pair in cs.enumerated() {
            let words = pair.element.hid == true ? "" : pair.element.text
            let body = chainBody(n: pair.offset + 1, time: stamp(pair.element.at), master: pair.element.by, prev: prev, thread: [headHash], text: words)
            let hash = chainDigest(body)
            var row = body
            row["hash"] = hash
            out.append(row)
            prev = hash
        }
        return out
    }
    func wallWindows() -> MTWallWindowList {
        var seen = Set<String>()
        var rows = MTWallWindowList()
        func take(_ post: MTBoardSeen) {
            guard seen.insert(post.id).inserted, let row = Self.window(of: post) else { return }
            rows.append(row)
        }
        for post in posts(on: nil) { take(post) }
        for wall in pages.keys {
            for post in posts(on: wall) { take(post) }
        }
        return rows
    }
    func place(of id: String) -> String? {
        if mine.contains(where: { $0.id == id }) { return "" }
        for pair in pages where pair.value.posts.contains(where: { $0.id == id }) { return pair.key }
        return nil
    }
    static func window(of post: MTBoardSeen) -> MTWallWindow? {
        let cs = post.comments.sorted { $0.at < $1.at }
        guard let first = cs.first, let last = cs.last else { return nil }
        var broken = false
        for i in cs.indices.dropFirst() {
            let gap = cs[i].at - cs[i - 1].at
            if !(gap < windowSilence) { broken = true }
        }
        let now = Date().timeIntervalSince1970
        let live = now - last.at < windowSilence && !broken
        let end = live ? now : last.at
        let length = max(0, end - first.at)
        let minutes = broken ? 0 : max(1, Int(length / windowSilence))
        let marks = cs.map { local($0.at) }
        let title = post.text.isEmpty ? post.id : String(post.text.prefix(80))
        return MTWallWindow(id: post.id, title: title, share: minutes, open: live, span: local(first.at) + " | " + local(last.at), to: last.at, marks: marks)
    }
    static func linkPost(_ id: String) -> String { "montana://wall/post/" + id }
    static func linkComment(_ post: String, _ comment: String) -> String {
        "montana://wall/comment/" + post + "/" + comment
    }
    /// THE SHORT LINK (the author's word 02.10): the wall's owner by the nick after «@» in their name field, as T1 shows it,
    /// and the post's number on that wall; a post with no number yet, or a wall with no nick, keeps the long link.
    static func linkPost(_ p: MTBoardSeen, on wall: String?) -> String {
        guard let n = p.n, let claimed = claimedName(of: wall),
              let path = ("@" + claimed).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return linkPost(p.id) }
        return "montana://wall/" + path + "/" + String(n)
    }
    static func linkComment(_ p: MTBoardSeen, _ number: Int, _ c: MTBoardComment, on wall: String?) -> String {
        let post = linkPost(p, on: wall)
        return post.hasPrefix("montana://wall/@") ? post + "/" + String(number) : linkComment(p.id, c.id)
    }
    static func claimedName(of wall: String?) -> String? {
        let said = wall.map { MTNameBook.declared[$0] ?? "" } ?? E2E.myDisplayName()
        return claimedName(in: said) ?? wall.flatMap { MTNameBook.name($0) }.flatMap { $0.isEmpty ? nil : $0 }
    }
    static func claimedName(in name: String) -> String? {
        guard let r = name.range(of: "@", options: .backwards) else { return nil }
        let tail = name[r.upperBound...].prefix { !$0.isWhitespace }
        return tail.isEmpty ? nil : String(tail)
    }
    /// The post a short link names, among the walls this phone holds, and the comment of that number in its chain.
    func find(name: String, number n: Int, comment k: Int?) -> (post: String, comment: String?)? {
        let walls: [String?] = [nil] + pages.keys.sorted().map { Optional($0) }
        for w in walls where Self.claimedName(of: w)?.caseInsensitiveCompare(name) == .orderedSame {
            guard let p = posts(on: w).first(where: { $0.n == n }) else { continue }
            var cid: String? = nil
            if let k {
                let i = k - (p.commentCount - p.comments.count) - 1
                if p.comments.indices.contains(i) { cid = p.comments[i].id }
            }
            return (p.id, cid)
        }
        return nil
    }
    /// A LINK IN A COMMENT ANSWERS THE FINGER (the author's word 02.10): every link of the one finder (MTLinks) -- the web's
    /// and every montana:// link -- in the system's blue.
    static func linked(_ text: String) -> AttributedString { MTLinks.linked(text, color: Color(uiColor: .systemBlue)) }

    func hideComment(post postId: String, _ cid: String) {
        mutate(postId, own: true) { p in
            guard let i = p.comments.firstIndex(where: { $0.id == cid }) else { return }
            p.comments[i].hid = p.comments[i].hid == true ? nil : true
        }
    }

    func comment(_ p: MTBoardSeen, on wall: String?, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var c = MTBoardComment(id: UUID().uuidString, by: E2E.myDisplayName(), glyph: E2E.myFaceGlyph(),
                               text: String(t.prefix(Self.commentLimit)), at: Date().timeIntervalSince1970,
                               fc: Self.commentFace())
        c.pv = lastSeal(p.id, on: wall)
        c.h = Self.seal(c)
        var kept = p
        kept.comments.append(c)
        kept.commentCount += 1
        _ = Self.chainFile(kept)
        guard let wall else {
            mutate(p.id, own: true) { q in var mc = c; mc.ref = ""; q.comments.append(mc) }
            return
        }
        if owned[wall] != nil {   // a channel of mine: my comment stands on my channel's post
            mutateOwned(wall, p.id) { q in var mc = c; mc.ref = ""; q.comments.append(mc) }
            return
        }
        send(MTBoardWord(t: "cmt", id: p.id, at: c.at, tx: c.text, bn: c.by, bg: c.glyph, cid: c.id, fc: c.fc, hh: c.h, pv: c.pv), to: wall)
        askAfterAct(wall)
        var said = c; said.m = true   // my own, as the owner's next page says it
        patchPost(wall, p.id) { s in s.comments.append(said); s.commentCount += 1 }
    }
    func pin(_ p: MTBoardSeen) { mutate(p.id, own: true) { q in q.pinned.toggle() } }
    /// THE WORDS OF MY OWN POST, CHANGED (the author's word 30.09): only on my own wall and only the words. A file keeps the name
    /// its place gave it at birth (fileName), and a repost keeps its writer's words. The wall's next page carries the new words to
    /// everyone who holds it: the edit moves the version, no new word rides the wire.
    @discardableResult
    func edit(_ id: String, words: String) -> Bool {
        let t = String(words.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.textLimit))
        guard let i = mine.firstIndex(where: { $0.id == id }), mine[i].author.isEmpty, mine[i].from == nil,
              t != mine[i].text, !t.isEmpty || !mine[i].media.isEmpty else { return false }
        mine[i].text = t
        mine[i].ed = Date().timeIntervalSince1970
        let next = MTLinkPreviewBuilder.firstWebURL(in: t)?.absoluteString
        let had = MTLinkPreview.parse(mine[i].lp)?.u
        if next != had { mine[i].lp = nil }
        saveMine(own: true)
        if let next, next != had {
            let pid = id
            Task { await self.attachCard(pid, url: next) }
        }
        MontanaTrace.mark("wall_edit", "id=\(String(id.prefix(10))) chars=\(t.count)")
        return true
    }
    /// OFF A WALL, BY ITS OWNER ALONE (the author's word 24.09: «only the owner deletes a post on their own page»): my
    /// own wall drops the post, and its writer is told they need not keep it for me; on another's wall no hand of mine
    /// takes a post down — my own post there included.
    /// The words changed the link: the card is read again and the wall's version moves with it.
    private func attachCard(_ id: String, url: String) async {
        guard let card = await MTLinkPreviewBuilder.wallCard(in: url)?.json else { return }
        await MainActor.run {
            guard let i = self.mine.firstIndex(where: { item in item.id == id }) else { return }
            guard MTLinkPreviewBuilder.firstWebURL(in: self.mine[i].text)?.absoluteString == url else { return }
            self.mine[i].lp = card
            self.mine[i].ed = Date().timeIntervalSince1970
            self.saveMine(own: true)
        }
    }

    func remove(_ p: MTBoardSeen, on wall: String?) {
        if let wall, owned[wall] != nil {   // a post of a channel of mine: off its page here and on every subscriber's
            owned[wall]?.removeAll { $0.id == p.id }
            saveOwned()
            MainActor.assumeIsolated { _ = MTGroup.shared.carryWallWord(MTBoardWord(t: "cdel", id: p.id), in: wall) }   // COMPAT-GATED
            return
        }
        guard wall == nil else { return }
        if let q = mine.first(where: { $0.id == p.id }), !q.author.isEmpty {
            send(MTBoardWord(t: "drop", id: p.id), to: q.author)   // the writer need not keep it for my wall
        }
        mine.removeAll { $0.id == p.id }
        saveMine(own: true)
    }
    /// SAVE: the files come to this phone and stay — from now on this phone is one of the post's peers.
    /// progress hears, file by file, the pieces this phone has brought: (the file's place, its pieces here). True when
    /// every file of the post is here.
    @discardableResult
    func keep(_ p: MTBoardSeen, on wall: String?, progress: (@Sendable (Int, Int) -> Void)? = nil) async -> Bool {
        for i in p.media.indices {
            var hook: (@Sendable (Int, Int) -> Void)? = nil
            if let progress { hook = { @Sendable n, _ in progress(i, n) } }
            guard await file(p, i, on: wall, progress: hook) != nil else { return false }
        }
        await MainActor.run { self.becomePeer(p, on: wall) }   // a post with no files, or its files already here
        return true
    }
    /// A FILE FETCHED MAKES THIS PHONE THE POST'S PEER (the author's word 24.09: «downloading someone's post on a wall
    /// makes this phone a peer of the post»): what it holds of the post stays — the sweep reads the kept files — and
    /// the wall's owner is told it keeps the post. The writer keeps theirs from the start.
    private func becomePeer(_ p: MTBoardSeen, on wall: String?) {
        let here = p.media.indices.map { Self.fileName(p.id, $0, p.media[$0].ext) }.filter { MontanaMediaStore.exists($0) }
        guard let wall else {
            if let q = mine.first(where: { $0.id == p.id }), !q.keepers.contains("") {
                mutate(p.id, own: true) { x in Self.toggle(&x.keepers, "", true) }
            }
            return
        }
        if var k = kept[p.id] {
            let all = Array(Set(k.files).union(here)).sorted()
            guard all != k.files.sorted() else { return }
            k.files = all
            kept[p.id] = k
            saveKept()
            return
        }
        var s = p; s.kept = true
        kept[p.id] = MTBoardKept(post: s, wall: wall, files: here)
        saveKept()
        guard !p.mine else { return }
        send(MTBoardWord(t: "keep", id: p.id, on: true), to: wall)
        patchPost(wall, p.id) { x in if !x.kept { x.kept = true; x.keepers += 1 } }
    }
    func unkeep(_ p: MTBoardSeen, on wall: String?) {
        guard let wall else { mutate(p.id, own: true) { q in Self.toggle(&q.keepers, "", false) }; return }
        guard !p.mine else { return }   // the writer keeps their post while it stands; only the wall's owner takes it down
        forgetKept(p.id)
        send(MTBoardWord(t: "keep", id: p.id, on: false), to: wall)
        patchPost(wall, p.id) { x in if x.kept { x.kept = false; x.keepers = max(0, x.keepers - 1) } }
    }
    /// REPOST: the post is kept here and stands on my own wall too, named by the wall it came from. ITS FILES COME UNDER
    /// THE BAR A POST GOES OUT UNDER (the author's word 25.09: «pressing repost shows the same progress bar as a post's
    /// publishing, to see the process»): the pieces this phone has brought, file by file, over the post on the wall it is
    /// taken from; files that did not all come say so, with a try-again. THE REPOST KNOWS WHERE IT CAME FROM (the author's
    /// words 25.09: «everything in a repost is clickable», «the one it came from, in the system's blue»): the wall and —
    /// when the post was that wall's owner's own — its writer, by reference on this phone, and the face this phone holds
    /// for them, so the repost wears it.
    func repost(_ p: MTBoardSeen, from wall: String) async {
        let pid = p.id
        let sizes = p.media.map { max(0, $0.size) }
        let started = await MainActor.run { () -> Bool in
            if let r = self.reposting[pid], !r.failed { return false }   // already on its way
            self.reposting[pid] = MTBoardOutgoing(id: pid, wall: wall, post: p, sizes: sizes,
                                                  confirmed: Array(repeating: 0, count: sizes.count))
            return true
        }
        guard started else { return }
        let whole = await keep(p, on: wall, progress: { i, n in DispatchQueue.main.async { MTBoard.shared.brought(pid, i, n) } })
        let own = p.own == true
        var face = p.face
        if face == nil, own { face = await Self.face(of: wall) }
        let worn = face
        await MainActor.run {
            guard whole else { self.reposting[pid]?.failed = true; return }
            self.reposting[pid] = nil
            guard !self.mine.contains(where: { $0.id == pid }) else { return }
            self.mine.append(MTBoardPost(id: pid, author: "", byName: p.byName, byGlyph: p.byGlyph,
                                         at: Date().timeIntervalSince1970, text: p.text, media: p.media, pinned: false,
                                         keepers: [""], likes: [], downloads: [], reposts: [], comments: [], from: Self.publicName(of: wall),
                                         face: worn, src: wall, srcBy: own ? wall : (p.mine ? "" : nil), lp: p.lp))   // "" — I wrote it
            self.saveMine(own: true)
            self.send(MTBoardWord(t: "rp", id: pid), to: wall)
            self.patchPost(wall, pid) { x in if !x.reposted { x.reposted = true; x.reposts += 1 } }
        }
        MontanaTrace.mark("wall_repost", "id=\(String(pid.prefix(10))) files=\(p.media.count) whole=\(whole ? 1 : 0)")
    }
    private func forgetKept(_ id: String) {
        guard kept.removeValue(forKey: id) != nil else { return }
        saveKept()
        // The files stay while my own wall still shows the post (a repost); else the sweep takes them.
    }

    // -- the files ----------------------------------------------------------------------------------

    /// The file of a post on this phone: fetched from the node's store by its chunks, kept under its wall name.
    /// WHAT A PLAYER READS BEFORE THE FILE IS WHOLE (25.09): a post's file as the loader needs it — its pieces and their key —
    /// laid, when whole, where a look's copy stands (MTBoardLook), so a tile and a touch find it as they always did.
    static func streamSource(_ p: MTBoardSeen, _ i: Int) -> MTStreamSource? {
        guard i < p.media.count else { return nil }
        let m = p.media[i]
        guard !m.chunks.isEmpty, 0 < m.size, let key = Data(base64Encoded: m.key) else { return nil }
        return MTStreamSource(name: Self.fileName(p.id, i, m.ext), ext: m.ext, size: m.size, key: key, chunks: m.chunks,
                              folder: MTBoardLook.folder())
    }
    func file(_ p: MTBoardSeen, _ i: Int, on wall: String?, progress: (@Sendable (Int, Int) -> Void)? = nil) async -> String? {
        guard i < p.media.count else { return nil }
        let m = p.media[i]
        let name = Self.fileName(p.id, i, m.ext)
        if MontanaMediaStore.exists(name) { progress?(m.chunks.count, m.chunks.count); return name }
        // WHAT WAS SEEN IS NOT BROUGHT AGAIN (the author's word 25.09: «why does it bring every time what I have already seen —
        // cache everything properly»): the copy the look brought (MTBoardLook) is taken into the store — the same bytes, opened
        // at once — and the touch makes this phone the post's peer as its own road does.
        if let seenCopy = MTBoardLook.here(p.id, i, m.ext) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wl_" + UUID().uuidString)
            if (try? FileManager.default.copyItem(at: seenCopy, to: tmp)) != nil, MontanaMediaStore.adopt(from: tmp, name: name) {
                progress?(m.chunks.count, m.chunks.count)
                await MainActor.run {
                    self.becomePeer(p, on: wall)
                    self.noteDownloaded(p, on: wall)
                }
                return name
            }
        }
        await MainActor.run { _ = self.fetching.insert(p.id) }
        defer { Task { @MainActor in self.fetching.remove(p.id) } }
        let chunks: [[String: Any]] = m.chunks.map { ["bid": $0.bid, "cs": $0.cs] }
        let outcome = await MontanaWakePush.fetchChunks(chunks, progress: progress)
        if case .lost = outcome {
            await MainActor.run { self.reportGone(p.id, on: wall) }
            return nil
        }
        guard let key = Data(base64Encoded: m.key) else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wl_" + UUID().uuidString)
        guard await MontanaMedia.downloadToFile(manifest: chunks, blobKey: key, totalSize: m.size, dest: tmp),
              MontanaMediaStore.adopt(from: tmp, name: name) else { return nil }
        await MainActor.run {
            self.becomePeer(p, on: wall)
            self.noteDownloaded(p, on: wall)
        }
        return name
    }
    /// A DOWNLOAD IS COUNTED ONCE PER PERSON, when every file of the post has come to this phone (the author's word
    /// 24.09: «the downloads' count must be right and must move»): on the owner's wall, and on this page at once — the
    /// owner's next page says the same number, for the owner counts each person once.
    private func noteDownloaded(_ p: MTBoardSeen, on wall: String?) {
        guard !p.media.isEmpty else { return }
        let all = p.media.indices.allSatisfy { MontanaMediaStore.exists(Self.fileName(p.id, $0, p.media[$0].ext)) }
        guard all, !countedDownload.contains(p.id) else { return }
        countedDownload.insert(p.id)
        guard let wall else { mutate(p.id, own: true) { q in Self.toggle(&q.downloads, "", true) }; return }
        guard kept[p.id]?.dl != true else { return }   // counted in a launch before this one
        kept[p.id]?.dl = true
        saveKept()
        send(MTBoardWord(t: "dl", id: p.id), to: wall)
        patchPost(wall, p.id) { x in x.downloads += 1 }
    }
    private func reportGone(_ id: String, on wall: String?) {
        guard !goneSaid.contains(id) else { return }
        goneSaid.insert(id)
        MontanaTrace.mark("wall_gone", "id=\(String(id.prefix(10))) wall=\(wall == nil ? "mine" : "theirs")")
        guard let wall else { reseed(id); return }
        send(MTBoardWord(t: "gone", id: id), to: wall)
    }
    /// The files of a post on my wall are gone from the node: I lay them again if I keep them, and I ask its keepers.
    private func reseed(_ id: String) {
        guard let p = mine.first(where: { $0.id == id }) else { return }
        if p.keepers.contains("") || p.author.isEmpty {
            Task { await Self.seedFiles(id, p.media) }
        }
        for k in p.keepers where !k.isEmpty { send(MTBoardWord(t: "seed", id: id), to: k) }
    }
    /// A keeper lays the files on the node again under the SAME key: the same bytes sealed by the same key in the same
    /// pieces give the same chunk names, so the manifest every page already carries finds them again.
    static func seedFiles(_ id: String, _ media: [MTBoardMedia]) async {
        var n = 0
        for (i, m) in media.enumerated() {
            let name = fileName(id, i, m.ext)
            guard MontanaMediaStore.exists(name), let key = Data(base64Encoded: m.key) else { continue }
            if await seal(file: MontanaMediaStore.url(name), kind: m.kind, name: m.name, ext: m.ext, key: key) != nil { n += 1 }
        }
        MontanaTrace.mark("wall_seed", "id=\(String(id.prefix(10))) files=\(n)/\(media.count)")
    }

    // -- a writer's hand ------------------------------------------------------------------------

    struct Attachment { let url: URL; let kind: String; let name: String; let ext: String; var frame: MTBoardFrame? = nil }

    /// A NEW POST, AT ONCE AS IT WILL STAND (the author's word 24.09): the files are taken into this phone's store under
    /// the post's own names — this phone is the post's first peer — and the post stands on its way (outgoing) with the
    /// writer's face, the words and the files' posters; publish lays the files and sends the words. nil: nothing to
    /// post, or a file could not be taken.
    func begin(on wall: String?, text: String, attachments: [Attachment], card: String? = nil) async -> String? {
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.textLimit))
        guard !t.isEmpty || !attachments.isEmpty else { return nil }
        let lp: String?
        if let card {
            lp = card
        } else {
            lp = await MTLinkPreviewBuilder.wallCard(in: t)?.json
        }
        let pid = "p" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24))
        var shown: [MTBoardMedia] = []
        var sizes: [Int] = []
        for (i, a) in attachments.prefix(Self.mediaLimit).enumerated() {
            let name = Self.fileName(pid, i, a.ext)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wl_" + UUID().uuidString)
            guard (try? FileManager.default.copyItem(at: a.url, to: tmp)) != nil,
                  MontanaMediaStore.adopt(from: tmp, name: name) else {
                MontanaTrace.mark("wall_write", "FAIL file=\(i) kind=\(a.kind) taking")
                return nil
            }
            let url = MontanaMediaStore.url(name)
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
            // A picture always stands in a frame: the one its writer set, or its own shape whole.
            var frame: MTBoardFrame? = nil
            if a.kind == "img" || a.kind == "vid" {
                frame = a.frame
                if frame == nil {
                    let kind = a.kind
                    let seen = await Task.detached(priority: .utility) { MTBoardImage.upright(url, kind: kind, longest: 256)?.size }.value
                    frame = seen.map { MTBoardFrame.own($0) }
                }
            }
            let thumb = await Self.poster(url, kind: a.kind, frame: frame)
            let dur: Double? = (a.kind == "vid" || a.kind == "aud") ? MontanaAudioDuration.of(url) : nil
            shown.append(MTBoardMedia(kind: a.kind, name: a.name, ext: a.ext, size: size, key: "", chunks: [], thumb: thumb, dur: dur,
                                      fr: frame))
            sizes.append(size)
        }
        let media = shown, lengths = sizes
        await MainActor.run {
            let post = Self.fresh(pid, on: wall, text: t, media: media, at: Date().timeIntervalSince1970, card: lp)
            self.outgoing[pid] = MTBoardOutgoing(id: pid, wall: wall, post: post, sizes: lengths,
                                                 confirmed: Array(repeating: 0, count: lengths.count))
            self.saveGoing()   // a post on its way outlives the run (25.09)
        }
        return pid
    }
    /// A NEW POST AS IT WILL STAND (the author's word 24.09: «the preview of the post one to one, as in the publication»):
    /// the one shape the page that writes it draws, and the one its wall shows while its files go to the node.
    static func fresh(_ pid: String, on wall: String?, text: String, media: [MTBoardMedia], at: Double, card: String? = nil) -> MTBoardSeen {
        MTBoardSeen(id: pid, byName: E2E.myDisplayName(), byGlyph: E2E.myFaceGlyph(), at: at, text: text, media: media,
                    pinned: false, keepers: 1, likes: 0, downloads: 0, reposts: 0, comments: [], commentCount: 0,
                    liked: false, kept: true, reposted: false, mine: true, from: nil,
                    face: wall == nil ? nil : myFace(), own: wall == nil, lp: card)
    }

    /// THE FILES ON THE NODE, THEN THE WORDS: each file is sealed and laid on the node's blind store, its pieces counted
    /// as the node confirms them — the post's bar reads that count — and when every file lies there the words go to the
    /// wall's owner. A file the node did not take leaves the post on its way, said so, to be tried again: the same
    /// letter names give the same pieces, and the node is asked what it holds already.
    func publish(_ pid: String) async -> Bool {
        // ONE LAY A POST AT A TIME (25.09): the page's check, the try-again, the return of the app and a door's revival may each
        // ask for it; a second asker finds the first at work and leaves the post to it.
        let taken = await MainActor.run { () -> Bool in
            guard self.outgoing[pid] != nil, !self.publishing.contains(pid) else { return false }
            self.publishing.insert(pid)
            self.outgoing[pid]?.failed = false
            return true
        }
        guard taken else { return false }
        let ok = await lay(pid)
        await MainActor.run { _ = self.publishing.remove(pid) }
        return ok
    }
    private func lay(_ pid: String) async -> Bool {
        guard let o = await MainActor.run(body: { () -> MTBoardOutgoing? in self.outgoing[pid] }) else { return false }
        var media: [MTBoardMedia] = []
        for (i, m) in o.post.media.enumerated() {
            let name = Self.fileName(pid, i, m.ext)
            let sealed = await Self.seal(file: MontanaMediaStore.url(name), kind: m.kind, name: m.name, ext: m.ext,
                                         letter: "wall-" + pid + "-" + String(i), thumb: m.thumb, dur: m.dur, frame: m.fr,
                                         progress: { n, _ in DispatchQueue.main.async { MTBoard.shared.confirmed(pid, i, n) } })
            guard let sealed else {
                MontanaTrace.mark("wall_write", "FAIL file=\(i) kind=\(m.kind)")
                await MainActor.run { self.outgoing[pid]?.failed = true; self.saveGoing() }
                return false
            }
            await MainActor.run { self.confirmed(pid, i, sealed.chunks.count) }   // the file is whole on the node: the bar says so
            media.append(sealed)
        }
        await MainActor.run { [media] in
            guard let o = self.outgoing.removeValue(forKey: pid) else { return }
            self.saveGoing()
            let p = o.post
            guard let wall = o.wall else {
                self.mine.append(MTBoardPost(id: pid, author: "", byName: p.byName, byGlyph: p.byGlyph, at: p.at, text: p.text,
                                             media: media, pinned: false, keepers: [""], likes: [], downloads: [], reposts: [],
                                             comments: [], from: nil, lp: p.lp))
                self.saveMine(own: true)
                return
            }
            var s = p; s.media = media
            // A CHANNEL IS A WALL (the author's words 06.10.2026 14:2x-14:4x MSK: «in channels posts as on the Wall of Thoughts; everything the wall publishes is published in a channel»): the owner's post stands on the
            // channel's page here, signed by the channel, and leaves to every subscriber by the group's carrier; there is no wall owner
            // to send it to and no pair's chat for its row.
            if MTGroup.isKey(wall) {
                let title = MTGroup.shared.state(wall)?.title ?? s.byName
                let post = MTBoardPost(id: pid, author: "", byName: title, byGlyph: MontanaAvatar.initial(title: title, name: ""), at: p.at,
                                       text: p.text, media: media, pinned: false, keepers: [""], likes: [], downloads: [], reposts: [],
                                       comments: [], from: nil, lp: p.lp)
                self.owned[wall, default: []].append(post)
                self.saveOwned()
                MTGroup.shared.carryWallPost(self.seen(post, by: Self.subscriber, conceal: true), in: wall)
                return
            }
            self.kept[pid] = MTBoardKept(post: s, wall: wall, files: media.indices.map { Self.fileName(pid, $0, media[$0].ext) })
            self.saveKept()
            let told = self.send(MTBoardWord(t: "post", id: pid, at: p.at, tx: p.text, md: media, bn: p.byName, bg: p.byGlyph, fc: p.face, lp: p.lp), to: wall)
            // THE POST STANDS IN THE PAIR'S CHAT (the author's word 30.09): the writer's row is born here, as the post leaves for the
            // wall's owner -- once, for the post on its way is taken out above; a post on my own wall stays out of every chat.
            if told { ChatStore.live?.appendWallPost(peer: wall, card: MTWallCard(id: pid, text: p.text, kind: media.first?.kind), mine: true) }
            self.askAfterAct(wall)
            var pg = self.pages[wall] ?? MTBoardPage(canWrite: true, posts: [], at: p.at)
            pg.posts.insert(s, at: pg.posts.firstIndex(where: { !$0.pinned }) ?? pg.posts.count)
            self.pages[wall] = pg
            self.savePages()
        }
        MontanaTrace.mark("wall_write", "id=\(String(pid.prefix(10))) files=\(media.count) wall=\(o.wall == nil ? "mine" : "theirs")")
        return true
    }
    /// The node confirmed a piece more of a post's file.
    private func confirmed(_ pid: String, _ i: Int, _ n: Int) {
        guard var o = outgoing[pid], i < o.confirmed.count, o.confirmed[i] < n else { return }
        o.confirmed[i] = n
        outgoing[pid] = o
    }
    /// A post on its way let go by its writer: its files go with the next sweep.
    func discard(_ pid: String) { outgoing.removeValue(forKey: pid); saveGoing() }
    /// A piece more of a repost's file came to this phone.
    private func brought(_ pid: String, _ i: Int, _ n: Int) {
        guard var o = reposting[pid], i < o.confirmed.count, o.confirmed[i] < n else { return }
        o.confirmed[i] = n
        reposting[pid] = o
    }
    /// A repost whose files did not all come, let go by its person.
    func letRepostGo(_ pid: String) { reposting.removeValue(forKey: pid) }
    /// The posts on their way to a wall, the newest first.
    func sending(on wall: String?) -> [MTBoardOutgoing] {
        outgoing.values.filter { $0.wall == wall }.sorted { $1.post.at < $0.post.at }
    }
    /// A POST ON ITS WAY GOES ON BY ITSELF (the author's word 25.09: «against failures, the network and other turns»): every post
    /// the node did not take whole — or one a run died under — is laid again when the app comes to the screen and when a door
    /// that was silent answers again; never from the background (the application's own state, not a window's phase), and
    /// never twice at once (publish). The person's own try-again stands as it was.
    func roadBack(_ why: String) {
        guard UIApplication.shared.applicationState == .active else { return }
        let due = outgoing.values.filter { $0.failed && !publishing.contains($0.id) }.map { $0.id }
        guard !due.isEmpty else { return }
        MontanaTrace.mark("wall_retry", "why=\(why) n=\(due.count)")
        for pid in due { Task { _ = await self.publish(pid) } }
    }

    /// A POST FROM THE SHARE SHEET OPENS THE WALL'S OWN PAGE (the author's words 29.09: «through the share menu I write on my own
    /// wall -- the first circle, choose it and write»; 02.10 19:17: «sharing onto the wall through Share must open the same
    /// publishing function with all its capabilities»). The sheet lays what was shared on the handoff shelf and leaves the
    /// words and the files' names under «pendingWall»; the app moves each file into my wall's drafts folder (MTBoardDrafts.take)
    /// with a picture's frame its own shape, as the page reads one it is given (MTBoardComposer.add), joins the words and the
    /// files to the draft my wall already holds (lay), and opens the wall's one new-post page over it (MTBoardComposer.reopen):
    /// the words to change, more pictures and files, the frames, the link's card, the draft kept, the check. A record leaves
    /// the keychain once its draft is laid; one this run took is never taken twice (the ring and the activation may both ask).
    /// A file the folder could not take stays on the shelf, and the shelf's week lets it go at last.
    private static var sheetTaken = Set<String>()   // BOUND-OK: the sheet's records this run took, one per share made by hand
    func takeFromSheet() {
        guard let d = MontanaKeychain.get("pendingWall"),
              let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return }
        let fresh: [SheetRecord] = rows.compactMap { row in
            guard let id = row["id"] as? String, Self.sheetTaken.insert(id).inserted else { return nil }
            return SheetRecord(id: id, words: (row["words"] as? String) ?? "", files: (row["files"] as? [[String: String]]) ?? [])
        }
        guard !fresh.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            let taken = fresh.map { Self.drafted($0) }
            await MainActor.run { MTBoard.shared.laySheet(taken) }
        }
    }
    struct SheetRecord { let id: String; let words: String; let files: [[String: String]] }
    struct SheetDraft { let id: String; let words: String; let files: [MTBoardDraftFile]; let missing: Int }
    /// One record's files moved off the shelf into the drafts folder, off the screen's thread.
    private static func drafted(_ r: SheetRecord) -> SheetDraft {
        var files: [MTBoardDraftFile] = []
        var missing = 0
        for f in r.files {
            guard let u = MontanaHandoff.url(f["src"] ?? ""), FileManager.default.fileExists(atPath: u.path) else { missing += 1; continue }
            let ext = f["ext"] ?? "", kind = MTPostMeasure.kind(ofExtension: ext)
            guard var df = MTBoardDrafts.take(u, kind: kind, name: f["name"] ?? "", ext: ext, move: true) else { missing += 1; continue }
            if kind == "img" || kind == "vid", let seen = MTBoardImage.upright(df.url, kind: kind, longest: 256)?.size,
               0 < seen.width, 0 < seen.height { df.fr = MTBoardFrame.own(seen) }
            files.append(df)
        }
        return SheetDraft(id: r.id, words: r.words, files: files, missing: missing)
    }
    /// The sheet's words and files join my wall's draft, held to what a post takes, and the wall's own page opens over it.
    private func laySheet(_ taken: [SheetDraft]) {
        var open = false
        for t in taken {
            var dr = draft(on: nil) ?? MTBoardDraft(text: "", files: [], at: Date().timeIntervalSince1970)
            let room = max(0, Self.mediaLimit - dr.files.count)
            let over = t.files.dropFirst(room).map { $0.id }
            if !over.isEmpty { DispatchQueue.global(qos: .utility).async { MTBoardDrafts.remove(over) } }
            let said = t.words.trimmingCharacters(in: .whitespacesAndNewlines)
            if !said.isEmpty {
                dr.text = dr.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? said : dr.text + "\n" + said
            }
            dr.files += t.files.prefix(room)
            lay(draft: dr, on: nil)   // an empty share lays nothing: the wall's draft stays as it was
            Self.dropFromSheet(t.id)
            MontanaTrace.mark("wall_sheet", "id=\(String(t.id.prefix(8))) files=\(min(room, t.files.count)) over=\(over.count) missing=\(t.missing) chars=\(said.count) draft")
            if !dr.empty { open = true }
        }
        if open { MTBoardComposer.reopen(on: nil) }
    }
    /// The sheet's record leaves the keychain -- after its draft is laid in the wall's store (the one remover).
    private static func dropFromSheet(_ id: String) {
        guard let d = MontanaKeychain.get("pendingWall"),
              var rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return }
        rows.removeAll { ($0["id"] as? String) == id }
        if rows.isEmpty { MontanaKeychain.delete("pendingWall") }
        else if let out = try? JSONSerialization.data(withJSONObject: rows) { MontanaKeychain.set("pendingWall", out) }
    }

    // -- a post being written -------------------------------------------------------------------

    static func wallKey(_ wall: String?) -> String { wall ?? "" }
    func draft(on wall: String?) -> MTBoardDraft? { drafts[Self.wallKey(wall)] }
    /// The page that writes a post lays it here at every change — the words as typed, a file the moment it is picked or taken
    /// off, a frame the moment it is set; an empty draft is let go, its files with it. A file taken off leaves the folder.
    func lay(draft d: MTBoardDraft, on wall: String?) {
        guard !d.empty else { dropDraft(on: wall, why: "emptied"); return }
        let k = Self.wallKey(wall)
        let was = drafts[k]
        let gone = Set((was?.files ?? []).map { $0.id }).subtracting(d.files.map { $0.id })
        drafts[k] = d
        saveDrafts()
        if !gone.isEmpty { let ids = Array(gone); DispatchQueue.global(qos: .utility).async { MTBoardDrafts.remove(ids) } }
        if was == nil {
            objectWillChange.send()
            MontanaTrace.mark("post_draft", "born wall=\(wall == nil ? "mine" : "theirs")")
        }
    }
    /// A draft let go — posted, emptied, or thrown away on its wall: its files leave with it.
    func dropDraft(on wall: String?, why: String) {
        guard let d = drafts.removeValue(forKey: Self.wallKey(wall)) else { return }
        saveDrafts()
        let ids = d.files.map { $0.id }
        if !ids.isEmpty { DispatchQueue.global(qos: .utility).async { MTBoardDrafts.remove(ids) } }
        objectWillChange.send()
        MontanaTrace.mark("post_draft", "dropped why=\(why) files=\(ids.count) chars=\(d.text.count)")
    }
    /// The page that writes a draft has closed: the wall under it draws the draft as it was left.
    func draftShown() { objectWillChange.send() }

    /// One file sealed and laid on the node's blind store: the media road's own sealing (MontanaMedia) and upload
    /// (MontanaWakePush), nothing of a road of its own. A keeper passes the post's key to lay the same chunks again;
    /// progress hears the pieces the node confirmed.
    static func seal(file: URL, kind: String, name: String, ext: String, letter: String? = nil, key: Data? = nil,
                     thumb: String? = nil, dur: Double? = nil, frame: MTBoardFrame? = nil,
                     progress: (@Sendable (Int, Int) -> Void)? = nil) async -> MTBoardMedia? {
        guard let r = await MontanaMedia.sealAndUpload(source: .file(file), letterMid: letter, key: key, progress: { _ in }) else { return nil }
        guard await MontanaWakePush.uploadChunks(["chunks": r.manifest], letter: nil, progress: progress) else { return nil }
        let chunks = r.manifest.compactMap { m -> MTBoardChunk? in
            guard let b = m["bid"] as? String, let c = m["cs"] as? Int else { return nil }
            return MTBoardChunk(bid: b, cs: c)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attrs?[.size] as? Int) ?? 0
        var shownPoster = thumb
        if shownPoster == nil { shownPoster = await poster(file, kind: kind, frame: frame) }
        let length: Double? = dur ?? ((kind == "vid" || kind == "aud") ? MontanaAudioDuration.of(file) : nil)
        return MTBoardMedia(kind: kind, name: name, ext: ext, size: size, key: r.blobKey.base64EncodedString(),
                            chunks: chunks, thumb: shownPoster, dur: length, fr: frame)
    }

    /// MY FACE, SMALL, OVER A POST I WRITE ON ANOTHER'S WALL (the author's word 24.09: «show the publisher's avatar in
    /// the post too»): the wall's owner keeps it with the post, and a visitor who never met me sees it over my words.
    /// Drawn once per face, on the main thread (the face's one owner, MontanaSelfFace, lives there).
    private static var faceMemo: (tag: Int, b64: String?)? = nil
    static func myFace() -> String? {
        let tag = MontanaSelfFace.tag
        if let m = faceMemo, m.tag == tag { return m.b64 }
        let out = MontanaSelfFace.image.flatMap { small($0, side: 96) }
        faceMemo = (tag, out)
        return out
    }
    /// MY FACE OVER A COMMENT (the author's word 25.09: «the commenter's avatar is not seen in the comments»): smaller than
    /// a post's — a page carries up to twenty comments a post.
    private static var commentFaceMemo: (tag: Int, b64: String?)? = nil
    static func commentFace() -> String? {
        let tag = MontanaSelfFace.tag
        if let m = commentFaceMemo, m.tag == tag { return m.b64 }
        let out = MontanaSelfFace.image.flatMap { small($0, side: 64) }
        commentFaceMemo = (tag, out)
        return out
    }
    /// THE FACES A WALL'S OWNER LENDS (the author's word 25.09: «the commenters' faces are still not seen — check everything»):
    /// a comment or a post written on my wall by a build that sent no small face of its writer — every build before 1936, and
    /// every comment and post written before it — wears the photo that writer published to this phone: their own published
    /// face, never a picture this phone set for them by hand. It is drawn small off the main thread, once per writer at a
    /// time, laid into the wall, and carried on the page exactly as the writer's own build carries it (MTBoardComment.fc,
    /// MTBoardPost.face); the page's version counts the faces, so the page goes to its visitors again once a face is lent.
    private var lending: Set<String> = []
    private func lendFaces(_ refs: Set<String>) {
        for ref in refs where !ref.isEmpty && !lending.contains(ref) {
            guard let file = MTNameBook.uniquePublishedPhoto(ref, files: ChatStore.live?.peerAvatars ?? [:]) else { continue }
            lending.insert(ref)
            Task.detached(priority: .utility) {
                let img = docImage(file)
                let big = img.flatMap { MTBoard.small($0, side: 96) }, small = img.flatMap { MTBoard.small($0, side: 64) }
                await MainActor.run { MTBoard.shared.lent(post: big, comment: small, to: ref) }
            }
        }
    }
    private func lent(post big: String?, comment small: String?, to ref: String) {
        lending.remove(ref)
        var moved = false
        for i in mine.indices {
            if let big, big.count <= Self.faceLimit, mine[i].author == ref, mine[i].from == nil, mine[i].face == nil {
                mine[i].face = big; moved = true
            }
            guard let small, small.count <= Self.faceLimit else { continue }
            for j in mine[i].comments.indices where mine[i].comments[j].ref == ref && mine[i].comments[j].fc == nil {
                mine[i].comments[j].fc = small; moved = true
            }
        }
        if moved { saveMine() }
    }
    /// The faces missing from what my wall already holds: posts and comments written before their writers' builds sent one.
    private func lendMissingFaces() {
        var refs = Set<String>()
        for p in mine {
            if !p.author.isEmpty, p.from == nil, p.face == nil { refs.insert(p.author) }
            for c in p.comments where c.fc == nil { if let r = c.ref, !r.isEmpty { refs.insert(r) } }
        }
        lendFaces(refs)
    }
    /// A correspondent's small face, from the photo they published (the critic 25.09: never one this phone set for them by
    /// hand — that picture is this phone's own and leaves with no post): what a repost of their own post wears.
    static func face(of conv: String) async -> String? {
        guard let file = await MainActor.run(body: { MTNameBook.uniquePublishedPhoto(conv, files: ChatStore.live?.peerAvatars ?? [:]) }) else { return nil }
        return await Task.detached(priority: .utility) { () -> String? in
            docImage(file).flatMap { small($0, side: 96) }
        }.value
    }
    /// A face drawn square at the given side, cut to fill it, as a base64 JPEG.
    static func small(_ img: UIImage, side: CGFloat) -> String? {
        guard 0 < img.size.width, 0 < img.size.height else { return nil }
        let s = max(side / img.size.width, side / img.size.height)
        let w = img.size.width * s, h = img.size.height * s
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            img.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        return drawn.jpegData(compressionQuality: 0.6)?.base64EncodedString()
    }

    /// Whose post it is, as far as this phone knows (the author's word 24.09: «a tap on the post's head, where the
    /// publisher's name is, goes to their page»): on my wall its writer's reference is mine to read; on another's the
    /// post is mine, the owner's own, or by a writer this phone is not told of — and a repost wears its first writer's
    /// name, a writer not named to this phone either.
    func writer(of p: MTBoardSeen, on wall: String?) -> MTBoardWriter {
        guard let wall else {
            guard let q = mine.first(where: { $0.id == p.id }) else { return p.mine ? .me : .unknown }
            // A REPOST ON MY WALL WEARS ITS WRITER when this phone knows them (the author's word 25.09): me, when I wrote it.
            if q.from != nil {
                if q.srcBy == "" { return .me }
                return q.srcBy.map { MTBoardWriter.peer($0) } ?? originalWriter(p.id, besides: nil)
            }
            return q.author.isEmpty ? .me : .peer(q.author)
        }
        if p.from != nil { return p.own == true ? .peer(wall) : originalWriter(p.id, besides: wall) }
        if p.mine { return .me }
        return p.own == true ? .peer(wall) : .unknown
    }
    /// THE WALL A REPOST CAME FROM, READ BY THE POST'S OWN NAME (the author's word 25.09: «after "Reposted from" the name must
    /// open its page — now it does not»): a repost keeps the name its writer gave the post, and a phone that holds the wall
    /// where the post stands as itself — not as a repost — knows that wall by its own reference; on my own wall the
    /// reference was kept when I took the post. No name of any person travels for it: the post's own name already does.
    /// nil — this phone holds the post nowhere as itself, and the repost's line stays a word.
    func source(of p: MTBoardSeen, on wall: String?) -> MTBoardWriter? {
        if wall == nil {
            guard let q = mine.first(where: { $0.id == p.id }), q.from != nil else { return nil }
            if let s = q.src { return .peer(s) }
        } else if mine.contains(where: { $0.id == p.id && $0.from == nil }) {
            return .me
        }
        return original(of: p.id, besides: wall).map { .peer($0.wall) }
    }
    /// THE THREAD A POST'S COMMENTS LIVE IN (the author's word 25.09: «the comments belong to the original's access»): a post's
    /// own; a repost's are its original's — one thread for the post wherever it is taken — read where this phone holds the
    /// original as itself, and written to that wall's owner, whose rules alone say who may see them and who may write them.
    /// nil — this phone holds the original nowhere, and its comments are not this phone's to see.
    func thread(of p: MTBoardSeen, on wall: String?) -> (wall: String?, post: MTBoardSeen)? {
        guard p.from != nil else { return (wall, p) }
        if let q = mine.first(where: { $0.id == p.id && $0.from == nil }) { return (nil, seen(q, by: "")) }
        if wall == nil, let s = mine.first(where: { $0.id == p.id && $0.from != nil })?.src,
           let o = pages[s]?.posts.first(where: { $0.id == p.id && $0.from == nil }) { return (s, o) }
        return original(of: p.id, besides: wall).map { (wall: $0.wall as String?, post: $0.post) }
    }
    /// The post itself, where it stands as itself on a wall this phone holds — the first such wall by its reference, so the
    /// answer never depends on the order a dictionary walks in.
    private func original(of id: String, besides wall: String?) -> (wall: String, post: MTBoardSeen)? {
        for w in pages.keys.sorted() where w != wall {
            if let o = pages[w]?.posts.first(where: { $0.id == id && $0.from == nil }) { return (w, o) }
        }
        return nil
    }
    /// A repost's writer, read off the post where it stands as itself (the author's word 25.09: «everything in a repost is
    /// clickable»): mine, that wall owner's, or a writer of that wall this phone knows.
    private func originalWriter(_ id: String, besides wall: String?) -> MTBoardWriter {
        if wall != nil, let q = mine.first(where: { $0.id == id && $0.from == nil }) { return q.author.isEmpty ? .me : .peer(q.author) }
        guard let o = original(of: id, besides: wall) else { return .unknown }
        return writer(of: o.post, on: o.wall)
    }
    /// Who wrote a comment, as far as this phone knows: on my wall its writer's reference is mine to read; on another's the
    /// owner says which comments are this visitor's own and which the owner's (MTBoard.shown), and the small face every
    /// other comment carries speaks for its writer.
    func commenter(_ c: MTBoardComment, of postId: String, on wall: String?) -> MTBoardWriter {
        guard let wall else {
            guard let q = mine.first(where: { $0.id == postId }),
                  let r = q.comments.first(where: { $0.id == c.id })?.ref else { return .unknown }
            return r.isEmpty ? .me : .peer(r)
        }
        if c.m == true { return .me }
        if c.o == true { return .peer(wall) }
        return .unknown
    }
    /// A correspondent whose build reads the wall: their phone may carry it here.
    func speaks(_ conv: String) -> Bool { cap.contains(conv) }

    /// THE WALL SAYS ITSELF BEHIND A LETTER OF THE PERSON'S OWN (the critic's N2): one who hides their presence speaks
    /// no «W», and an ask would say they are here — so no owner learned their build reads the wall, and none carried
    /// it. Right after their own letter to a correspondent — a moment that correspondent sees anyway — one «hi» says
    /// it, once a launch per correspondent.
    static func introduce(to conv: String) {
        DispatchQueue.main.async {
            let b = shared
            guard !MontanaPresencePrivacy.sharing, !b.hiSaid.contains(conv) else { return }
            b.hiSaid.insert(conv)
            b.send(MTBoardWord(t: "hi"), to: conv)
        }
    }
    /// THE POSTER A POST CARRIES (the author's word 24.09: «the post's picture is blurred after it is published»; 29.09: «the
    /// posts in the feed show blurred photos — fix it at the root»): the part of the picture its frame shows — every pixel of
    /// it spent on what the tile draws — its longest side 640 pixels, the tile's own width on a two-times screen and two thirds
    /// of it on three (320 stretched over a 1080-pixel tile was the blur itself), and its words held under a budget inside
    /// the bound every build of the wall keeps (thumbLimit): a page carries up to thirty posts to every correspondent. A phone
    /// that holds the file draws the file itself (MTBoardPicture); the poster is what a visitor sees before a look brings it.
    static let posterSide: CGFloat = 640
    static let posterBudget = 52_000
    static func poster(_ file: URL, kind: String, frame: MTBoardFrame? = nil) async -> String? {
        guard kind == "img" || kind == "vid" else { return nil }
        return await Task.detached(priority: .utility) { () -> String? in
            let reach = frame.map { posterSide / CGFloat(max(0.05, min($0.w, $0.h))) } ?? posterSide
            guard let whole = MTBoardImage.upright(file, kind: kind, longest: min(reach, 2400).rounded()) else { return nil }
            let img = frame.map { MTBoardImage.cut(whole, $0) } ?? whole
            guard 0 < img.size.width, 0 < img.size.height else { return nil }
            var side = posterSide
            while true {
                let scale = min(1, side / max(img.size.width, img.size.height))
                let size = CGSize(width: max(1, (img.size.width * scale).rounded()), height: max(1, (img.size.height * scale).rounded()))
                let fmt = UIGraphicsImageRendererFormat()
                fmt.scale = 1
                let small = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
                guard let b64 = small.jpegData(compressionQuality: 0.6)?.base64EncodedString() else { return nil }
                if b64.count <= posterBudget || side <= 120 { return b64 }
                side = (side * 0.8).rounded()
            }
        }.value
    }
}

/// A POST'S POSTER, DECODED OFF THE MAIN THREAD AND KEPT (the author's word 25.09: «the swipes between the pages seem to hang»;
/// the diary, T1 1937: 294 ms of the main thread the first time the feed stood): a tile used to decode the poster its post
/// carries — a JPEG of up to thirty thousand characters — inside its own drawing, on the main thread, for every picture of
/// every post that came onto the screen, and the mosaic decoded it again for its shape. The poster is decoded once, off the
/// main thread, and kept by its own words; its shape is read from its header alone.
enum MTBoardPoster {
    private static let pictures: NSCache<NSString, UIImage> = MontanaCaches.kept("board-posters", cost: 32_000_000)
    private static let shapes = NSCache<NSString, NSNumber>()
    private static func key(_ b64: String) -> NSString { String(b64.hashValue) as NSString }
    /// The poster when it is already decoded; nil — not yet, and nothing is decoded here.
    static func kept(_ b64: String?) -> UIImage? {
        guard let b64, !b64.isEmpty else { return nil }
        return pictures.object(forKey: key(b64))
    }
    static func decoded(_ b64: String?) async -> UIImage? {
        guard let b64, !b64.isEmpty else { return nil }
        if let hit = pictures.object(forKey: key(b64)) { return hit }
        let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let d = Data(base64Encoded: b64), let img = UIImage(data: d) else { return nil }
            return img.preparingForDisplay() ?? img
        }.value
        if let img { pictures.setObject(img, forKey: key(b64), cost: Int(img.size.width * img.size.height * 4)) }
        return img
    }
    /// A poster's shape, width over height, from its header: no pixel of it is decoded.
    static func shape(_ b64: String?) -> CGFloat? {
        guard let b64, !b64.isEmpty else { return nil }
        if let n = shapes.object(forKey: key(b64)) { return CGFloat(n.doubleValue) }
        guard let d = Data(base64Encoded: b64), let src = CGImageSourceCreateWithData(d as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, 0 < w, 0 < h else { return nil }
        shapes.setObject(NSNumber(value: w / h), forKey: key(b64))
        return CGFloat(w / h)
    }
}

/// A POST'S PICTURE, UPRIGHT AND CUT (the author's word 24.09): one road for the poster a post carries, the tile a phone
/// draws from the file it holds, and the picture a frame is set on — the system's own thumbnailer for a picture (its
/// orientation applied, never more pixels than asked), the poster's moment of a video.
enum MTBoardImage {
    static func upright(_ url: URL, kind: String, longest: CGFloat) -> UIImage? {
        if kind == "vid" {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: longest, height: longest)
            guard let cg = try? gen.copyCGImage(at: posterMoment(url.lastPathComponent, gen), actualTime: nil) else { return nil }
            return UIImage(cgImage: cg)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: max(16, longest),
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
    /// A tile's picture from a file on this phone: decoded so the part its frame shows has the tile's own pixels (never
    /// more than 2400 on the picture's longest side), then cut to it; a post from before the frame, the whole picture.
    static func drawn(_ url: URL, kind: String, frame: MTBoardFrame?, pixels: CGSize) -> UIImage? {
        let need = frame.map { max(pixels.width / CGFloat(max(0.01, $0.w)), pixels.height / CGFloat(max(0.01, $0.h))) }
            ?? max(pixels.width, pixels.height) * 1.5
        guard let img = upright(url, kind: kind, longest: min(max(need, 64), 2400).rounded()) else { return nil }
        return frame.map { cut(img, $0) } ?? img
    }
    /// The part a frame shows, in the picture's own pixels.
    static func cut(_ img: UIImage, _ f: MTBoardFrame) -> UIImage {
        guard let cg = img.cgImage else { return img }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let r = CGRect(x: CGFloat(f.x) * w, y: CGFloat(f.y) * h, width: CGFloat(f.w) * w, height: CGFloat(f.h) * h).integral
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard 1 <= r.width, 1 <= r.height, let part = cg.cropping(to: r) else { return img }
        return UIImage(cgImage: part)
    }
}

/// THE WALL'S DRAFTS FOLDER (25.09): the files of the posts being written on this phone, each under a name of its own, kept by
/// this device alone — a draft is finished or thrown away where it was begun (SeedScope: the record is the person's, the folder
/// stays). Application Support/Montana/WallDrafts, out of the backup as the media store is; a picked file used to lie in the
/// temporary folder, which the system empties between runs. What no draft names is let go at the wall's reading.
enum MTBoardDrafts {
    private static var dirCache: URL?
    static func folder() -> URL {
        if let c = dirCache { return c }
        var d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana", isDirectory: true)
            .appendingPathComponent("WallDrafts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        if (try? d.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true {
            var rv = URLResourceValues(); rv.isExcludedFromBackup = true
            try? d.setResourceValues(rv)
        }
        dirCache = d
        return d
    }
    static func url(_ id: String) -> URL { folder().appendingPathComponent(id) }
    private static func fresh(_ ext: String) -> String {
        "d" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24)) + (ext.isEmpty ? "" : "." + ext)
    }
    /// A picked file comes into the folder under a name of its own — copied, or moved when the source is the page's own copy —
    /// with what the post shows of it: its size, a track's or a video's length; a picture's frame is read by the page.
    static func take(_ src: URL, kind: String, name: String, ext: String, move: Bool) -> MTBoardDraftFile? {
        let id = fresh(ext), dst = url(id)
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let ok = move ? (try? FileManager.default.moveItem(at: src, to: dst)) != nil
                      : (try? FileManager.default.copyItem(at: src, to: dst)) != nil
        guard ok else { return nil }
        return file(id, kind: kind, name: name, ext: ext)
    }
    /// A picture's bytes from the library come into the folder as a file of their own.
    static func take(_ data: Data, kind: String, ext: String) -> MTBoardDraftFile? {
        let id = fresh(ext)
        guard (try? data.write(to: url(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return nil }
        return file(id, kind: kind, name: id, ext: ext)
    }
    private static func file(_ id: String, kind: String, name: String, ext: String) -> MTBoardDraftFile {
        let dst = url(id)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: dst.path)
        let size = ((try? FileManager.default.attributesOfItem(atPath: dst.path))?[.size] as? Int) ?? 0
        var dur: Double? = nil
        if kind == "vid" || kind == "aud" { let d = MontanaAudioDuration.of(dst); if d.isFinite, 0 < d { dur = d } }
        return MTBoardDraftFile(id: id, kind: kind, name: name, ext: ext, size: size, dur: dur)
    }
    static func remove(_ ids: [String]) {
        for id in ids where !id.isEmpty { try? FileManager.default.removeItem(at: url(id)) }
    }
    private static func newborn(_ id: String) -> Bool {
        guard let v = try? url(id).resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
              let born = v.creationDate ?? v.contentModificationDate else { return true }
        return Date().timeIntervalSince(born) < MontanaMediaStore.newbornGrace
    }
    /// What no draft names is let go — a file taken by a run that died before its draft was laid, or a draft of a person gone.
    /// A file born within the minute is spared: it may be a pick the page is laying this very moment (the media sweep's rule).
    static func sweep(keeping: Set<String>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder().path) else { return }
        let gone = names.filter { !$0.hasPrefix(".") && !keeping.contains($0) && !newborn($0) }
        guard !gone.isEmpty else { return }   // SILENT-OK: a cleanup, nothing to report
        remove(gone)
        MontanaTrace.mark("post_draft", "swept files=\(gone.count)")
    }
}


/// A PICTURE BROUGHT TO BE SEEN, AND KEPT UNDER A BOUND (the author's word 25.09: «on my page and on another's the media are
/// blurred and not beautiful»; 29.09: «fix it at the root»): on another's wall a tile drew the poster the post carries -- 320
/// pixels stretched over the width. The picture itself is brought from the node's blind store, by the same chunks a touch
/// brings, and the tile draws it at its own pixels. A LOOK ASKS NOTHING (the critic's P1): no keep word, no keeper, no
/// download counted -- the wall's owner learns nothing of it (MTBoard.file, the touch's road, makes the phone the post's
/// peer; this does not). A VIDEO IS NOT BROUGHT AHEAD (25.09): its tile plays it by itself through the loader (MTBoardClip,
/// MTStreams), piece by piece as the player asks, and a file the player finished lands in this same folder under its name.
/// THE FOLDER IS THIS PHONE'S OWN (29.09): it stood in Caches, which the system empties at will -- T3 brought the same
/// picture three times in a day, and between the times the tile stood on its poster; the node keeps a piece a week, so a
/// picture emptied after that is a poster for good. Application Support/Montana/WallLook, out of the backup as the media
/// store is, trimmed by this phone alone: the latest ones, a gigabyte and three hundred files at most; what earlier builds
/// left in Caches is moved here once.
enum MTBoardLook {
    static let keep = 300
    static let budget: Int64 = 1_000_000_000
    private static let lock = NSLock()
    private static var going = Set<String>()
    private static let dir: URL = {
        let fm = FileManager.default
        var d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana", isDirectory: true)
            .appendingPathComponent("WallLook", isDirectory: true)
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        if (try? d.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true {
            var rv = URLResourceValues(); rv.isExcludedFromBackup = true
            try? d.setResourceValues(rv)
        }
        let old = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("WallLook")
        if let names = try? fm.contentsOfDirectory(atPath: old.path) {
            for n in names where !n.hasPrefix(".") { try? fm.moveItem(at: old.appendingPathComponent(n), to: d.appendingPathComponent(n)) }
            try? fm.removeItem(at: old)
        }
        return d
    }()
    static func folder() -> URL { dir }
    /// The picture brought for this tile, when it lies here.
    static func here(_ pid: String, _ i: Int, _ ext: String) -> URL? {
        let u = folder().appendingPathComponent(MTBoard.fileName(pid, i, ext))
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    private static func claim(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }   // LOCK-OK: one set, in memory
        return going.insert(name).inserted
    }
    private static func release(_ name: String) {
        lock.lock(); defer { lock.unlock() }   // LOCK-OK: one set, in memory
        going.remove(name)
    }
    static func bring(_ m: MTBoardMedia, pid: String, i: Int) async -> URL? {
        if let u = here(pid, i, m.ext) { return u }
        guard m.kind == "img", !m.chunks.isEmpty,
              let key = Data(base64Encoded: m.key) else { return nil }
        let name = MTBoard.fileName(pid, i, m.ext)
        guard claim(name) else { return nil }
        defer { release(name) }
        let chunks: [[String: Any]] = m.chunks.map { ["bid": $0.bid, "cs": $0.cs] }
        let outcome = await MontanaWakePush.fetchChunks(chunks, need: .look)   // a tile on the screen, after what a player waits for
        if case .lost = outcome { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wlk_" + UUID().uuidString)
        guard await MontanaMedia.downloadToFile(manifest: chunks, blobKey: key, totalSize: m.size, dest: tmp) else {
            try? FileManager.default.removeItem(at: tmp)
            return nil
        }
        let dest = folder().appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil else { return nil }
        MontanaTrace.mark("wall_look", "id=\(String(pid.prefix(10))) i=\(i) bytes=\(m.size)")
        trim()
        return dest
    }
    /// The folder keeps the latest seen, by count and by the disk they take; the oldest go first. A FILE A PLAYER READS IS NOT
    /// THE TRIM'S (the author's word 03.10: «on T2 a big video, over a gigabyte, does not open -- high priority»): a stream lays
    /// its file here as a part at the file's whole length beside its ledger (MTStreamLoader), and this trim, run after every
    /// picture brought, counted that length -- 1.1 GB, over the budget by itself -- and took every picture, then the part and
    /// its ledger from under the player (T2 03.10: 17:32:45Z stream_open pieces=2123; 17:45:49Z item failed, a wall_look's
    /// trim a second later). A file whose loader lives (MTStreams.holds) is neither counted nor taken -- its bound is the
    /// loaders' own, the latest thirty-two; and a file counts by the disk it takes, so a part counts only the pieces laid.
    private static func trim() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey]
        guard let found = try? fm.contentsOfDirectory(at: folder(), includingPropertiesForKeys: keys) else { return }
        let all = found.filter { !MTStreams.holds(MTStreamLoader.fileOf($0.lastPathComponent)) }
        func at(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        func bytes(_ u: URL) -> Int64 { Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) }
        var total = all.reduce(Int64(0)) { $0 + bytes($1) }
        var count = all.count
        for u in all.sorted(by: { at($0) < at($1) }) {
            guard keep < count || budget < total else { break }
            total -= bytes(u); count -= 1
            try? fm.removeItem(at: u)
        }
    }
}
