import Foundation
import Combine
import SafariServices
import SwiftUI
import WebRTC

/// THE DOORS OF THE APPLICATIONS (docs/APPS-API.md; the author's words 02.11.2026 18:50 UTC and 18:52 UTC, links 14812 and 14813: «like
/// an API for each application»): shared code reaches another application only here. An application the edition does not carry
/// is nil, and what stands on it is not drawn -- no #if names an edition; the target's own MTEdition fills the doors. A static let
/// is born on its first read, so no launch order reads a door before it stands.
enum MTApps {
    #if !MONTANA_MESSENGER   // no coins in Messenger (the author's word 17130; cut C6): their door is not declared there
    static let coins: MTCoinDoor? = MTEdition.coins
    /// The letters' coins, watched (slice S2b b7): one watch for every bubble, as the book was one; silent where no door stands.
    @MainActor static let letterCoinsWatch = MTDoorWatch(coins?.changes(.letters))
    /// My available and the owner's switch, watched (slice S2b b7b); the pairs' told coins and levels, apart: the available beats
    /// each second, and a pair's face is not drawn again at that beat.
    @MainActor static let balanceWatch = MTDoorWatch(coins?.changes(.balance))
    @MainActor static let toldWatch = MTDoorWatch(coins?.changes(.told))
    /// The transfers with a person, watched (slice S2b b7d): the coins' fold, drawn again when it folds anew.
    @MainActor static let transfersWatch = MTDoorWatch(coins?.changes(.transfers))
    /// A chat's Money Flow (slice S2b b7d2): on only where the coins stand and the chat turned it on; its turn, watched.
    static func flowOn(_ conv: String) -> Bool { coins?.flowOn(conv) == true }
    @MainActor static let flowWatch = MTDoorWatch(coins?.changes(.flow))
    #else
    static func flowOn(_ conv: String) -> Bool { false }   // no Money Flow in Messenger: every feed reads oldest-first (cut C6)
    #endif
    #if !MONTANA_MESSENGER
    static let vpn: MTVPNDoor? = MTEdition.vpn
    static let mesh: MTMeshDoor? = MTEdition.mesh
    #endif
    #if !MONTANA_MESSENGER   // no chess in Messenger (the author's words 16913 and 17086; cut C5): its door is not declared there
    static let chess: MTChessDoor? = MTEdition.chess
    #endif
    #if !MONTANA_MESSENGER
    static let wall: MTWallDoor? = MTEdition.wall
    #endif
    #if !MONTANA_MESSENGER
    static let youtube: MTYouTubeDoor? = MTEdition.youtube
    #endif
}

#if !MONTANA_MESSENGER
// THE PROTOCOL'S VPN AND MESH ARE NOT COMPILED INTO MONTANA MESSENGER (the author's words 16789 and 16791, 04.11.2026 23:23-23:25
// UTC, App Review 2.3.1(a): «the binary carries VPN, vpn, Proxy, tunnel /// clean it out»): a nil door still wrote its names into
// the binary, so here alone an #if names an edition -- MONTANA_MESSENGER, set by the MontanaMessenger target -- and removes them.
/// THE MESH DOOR (the author's words 03.11.2026 22:30-22:32 UTC, links 15844-15846: «take the mesh and the P2P walls wholly out
/// of the Messenger», «cut the mesh wholly out of the Messenger»): the radio between phones nearby and the mesh wall's room. The
/// Protocol carries them; Montana Messenger does not -- its door is nil, MontanaBLEMesh.swift and MontanaMeshView.swift stand
/// outside its target, and no Bluetooth reaches its binary. Where no door stands nobody is findable on the mesh.
protocol MTMeshDoor: AnyObject {
    func setDiscoverable(_ on: Bool)
    func start()
    func powerDown()
    var linkCount: Int { get }
    var knownPeerCount: Int { get }
    var queuedFragments: Int { get }
    /// A sealed letter or blob handed to the radio: true when the radio took it.
    func send(to conv: String, envelope: Data) -> Bool
    func sendBlob(to conv: String, blobId: String, sealed: Data) -> Bool
    /// The mesh wall's room: my words and my media to everyone on the mesh, and the name a neighbour gave themselves there.
    func say(_ text: String)
    @MainActor func share(_ row: Message) -> Bool
    func name(of ref: String?) -> String?
    /// THE MESH WALL'S PAGE (link 15898; the author's word 15884 -- the code and its logic): the pane .mesh -- its head, my card with
    /// the findability switch, who is here and the room's row; a neighbour tapped opens the normal chat. Where no door stands the
    /// pane draws nothing, and none of it is compiled into the shared files.
    @MainActor func page(panel: MontanaTimePanel, onOpenChat: @escaping (String) -> Void) -> AnyView
    /// The local network's own discovery (Bonjour): the announce, its end, a look round, and whether the system let it stand.
    func advertise(port: UInt16, directPort: UInt16)
    func stopAdvertising()
    func browse(timeout: TimeInterval) -> [MontanaPeer]
    var announceAccepted: Bool { get }
    /// The router's door (NAT-PMP, then UPnP), asked of the router on the local network, and what it answered.
    func openRouterDoor()
    var routerDoor: (open: Bool, external: String, port: UInt16) { get }
}
#endif

/// THE LOCAL NETWORK (the author's word 03.11.2026 22:44 UTC, link 15863: «remove wholly everything connected with the local
/// network, the mesh and Bluetooth too, and everything connected with it»): the local network is the mesh's and is reached only
/// where the mesh door stands. Montana Messenger has none, so it knocks on no address of a local network, names none of its own,
/// lets no call pair over one, and its Info.plist claims no such access -- the system never asks it about the local network.
enum MTLocalNetwork {
    #if MONTANA_MESSENGER
    static let reached = false
    #else
    static var reached: Bool { MTApps.mesh != nil }
    #endif
    /// An address this app may knock on: any where the local network is reached; else a worldwide one, or the device itself.
    static func admits(_ ip: String) -> Bool {
        reached || MontanaTransport.isGlobalIP(ip) || MontanaTransport.isLoopback(ip)
    }
    /// One ICE candidate («candidate:F C proto prio ADDRESS port typ ...»): the address is the fifth field, and a name ending
    /// in «.local» is the engine's own mask over a local address.
    static func admits(candidate line: String) -> Bool {
        guard !reached else { return true }
        let f = line.split(separator: " ")
        guard f.count > 4 else { return false }
        let host = String(f[4])
        return !host.lowercased().hasSuffix(".local") && admits(host)
    }
    /// A session description with every candidate of a local network taken out of it.
    static func keep(sdp: String) -> String {
        guard !reached else { return sdp }
        return sdp.components(separatedBy: "\r\n")
            .filter { !$0.hasPrefix("a=candidate:") || admits(candidate: String($0.dropFirst(2))) }
            .joined(separator: "\r\n")
    }
}

/// THE DOOR'S WATCH (slice S2b b7): a shared view is drawn again when what it reads behind a door changes, and names nothing of
/// the application -- the door hands the change, the watch passes it on. Each thing watched has its own watch, so a view wakes
/// only for what it reads (a bubble never at a coin minted).
@MainActor final class MTDoorWatch: ObservableObject {
    private var held: AnyCancellable?
    init(_ changes: AnyPublisher<Void, Never>?) {
        held = changes?.sink { [weak self] in self?.objectWillChange.send() }
    }
}

#if !MONTANA_MESSENGER   // no coins in Messenger (cut C6)
/// What a shared view watches behind the coin door (slice S2b b7): the letters' coins, the book's own count by letter; my available
/// and the owner's switch to show it; the coins and levels the pairs told.
enum MTCoinWatched { case letters, balance, told, transfers, flow }

/// THE COIN DOOR: what shared code asks of the coins. Its first member is the wallet's level, the one term of the person's level the
/// coins hold (slice S2a); the letters, the badge and the send come through it slice by slice (S2b).
protocol MTCoinDoor: AnyObject {
    /// The wallet's level of π now (Canon, «The level of the wallet»); nil until the book has read its file, so it is never said as
    /// none.
    var walletLevel: Int? { get }
    /// THE WALLET'S CHAINS OF THE BUILDS BEFORE (slice S2b b7f2): the coins' folder they were written in; the TimeChain folder takes
    /// them in once a seat (MTTimeChainPlace), off the main thread, under its lock.
    var chainsBefore: URL? { get }
    /// A moment of the application the coins keep their own work at (slice S2b): the launch warms the book, the return gathers
    /// the seed's devices and their tips, a tunnel turned connected wakes the minting of its seconds.
    @MainActor func moment(_ m: MTAppMoment)
    /// THE WORD ABOUT ONESELF, its coins' part (slice S2b b3): whether my coin key and my balance are due to this pair now -- the key
    /// is derived for the word, never waited for.
    func about(to peer: String, askKey: Bool, now: Double) -> MTCoinAbout
    /// The coins' fields of the word, built only when the word goes: the balance (c), the coin key (k), my words' tag (o).
    func word(_ a: MTCoinAbout, to peer: String) -> [String: Any]
    /// The word went: the balance told and the key told are marked for this pair.
    func told(_ a: MTCoinAbout, to peer: String)
    /// A pair's word about itself: its balance, coin key and words' tag noted; true when it asked for my key again (q).
    @MainActor func heardAbout(_ o: [String: Any], from peer: String, at: Double) -> Bool
    /// The balance's tail of my presence word («C» and the balance); empty while hidden or unread.
    var balanceTail: String { get }
    /// A pair's presence word told its balance, or its Global Level (-1: withdrawn).
    func heardBalance(_ coins: Int, from peer: String, at: Double)
    func heardLevel(_ level: Int, from peer: String, at: Double)

    // THE STORE'S COIN LETTERS (slice S2b b4): a coin letter rides the chat's own road and its coins follow that road. Shared code
    // asks only whether a text or a row is one; what its coins do at each step is the coins' own.
    /// Whether a text reads as a coin letter: never edited into, never carried by a group, never ended by the carriage's clock.
    func isLetter(_ text: String) -> Bool
    /// Whether a row is a coin letter in its own right (a forward, a reply, an edited row or a row with media is none).
    func isLetter(_ m: Message) -> Bool
    /// A text that reads as a coin letter and is not the one the transfer's door is sending now: the send refuses it (06.10).
    func strays(_ text: String) -> Bool
    /// A coin letter of mine on its way, still holding its coins: its deletion waits for its road to end.
    @MainActor func travels(_ m: Message) -> Bool
    /// A row's rung moved: a coin letter of mine holds its coins or gives them back by its road (05.10).
    @MainActor func hold(_ m: Message, in chat: String)
    /// The queue's beat: a coin letter of mine past its day gives its coins back (10.10).
    @MainActor func due(_ store: ChatStore)
    /// The row leaves by a road the hand does not hold: a coin letter of mine still holding its coins gives them back first.
    @MainActor func release(_ m: Message, in chat: String)
    /// A receipt for a coin letter of mine whose row is gone: the coins that came back are taken again.
    @MainActor func arrived(_ mid: String, from chat: String)
    /// The history stands: the book holds every coin letter the chats hold, and the transfers' waiting records are decided.
    @MainActor func settle(_ store: ChatStore)
    /// A correspondent's row landed, asked at the place where the credit stands on disk before the row (04.10 23:57): a coin letter
    /// is credited, a transfer's telling letter asks the nodes, a chosen person's letter is paid by itself a turn later.
    @MainActor func landed(_ row: Message, in chat: String, store: ChatStore)
    /// Coins given on a letter by the reaction's own word: credited once by the name it carries.
    @MainActor func reacted(_ c: Int, ref: String, on sid: String, from chat: String)
    /// Coins on my post a build before the chain's sends carried in the word: credited once by the gift's name, on the post's row.
    @MainActor func gifted(_ c: Int, from peer: String, ref: String, on target: String)
    /// A word named a SEND of the chain (a paid reaction, coins on a post): its coins come by the scan alone.
    @MainActor func heardSend(_ tx: String, on target: String)
    /// Coins on another's post leave by the pair's SEND under the post's name; the post's word only names it.
    @MainActor func send(_ coins: Int, to conv: String, on target: String) async -> MTCoinSent
    /// Whether coins can go to this pair: every open pair of other words than mine.
    @MainActor func canPay(_ chat: Chat, store: ChatStore) -> Bool
    /// COINS ON THE CORRESPONDENT'S LETTER (slice S2b b6): the book pays or refuses; false when nothing left.
    @MainActor func react(_ coins: Int, on m: Message, in chat: Chat, store: ChatStore) async -> Bool
    /// The hand's retry of a coin letter whose coins came back takes them again first: a short balance refuses it; every other
    /// row may be retried.
    @MainActor func mayRetry(_ m: Message) -> Bool
    /// GIVE A COIN (slice S2b b6): the message menu's coin rows under a correspondent's letter -- one coin, and the levels of π the
    /// balance holds; onCoin gives the amount tapped.
    @MainActor func giveRow(onCoin: @escaping (Int) -> Void) -> AnyView
    /// THE COINS ON THE LETTER (slice S2b b7): the total given on a letter, and its plate beside the letter's answers.
    @MainActor func coinsOn(_ mid: String) -> Int
    @MainActor func letterCoins(_ coins: Int) -> AnyView
    /// OUR COIN (slice S4c1): the one drawing of the coin, the coins' own view (MTMintCoin) -- the composer's coin key, the bar's
    /// coin mark, the Money Flow row; turn: one turn on appearing and at every change, nil spins while spinning. And the Money Flow's
    /// beginning in the middle of the chat (MTMoneyFlowBegins), one turn at every change of tick.
    @MainActor func coin(spinning: Bool, side: CGFloat, turn: Int?) -> AnyView
    @MainActor func flowBegins(tick: Int) -> AnyView
    /// A change of what a shared view watches (MTDoorWatch), announced before it lands, as an observed object's is.
    @MainActor func changes(_ what: MTCoinWatched) -> AnyPublisher<Void, Never>
    /// THE BADGES ON A FACE (slice S2b b7b): my available, the one number of my coins, live (walletLevel says whether the book is
    /// read); whether the owner shows the coins (Privacy); the coins and the Global Level a pair last told, each no higher than its
    /// own chain proves.
    @MainActor var available: Int { get }
    @MainActor var shown: Bool { get }
    @MainActor func toldCoins(_ conv: String) -> Int?
    @MainActor func toldLevel(_ conv: String) -> Int?
    /// A count of coins on a face, the coins' own pill in its short form; and its spoken words.
    @MainActor func badge(_ coins: Int, height: CGFloat) -> AnyView
    func spokenBalance(_ coins: Int) -> String
    /// THE OWNER'S SWITCH (slice S2b b7c): its line in Appearance, On or Off, and the switch itself in Privacy beside the page's
    /// own icon; the coins said in the deletion's question while the account holds any (nil: none).
    @MainActor func showLine() -> AnyView
    @MainActor func showSwitch(icon: AnyView) -> AnyView
    @MainActor func heldWords() -> Text?
    /// THE COIN FROM THE FIELD (slice S2b b7d): a pair's coin weighed by the available and sent by its transfer; a group's coin is
    /// the Send page over the group's people, each pick paid by its pair (sent: the field is emptied).
    @MainActor func transfer(_ coins: Int, to chat: Chat, store: ChatStore) async -> MTCoinTransfer
    @MainActor func groupSend(group: String, each: Int, sent: @escaping () -> Void) -> AnyView
    /// A MOVE'S PAGE (slice S2b b7d): the transaction a coin letter's bubble or a person's transfer opens; the auto-reactions' page
    /// the coin's hold opens.
    @MainActor func movePage(_ route: MTMoveRoute, peer: String) -> AnyView
    @MainActor func autoReactPage() -> AnyView
    /// THE TRANSFERS WITH A PERSON (slice S2b b7d): newest first, nil while the coins' fold is unread (MTAppMoment.transfersAsked).
    @MainActor func transfers(with peers: Set<String>) -> [MTTransferLine]?
    /// THE MONEY FLOW OF A CHAT (slice S2b b7d2): this chat's turn of the feed, read from any thread, and its switch.
    func flowOn(_ conv: String) -> Bool
    @MainActor func setFlow(_ conv: String, _ on: Bool)
    /// THE COINS' OWN PAGES (slice S2b b7e): the wallet's page, and a post's Participation -- its windows and rights, as the core
    /// confirmed them.
    @MainActor func coinsPage(ui: UIState) -> AnyView
    @MainActor func participation() -> AnyView
    /// THE COINS' WORDS IN SETTINGS (decision 531 (a), guard 4 of docs/APPS-API.md): the Questions page -- the level by the wallet,
    /// the minting, the ticker -- and the footer of Access by level, which names the coins among the three terms of the level. An
    /// edition without coins says neither, so neither is written in a shared file.
    @MainActor func questionsPage() -> AnyView
    var levelRule: String { get }
    /// THE COINS' WORDS IN SHARED VIEWS (guard 4 of docs/APPS-API.md): what a coin from the field came to, the field's hint in the
    /// coin mode, the note of a chat a coin letter of which is on its way, the seed's line -- keys of the catalog the coins say, so
    /// an edition without coins writes none of them in a shared file.
    func said(_ w: MTCoinWord) -> String
    /// THE COINS' OWN KEYS (guard 4 of docs/APPS-API.md, as every door's): the settings a copy carries -- the
    /// owner's switch and what it said, the retired badges' switch, the person's rate, the main unit -- the keys of the person on this
    /// phone -- the balances and the levels the pairs told -- and the person's coin folder a seat parks. An edition without coins
    /// writes none of them, and its copy names none.
    var settingKeys: [String] { get }
    var seatKeys: [String] { get }
    var seatFolders: [String] { get }
    /// THE RED MINUS (slice S2b b5): the coins this pair's bubble or call just paid, risen over the way to the newest; a view of
    /// the coins' own, drawn only where the door stands.
    @MainActor func payPop(chat: String, pin: ChatConversationView.FeedPin) -> AnyView
    /// THE COIN LETTER'S FACE (slice S2b b6): our coin and its count inside the bubble's plate; nil for a row that is no coin letter.
    @MainActor func letterFace(_ m: Message, failed: Bool) -> AnyView?
    /// THE AVAILABLE BALANCE ABOVE THE FIELD (slice S2b b6): the plate the bar's coin mode stands on the feed's side; onClose takes
    /// the bar back to the microphone.
    @MainActor func balancePlate(onClose: @escaping () -> Void) -> AnyView
    /// A coin letter to a person on the shelf: credited in their own book by their own words, the trace naming the seat.
    func shelfLanded(_ text: String, mid: String, from conv: String, words: String, seat: String) async
}
#endif

#if !MONTANA_MESSENGER
/// THE VPN DOOR: what shared code asks of the VPN (slice S3a). Its first member is the VPN wall's page, the pane .vpn, searched by
/// the word at the head; the app's moments, the phone's path and the call's word come through it (slice S3b b1).
protocol MTVPNDoor: AnyObject {
    @MainActor func page(panel: MontanaTimePanel, query: String) -> AnyView
    /// A moment of the application the VPN keeps its own work at: the launch warms the server book, the app shown wakes the page's
    /// quiet beats and hidden rests them, the return reads the tunnel and what its extension wrote while the app was away.
    @MainActor func moment(_ m: MTAppMoment)
    /// The install road asked at launch: the tunnel stopped, the app leaves (true).
    @MainActor func installRoad() -> Bool
    /// The system's word for every app, carried to the tunnel at each path the phone takes; off the main thread.
    func path(satisfied: Bool, tunnel: Bool)
    /// The interface set or the tunnel fact changed: a tunnel not ours is judged a moment later.
    @MainActor func foreignTunnel(present: Bool, satisfied: Bool)
    /// The store was replaced under the living (a copy laid, the seed changed): what the VPN holds in memory is let go (slice S3b b2).
    func storeReplaced()
    /// THE WALL STANDS WHERE THE PLATFORM ADMITS A TUNNEL (slice S3b b3): the globe opens the VPN wall, else the P2P wall; the
    /// library shows its icon only then.
    var carried: Bool { get }
    /// The globe or the library's icon was touched toward the wall: the page reports the milliseconds to its opening.
    @MainActor func opened()
    /// The VPN's own glyph, the globe on a stand, for the library's icon.
    @MainActor func glyph(color: Color, size: CGFloat) -> AnyView
    /// The coin's pull on the wall's page: every plan is loaded now, by the person's own hand.
    @MainActor func refresh() async
    /// Montana's tunnel is connected; or any VPN stands -- Montana's or another app's (the coins ask, fold-7).
    @MainActor var connected: Bool { get }
    @MainActor var anyTunnel: Bool { get }
    /// The reference a VPN payment's coins carry in the book (the coins' history says its source by it).
    var payRefPrefix: String { get }
    /// The VPN's settings a copy carries (servers, plans, the one chosen, the pin and fold, the plans' number for the phone), and
    /// its keys of this device alone (the tunnel's clock, the delays, the hand, the install road, the nodes' access token).
    var settingKeys: [String] { get }
    var deviceKeys: [String] { get }
    /// Its keys a seat parks (the retired names of the VPN wall's asking, kept for old copies), and its collections a copy lays
    /// back as a union, each with what a record is known by (a server by its id, a plan by its link) -- named here, never in
    /// SeedScope, so that Montana Messenger compiles no word of them (decision 651 = a).
    var seatKeys: [String] { get }
    var unionKnownBy: [String: [String]] { get }
}
#endif

#if !MONTANA_MESSENGER   // no chess in Messenger (the author's words 16913 and 17086; cut C5)
/// THE CHESS DOOR: what shared code asks of chess (slice S4b) -- the library's icon and page, a game's board on a chat's stack, the
/// chat's mark and the invitation's answer. A game's letter itself is read by the edition's reader (MTEditionLetters.game), which
/// the notification extension holds too.
protocol MTChessDoor: AnyObject {
    /// The game's own icon, square, at a side.
    @MainActor func icon(size: CGFloat) -> AnyView
    /// The chess page, opened from the library.
    @MainActor func page(_ open: MTGameOpen, ui: UIState, store: ChatStore) -> AnyView
    /// A game's board on a chat's own stack: the back leads home to the letters.
    @MainActor func board(_ game: String, in chat: Chat) -> AnyView
    /// THE GAME ON THE SCREEN (29.09): the banner judge shows no word of it, and the player keeps quiet under it.
    var shownGame: String? { get }
    /// An invitation from the pair to me that nobody has answered; and the state of an answered invitation's game, in words.
    func awaitsMe(_ game: String, rows: [Message]) -> Bool
    func status(_ game: String, rows: [Message]) -> String?
    /// The pair's game while it is invited or played (the author's word 30.09 23:26): the chat's mark is ringed by it and enters it.
    @MainActor func playedGame(in chat: Chat, store: ChatStore) -> String?
    /// A new game from the chat, under the chat's clock: the game's name, nil when the invitation could not leave.
    @MainActor func invite(to chat: Chat, store: ChatStore) -> String?
    /// THE ACCEPT, AND ONLY THEN THE BOARD (the author's words 06.10.2026 20:5x UTC): true when the acceptance left; and the Decline.
    @MainActor func join(_ game: String, in chat: Chat, store: ChatStore) -> Bool
    @MainActor func decline(_ game: String, in chat: Chat, store: ChatStore)
    /// The training game with the phone's own engine, the person's content; the level they chose, their setting.
    var dataKeys: [String] { get }
    var settingKeys: [String] { get }
}
#endif

#if !MONTANA_MESSENGER
/// THE WALL DOOR: what shared code asks of the Wall of Thoughts (slice S4c2) -- the app's moments the wall keeps its own work at,
/// the files it names, its words on the wire, a channel's wall and the keys a copy carries. The wall's word itself (wallMark) is
/// the wire's: every edition buries it unread, and an edition with no wall carries none of a channel's wall words (.refused).
protocol MTWallDoor: AnyObject {
    // THE MOMENTS (S4c2 p1)
    /// The leave to the background: gathered on main, stored under a background task; main waits for nothing.
    func flushForBackground()
    /// A post the node did not take whole goes on by itself: at the return to the screen, at a door come back.
    func roadBack(_ why: String)
    /// The return: a few walls never heard of, each at a moment of its own; the owner's carry, only while the presence is shown.
    func sweep()
    func schedulePush()
    /// The wall's writes on their way are on the disk when these return: for the seats and the wipes, never from a SwiftUI
    /// body, action or onChange (tools/mt-wall-lock-check.py); and the wall read again for a person lifted into the seat.
    func drain()
    func flush()
    func reread()
    // THE FILES (S4c2 p2)
    /// The files the wall keeps, named by no letter: the sweep leaves them; and the folder of the pictures it brought.
    var allFiles: Set<String> { get }
    var folder: URL { get }
    /// A post the share sheet wrote for my own wall.
    func takeFromSheet()
    /// The book of contacts changed: a wall kept for contacts is carried anew.
    func bookChanged()
    // THE LETTERS (S4c2 p3)
    /// A word of the wall arrived: true when it was the wall's to read; a page of a wall, and its receipt once it is on the disk.
    func handle(_ text: String, from conv: String, isFromMe: Bool) -> Bool
    func isPage(_ text: String) -> Bool
    func receiptOnceWritten(chat: String, mid: String?)
    /// Behind a letter of the person's own the wall says it is read here; a receipted page is the version that visitor holds.
    func introduce(to conv: String)
    func delivered(text: String, to conv: String)
    /// My wall's version in the word about oneself, and a pair's version heard in theirs.
    func spokenVersion(for peer: String) -> String
    func heard(version: String, from peer: String)
    /// The node no longer holds a piece of a post's file.
    func piecesGone(_ post: MTStreamPost)
    // A CHANNEL'S WALL (S4c2 p4)
    /// A channel's post on the wire (the wall's word «cpost»).
    func isChannelPost(_ text: String) -> Bool
    /// A word of a channel's wall, read: the owner applies a subscriber's mark by its seat (ref), a subscriber lays the owner's
    /// word on the channel's page (ref nil); false when it is no word of the wall.
    @MainActor func channelWord(_ text: String, from ref: String?, in key: String) -> Bool
    /// A channel's wall posts come into its feed as its rows.
    @MainActor func fold(channel key: String, store: ChatStore)
    // THE VIEWS (S4c2 p5): the wall's pages and rows, drawn by the wall; a shared page holds only their sheet and its route.
    /// The feed of my people's walls, the logo's page: the word at the head narrows it, «Write» stands while no search holds the
    /// page, and room is kept at the bottom for the floating player.
    @MainActor func feed(panel: MontanaTimePanel, query: String, writes: Bool, reserve: CGFloat) -> AnyView
    /// A wall on a page that scrolls by itself (My page: owner nil), its sheets and pages on its own stack.
    @MainActor func pane(owner: String?) -> AnyView
    /// A wall's rows inside a page that is a list: each post a row of that list, its sheets and pages rising from the list
    /// (MTPagePresenting); and the look a person's page asks as it opens (MTBoard.look).
    @MainActor func rows(owner: String?, edge: CGFloat, sheet: Binding<MTAppSheet?>, page: Binding<MTPageRoute?>) -> AnyView
    func look(_ owner: String?)
    /// A post's link in a letter: its page at a tap, its preview and menu on a hold; nil -- no link of the wall.
    @MainActor func linkAction(_ url: URL) -> UIAction?
    @MainActor func linkMenu(_ url: URL, in view: UITextView) -> UITextItem.MenuConfiguration?
    /// A post's link opened from without: true when the post is held here and its comments rose.
    func openComments(_ url: URL) -> Bool
    /// The feed's and my wall's posts, as the music's tracks (the source «Walls»).
    @MainActor func tracks() -> [MusicTrack]
    /// The page ground's preview: the wall's write button and one post of my wall saying what it is.
    @MainActor func preview() -> AnyView
    /// Who can write on my wall (true), and who can see it.
    @MainActor func rulePage(write: Bool) -> AnyView
    // THE KEYS (S4c2 p6)
    /// The wall's values a copy carries (the account's, the person's settings), this device's own, and the person's on this phone.
    var dataKeys: [String] { get }
    var settingKeys: [String] { get }
    var deviceKeys: [String] { get }
    var seatKeys: [String] { get }
}
#endif

#if !MONTANA_MESSENGER
/// THE YOUTUBE DOOR (slice S8; decision 531 (a), App Review 5.2.2 -- a third party's content played inside the app): a YouTube link
/// in a letter, a card or a peer's page plays in YouTube's own player inside our mini player. Messenger carries no YouTube and
/// compiles neither this door nor its uses (cut C4): a YouTube link opens where it lives. No search goes out of the app: the music
/// page finds the person's own tracks alone (the author's word 04.11.2026 13:21 UTC: «only internal, and no external services of
/// music search»).
protocol MTYouTubeDoor: AnyObject {
    /// A tap on a link: a YouTube video plays here; false -- the link is not this player's.
    func play(_ url: URL, title: String?) -> Bool
    /// YouTube sounds now (the sound's ledger asks it); a sound of ours starts -- YouTube rests where it stands, one sound at a time.
    var sounds: Bool { get }
    func rest()
}
#endif

#if !MONTANA_MESSENGER   // the game's page and push are chess's alone (cut C5)
/// The chess page opened from the library: its own sheet over the tabs, at most one.
struct MTGameOpen: Identifiable {
    let id = UUID()
    var chat: String? = nil
    var game: String? = nil
}

/// A GAME OPENED FROM ITS INVITATION (the author's word 29.09: «a tap on the invitation's bubble opens the game's page, as
/// a post opens whole»): pushed on the conversation's own stack, as a post's whole letter is (MTLetterPage) -- the system's
/// back leads home to the letters, and the chat is never closed under it.
struct MTGamePush: Hashable, Identifiable {
    let game: String
    var id: String { game }
}
#endif

/// WHERE A WRITER'S NAME LEADS (the author's word 25.09: «it shows the page crookedly — it must show it whole; the page has one
/// owner, nothing is redrawn»): my own name leads to My page — the one «My profile» and the drawer's face open, face and all
/// (MontanaMyProfileView) — never to the room of my saved letters, which is its panes alone; a correspondent's leads to their
/// page (MontanaPeerInfoScreen). Every edition's (slice S4c2); an application's own page
/// rides it too, drawn behind its door and known to the stack by its name alone (MTAppPage).
enum MTPageRoute: Hashable, Identifiable {
    case mine
    case person(Chat)
    case words(MTLetterRead)   // a folded post opened whole on the letter's page (26.09)
    case app(MTAppPage)        // an application's page: its pictures and videos, one screen each, up and down (29.09)
    var id: String {
        switch self {
        case .mine: return "me"
        case .person(let c): return "p#" + c.id
        case .words(let r): return "w#" + r.id
        case .app(let a): return a.id
        }
    }
}
struct MTAppPage: Hashable {
    let id: String
    let draw: @MainActor () -> AnyView
    static func == (a: MTAppPage, b: MTAppPage) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// WHAT AN APPLICATION SHOWS OVER A SHARED PAGE (slice S4c2): a sheet the page holds by its name and the door draws -- handed the
/// page's route, so a name in it leads on the page's own stack, and its close.
struct MTAppSheet: Identifiable {
    let id: String
    let draw: @MainActor (_ page: Binding<MTPageRoute?>, _ close: @escaping () -> Void) -> AnyView
}

/// THE ONE PRESENTER OF A PAGE (the critic 25.09; slice S4c2: one application's presenter made every page's): an
/// application's sheet and a page of the route rise OVER the list or the stack that draws the page -- never from inside one of its
/// rows. A destination or a sheet set inside a lazy container is lost when its row leaves the screen (the platform says so of
/// navigationDestination), so every page that draws posts -- a person's page, my page, the feed -- wears this once, on the
/// container itself.
struct MTPagePresenting: ViewModifier {
    @Binding var sheet: MTAppSheet?
    @Binding var page: MTPageRoute?
    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet) { s in s.draw($page, { sheet = nil }) }
            .navigationDestination(item: $page) { r in
                switch r {
                case .mine: MontanaMyProfileView().montanaMotionMeter()
                case .person(let c): MontanaPeerInfoScreen(chat: c).montanaMotionMeter()
                case .words(let r): MTLetterPage(letter: r).montanaMotionMeter()   // a folded post, whole (26.09)
                case .app(let a): a.draw().montanaMotionMeter()
                }
            }
    }
}

#if !MONTANA_MESSENGER   // a game's letter is the Protocol's alone (cut C5)
extension Message {
    /// A letter of a game as the edition reads it (MTRowLetter.game): a forwarded, edited or answering letter, or one with a file, is none.
    var gameLetter: MTGameLetter? {
        guard !isForwarded, !edited, replyText == nil,
              imageFile == nil, videoFile == nil, audioFile == nil, docFile == nil else { return nil }
        return MTRowLetter.game(text)
    }
    /// A letter of a game after its invitation (MTGameLetter.step): the feed, the list record, the unread count and the banner pass
    /// it by.
    var isGameStep: Bool { gameLetter?.step == true }
}
#endif

#if !MONTANA_MESSENGER   // no coins in Messenger (cut C6)
/// A word the coins say in a shared view (MTCoinDoor.said): a title and its reason for each answer of a coin from the field, the
/// field's hint, a chat's note while a coin letter travels, the seed's line.
enum MTCoinWord { case short, shortWhy, notSent, noKeyWhy, travel, travelWhy, fieldHint, chatTravels, seed }

/// What a send of coins came to (slice S2b b4): sent under its record's name, pending its node's word, refused and why, or failed.
enum MTCoinSent { case sent(String), pending, refused(String), failed }

/// What a coin from the field came to (slice S2b b7d): sent under its record's name, short of the available, its node's word
/// undecided, refused, no coin key of the pair yet, or paced by the chain's node.
enum MTCoinTransfer { case sent(String), short, pending, refused, noKey, paced }

/// A MOVE'S PAGE ON A STACK (slice S2b b7d): the row a move is named by, and whether it is mine; a chat's or a person's page carries it
/// on its own stack, and the coin door draws the page.
struct MTMoveRoute: Hashable, Identifiable {
    let ref: String
    let mine: Bool
    var id: String { ref }
}

/// ONE TRANSFER WITH A PERSON (slice S2b b7d), as a person's page draws it: its glyph, kind and moment, its coins signed and said, and
/// what it opens -- the record in the Explorer, or the move's own page.
struct MTTransferLine: Identifiable {
    enum Opens { case web(URL), move(MTMoveRoute) }
    let id: String
    let glyph: String
    let category: String
    let at: Double
    let credit: Bool
    let said: String
    let opens: Opens
}

/// What the coins say of the word about oneself to one pair: due or not, and what it would carry.
struct MTCoinAbout {
    var keyDue = false, coinsDue = false
    var coins: Int? = nil, key: String? = nil
    var at: Double = 0
}
#endif

/// THE APPLICATION'S MOMENTS an application behind its door answers: shared code says when, the application says what.
/// The seat's moments (slice S2b b2): the person leaving the seat, the person forgotten with no other seat, a person seated.
/// The seed forgetting (slice S2b b7c): what the seed stands in on the nodes leaves while its words still derive the names.
/// The transfers asked (slice S2b b7d): a person's transactions tab opens, so the coins fold once.
/// The app shown, returned after a leaving, and hidden (slice S3b b1): the VPN page's quiet beats and the tunnel's reading.
enum MTAppMoment {
    case launched, launching, active, seatLeaving, forgottenAlone, seated, seedForgetting, transfersAsked, shown, returned, hidden
    #if !MONTANA_MESSENGER
    case tunnelConnected
    #endif
}

/// A PAGE OF THE WEB INSIDE THE APP (the author's word 12.10.2026 10:1x UTC: «inside the Explorer at once in the app»; slice S2b b7d:
/// the browser is no coins' own -- a document of Montana opens in it too): the platform's own browser sheet over the page, never a
/// jump out of the app.
struct MTWebLink: Identifiable { let url: URL; var id: String { url.absoluteString } }
struct MTWebSheet: UIViewControllerRepresentable {
    let url: URL
    static func open(_ url: URL) {
        MTTop.present(SFSafariViewController(url: url), kind: "web-sheet")
    }
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
