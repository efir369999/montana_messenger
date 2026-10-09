//
//  ContentView.swift
//  Montana — a Montana messenger
//
//  There is no entry here. A person is born as an identity out of twenty-four words, or opens
//  an existing one with them; every action carries its own signature and asks nothing else.
//

import SwiftUI
import CryptoKit
import MontanaBindings
import PhotosUI
import UserNotifications
import UIKit
import Network
import AVKit
import MediaPlayer
import AVFoundation
import LocalAuthentication
import UniformTypeIdentifiers
import CoreImage
import QuickLook
import Photos
import CoreLocation
import ContactsUI
import Contacts

// Brand gold color

// Color from hex string #RRGGBB (for deterministic avatars, see MontanaAvatar).
extension Color {
    init(montanaHexString hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255.0,
                  green: Double((v >> 8) & 0xff) / 255.0,
                  blue: Double(v & 0xff) / 255.0)
    }
    func montanaHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r*255).rounded()), Int((g*255).rounded()), Int((b*255).rounded()))
    }
}
/// THE SKIN (the author's word 09.09): one choice, read by every shape and face of the tree.
/// `geometric` — Montana's own geometry, saved as it stands: hexagon faces, octagon buttons and
/// bubbles. `native` — the platform's own look end to end: circles, capsules, rounded bubbles in
/// the system's blue and grey, glass under every button. Nobody branches on the skin by hand:
/// the shapes and the face ask here, so a new skin is one more case, not a hunt through views.
enum MontanaSkin: String, CaseIterable {
    case geometric, native
    /// The key carries a generation: «native for everyone» (the author's word 10.09) — a choice
    /// stored under the old key is not read, every device starts native, and the picker writes here.
    static let key = "montanaSkin.v2"
    /// THE PLATFORM'S OWN LOOK IS THE ONLY LOOK (the author's word 22.09: the geometric skin leaves the
    /// appearance page). A tree that still holds the old word answers «native» all the same.
    static var current: MontanaSkin { .native }
    static var isNative: Bool { current == .native }
}

// Appearance theme — SSOT default hex values (mirror the current Montana style), read by both
// the chat bubbles and the Appearance editor so the preview matches the chat exactly.
enum BT {
    // THE ONE DEFAULT OF A BUBBLE (the author's word 11.09, the dark reference over a photo):
    // theirs a translucent dark grey, mine a translucent blue, white letters on both, no rim,
    // the picture showing through. Every style starts here — «Montana» under the native skin wears the platform's own flat blue
    // on mine and its grey on theirs, with these white letters (the author's words 26.09 and 29.09),
    // «Custom» edits from it — so a chat and the editor's preview cannot tell two stories (1466:
    // the phone stood on «Custom» with the old muted-black defaults while only the «Montana»
    // branch carried the reference).
    // The fill is as translucent as the editor's slider allows (the author's word 11.09: «the
    // most transparent by default»); fillFloor is that slider's lower bound — one number.
    static let fillFloor = 0.20
    static let mF1="0A85FF", mF2="0A85FF", mTx="FFFFFF", mOl="FFFFFF", mOlOp=0.0, mOlW=0.0, mOp=fillFloor
    static let pF1="6B6B6B", pF2="6B6B6B", pTx="FFFFFF", pOl="FFFFFF", pOlOp=0.0, pOlW=0.0, pOp=fillFloor
    static let bg1="000000", bg2="0A0A0A"
    /// The bubble defaults carry a generation (as the skin key does): values saved under the old
    /// muted-black defaults are dropped once, so every device wakes on the reference; the
    /// person's own background stays.
    static let gen = "bubbleTheme.gen", genNow = "2"
    static let bubbleKeys = ["bubbleStyle", "cbMineFill1", "cbMineFill2", "cbMineOpacity", "cbMineText", "cbMineOutline",
                             "cbMineOutlineOp", "cbMineOutlineW", "cbPeerFill1", "cbPeerFill2", "cbPeerOpacity", "cbPeerText",
                             "cbPeerOutline", "cbPeerOutlineOp", "cbPeerOutlineW"]
    static func dropStale() {
        let d = UserDefaults.standard
        guard d.string(forKey: gen) != genNow else { return }
        bubbleKeys.forEach { d.removeObject(forKey: $0) }
        d.set(genNow, forKey: gen)
    }
    /// A colour still being chosen in the editor, before Save: the bubbles and the ground read it
    /// through the same door as the stored value — so the preview IS the chat (11.09).
    static var candidate: (key: String, hex: String)?
    static func hex(_ key: String, _ stored: String) -> String { candidate?.key == key ? candidate!.hex : stored }
}

func nowHHMM() -> String { MTClock.time(Date()) }
/// The visible stamp for a KNOWN moment: the bubble label and the row order must tell one
/// story ([C-1]) — a letter fetched from the node box after a sleep used to wear the fetch
/// moment while standing sorted by its birth.
func hhmm(at ts: TimeInterval) -> String { MTClock.time(Date(timeIntervalSince1970: ts)) }

// Highlight links (and make them clickable) in message text.
// A BARE HOST IS A LINK (the author's word 22.09), AND SO IS EVERY MONTANA LINK (02.10): the links are the one
// finder's (MTLinks) -- a dot with a letter on either side, or the Montana scheme, is shown to it.
// The link's word is white, underlined, on my blue and on their glass under the native skin (the author's words 10.09,
// 11.09, 26.09).
func linkify(_ s: String, mine: Bool = true) -> AttributedString {
    MTLinks.linked(s, color: MontanaNativeBubble.link(mine: mine), underline: true)
}
// ── THE MONTANA MESSAGE STYLE (SSOT) ──────────────────────────────────────────
// «montana» is the default style; «classic» is the old one (palette colour / gray).
// Own bubble: a black gradient (light top -> deep bottom) so it reads as volumetric like the
// peer's gold gradient, not a flat black rectangle. The gold outline sits on top.
let montanaBlackGradient = LinearGradient(colors: [Color(white: 0.30), Color(white: 0.13), Color(white: 0.03)],
                                          startPoint: .top, endPoint: .bottom)
// The cool white black sheen, paired with its halo.
let montanaWhiteSheenGradient = LinearGradient(colors: [
    Color(red: 0x38/255.0, green: 0x39/255.0, blue: 0x3C/255.0),
    Color(red: 0x1B/255.0, green: 0x1B/255.0, blue: 0x1E/255.0),
    Color(red: 0x06/255.0, green: 0x06/255.0, blue: 0x08/255.0)],
    startPoint: .top, endPoint: .bottom)
// Consecutive same-author messages group only within 10 minutes (abs(timestamp delta) <
// 10*60); a larger gap breaks the group so the earlier message gets a tail. bubbleGlowRadius — row gaps below are kept >= it.
let msgMergeGap: Double = 10 * 60
let bubbleGlowRadius: CGFloat = 6
let bubbleOutlineGray = Color(white: 0.45)   // sender outline (peer keeps the gold outline)

// Color palette for own messages (user selects it in Appearance)
let bubblePalette: [Color] = [
    .indigo,
    Color(red: 0.20, green: 0.60, blue: 1.00),   // light blue
    Color(red: 0.30, green: 0.78, blue: 0.45),   // green
    Color(red: 0.85, green: 0.32, blue: 0.55),   // pink
    Color(red: 0.60, green: 0.45, blue: 0.95),   // purple
    Color(red: 0.95, green: 0.45, blue: 0.25),   // orange
    Color(red: 0.20, green: 0.70, blue: 0.70)    // turquoise
]

// Controls visibility of the bottom menu (hide it when a chat is open)
/// THE FINGER'S OFFSET OF THE PANES (the author's word 24.09: «do it right, with nothing left over» — the pages follow
/// the finger as the reference's do): a thing of its own, watched by the slide alone (MTPaneSlide). The chats page reads
/// nothing of it, so its rows are not built again on every move of the finger; only the slide moves.
final class MTTurnDrag: ObservableObject {
    @Published var x: CGFloat = 0   // the pane's offset: the finger's translation while it drags, the settle's after
    /// Where the pane STANDS this frame: the platform's own interpolation of `x` while a settle runs, written by the
    /// pane's shift as it is drawn (MTPaneShift), the same as `x` under the finger. Read once, at a stroke's start: a
    /// stroke that lands mid-settle continues from here, as the reference reads its presentation layer. Nothing watches it.
    var shown: CGFloat = 0
}

@Observable class UIState {
    // The chat opens as an OVERLAY ON TOP OF TabView (the tab bar is physically beneath it,).
    // Hiding the bar with the .toolbar(.hidden, for: .tabBar) modifier is NOT allowed: on iOS 26 it breaks
    // the ScrollView height of the pushed screen — the feed «won't scroll» (content is longer than the screen).
    var overlayChat: Chat?
    var overlayJump: MID?
    /// A forward asked for outside the chat (the video feed): the chat opens at the letter and
    /// its own executor forwards it — one forward road for the whole client ([C-1]).
    var pendingForward: MID?
    var pendingForwardMany: [MID]?   // several letters chosen on the profile, forwarded through the chat's picker
    /// WHAT STANDS UNDER THE TOP BAR (the author's word 17.09): the chats, the contacts, the calls —
    /// and the music (the author's word 23.09: «the music tab as the calls»), the feed (25.09) and the network
    /// (the author's word 25.09: «a full page under the time panel, as the chats, the calls, the contacts and
    /// the feed») — the tab bar's tabs, moved up into the bar. One owner, read by the bar and the page.
    /// THE NETWORK IS DISBANDED INTO WALLS (the author's word 29.09: «we have three new applications -- the VPN wall, the
    /// mesh wall, the P2P wall -- walls common for publications»). The VPN wall left with the VPN for its own app, Montana Wallet
    /// (the author's word 08.10.2026): the P2P wall stands under the globe, in the finger's row; the mesh wall is a page under
    /// the bar opened from the drawer.
    enum Pane { case chats, groups, channels, contacts, calls, music, feed, mesh, p2p, gallery }   // the feed: the logo's page; the P2P wall: the globe's page; the gallery: the dynamic glyph's other page (25.09)
    var pane: Pane = .chats
    /// THE PAGES' GLYPHS, ONE OWNER FOR THE BAR AND THE DRAWER (the author's word 23.09: «I like the calls glyph: it is
    /// empty inside, only its outline is drawn — make the chats glyph the same, empty in the middle, its shape kept, and
    /// the player's too»): a page is named by the same glyph wherever it is named, and each is an outline, none filled.
    enum Glyph {
        /// THE DRAWER'S GLYPH, the panel's leftmost (the author's word 25.09: «make the leftmost button native, like the
        /// example, the size of the other glyphs»): the app library's grid glyph in place of one's own face.
        static let drawer = "square.grid.2x2"
        static let contacts = "person.crop.circle"
        static let calls = "phone"
        static let chats = "message"
        static let music = "play"
        static let gallery = "photo.on.rectangle.angled"
    }
    /// THE PAGES OVER THE TABS (the author's word 19.09: as native as the drawer and the chat): the
    /// settings and the profile are one open page at a time, risen over the tabs in the chat's own
    /// sliding container and closed by the cross or by the screen-edge swipe. The network left this slot
    /// for the finger's row (the author's word 25.09): it is a page under the bar, as the calls are.
    enum Page: String, Identifiable { case settings, profile, card, birth, notifications, keeping; var id: String { rawValue } }   // birth: one more person of Montana, from the drawer's plus
    var overlayPage: Page?
    /// The document page over everything (the author's word 19.09): the whole screen, above the tabs and the open chat.
    var docPage: MTDocOpen?
    /// THE PLACE PAGE STANDS OVER EVERYTHING TOO (the author's word 23.09: «only the cross in that
    /// corner»). Raised inside the chat's own navigation, the page stood UNDER the chat's bar: the
    /// navigation controller drew the chat's back chevron and the chat's name over it, and the
    /// page's own cross sat beside a back it does not own. The document page already knew the
    /// answer — the slot above the tabs and the open chat — and the place page takes it.
    var placeAsk: MTPlaceAsk?
    /// A place a letter carries, opened over everything the same way (the author's word 23.09).
    var placeOpen: MTPlaceLetter?
    /// THE CHAT'S BACKGROUND OVER EVERYTHING TOO (the author's word 23.09: «what are these extra buttons at the top —
    /// only the cross and the checkmark»). Raised inside the peer card's navigation, the chooser and its preview
    /// shared one bar with the card: the card's back arrow and dots stood beside the chooser's cross and the
    /// preview's cross and checkmark. The slot of the document and the place is its.
    var chatWall: MTWallOpen?
    var chessPage: MTChessOpen?
    var walletPage: MTPageFlag?
    /// PASSWORDS (the author's word 06.10.2026 17:4x MSK): the person's secrets, a page of its own over the tabs (MTPasswordsPage).
    var passwordsPage: MTPageFlag?
    var settingsShown: Bool {
        get { overlayPage == .settings }
        set { if newValue { overlayPage = .settings } else if overlayPage == .settings { overlayPage = nil } }
    }
    /// THE SIDE DRAWER (the author's word 17.09): opened by the face top left or by a drag from the
    /// screen's left edge; the page slides right over it, as the reference does.
    var drawerOpen = false
    /// THE FACE WITH THE NAME IN THE DRAWER OPENS MY PAGE (the author's word 24.09): the very page «My profile»
    /// opens from Settings (MontanaMyProfileView) — one page, one source, risen over the tabs like the settings.
    var profileShown: Bool {
        get { overlayPage == .profile }
        set { if newValue { overlayPage = .profile } else if overlayPage == .profile { overlayPage = nil } }
    }
    /// THE GALLERY IS CHOSEN AS THE MUSIC IS (the author's word 25.09: «the same as the network page»): a page under the bar
    /// in the dynamic glyph's slot; nothing asks and nothing answers -- the page stands built in the row (askGallery).
    /// THE DYNAMIC GLYPH ON THE TIME PANEL (the author's word 18.09): the last opened of the player
    /// and the gallery stands in the panel's second slot, before the fixed calls glyph; the choice
    /// outlives the launch.
    var lastMedia: String = UserDefaults.standard.string(forKey: "lastMediaPane") ?? "music" {
        didSet { UserDefaults.standard.set(lastMedia, forKey: "lastMediaPane") }
    }
    /// THE MUSIC IS CHOSEN AS THE CALLS ARE (the author's word 23.09): the drawer's row and the dynamic glyph put the
    /// music page under the bar; its big page unfolds from the player's plate at the page's head.
    func askMusic() { lastMedia = "music"; pane = .music }
    /// THE DYNAMIC GLYPH IS THE MUSIC'S WHILE THE MUSIC PAGE STANDS (the critic 24.09): the gallery opened over the music
    /// page made the glyph the gallery's while the puck stood under it for the music, and the music's glyph was gone.
    var mediaIsMusic: Bool { pane == .music || (pane != .gallery && lastMedia != "gallery") }
    /// THE GALLERY IS A PAGE UNDER THE BAR TOO (the author's word 25.09): chosen as the music is, in the dynamic glyph's slot.
    func askGallery() { lastMedia = "gallery"; pane = .gallery }
    /// THE TABS IN THE PANEL'S OWN ORDER (the author's word 24.09), left to right: the panes the puck stands under —
    /// the contacts, the calls, THE FEED under the logo between them and the chats (the author's word 25.09: «the feed page as
    /// whole as the chats, the calls and the contacts, turning sideways as they do»), the chats, the dynamic glyph's page --
    /// the music while the glyph is the music's, else the gallery (25.09) -- and THE NETWORK under the globe at the row's end
    /// (the author's word 25.09): its P2P wall since the VPN left for its own app (08.10.2026).
    var turnOrder: [Pane] { [.contacts, .calls, .feed, .chats, mediaIsMusic ? .music : .gallery, .p2p] }
    /// THE PAGE'S OWN HOLDS (24.09): the chats page says whether something of its own stands open — the search, the
    /// selection, a row's menu, the gallery, the code page, the music's page, the deletion's sheet; nothing else
    /// knows them. The tabs do not turn while it holds.
    var pageHolds = false
    /// May the tabs turn under the finger now: nothing over the tabs, nothing held by the page.
    var tabsMayTurn: Bool {
        overlayChat == nil && overlayPage == nil && docPage == nil && placeAsk == nil && placeOpen == nil
            && chatWall == nil && chessPage == nil && walletPage == nil && passwordsPage == nil && !drawerOpen && !pageHolds
    }
    /// THE ROW'S LEFT END (the author's word 25.09: «a swipe past the contacts opens the side panel»): the pane is the first
    /// of the row and nothing stands to its left -- a stroke to the right there is the drawer's, not the rubber band's.
    var turnAtRowStart: Bool { turnOrder.first == pane }
    /// THE PAGES FOLLOW THE FINGER (the author's word 24.09; the reference's way). While the stroke runs the pane moves
    /// by the finger's translation, and the tab beside it — the next on a stroke to the left, the one before on a
    /// stroke to the right — slides in from its side; at the row's end the pane resists (the reference's rubber band).
    /// At the release the way is read the reference's way — a moving finger says the way, a still one the distance —
    /// and the roles swap WHERE THE PAGES STAND: the neighbour becomes the pane, the pane its neighbour on the other
    /// side, and both slide home; the pane is chosen exactly as the glyph's tap chooses it, and the puck follows it.
    let turnDrag = MTTurnDrag()
    struct TurnNeighbour: Equatable { let pane: Pane; let side: Int }   // side: +1 on the right, -1 on the left
    var turnNeighbour: TurnNeighbour?
    @ObservationIgnored private var settleToken = UUID()
    @ObservationIgnored private var strokeBase: CGFloat = 0   // where the pane stood when the stroke began (the reference's fraction offset)
    private static let settleSpring = Animation.spring(response: 0.35, dampingFraction: 0.9)
    /// The reference's rubber band at the row's end.
    private static func rubber(_ offset: CGFloat) -> CGFloat {
        let range: CGFloat = 600, k: CGFloat = 0.4
        return (offset < 0 ? -1 : 1) * (1 - 1 / ((abs(offset) * k / range) + 1)) * range
    }
    func turnStroke(_ state: UIGestureRecognizer.State, x: CGFloat, vx: CGFloat, width: CGFloat) {
        let order = turnOrder
        guard let i = order.firstIndex(of: pane) else { return }
        // The stroke moves the pane from where it STOOD when the stroke began (the reference's fraction offset): a
        // stroke that lands mid-settle continues the settle instead of cutting it to rest.
        switch state {
        case .began, .changed:
            if state == .began { MTFrameMeter.shared.moveBegan(); strokeBase = beginStroke() }   // the pane under the finger, to the settle's end (25.09)
            let total = strokeBase + x
            let side = total < 0 ? 1 : (total > 0 ? -1 : 0)
            if side != 0, order.indices.contains(i + side) {
                let n = TurnNeighbour(pane: order[i + side], side: side)
                if turnNeighbour != n { turnNeighbour = n }
                turnDrag.x = total
            } else {
                if turnNeighbour != nil { turnNeighbour = nil }
                turnDrag.x = Self.rubber(total)
            }
        case .ended, .cancelled, .failed:
            let total = strokeBase + x
            var goes = false
            if state == .ended, let n = turnNeighbour {
                if abs(vx) > 10 { goes = n.side > 0 ? (total < 0 && vx < 0) : (total > 0 && vx > 0) }
                else { goes = abs(total) > width / 2 }
            }
            MontanaP2PTrace.mark("tab_swipe", "dx=\(Int(total)) v=\(Int(vx)) goes=\(goes ? 1 : 0) at=\(pane)")
            settle(goes: goes, width: width)
        default: break
        }
    }
    /// THE ROLES SWAP AFTER THE SPRING, NOT BEFORE IT (the author's word 30.09 ~23:13: «systemically, without hand-written
    /// stories, super fast»): the spring carries the neighbour to the pane's place under the same roles, and at its end the
    /// pane becomes the neighbour in one still transaction -- every reader of the pane is drawn again once, with nothing moving
    /// (T1 30.09: the swap at the release rebuilt the pages in the middle of every settle). The landing's own cost is the
    /// response the finger feels next (tap:pane:land).
    private func settle(goes: Bool, width: CGFloat) {
        let token = UUID(); settleToken = token
        let side = goes ? (turnNeighbour?.side ?? 0) : 0
        withAnimation(Self.settleSpring, completionCriteria: .logicallyComplete) {
            turnDrag.x = -CGFloat(side) * width
        } completion: { [weak self] in
            guard let self, self.settleToken == token else { return }
            let from = self.pane
            var still = Transaction(); still.disablesAnimations = true
            withTransaction(still) {
                if side != 0, let n = self.turnNeighbour { self.pane = n.pane }
                self.turnNeighbour = nil
                self.turnDrag.x = 0
            }
            MTFrameMeter.shared.moveEnded("pane:" + String(describing: self.pane))
            if from != self.pane {
                MontanaP2PTrace.mark("tab_turn", "to=\(self.pane) from=\(from)")
                MTFrameMeter.shared.tap("pane:land:" + String(describing: self.pane))
            }
        }
    }
    /// A stroke's start: a settle still running is cut WHERE IT STANDS -- its completion disowned, the model set to the
    /// drawn place with no animation -- and that place is the stroke's base. The neighbour the settle was sliding
    /// keeps standing; the stroke's own side chooses it again or lets it go.
    private func beginStroke() -> CGFloat {
        settleToken = UUID()
        let base = turnDrag.shown
        var still = Transaction(); still.disablesAnimations = true
        withTransaction(still) { turnDrag.x = base }
        return base
    }
    func openChat(_ c: Chat, jump: MID? = nil) {
        overlayJump = jump
        MTFrameMeter.shared.moveBegan()   // the chat's rise, to the platform's own end (25.09)
        withAnimation(.easeOut(duration: 0.25), completionCriteria: .logicallyComplete) { overlayChat = c } completion: {
            MTFrameMeter.shared.moveEnded("chat:open")
        }
    }
    /// «SHOW IN CHAT» — THE ONE ROAD ([C-1], the author's word 18.09: it worked now and then). The
    /// profile's menu, the player bar and the list all ask here: the chat already open jumps to the
    /// letter by this record (a nonce, so the same letter can be asked twice), any other chat opens
    /// at it. No notification that only an open chat could hear, no delay to guess by.
    struct LetterAsk: Equatable { let chat: String; let mid: MID; let nonce = UUID() }
    var letterAsk: LetterAsk?
    func showLetter(_ c: Chat, _ mid: MID) {
        if overlayChat?.name == c.name { letterAsk = LetterAsk(chat: c.name, mid: mid) }
        else { openChat(c, jump: mid) }
    }
    func closeChat() {
        MTFrameMeter.shared.moveBegan()
        withAnimation(.easeOut(duration: 0.22), completionCriteria: .logicallyComplete) { overlayChat = nil } completion: {
            MTFrameMeter.shared.moveEnded("chat:close")
        }
        overlayJump = nil
    }
}

// ════════════════════════════════════════════════════════════
//  • name — the title is taken in the phone's language automatically
//  • flag — the flag emoji is computed from the country code (no need to enter it manually)
// ════════════════════════════════════════════════════════════



// ════════════════════════════════════════════════════════════
// ROOTVIEW — decides what to show
// ════════════════════════════════════════════════════════════
struct RootView: View {
    // The one question this screen asks: does this device hold a person. The answer is the seed
    // itself — a separate marker would be a second truth, and the day the two disagree the
    // person is shown a stranger's screen.
    @State private var hasSeed = MontanaSeed.hasSeed
    @ObservedObject private var seats = MTSeats.shared        // the persons of Montana on this phone (the second identity checklist)
    @State private var termsAccepted = MontanaSafety.termsAccepted   // Guideline 1.2: the terms come before the first word
    @State private var showWelcome = false
    @State private var needPassword = false
    @AppStorage(MontanaSkin.key) private var skin = MontanaSkin.native.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MontanaP2PTrace.markOnce("root_body")   // measure: when SwiftUI began building the root screen
        return Group {
            if seats.moving {
                // A MOVE BETWEEN SEATS (the second identity checklist, 1.3): the screen of the person leaving steps aside with the
                // store it held; the platform's own indicator stands for the second the move takes.
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity).montanaPageGround()
            } else if !hasSeed {
                MontanaOnboardingView(onDone: {
                    seats.doneAdding()
                    hasSeed = MontanaSeed.hasSeed
                    // Closing onboarding without a seed means the seed never landed:
                    // the screen stays, and it looks like a dead button. Such silence on the
                    // main road IS a defect — it is recorded and spoken to the person.
                    if !hasSeed { MontanaP2PTrace.mark("onboarding_stuck", "identity=0") }
                    showWelcome = hasSeed
                    if hasSeed { MontanaMeeting.replayPendingInvite() }   // the link that waited for the identity (F-8)
                })
                // THE WAY BACK (the second identity checklist, 1.4): the seat was emptied to make a second person, and the one
                // who waits on the shelf comes back by the platform's own cross.
                .overlay(alignment: .topLeading) {
                    if seats.canReturn {
                        MontanaCallMark(glyph: "xmark", label: "Cancel") { seats.returnToLast() }
                            .padding(.leading, MontanaCallMark.sidePad).padding(.top, MontanaCallMark.topPad)
                    }
                }
            } else if hasSeed && !termsAccepted {
                MontanaTermsGate { MontanaSafety.acceptTerms(); withAnimation(.easeInOut(duration: 0.3)) { termsAccepted = true } }
            } else if showWelcome {
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.5)) { showWelcome = false }
                }
            } else {
                // A seat move exchanges every account-owned file and vault value.  `MainTabView`
                // owns its `ChatStore` as a StateObject, so the seated person's id belongs to its
                // identity too: otherwise SwiftUI may remount the retired store after the lift and
                // let it draw an empty or previous person's chats and faces.
                MainTabView().id(skin + "|seat:" + (seats.activeId ?? "unseated"))
            }
        }
        .preferredColorScheme(.dark)   // the whole theme is dark
        .onReceive(NotificationCenter.default.publisher(for: .montanaSeedForgotten)) { _ in
            hasSeed = MontanaSeed.hasSeed   // the boundary that forgets a person tells the screen
        }
        .onChange(of: seats.moving) { _, m in if !m { hasSeed = MontanaSeed.hasSeed } }   // the move ended: whoever is seated now
        .onChange(of: scenePhase) { _, phase in
            // 05.09 — every phase change is a line: «folded by itself» was invisible in the diary.
            MontanaP2PTrace.mark("scene_phase", phase == .background ? "background" : (phase == .active ? "active" : "inactive"))
            if phase == .background {
                MTForeground.active = false
                E2E.shared.persistHistory()          // force-save history (debounce may not have fired)
                MTBoard.shared.flush()               // the wall's drafts and the posts on their way, before the run may die (25.09)
                // Stage 8.2: undelivered letters keep the process alive for the system grace
                // window — a letter that can be handed over in seconds does not wait for the
                // next launch. The queue itself is on disk either way.
                MontanaDeliveryEngine.shared.backgroundHoldIfPending()
                MontanaP2PNode.shared.onBackground()
            }
            if phase == .active {
                MTForeground.active = true
                MontanaDeliveryEngine.shared.releaseBackgroundHold("foreground")
                MTCompressResume.shared.runAll()   // stage 8.4: encoding killed by the window continues here
                MTBoard.shared.roadBack("foreground")   // a post the node did not take whole goes on by itself (25.09)
            }
            if phase == .active {
                // THE EXTENSION BOX DRAINS HERE TOO. A letter that arrived by push with the
                // app in background is stored by the extension; the drain stood on launch,
                // willPresent and the banner tap — but NOT on returning to the live app via
                // the app switcher. Precedent 20.08 20:52: a letter lay in T2's own box for
                // five minutes while the person stared at an empty chat, and arrived only by
                // the sender's sparse retry.
                MontanaWakePush.drainInbox()
                // THE NODE BOX — on the same motion. The pickup stood in
                // applicationDidBecomeActive, which the SwiftUI lifecycle never calls — 16
                // chunk receipts lay in the node box for half an hour through live app
                // openings (precedent 22.08 02:10-02:30). The real activation road is this one.
                MontanaWakePush.fetchBoxKick()
                Task { await MontanaWakePush.sweepPresence() }   // every peer's last word, one question (11.09)
                MontanaP2PNode.shared.onForeground() // the node's announcement dies in sleep — raise it anew
                E2E.shared.sendLinkToAll()             // the daily link, preloaded to every correspondent (15.09)
                E2E.shared.broadcastAbout()            // my bio and my link, to whoever lacks them (24.09)
                MTBoard.shared.sweep()                 // a few walls never heard of, each at a moment of its own (24.09)
                // The owner carries the wall to whoever speaks it (24.09) — at a return only while the presence is
                // shown: for one who hides it, a carry here would say they came back (the critic's N6).
                if MontanaPresencePrivacy.sharing { MTBoard.shared.schedulePush() }
                // Off the main thread: the first root render of a launch takes seconds, and
                // the person would wait staring at a frozen screen. Name reconciliation is in no hurry.
                Task.detached(priority: .utility) {
                    if let seed = MontanaSeed.mnemonic.flatMap({ MontanaQueueKeys.masterSeed($0) }) {
                        MontanaNames.keepInStep(masterSeed: seed)
                    }
                }
                MontanaKeychain.delete("nseUnread") // legacy second badge ledger: gone for good ([C-1])
                E2E.shared.remirrorShareStore()
                MontanaHousekeeping.run()   // disk cleanup — one call, and not only on return from background
                if !UserDefaults.standard.bool(forKey: "profilePurge805") {
                    // The four retired profile fields leave the device, and the nick book drops
                    // the artefacts of the old name-into-nick mix-up: a real nick never holds a
                    // space, and never equals the declared name lowercased.
                    for k in ["userLastName", "userUsername", "userBio", "userBirthday"] {
                        UserDefaults.standard.removeObject(forKey: k)
                    }
                    E2E.shared.purgeNameArtefacts()
                    UserDefaults.standard.set(true, forKey: "profilePurge805")
                }
                E2E.shared.recalcBadge()            // badge = the app's truth (remove NSE drift)
                MTNameBook.purgeCopiedCardNames()   // once: the peer's old word copied into card names by the retired doors (18.09)
            }
            if phase == .background {
                E2E.shared.clearSecretCache()
            }
        }
    }

}

/// A PROFILE'S EDIT HAS ONE ROAD (the critic 23.09): the profile hands it to the chats page, which writes the
/// name book (ChatsListView.updateChat). The chat's profile was handed this road by hand; the same page opened
/// from the contacts was handed none, and «Done» dropped the edit without a word. The road is every profile's
/// own now — the profile's and the chat's default — so a page opened without it cannot exist.
func mtHandProfileEdit(_ id: String, _ first: String, _ last: String?, _ note: String?, _ photo: String?, _ members: [String]) {
    NotificationCenter.default.post(name: .chatMetaUpdated, object: nil, userInfo: [
        "id": id, "first": first, "last": last ?? "", "note": note ?? "",
        "photo": photo ?? "", "members": members,
    ])
}

// Chat on top of TabView: its own NavigationStack (the chat navbar and the profile NavigationLink stay alive),
// a «back» button + interactive swipe from the left edge (like the system pop).
struct ChatOverlay: View {
    @State private var overlaySize: CGSize = MTScene.size()   // the window's size from the first frame: the page rides the slide (see body)
    let chat: Chat
    var jump: MID? = nil
    var onClose: (() -> Void)? = nil
    init(chat: Chat, jump: MID? = nil, initialSize: CGSize? = nil, onClose: (() -> Void)? = nil) {
        self.chat = chat; self.jump = jump; self.onClose = onClose
        _overlaySize = State(initialValue: initialSize ?? MTScene.size())
    }
    @Environment(UIState.self) private var ui
    @EnvironmentObject private var store: ChatStore
    @State private var handle = MTSlideHandle()
    var body: some View {
        // THE BACK SWIPE IS THE PLATFORM'S (the author's word 18.09: as the drawer opens from the
        // chat): the chat is hosted by the same kind of container as the drawer's page — the system's
        // screen-edge pan moves it by its transform on every touch, the feed's scroll waits for the
        // edge pan to fail (the platform's own rule for its back gesture), the release is the
        // system's spring. A SwiftUI drag ran beside the feed's scroll and the chat scrolled while it slid.
        // Hosted screens inherit no environment: the state objects ride in by hand.
        // THE PAGE IS BORN ONCE, AT ITS SIZE (24.09, the noticed point 6 — the author's word «close it»): the size rides in
        // the key so that a turn of the screen re-hosts the page with the new one, and the overlay began at 0x0 — the
        // first measure changed the key and the page was built twice at its opening (T1 15:21:49.470Z «field_born»,
        // bar-field w=0, .547Z «field_born» again). THE SIZE IS THE WINDOW'S FROM THE FIRST FRAME (the author's word
        // 24.09: on 1916 a chat slid in from the side, and it no longer did): an overlay that held nothing until its
        // measure let the slide carry an empty view, and the chat appeared after it without moving. The window's own
        // size (MTScene.size) is known before any layout and is the size the container measures, so the page is hosted
        // on the first frame, rides the slide in from the trailing edge, and its key does not change -- it is still
        // built once. Only a window with no size yet waits for the measure (Color.clear), never a page built at 0x0.
        Group { if overlaySize == .zero { Color.clear } else {
        MontanaSlideHost(content: NavigationStack {
            // THE BACK STANDS IN THE CHAT'S ONE ROW (the author's word 05.10.2026 14:04 MSK: «back as the chess, the step as between
            // the handset and the chess»): the chat stands in its own stack over the tabs, so the system gives it no back button of
            // its own; the back is the first round of the chat's top (chatTop), the marks' one size and one step.
            ChatConversationView(chat: chat, onChatUpdate: mtHandProfileEdit, jumpTargetId: jump, onBack: { handle.close?() })
            .tint(.primary)   // the bar's marks in the label colour, as the system's own apps draw them
            // ONE OWNER OF THE KEYBOARD'S EDGE (T3 screenshot 20.09 14:31: the host grew under the
            // finger — the chat's background ran down to the keys — while the bar stood on the old
            // edge). The stack hosts its page in a hosting view of its own, and that view keeps a
            // keyboard region of its own, moved by a notification that never comes during a drag.
            // The page ignores the keyboard region: the edge is the host's keyboardLayoutGuide
            // (keyboardPinned below), and nothing else.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.mtWindowSize, overlaySize)
        .environment(ui).environmentObject(store)
        .montanaRoot(),
        key: "\(chat.id)|\(jump ?? "")|\(Int(overlaySize.width))x\(Int(overlaySize.height))",
        handle: handle,
        keyboardPinned: true,   // the chat's floor is the keyboard's edge (the author's word 20.09)
        onClosed: {
            if let onClose { onClose() }
            else { ui.overlayChat = nil; ui.overlayJump = nil }
        })   // removed without animation (removal .identity): the slide was the exit
        } }
        .ignoresSafeArea()
        // THE OVERLAY'S SIZE IS THE SCREEN'S, NOT THE KEYBOARD'S: measured on the container, which
        // the keyboard never shrinks. Measured inside the hosted tree it would follow the keyboard
        // edge frame by frame, and the key above would re-host the chat on every frame of a drag.
        // A ZERO MEASURE IS NO SIZE (24.09, the noticed point 3): as the overlay leaves — closed, or replaced by another
        // chat — its container measures 0x0, the key changed, and the leaving chat was built once more in a window of no
        // width (T3 02:57:01.779Z «field_born», «entered», bar-field w=0, «left»): every close said «left, entered, left».
        .mtMeasureSize(Binding(get: { overlaySize }, set: { if $0.width > 0, $0.height > 0 { overlaySize = $0 } }))
    }
}

/// The back button's way to the container: the container lends its close.
final class MTSlideHandle { var close: (() -> Void)? }

/// EVERY SEPARATE PAGE CLOSES WITH THE PLATFORM'S BACK SWIPE (the author's word 19.09, [C-1]): the
/// settings, the network, the gallery, the music page, the profile — each rides in the ONE sliding
/// container the chat and the drawer's page already ride in. The screen-edge pan slides the page off
/// to the right, one to one with the finger, and the page's own dismissal follows; a page pushed
/// deeper inside keeps the system's own pop. Hosted screens inherit no environment: the state
/// objects ride in by hand at the call site.
struct MontanaSlidePage<Content: View>: View {
    let key: String
    let onClosed: () -> Void
    let content: Content
    @State private var handle = MTSlideHandle()
    init(_ key: String, onClosed: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.key = key; self.onClosed = onClosed; self.content = content()
    }
    var body: some View {
        MontanaSlideHost(content: content.montanaRoot().environment(\.montanaClose, { handle.close?() }),
                         key: key, handle: handle, onClosed: onClosed)
            .ignoresSafeArea()
    }
}

/// THE PAGE'S OWN CLOSE: a page hosted in the sliding container leaves by this action — the
/// system's dismiss has nothing to dismiss there; a page the system presents keeps its own.
struct MontanaCloseKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    var montanaClose: (() -> Void)? { get { self[MontanaCloseKey.self] } set { self[MontanaCloseKey.self] = newValue } }
}

/// HOW A PAGE OVER THE CHAT LEAVES, DECIDED ONCE (the critic 22.09). A page hosted in the sliding
/// container leaves by ITS OWN close; the system's dismiss has nothing to dismiss there (the page
/// law, 19.09). Eight screens held the very same two lines, each reading the pair for itself —
/// a plumbing every SwiftUI screen must do — while the CHOICE between them was written out eight
/// times. The plumbing stays where it must; the choice has one home.
///
/// No isolation of its own: it stands exactly where the eight copies stood, inside a screen's
/// own method, and calls exactly what they called — so whatever compiled before compiles now.
func mtLeavePage(_ close: (() -> Void)?, _ dismiss: DismissAction) {
    if let close { close() } else { dismiss() }
}

/// A PAGE OVER ITS OWNER, THE CHAT'S WAY ([C-1], the author's word 19.09: closing as native as the
/// drawer and the chat). The page rides in over its owner from the right and leaves by the
/// screen-edge pan in the one sliding container — no sheet, no card, nothing grey beneath: the
/// owner stands under it exactly as the chats stand under an open chat.
struct MTPageFlag: Identifiable { let id: String }
struct MontanaPageSlot<Item: Identifiable, Page: View>: ViewModifier {
    @Binding var item: Item?
    let page: (Item) -> Page
    /// THE PAGE'S RISE IS ONE EXPLICIT ANIMATION WITH ITS OWN END (25.09): what stands in the slot follows the item through
    /// withAnimation, so the platform's completion says when the slide is over and the motion meter ends there; the leave is
    /// the slide host's own (removal .identity) and needs no animation here.
    @State private var shown: Item? = nil
    func body(content: Content) -> some View {
        ZStack {
            content
            if let it = shown {
                let key = String(describing: it.id)
                MontanaSlidePage(key, onClosed: { item = nil }) { page(it) }
                    .id(key)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .identity))
                    .zIndex(9)
            }
        }
        .onAppear { if shown?.id != item?.id { shown = item } }
        .onChange(of: item.map { String(describing: $0.id) }) { _, key in
            guard let key, let it = item else { shown = nil; return }
            MTFrameMeter.shared.moveBegan()
            withAnimation(.easeOut(duration: 0.25), completionCriteria: .logicallyComplete) { shown = it } completion: {
                MTFrameMeter.shared.moveEnded("page:rise:" + String(key.prefix(24)))
            }
        }
    }
}
extension View {
    func montanaPage<Item: Identifiable, Page: View>(item: Binding<Item?>, @ViewBuilder page: @escaping (Item) -> Page) -> some View {
        modifier(MontanaPageSlot(item: item, page: page))
    }
    func montanaPage<Page: View>(isPresented: Binding<Bool>, key: String, @ViewBuilder page: @escaping () -> Page) -> some View {
        montanaPage(item: Binding<MTPageFlag?>(get: { isPresented.wrappedValue ? MTPageFlag(id: key) : nil },
                                            set: { isPresented.wrappedValue = $0 != nil }),
                    page: { _ in page() })
    }
}

/// THE SLIDING HOST (the author's word 18.09, the drawer's law): a hosted screen the system's
/// screen-edge pan slides off to the right — one to one with the finger, the platform's spring at
/// the release carrying the finger's velocity; past a third of the width or a flick it leaves, else
/// it returns. Every scroll and swipe inside waits for the edge pan to fail.
struct MontanaSlideHost<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let key: String   // what the hosted tree is built from: the chat, the jump, the measured size
    let handle: MTSlideHandle
    var keyboardPinned = false   // the page's floor is the keyboard's top edge (UIKit's keyboardLayoutGuide)
    var onClosed: () -> Void
    func makeUIViewController(context: Context) -> MontanaSlideController {
        let c = MontanaSlideController(content: AnyView(content), keyboardPinned: keyboardPinned)
        c.key = key
        c.onClosed = onClosed
        handle.close = { [weak c] in c?.close() }
        return c
    }
    /// THE HOSTED TREE IS NOT RE-HOSTED ON EVERY PASS OF THE OUTER BODY (the author's word 18.09: the
    /// profile's buttons did not fire at the first touch). The outer body runs on every change of the
    /// store and the UI state; setting the root again under a finger re-laid the bar and dropped the
    /// press. The hosted tree observes the store by itself; the root is set again only when what it
    /// is built from has changed — the key.
    func updateUIViewController(_ c: MontanaSlideController, context: Context) {
        // A PAGE THAT HAS LEFT IS NEVER BUILT AGAIN (24.09, the noticed point 3): the last pass of a closing page came with a
        // changed key and built the page anew under the slide — a second life that appeared and vanished in eighty
        // milliseconds, and spoke for it.
        guard !c.closed else { return }   // SILENT-OK: the page has left; nothing of it is built again
        if c.key != key { c.key = key; c.updateContent(AnyView(content)) }
        c.onClosed = onClosed
    }
}

/// THE PAGE'S OWN ROOT: while the bar's node stands lifted above the place the page gave it, a touch
/// there is the bar's — decided here, above every wrapper the page puts around its views (a wrapper
/// answers by its own bounds and would swallow the touch).
final class MTSlideRootView: UIView {
    weak var liftedNode: UIView?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let n = liftedNode, n.window != nil, !n.isHidden, n.alpha > 0.01 {
            let p = convert(point, to: n)
            if n.point(inside: p, with: event), let hit = n.hitTest(p, with: event) { return hit }
        }
        return super.hitTest(point, with: event)
    }
}
final class MontanaSlideController: UIViewController, UIGestureRecognizerDelegate {
    let host: UIHostingController<AnyView>
    private let keyboardGeometry: MTChatKeyboardGeometry
    var key = ""
    var onClosed: (() -> Void)?
    private var animator: UIViewPropertyAnimator?
    private(set) var closed = false   // the page has left: the host builds nothing of it again (24.09)
    private let keyboardPinned: Bool
    /// Set when MTTop presents the container without motion: the page slides in by itself, timed from this moment.
    var risesAt: CFTimeInterval? = nil
    private var rose = false
    init(content: AnyView, keyboardPinned: Bool = false) {
        let geometry = MTChatKeyboardGeometry()
        keyboardGeometry = geometry
        host = MontanaHost.make(content.environment(\.mtChatKeyboardGeometry, keyboardPinned ? geometry : nil))
        self.keyboardPinned = keyboardPinned
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("no coder") }
    override func loadView() { view = MTSlideRootView() }
    /// THE PAGE TURNS (the critic 24.09, T1 03:11:47Z): the keyboard's owner hears it first, so the panel that stands as
    /// the field's input view is measured anew at the keys' height of the orientation the page turns to.
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if keyboardPinned { MTKeyboard.shared.turning(to: size) }
    }
    /// THE ROOT KEEPS ITS SHAPE (24.09, the author's word: «the post's page opens right only the second time»). The host
    /// was born with MontanaHost.make — AnyView(X.montanaRoot()) — and a changed key handed it a bare AnyView(X): another
    /// type under AnyView, and the platform destroys the old hierarchy and builds a new one. The first key change after a
    /// chat opened (the first keys to rise, whoever's they were) tore the whole chat down under the finger: the profile
    /// pushed over it, the post's sheet over the profile and the focused field went with it (T3 22:09:06.848: kb_show,
    /// then field_born, «entered» — the chat was back and the wall gone); every later change kept the type, which is
    /// why the second time worked. One hand builds the root, at birth and at every update (MontanaHost.reroot).
    func updateContent(_ content: AnyView) {
        MontanaHost.reroot(host, content.environment(\.mtChatKeyboardGeometry, keyboardPinned ? keyboardGeometry : nil), why: "slide")
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(host)
        host.view.backgroundColor = .black
        if keyboardPinned {
            keyboardGeometry.container = view
            // THE KEYBOARD'S EDGE IS THE PLATFORM'S OWN GUIDE (the author's word 20.09: one motion,
            // the iOS way, nothing hand-written; T3 measured: the keys went down, the bar hung).
            // The hosted tree's bottom is UIKit's keyboardLayoutGuide: the platform moves it with
            // the keyboard's own animation when the keys rise, and frame by frame under the finger
            // during the interactive dismiss — the feed, the bar and the keyboard travel as one.
            // SwiftUI's own keyboard region is taken away from the tree: two owners of one edge were
            // two motions under one finger — the keyboard slid under the touch while the bar waited
            // for a notification that never comes during a drag. (The reference reaches the same feel
            // by moving the system keyboard window through a private class; the guide is the public word.)
            host.safeAreaRegions = [.container]
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            // THE HOST IS THE WHOLE PAGE; THE KEYBOARD RAISES ITS FLOOR FROM INSIDE (20.09): a host
            // whose bottom the platform moved laid its tree out for the final size at once, and the
            // bar stood up there waiting for the keys. The guide is still read — as the number the
            // page is lifted by (MTChatKeyboardGeometry.lift), animated by the keyboard's spring.
            // The tracker (see MTChatKeyboardGeometry): a point tied to the guide's top edge, moved by
            // the platform with the keyboard — its presentation frame is the edge in every frame, and
            // a constraint to the guide keeps the container laying out under a dragging finger.
            let tracker = UIView()
            tracker.translatesAutoresizingMaskIntoConstraints = false
            tracker.isUserInteractionEnabled = false
            tracker.alpha = 0
            view.addSubview(tracker)
            keyboardGeometry.tracker = tracker
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                tracker.topAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
                tracker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tracker.widthAnchor.constraint(equalToConstant: 1),
                tracker.heightAnchor.constraint(equalToConstant: 1),
            ])
            MTKeyboard.shared.ride(view, geometry: keyboardGeometry)   // the keyboard's own move: one transition, its spring
        } else {
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
        }
        host.didMove(toParent: self)
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(pan(_:)))
        edge.edges = .left; edge.delegate = self
        view.addGestureRecognizer(edge)
    }
    /// The edge pan wins over the feed's scroll and the rows' swipes: THE PANS wait for it to fail —
    /// the platform's own rule for its back gesture, which holds only scroll views back. A tap or a
    /// press waits for nothing (the author's word 18.09: the back button at the very edge and the
    /// dots did not fire at the first touch — every recogniser of the screen was made to wait for the
    /// edge pan, and a still finger at the edge kept it in doubt until the lift). Another edge pan —
    /// the system's own pop on a pushed page — is not held either: it is deeper and takes the touch.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        g is UIScreenEdgePanGestureRecognizer && other is UIPanGestureRecognizer && !(other is UIScreenEdgePanGestureRecognizer)
    }
    /// A SwiftUI gesture of the hosted tree (the music cover's drag, 19.09) is not a pan of the
    /// platform's: it neither waits for the edge pan nor yields to it, and whichever began first
    /// took the touch — the back swipe died on the cover. The edge pan recognises alongside it.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g is UIScreenEdgePanGestureRecognizer && !(other is UIPanGestureRecognizer)
    }
    private func apply(_ x: CGFloat) {
        host.view.transform = CGAffineTransform(translationX: max(0, x), y: 0)
    }
    /// A PAGE THAT OPENS OVER A TYPING SCREEN TAKES THE KEYBOARD DOWN (the author's word 23.09: «on a tap on a place
    /// the keyboard stays hanging»). Closing a page resigned the field (the back swipe and the back button, below);
    /// opening one did not: the chat's field stayed the first responder under a page that has no field, and its keys
    /// hung over the map — the same for a document and every page of this one road. The platform's own word for
    /// «nobody types now» is resignFirstResponder sent up the chain; the chat, the page of its own keyboard, keeps it.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !keyboardPinned {
            // THE LINE SAYS WHAT HAPPENED, NOT WHAT WAS ASKED (23.09): it said «the keyboard went down» on every page,
            // keys or none -- a fact the diary never saw. It speaks when the keys were up.
            let keysUp = MTKeyboard.shared.isUp
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            if keysUp { MontanaP2PTrace.markFolded("page_keys", "a page opened — the keyboard went down", window: 10) }
        }
        if risesAt != nil, !rose { apply(max(view.bounds.width, MTScene.size().width)) }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let asked = risesAt, !rose else { return }
        rose = true
        let first = Int((CACurrentMediaTime() - asked) * 1000)
        let name = String(key.prefix(24))
        MTFrameMeter.shared.moveBegan()
        let a = UIViewPropertyAnimator(duration: 0.25, curve: .easeOut) { self.apply(0) }
        a.addCompletion { _ in
            MTFrameMeter.shared.moveEnded("page:rise:" + name)
            MontanaP2PTrace.mark("page_rise", "page=\(name) first_ms=\(first) settled_ms=\(Int((CACurrentMediaTime() - asked) * 1000))")
        }
        a.startAnimation()
        animator = a
    }
    /// The finger dragging the keyboard moves the guide frame by frame: the page follows at once.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if keyboardPinned { keyboardGeometry.followGuide() }
    }
    @objc private func pan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            MTFrameMeter.shared.moveBegan()   // the page under the finger, to the settle's end (25.09)
            animator?.stopAnimation(true); animator = nil
            // THE KEYBOARD LEAVES WITH THE SCREEN (the author's word 18.09: it hung over the chats
            // after the back swipe). Nothing resigns the field by itself when a hosted screen slides
            // off — the platform's own word for a hierarchy is endEditing: the field resigns, the
            // keyboard goes down with the page from the first movement of the swipe.
            host.view.endEditing(true)
        case .changed:
            apply(g.translation(in: view).x)
        case .ended, .cancelled, .failed:
            let x = g.translation(in: view).x, v = g.velocity(in: view).x
            let out = abs(v) > 300 ? v > 0 : x > view.bounds.width / 3
            settle(out, velocity: v)
        default: break
        }
    }
    func close() { host.view.endEditing(true); MTFrameMeter.shared.moveBegan(); settle(true, velocity: 0) }   // the back button: the same resign
    private func settle(_ out: Bool, velocity: CGFloat) {
        let target: CGFloat = out ? view.bounds.width : 0
        let distance = max(1, abs(target - host.view.transform.tx))
        let spring = UISpringTimingParameters(dampingRatio: 1, initialVelocity: CGVector(dx: velocity / distance, dy: 0))
        let a = UIViewPropertyAnimator(duration: 0.3, timingParameters: spring)
        a.addAnimations { self.apply(target) }
        let name = String(key.prefix(24))
        a.addCompletion { _ in MTFrameMeter.shared.moveEnded("slide:" + (out ? "off:" : "back:") + name) }   // the platform's own end (25.09)
        if out {
            a.addCompletion { [weak self] _ in
                guard let self, !self.closed else { return }
                self.closed = true
                self.onClosed?()
            }
        }
        a.startAnimation()
        animator = a
    }
}

// ════════════════════════════════════════════════════════════
// MAINTABVIEW — BOTTOM TAB MENU
// ════════════════════════════════════════════════════════════
// iPad / Split View: layout math needs the real window size, not the device screen.
// One measured source: a root calls .mtMeasureSize($state) and publishes it via
// the environment; readers fall back to UIScreen only when no root has measured yet.
/// The page lends its own geometry to the feed. No keyboard notifications, cached rest height,
/// or search through private hosting views: the same guide owns both the page and its inset.
/// THE KEYBOARD'S MOVE IS ONE TRANSITION, THE REFERENCE'S WAY (the author's word 20.09: «do it one to
/// one»). One notification → one transition for everything that moves: the bar (a UIKit node of its
/// own, moved by its layer's position) and the feed (its offset) get the same spring that the keyboard
/// itself is drawn with — CASpringAnimation mass 3 / stiffness 1000 / damping 500 over 0.5 s, linear
/// timing (on the newest system — the reference's newer spring) — computed by Core Animation
/// in the render server, the same process and tick that draws the keys: nothing sampled, no frame
/// behind, no layout of ours per frame. Under a dragging finger the platform moves the keyboard and
/// its guide; a point tied to the guide keeps the container laying out, and the same two things are
/// placed at once, without a transition — their interactive offset. The guide is the one source of
/// where the keyboard is.
enum MTKeyboardSpring {
    /// The reference's spring for the system keyboard curve (curve 7) — on the new system, its newer one.
    /// `speed` 2 — the reference's settle after an interactive release: the same spring, twice as fast.
    static func animation(_ keyPath: String, from: Any, to: Any, speed: Float = 1) -> CASpringAnimation {
        let a = CASpringAnimation(keyPath: keyPath)
        a.speed = speed
        if #available(iOS 26.0, *) {
            a.mass = 1; a.stiffness = 555.027; a.damping = 47.118; a.duration = 0.3832
            a.allowsOverdamping = false
        } else {
            a.mass = 3; a.stiffness = 1000; a.damping = 500; a.duration = 0.5
        }
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        a.fromValue = from; a.toValue = to
        a.isRemovedOnCompletion = true
        a.fillMode = .forwards
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        return a
    }
    /// The same spring for a SwiftUI value that rides with the keys (the «down» button's height).
    static func swiftUI(speed: Float) -> Animation {
        let a: Animation
        if #available(iOS 26.0, *) { a = .interpolatingSpring(mass: 1, stiffness: 555.027, damping: 47.118, initialVelocity: 0) }
        else { a = .interpolatingSpring(mass: 3, stiffness: 1000, damping: 500, initialVelocity: 0) }
        return a.speed(Double(speed))
    }
    static func duration(speed: Float) -> Double {
        let base: Double
        if #available(iOS 26.0, *) { base = 0.3832 } else { base = 0.5 }
        return base / Double(speed)
    }
}
final class MTChatKeyboardGeometry: NSObject {
    weak var container: UIView?
    weak var tracker: UIView?          // a point on the guide's top: keeps the container laying out under a finger
    weak var rider: MTRiderView?       // the bar's node: moved by its layer
    /// THE ROW OF BUTTONS UNDER THE TURNED FEED (the author's word 03.10 13:35): with the field on top, the open bar's
    /// lower tier stays on the keys -- a node of its own, moved by its layer in the keys' spring as the bar is in normal mode.
    weak var rowRider: MTRiderView?
    weak var feed: MTFeedFrame?        // the feed: moved by its offset
    /// THE BAR IS THE KEYBOARD'S ACCESSORY — BY ITS HEIGHT (the author's word 21.09: nothing slides
    /// under the field, the letters and the bar go down as one). The platform arms the interactive
    /// dismiss where the keyboard's frame begins, and that frame includes the input accessory view:
    /// a transparent accessory of the bar's height puts that edge at the bar's top. Measured 1803
    /// (07:36:46): the keys stood still for the bar's 52 points of finger travel while the feed
    /// scrolled 1:1 — the newest letter slid 33 points under the bar and jumped back at the release.
    /// The reference binds the keyboard's edge to the finger plus its input panel's height
    /// (getWindowInputAccessoryHeight); here the platform's own accessory does the binding, and the
    /// bar stays a node of the page — only its HEIGHT rides in the keyboard's frame.
    /// THE ACCESSORY IS THE FIELD'S TIER, A CONSTANT — NEVER THE BAR AS MEASURED, AND NOW BY
    /// CONSTRUCTION: it is given at birth and kept in a `let`, so a second owner cannot be written at
    /// all. Measured 1809 (T1 frozen) and again on 1878 (T1, 17:39:47, the author typing at the field's
    /// edge): `field_grow 117->137` (a word wrapped) -> `rider_size h=297` (the bar grew by 20) ->
    /// `acc_sync 277->297` (the accessory followed) -> `kb_place c=331 bar_top=264` — the page flew UP
    /// by 20 points, because the announced keyboard frame is one layout ahead of the accessory's own
    /// bounds the cover is measured from — and 26 ms later `kb_settle 331->311 … bar_top=284` put it
    /// back. Every wrapped line, and every erased one in mirror: the jump the author sees in the field
    /// and in the buttons under it. A gate on that sync («only at a quiet moment») narrows the window;
    /// it cannot close a value that feeds itself — the bar's height fed the accessory, the accessory fed
    /// the keyboard's frame, the frame placed the bar. Typing gives birth to NO keyboard frame now: the
    /// height is the bar AT REST, owned by the field (MTInputField.restingBar), moved by nothing.
    let accessory = MTKeyboardAccessorySpacer(MTInputField.restingBar)
    /// WHERE THE BAR STANDS (the author's word 02.10 19:17: «the chats with the input field on top, everything even, native
    /// and exact in the keyboard's work»): on the keys -- its node rides them by its layer and the keys leave the bar's room
    /// above them (the accessory) -- or at the top edge of the turned feed under the navigation bar, where the keys move the
    /// feed alone: the bar keeps its place, the accessory is no room at all, and the platform's interactive drag begins at
    /// the keys' own top. One fact, written by the bar's node (MTKeyboardRider) where the page puts it, read by the placement
    /// here and by the field's room (MTInputField).
    var barOnKeys = true
    private(set) var covered: CGFloat = 0
    private var riding = false
    private var rideEnd: DispatchWorkItem?
    /// The platform's interactive drag is on: the feed says so from the drag's begin to its end.
    private var fingerDown: Bool { feed?.cv.keyboardGestureActive ?? false }
    /// The accessory's height as the platform has laid it out — the number every keyboard frame agrees
    /// with; our own `height` only until the first layout gives it a body.
    var accessoryLaidHeight: CGFloat { accessory.laidHeight }
    /// The page's safe bottom: the line every cover is measured from.
    private var pageBottom: CGFloat { container?.safeAreaLayoutGuide.layoutFrame.maxY ?? 0 }
    /// How far the KEYS cover the page NOW, by the platform's own placement: the accessory it lays
    /// directly above the keys names the keys' top by its bottom edge — on every system, under a
    /// finger and at rest. Without an accessory in the keyboard's window (another responder's keys)
    /// the guide's top is the keys' top. THE GUIDE ALONE CANNOT NAME THE KEYS (measured 1804, the
    /// author's word: one behaviour on every device is the invariant): on 26.6 it stood at the
    /// accessory's top at the rise and at the keys' top under the finger; on 18.5 it included the
    /// accessory at the first rise and not at the second — the bar landed under the keys by exactly
    /// the accessory. A value whose meaning moves is not a source; it is taken out of the arithmetic.
    var guideCovered: CGFloat {
        guard let container else { return 0 }
        // THE KEYS ARE DOWN, NOTHING IS COVERED (22.09): the platform's own word (keyboardWillHide) closes the
        // question before any geometry is read — an accessory left in the window after the hide, or a guide
        // that never came back, cannot keep the bar lifted over no keyboard.
        if !MTKeyboard.shared.isUp, !fingerDown { return 0 }
        if accessory.window != nil {
            let r = accessory.convert(accessory.bounds, to: container)
            // A WINDOW STILL TURNING (the critic 24.09, T1 03:11:47Z and 03:12:13Z): the keyboard's window turns after the
            // page's, and its accessory read in the page's new coordinates named a keys' top of 220 on a 926-point page --
            // the page flew up by 672, its bar to y=-338, for four frames on every turn to upright. A measure taken in
            // another orientation is no measure: the page keeps its place until the platform's last word (did-change).
            guard abs(r.width - container.bounds.width) < 1 else {
                MontanaP2PTrace.markFolded("kb_turn_skip", "acc_w=\(Int(r.width)) page_w=\(Int(container.bounds.width))", window: 2)
                return covered
            }
            let keysTop = accessory.convert(accessory.bounds, to: container).maxY
            return max(0, pageBottom - keysTop)
        }
        return max(0, pageBottom - container.keyboardLayoutGuide.layoutFrame.minY)
    }
    /// The keys' cover at the end of a move the platform announces: the announced end frame includes
    /// the accessory standing in its window (measured on 18.3, 18.5 and 26.6 alike: keys + 52).
    func cover(announced f: CGRect) -> CGFloat {
        guard let container else { return 0 }
        guard abs(f.width - container.bounds.width) < 1 else { return covered }   // a frame of another orientation (24.09)
        let r = container.convert(f, from: nil)
        let keysTop = r.minY + (accessory.window == nil ? 0 : accessoryLaidHeight)
        return max(0, pageBottom - keysTop)
    }
    /// The feed's truth: what the page is lifted by now (the model; the presentation rides the spring).
    var coveredHeight: CGFloat { covered }
    func keyboardTop(in view: UIView) -> CGFloat? {
        guard let container, guideCovered > 1 else { return nil }
        return container.convert(container.keyboardLayoutGuide.layoutFrame, to: view).minY
    }
    /// A layout pass UNDER A DRAGGING FINGER: the bar and the feed stand where the guide stands, at
    /// once. Only then (measured 1796: the guide's own layout pass ran BEFORE the keyboard's
    /// notification, the page snapped to the end at once and the transition found nothing left to
    /// move); a move of the keys by themselves is the notification's transition alone.
    func followGuide() {
        // EVERY LAYOUT PASS PLACES THE PAGE WHERE THE PLATFORM PUT THE KEYS (22.09). The gates that stood
        // here — «only under a finger», «only while the pan is .changed», «never during a ride» — were the
        // windows in which the keys moved and the bar did not (the bar hanging mid-screen over a
        // half-hidden keyboard, the author's screenshot 21.09 17:40). Now the one exception is a ride in
        // flight with no finger on the feed: it runs to its end and places from the guide itself; a finger
        // arriving mid-ride takes over at once — the ride is cut and the frames are the guide's.
        if riding {
            guard fingerDown else { return }
            cutRide()
        }
        place(guideCovered)
    }
    private func cutRide() {
        rideEnd?.cancel(); rideEnd = nil
        riding = false
        rider?.host?.view.layer.removeAnimation(forKey: "keyboard")
        rowRider?.host?.view.layer.removeAnimation(forKey: "keyboard")
        feed?.cv.layer.removeAnimation(forKey: "keyboard")
    }
    /// The keyboard's own move: ONE transition — the bar's layer and the feed's offset in the keyboard's spring.
    func rideKeyboard(announced f: CGRect?) {
        container?.layoutIfNeeded()   // the guide's constraint already holds the new edge
        let target = f.map { cover(announced: $0) } ?? guideCovered
        guard abs(target - covered) > 0.5 else { return }
        riding = true
        // A release after a drag settles twice as fast (the reference's own rule); a move of the keys by themselves — the keyboard's pace.
        let speed: Float = (feed?.cv.keyboardGestureActive ?? false) ? 2 : 1
        MontanaP2PTrace.mark("kb_lift", "from=\(Int(covered)) to=\(Int(target)) spring speed=\(Int(speed))")
        place(target, speed: speed)
        rideEnd?.cancel()
        let end = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.riding = false
            self.rideEnd = nil
            self.container?.layoutIfNeeded()
            self.place(self.guideCovered)   // settled: where the guide finally stands
        }
        rideEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + MTKeyboardSpring.duration(speed: speed), execute: end)
    }
    /// A MOVE THE PLATFORM ANNOUNCES WITHOUT A TRANSITION (duration 0): the guide already stands
    /// where the keys are, and no transition will come to move the page there — it is placed at once.
    /// The one case the transition never covered (the author's word 21.09): the profile pushed over
    /// a focused field folded the keyboard under the push, the page kept its lift, and the chat came
    /// back with the bar hanging over no keyboard. A finger's own frames are the guide's layout pass.
    func settle(announced f: CGRect?) {
        // A finger on the feed is no reason to leave the page where it was (22.09): the announced end is the
        // platform's own placement, and the next layout pass (the guide's) corrects it frame by frame.
        guard !riding else { return }
        container?.layoutIfNeeded()
        let c = f.map { cover(announced: $0) } ?? guideCovered
        if abs(c - covered) > 0.5 {
            MontanaP2PTrace.mark("kb_settle", "from=\(Int(covered)) to=\(Int(c)) guide=\(Int(guideCovered))")
            place(c)
        }
        // AN ANNOUNCEMENT IS NOT THE KEYS (measured 1851, T1 23:56:37: at the first tape the keyboard
        // announced a frame of 370 with no move to follow, while the keys on the screen stayed at 397 —
        // the bar stood 27 points under the keys for the whole tape and after it). The announced frame
        // places the bar now; where the platform FINALLY put the keys — the accessory's own edge in the
        // window — is read once the platform's turn is over, and the bar stands there. The same reading
        // a ride ends with.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.riding else { return }
            self.container?.layoutIfNeeded()
            let g = self.guideCovered
            guard abs(g - self.covered) > 0.5 else { return }
            MontanaP2PTrace.mark("kb_settle", "from=\(Int(self.covered)) to=\(Int(g)) why=guide")
            self.place(g)
        }
    }
    /// `speed` nil — at once, no transition (the finger's frame). The spring BEGINS WITH THE CURRENT
    /// STATE (the reference's rule): a move interrupted by the next one starts from where the layer
    /// actually is, not from the model it never reached.
    private func place(_ c: CGFloat, animated: Bool = false, speed: Float? = nil) {
        let moved = abs(c - covered) > 0.5
        covered = c
        if let rider, !barOnKeys {
            // THE BAR AT THE TOP RIDES NOTHING (02.10): it stands where the page put it, the keys cover the feed alone.
            (container as? MTSlideRootView)?.liftedNode = nil
            rider.lift = 0
            rider.host?.view.layer.removeAnimation(forKey: "keyboard")
            if moved { MontanaP2PTrace.mark("kb_place", "c=\(Int(c)) bar=top anim=\(speed == nil ? 0 : 1)") }
            // Its row of buttons, when open, rides the keys as the whole bar does on them (03.10).
            if let row = rowRider { ride(row, c, moved: moved, speed: speed) }
        } else if let rider {
            ride(rider, c, moved: moved, speed: speed)
        } else if moved {
            MontanaP2PTrace.mark("kb_place", "c=\(Int(c)) rider=nil")
        }
        feed?.keyboardCovered(c, speed: speed)
    }
    /// A node that stands on the keys, moved to the cover `c` by its layer (the bar in normal mode, the row under the turned feed).
    private func ride(_ rider: MTRiderView, _ c: CGFloat, moved: Bool, speed: Float?) {
        do {
            // THE NODE INSIDE MOVES, NOT THE VIEW THE PAGE OWNS (measured 1798: `kb_place bar_top=529` at the
            // transition, `bar_top=840` at its end — the page re-set the frame of the view it lays out and
            // undid the transform). The page keeps its view where it put it; the hosted node inside is
            // moved by its layer's position, and nothing of the page ever sets that.
            let node = rider.host?.view
            // ONLY WHILE LIFTED (the author's word 22.09: the pin sheet's buttons answered only on their words):
            // with the keys down the node stands where the page put it, and a sheet drawn over the page
            // stands over it — the root must not hand the sheet's touches to the bar beneath.
            (container as? MTSlideRootView)?.liftedNode = c > 0.5 ? node : nil
            let now = ((node?.layer.presentation() ?? node?.layer)?.position.y) ?? 0
            rider.lift = c   // the model: the node's place, re-applied on every layout of the page's view
            let to = node?.layer.position.y ?? 0
            if let speed, let node {
                node.layer.add(MTKeyboardSpring.animation("position.y", from: now, to: to, speed: speed), forKey: "keyboard")
            } else {
                node?.layer.removeAnimation(forKey: "keyboard")
            }
            if moved || speed != nil, let w = rider.window, let node { MontanaP2PTrace.mark("kb_place", "c=\(Int(c)) bar_top=\(Int(node.convert(node.bounds, to: w).minY)) anim=\(speed == nil ? 0 : 1)") }
            MTHoldOverlayState.shared.follow(speed: speed)   // the slot went with the node: the crown asks it, in the keys' spring
        }
    }
}
/// THE EDGE WASH OF THE REFERENCE (read 21.09 in WallpaperEdgeEffectNodeImpl): the polosa's content
/// is THE WALLPAPER ITSELF — its gradient and its pattern, aligned to the page (offset −rect.minY) —
/// at alpha 0.75 under a gradient mask: the letters near the edge sink into the ground. No colour of
/// its own, no glass: the chat's ground drawn once more, cut to the edge's shape (solid at the screen's
/// edge, fading over 80 above the bar / 60 under the panel). The same on every system; no touch taken.
struct MTEdgeWash: View {
    enum Edge { case top, bottom }
    let edge: Edge
    let fade: CGFloat      // the gradient's size, the reference's edge size
    let solid: CGFloat     // the opaque run beyond the gradient, to the screen's edge
    static let alpha = 0.75
    /// THE REFERENCE'S EDGE SIZES, ONE OWNER (23.09: the chat's washes and the chat list's fade read them): the top
    /// wash fades over its last 80 and reaches 34 past the bar's lower edge; the bottom one fades in over 60 from 20
    /// above the panel's top.
    static let topFade: CGFloat = 80
    static let topReach: CGFloat = 34
    static let bottomFade: CGFloat = 60
    static let bottomReach: CGFloat = 20
    private var shape: some View {
        VStack(spacing: 0) {
            if edge == .bottom { LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: fade) }
            Color.black.frame(height: max(0, solid))
            if edge == .top { LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: fade) }
        }
    }
    var body: some View {
        let win = MTScene.size()
        MontanaChatBackdrop()
            .frame(width: win.width, height: win.height)
            .opacity(Self.alpha)
            .mask(alignment: edge == .top ? .top : .bottom) { shape }
            .allowsHitTesting(false)
    }
}
/// THE BAR IS A NODE OF ITS OWN (the reference's input panel node): a hosted tree of a fixed place in
/// the page, moved by its layer with the keyboard — never laid out again for the move. Sized by its content.
final class MTRiderView: UIView {
    var host: UIHostingController<AnyView>?
    /// THE LAST HEIGHT THIS VIEW ACTUALLY TOLD THE RECORD (22.09). A measuring pass is not news: the
    /// platform asks for a size many times per layout, and the line was written whenever the answer
    /// differed from the view's CURRENT bounds -- true on every pass of a freshly born bar (was=0).
    /// Measured on T1: 107 lines in twelve seconds, nine a second, each a formatted string and a pass
    /// through the scrubber on the screen's own thread, and all of them saying the same 102. The
    /// record hears a height when the height changes.
    var told: CGFloat = -1
    /// How far the node inside stands above the place the page gave this view (the keyboard's cover).
    var lift: CGFloat = 0 { didSet { if lift != oldValue { setNeedsLayout(); layoutIfNeeded() } } }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let v = host?.view else { return }
        v.bounds = CGRect(origin: .zero, size: bounds.size)
        v.center = CGPoint(x: bounds.midX, y: bounds.midY - lift)
        // NOTHING IS TOLD FROM HERE (22.09). The bar's own layout used to hand its height to the
        // keyboard's accessory, and one wrapped word travelled bar -> accessory -> keyboard frame ->
        // the page's place and back (measured 1878 — see MTChatKeyboardGeometry.accessory). A layout of
        // the bar is a layout of the bar, and nothing else.
    }
    /// The node stands above this view's own bounds while lifted: touches there are its own.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let v = host?.view else { return super.point(inside: point, with: event) }
        return v.frame.contains(point)
    }
}
struct MTKeyboardRider<Content: View>: UIViewRepresentable {
    let geometry: MTChatKeyboardGeometry?
    /// The node rides the keys (the bar under the feed) or stands at the top edge of the turned feed (02.10).
    var onKeys = true
    /// The open bar's row of buttons under the turned feed (03.10): it rides the keys, and writes neither the bar's place nor its node.
    var row = false
    let content: Content
    func makeUIView(context: Context) -> MTRiderView {
        if !row { geometry?.barOnKeys = onKeys }   // before the tree is born: the field inside reads where its bar stands
        let v = MTRiderView()
        v.backgroundColor = .clear
        let h = MontanaHost.make(AnyView(content))
        h.view.backgroundColor = .clear
        h.safeAreaRegions = []   // the page's insets are the page's; the bar stands where the page puts it
        h.sizingOptions = [.intrinsicContentSize]   // the tree's size is the view's intrinsic size — the node reads it to grow
        v.host = h
        v.addSubview(h.view)
        if row {
            geometry?.rowRider = v
            v.lift = geometry?.coveredHeight ?? 0   // a row opened over standing keys is born on them
        } else { geometry?.rider = v }
        return v
    }
    func updateUIView(_ v: MTRiderView, context: Context) {
        if !row { geometry?.barOnKeys = onKeys }   // before the tree's update: the field inside reads where its bar stands
        if let h = v.host { MontanaHost.reroot(h, AnyView(content), why: row ? "rider-row" : "rider") }   // the birth's own shape: a bare AnyView rebuilt the bar at its first update (24.09)
        if row { geometry?.rowRider = v } else { geometry?.rider = v }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView v: MTRiderView, context: Context) -> CGSize? {
        guard let h = v.host else { return nil }
        let w = proposal.width ?? MTScene.size().width
        let size = h.sizeThatFits(in: CGSize(width: w, height: .greatestFiniteMagnitude))
        if abs(size.height - v.told) > 0.5 {
            let was = v.told >= 0 ? v.told : v.bounds.height
            MontanaP2PTrace.mark("rider_size", "h=\(Int(size.height)) was=\(Int(was))")
            v.told = size.height
        }
        return size
    }
}
/// The keyboard's accessory as a HEIGHT alone: transparent, no touch of its own, laid out by the
/// platform from its intrinsic size (the accessory's flexible height, the platform's own rule). Its
/// one work is where the keyboard's frame — and so the interactive drag — begins.
final class MTKeyboardAccessorySpacer: UIView {
    /// GIVEN AT BIRTH, AND AFTERWARDS WRITTEN BY ONE HAND ONLY: the bar's SHAPE (the author's word
    /// 23.09 — folded on the keys, or unfolded with its buttons). A shape is a discrete choice of the
    /// finger, never a measure: typing, a wrapped word, a field of thirteen lines write nothing here,
    /// so the loop of 1809 and 1878 (the bar's height fed the accessory, the accessory fed the
    /// keyboard's frame, the frame placed the bar) cannot close. The one writer is `settle(to:)`.
    private(set) var height: CGFloat
    init(_ height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        autoresizingMask = .flexibleHeight
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: height) }
    /// The shape changed: the room the keys leave for the bar changes with it. Answers whether it did,
    /// so the caller reloads the responder's input views ONLY then.
    func settle(to h: CGFloat) -> Bool {
        guard 0.5 < abs(h - height) else { return false }
        height = h
        invalidateIntrinsicContentSize()
        MontanaP2PTrace.mark("acc_shape", "h=\(Int(h))")
        return true
    }
    /// The height the platform has given this view — `height` only until the first layout.
    var laidHeight: CGFloat { bounds.height > 1 ? bounds.height : height }
}
private struct MTChatKeyboardGeometryKey: EnvironmentKey {
    static let defaultValue: MTChatKeyboardGeometry? = nil
}
extension EnvironmentValues {
    var mtChatKeyboardGeometry: MTChatKeyboardGeometry? {
        get { self[MTChatKeyboardGeometryKey.self] }
        set { self[MTChatKeyboardGeometryKey.self] = newValue }
    }
}
private struct MTWindowSizeKey: EnvironmentKey { static let defaultValue: CGSize = .zero }
extension EnvironmentValues { var mtWindowSize: CGSize { get { self[MTWindowSizeKey.self] } set { self[MTWindowSizeKey.self] = newValue } } }
extension View {
    func mtMeasureSize(_ size: Binding<CGSize>) -> some View {
        // GeometryReader-background: fires on EVERY size change, both rotation directions. The
        // measured value is always the CURRENT container, so no consumer (settings header width,
        // bubble width, field cap) can latch a landscape size and stay crooked back in portrait.
        background(
            GeometryReader { g in
                Color.clear
                    .onAppear { if size.wrappedValue != g.size { size.wrappedValue = g.size } }
                    .onChange(of: g.size) { _, v in if size.wrappedValue != v { size.wrappedValue = v } }
            }
        )
    }
}

/// A FRAME IN THE DIARY (19.09): a view's place on the screen, written once when it appears and
/// again when it moves — the measure that tells where a page really stood on a phone nobody can
/// look at (T3: «the face flew away» three builds running, and every fix was a guess).
struct MTFrameMark: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        GeometryReader { g in
            let f = g.frame(in: .global)
            Color.clear
                .onAppear { Self.write(name, f) }
                .onChange(of: f) { _, v in Self.write(name, v) }
        }
    }
    /// WRITTEN WHEN THE FRAME COMES TO REST (25.09, T1's diary of 1938: the player's row wrote sixty lines a second for the
    /// whole of every stroke between the pages, riding with the pane): a frame in motion is not a place. The line is written
    /// once the frame has rested an eighth of a second, with the frame it rests at (MTMarkRest).
    private static func write(_ name: String, _ f: CGRect) {
        MTMarkRest.settle("frame:" + name) {
            // The app's OWN window answers, not the shared screen: mirroring, an external display,
            // split view and enlarged text give the screen other numbers than the window the page
            // actually lives in.
            let win = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first
            let s = win?.bounds ?? .zero
            let ins = win?.safeAreaInsets ?? .zero
            MontanaP2PTrace.mark("frame", "\(name) x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height)) screen=\(Int(s.width))x\(Int(s.height)) safe_top=\(Int(ins.top)) safe_bottom=\(Int(ins.bottom))")
        }
    }
}

/// A FRAME'S LINE WAITS FOR THE FRAME TO REST (25.09): one pending write a name, an eighth of a second after its last move —
/// a one-shot wait each, never a timer; the last frame named wins.
enum MTMarkRest {
    nonisolated(unsafe) private static var pending: [String: DispatchWorkItem] = [:]
    static func settle(_ name: String, _ write: @escaping () -> Void) {
        pending[name]?.cancel()
        let w = DispatchWorkItem { pending[name] = nil; write() }
        pending[name] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.125, execute: w)
    }
}

/// WHERE A PAGE'S CONTENT STANDS ACROSS THE SCREEN (24.09): the horizontal half of a frame — its left edge and its
/// width — written when it appears and when either changes, not on every scroll: a page opened from the chat and the
/// same page opened from the list are compared by it, and the settings' edge is the measure.
struct MTEdgeMark: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        GeometryReader { g in
            let f = g.frame(in: .global)
            Color.clear
                .onAppear { Self.write(name, f) }
                .onChange(of: "\(Int(f.minX))/\(Int(f.width))") { _, _ in Self.write(name, f) }
        }
    }
    /// Where it stands across the screen and down it (25.09: a hole above a row is a number in the diary, y and h).
    private static func write(_ name: String, _ f: CGRect) {
        MTMarkRest.settle("edge:" + name) {   // written at rest, as the frame's line (25.09)
            MontanaP2PTrace.mark("edge", "\(name) x=\(Int(f.minX)) w=\(Int(f.width)) y=\(Int(f.minY)) h=\(Int(f.height)) screen=\(Int(MTScene.size().width)) side=\(Int(MTPageEdge.side))")
        }
    }
}

/// THE PAGE'S SIDE MARGIN, ONE NUMBER (24.09): the settings' cards, My page's posts, a person's page and its panes all
/// stand this far from the screen's edge.
enum MTPageEdge {
    static let side: CGFloat = 16
    /// THE CANVAS'S SIDE MARGIN (the author's word 26.09: «on the contacts, the calls and the chats, the margins at the sides down
    /// to the least»): the rows' canvas stands this far off the list's sides -- the least margin, the platform's default layout
    /// margin of a view (MTChatListView.canvasRow, the search's results).
    static let canvas: CGFloat = 8
}

/// THE FEED'S GLYPH IS THE LOGO (the author's word 25.09: «a tap on the logo opens the feed»): the page is named by the logo
/// wherever it is named — the time panel's centre and the drawer's row — one drawing of it (UIState.Glyph: one glyph a page).
struct MTFeedGlyph: View {
    var side: CGFloat = 36
    var body: some View {
        // THE LOGO ON THE SYSTEM'S GLASS (the author's word 26.09: «in the time panel too the new icon, without the black ground, on
        // the system's one-tone liquid glass»): under the native skin the gold logo stands on the tree's round glass plate
        // (MTGlassCirclePlate), as the app's icon now stands on the platform's glass; the black hexagon with its rim is the other skin's.
        if MontanaSkin.isNative {
            MTGlassCirclePlate()
                .overlay(Image("Logo").resizable().scaledToFit().padding(side / 4))
                .frame(width: side, height: side)
        } else {
            MontanaHexagon().fill(Color.black)
                .overlay(Image("Logo").resizable().scaledToFit().padding(side / 4))
                .overlay(MontanaHexagon().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: side, height: side)
        }
    }
}

/// THE SIDE DRAWER (the author's word 17.09, «exactly as the reference»): a dark panel at the
/// left — the face, the name, then the rows «Contacts» and «Chats» — lying under the page. The
/// page slides right to reveal it: from the face top left, or from a drag that begins at the
/// screen's left edge; a tap on the dimmed page or a drag back closes it.
/// THE COUNT BADGE (the author's word 17.09): the platform's red counter — on the time panel's logo
/// and on the drawer's rows; nothing when there is nothing to count.
struct MTCountBadge: View {
    let count: Int
    var word: String? = nil
    init(_ count: Int) { self.count = count }
    /// The same badge carrying a short word of its own (the wallet's balance in MTPiLevels.short).
    init(word: String) { self.count = word.isEmpty ? 0 : 1; self.word = word }
    var body: some View {
        if count > 0 {
            // The platform's app-icon badge: a 20-point red capsule, the number in 13 semibold, its
            // centre at the icon's corner.
            Text(verbatim: word ?? (count > 99 ? "99+" : String(count)))   // USER-DATA: a count
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 6).frame(minWidth: 20).frame(height: 20)
                .background(Color.red, in: Capsule())
        }
    }
}

/// One catalogue owns the tiles, search rows and destinations of the app library.
enum MTApplication: String, CaseIterable, Identifiable {
    case contacts, calls, feed, chats, groups, channels, music, gallery, chess, wallet, meshWall, p2pWall, card, passwords, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contacts: return String(localized: "Contacts", bundle: MTLanguage.bundle)
        case .calls: return String(localized: "Calls", bundle: MTLanguage.bundle)
        case .feed: return String(localized: "Wall of Thoughts", bundle: MTLanguage.bundle)   // the author's word 30.09: the common feed of the posts on the walls is the Wall of Thoughts
        case .chats: return String(localized: "Chats", bundle: MTLanguage.bundle)
        case .groups: return String(localized: "Groups", bundle: MTLanguage.bundle)
        case .channels: return String(localized: "Channels", bundle: MTLanguage.bundle)
        case .music: return String(localized: "Music", bundle: MTLanguage.bundle)
        case .gallery: return String(localized: "Gallery", bundle: MTLanguage.bundle)
        case .meshWall: return String(localized: "Mesh wall", bundle: MTLanguage.bundle)
        case .p2pWall: return String(localized: "P2P wall", bundle: MTLanguage.bundle)
        case .card: return String(localized: "Business card", bundle: MTLanguage.bundle)
        case .settings: return String(localized: "Settings", bundle: MTLanguage.bundle)
        case .passwords: return String(localized: "Passwords", bundle: MTLanguage.bundle)   // the author's word 06.10.2026 17:4x MSK
        case .chess: return String(localized: "Chess", bundle: MTLanguage.bundle)
        case .wallet: return String(localized: "TimeCoin", bundle: MTLanguage.bundle)   // the author's word 04.10.2026 18:00 MSK: «rename the wallet TimeCoin»
        }
    }
    var group: MTLibraryGroup {
        switch self {
        case .contacts, .calls, .chats, .groups, .channels: return .communication
        case .feed, .card, .wallet, .meshWall, .p2pWall: return .montana   // the walls beside the feed: publications common to people (29.09)
        case .music, .gallery, .chess: return .media
        case .settings, .passwords: return .utilities
        }
    }
    func badge(in store: ChatStore) -> Int {
        switch self {
        case .calls: return store.missedCallsUnseen
        // THE GROUPS AND THE CHANNELS ARE APPS OF THEIR OWN (the author's words 06.10.2026 11:5x-12:0x MSK): each counts the unread of its own rows.
        case .chats: return store.unreadCounts.keys.filter { !MTGroup.isKey($0) }.count
        case .groups: return store.unreadCounts.keys.filter { MTGroup.isKey($0) && MTGroup.shared.kind($0) != .channel }.count
        case .channels: return store.unreadCounts.keys.filter { MTGroup.shared.kind($0) == .channel }.count
        default: return 0
        }
    }
}

enum MTLibraryGroup: String, CaseIterable, Identifiable {
    case communication, montana, media, utilities
    var id: String { rawValue }
    var title: String {
        switch self {
        case .communication: return String(localized: "Communication", bundle: MTLanguage.bundle)
        case .montana: return "Montana"
        case .media: return String(localized: "Media", bundle: MTLanguage.bundle)
        case .utilities: return String(localized: "Utilities", bundle: MTLanguage.bundle)
        }
    }
}


/// ONE FACE AT THE HEAD OF THE DRAWER: the circle, the ring of the person shown, the count of the unread, the name under it.
struct MTDrawerFace<Picture: View>: View {
    let picture: Picture
    let name: String
    let ring: Bool
    let count: Int
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                picture
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ring ? MontanaOctagon.platformBlue : Color.white.opacity(0.45), lineWidth: ring ? 3 : 1))
                if count != 0 { MTCountBadge(count).offset(x: 6, y: -6) }
            }
            if !name.isEmpty {
                Text(verbatim: name)   // USER-DATA: the person's own name
                    .font(.caption).foregroundColor(.white)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .frame(width: 88, alignment: .top)
        .contentShape(Rectangle())
    }
}

/// ONE MORE PERSON FROM THE DRAWER'S PLUS (the second identity checklist, stage 1): the first screen as a page over the tabs.
struct MTBirthPage: View {
    let done: () -> Void
    var body: some View {
        MontanaOnboardingView(onDone: done)
    }
}

struct MontanaSideDrawer: View {
    @AppStorage("appLibraryIcons") private var icons = false
    @AppStorage("appLibraryPins") private var savedPins = "chats,contacts,calls,feed"
    @AppStorage("userName") private var selfName = ""
    @State private var sections: [MTLibrarySection] = []
    @Environment(UIState.self) private var ui
    @EnvironmentObject private var store: ChatStore
    @AppStorage("avatarData") private var avatarData: Data = Data()
    @ObservedObject private var seats = MTSeats.shared   // the persons of Montana waiting on this phone's shelf
    @State private var leaving = false
    private var hasSeed: Bool { MontanaSeed.hasSeed }
    // The library and its sliding container read exactly the same width, including after rotation.
    static func width(of container: CGFloat) -> CGFloat { round(container * 0.78) }
    private var apps: [MTApplication] { MTApplication.allCases }
    private var pins: Set<MTApplication> {
        Set(savedPins.split(separator: ",").compactMap { MTApplication(rawValue: String($0)) })
    }
    private var catalogueKey: [String] {
        [savedPins, MTLanguage.locale.identifier] + apps.map { $0.rawValue + $0.title }
    }
    private func leave(then action: @escaping () -> Void = {}) {
        guard !leaving else { return }
        leaving = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { ui.drawerOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
    }
    private func perform(_ app: MTApplication, _ command: MTLibraryCommand) {
        switch command {
        case .open: open(app)
        case .pin:
            var next = pins
            if next.contains(app) { next.remove(app) } else { next.insert(app) }
            savedPins = MTApplication.allCases.filter { next.contains($0) }.map(\.rawValue).joined(separator: ",")
        }
    }
    private func open(_ app: MTApplication) {
        leave {
            switch app {
            case .chess: ui.chessPage = MTChessOpen()
            case .wallet: ui.walletPage = MTPageFlag(id: "wallet")
            case .passwords: ui.passwordsPage = MTPageFlag(id: "passwords")
            case .contacts: ui.pane = .contacts
            case .calls: ui.pane = .calls
            case .feed: ui.pane = .feed
            case .chats: ui.pane = .chats
            case .groups: ui.pane = .groups
            case .channels: ui.pane = .channels
            case .music: ui.askMusic()
            case .gallery: ui.askGallery()
            case .meshWall: ui.pane = .mesh
            case .p2pWall: ui.pane = .p2p
            case .card: ui.overlayPage = .card
            case .settings: ui.settingsShown = true
            }
        }
    }
    /// THE FACES AT THE HEAD OF THE DRAWER (the second identity checklist): the person seated when a seed is held, every
    /// person on the shelf, and the plus that opens the first screen from zero -- one more person beside those that stand.
    @ViewBuilder private func montanaFace() -> some View {
        let name = selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        Button {
            leave { ui.profileShown = true }
        } label: {
            MTDrawerFace(picture: MTSelfFace(size: 48),
                         name: name, ring: true, count: 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Montana"))
    }
    /// A person of Montana on this phone's shelf (the second identity checklist, stage 5): the name and the face the seat
    /// kept when it was parked; the touch moves the seat (MTSeats.switchTo), the move shows itself.
    private func parkedFace(_ s: MTSeats.Seat) -> some View {
        Button {
            leave { seats.switchTo(s.id) }
        } label: {
            MTDrawerFace(picture: AvatarCircle(photoURL: nil, color: .black, initial: s.glyph, size: 48, image: MTSeats.face(s.id)),
                         name: s.name, ring: false, count: 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: s.name.isEmpty ? "Montana" : s.name))   // USER-DATA: the person's own name, or the app's
    }
    private var plusFace: some View {
        Button {
            leave { ui.overlayPage = .birth }
        } label: {
            MTDrawerFace(picture: ZStack {
                Circle().fill(Color.white.opacity(0.08))
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 24)).foregroundColor(.white)
            }.frame(width: 48, height: 48), name: "", ring: false, count: 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Choose how to sign in"))
    }
    private var faces: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                if hasSeed { montanaFace() }
                ForEach(seats.parked) { parkedFace($0) }
                plusFace
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    private var version: some View {
        Text(verbatim: AppVersion.full) // USER-DATA: the build's own number
            .font(.caption2).foregroundColor(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
    }
    /// THE DRAWER AS IT STOOD ON 1949 (the author's word 29.09: «make it a list as it was on build 1949 -- the same style of the
    /// words, they simply scroll; take the library's fields and its search off the top for now; this view by default, a list,
    /// and a smooth scroll with no border»): the faces, then every application as a row -- the glyph, the bold word, the
    /// count -- in one scroll view of the platform's, «Settings» and the build's number at its foot. The icons' grid stays a
    /// choice, made in Settings, Appearance, Application icons (MTLibraryIconStyleView).
    var body: some View {
        GeometryReader { g in
            let full = g.size.width + g.safeAreaInsets.leading + g.safeAreaInsets.trailing
            let width = max(0, Self.width(of: full) - g.safeAreaInsets.leading)
            if icons {
                VStack(spacing: 8) {
                    faces.zIndex(1)
                    MTLibrarySearch(sections: sections, indexed: false, icons: true,
                                    columns: max(1, Int((width - 16) / 104)),
                                    pins: pins, badges: badges, select: open, command: perform,
                                    header: AnyView(EmptyView()), footer: AnyView(version))
                }
                .padding(.top, 8)
                .frame(width: width)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    column
                        .frame(width: width, alignment: .leading)
                        .frame(minHeight: g.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .montanaPageGround(still: true)
        .onChange(of: catalogueKey, initial: true) { _, _ in
            sections = MTLibrarySection.ordered(apps: apps, query: "", searching: false, pins: pins)
        }
        .onChange(of: ui.drawerOpen) { _, value in if value { leaving = false } }
    }
    private var badges: [MTApplication: Int] {
        Dictionary(uniqueKeysWithValues: apps.map { ($0, $0.badge(in: store)) })
    }
    /// The 1949 column: the faces at the head, the rows, «Settings» pressed to the foot with the build's number under it.
    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            faces.padding(.horizontal, 8).padding(.top, 8)   // the faces' own 16 and 8 more: the face over the glyphs' column, 24 from the edge
            VStack(alignment: .leading, spacing: 0) {
                ForEach(apps.filter { $0 != .settings }) { row($0) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            Spacer()
            row(.settings).padding(.horizontal, 24)
            Text(verbatim: AppVersion.full)   // USER-DATA: the build's own number
                .font(.caption2).foregroundColor(.gray)
                .padding(.leading, 24 + 52)   // the row's glyph column and its gap: the number starts under the word
                .padding(.bottom, 8)
        }
    }
    /// A row of the 1949 list: the application's icon in 30 points (the author's word 29.09: every row wears the Montana OS
    /// set at one size), the word in 22 bold, the page's own count; the whole row answers.
    /// The library's own renderer draws it, so the style chosen in Appearance holds in the drawer as in the library.
    private func row(_ app: MTApplication) -> some View {
        Button { open(app) } label: {
            HStack(spacing: 22) {
                MTApplicationIcon(app: app, side: 30)
                Text(app.title).font(.system(size: 22, weight: .bold)).foregroundColor(.white).lineLimit(1)
                MTCountBadge(badges[app] ?? 0)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MTLibraryHeading: View {
    let content: AnyView
    var body: some View { content }
}

/// The search field has one stable host outside reusable cells, so a result reload keeps its focus.
private final class MTLibraryTable: UITableView {
    private let heading: UIHostingController<AnyView>
    private var headingNeedsSize = true
    private var headingWidth: CGFloat = 0
    init(header: AnyView) {
        heading = MontanaHost.make(MTLibraryHeading(content: header))
        super.init(frame: .zero, style: .grouped)
        heading.view.backgroundColor = .clear
        tableHeaderView = heading.view
        alwaysBounceVertical = true
        clipsToBounds = false
        sectionHeaderTopPadding = 0
        contentInsetAdjustmentBehavior = .never
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateHeading(_ content: AnyView) {
        MontanaHost.reroot(heading, MTLibraryHeading(content: content), why: "library-heading")
        headingNeedsSize = true
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, headingNeedsSize || headingWidth != bounds.width else { return }
        headingNeedsSize = false
        headingWidth = bounds.width
        let height = ceil(heading.sizeThatFits(in: CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)
        let size = CGSize(width: bounds.width, height: height)
        if heading.view.frame.size != size {
            heading.view.frame = CGRect(origin: .zero, size: size)
            tableHeaderView = heading.view
        }
    }
}

/// The table extends to the window edges, with the same edge wash as the chat lists.
/// Only its insets change; no measured geometry is published back into the page's layout.
private final class MTLibraryFrame: UIView {
    let table: MTLibraryTable
    private var over: CGFloat = 0
    private let fade = CAGradientLayer()
    init(table: MTLibraryTable) {
        self.table = table
        super.init(frame: .zero)
        clipsToBounds = false
        table.clipsToBounds = true
        table.mtHideEdgeEffects()
        addSubview(table)
        layer.mask = fade
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
    override var center: CGPoint { didSet { if center != oldValue { setNeedsLayout() } } }
    override var frame: CGRect { didSet { if frame.origin != oldValue.origin { setNeedsLayout() } } }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1 else { return }
        let own = table.contentOffset.y + over
        let top = window.map { max(0, -convert(CGPoint(x: 0, y: $0.bounds.minY), from: $0).y) } ?? 0
        let bottom = window.map { max(0, convert(CGPoint(x: 0, y: $0.bounds.maxY), from: $0).y - bounds.maxY) } ?? 0
        let rect = CGRect(x: 0, y: -top, width: bounds.width, height: bounds.height + top + bottom)
        if table.frame != rect { table.frame = rect }
        over = top
        let insets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        if table.contentInset != insets {
            table.contentInset = insets
            table.verticalScrollIndicatorInsets = insets
        }
        if abs(table.contentOffset.y - (own - top)) > 0.5 { table.contentOffset.y = own - top }
        let stops = MTChatListFrame.fadeStops(height: rect.height, top: top, bottom: top + bounds.height, up: true, down: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = rect
        fade.locations = stops.map { NSNumber(value: Double($0.at)) }
        fade.colors = stops.map { UIColor(white: 0, alpha: $0.alpha).cgColor }
        CATransaction.commit()
    }
}

/// The platform owns alphabetical sections, the index rail, scrolling and row selection.
private struct MTLibrarySearch: UIViewRepresentable {
    let sections: [MTLibrarySection]
    let indexed: Bool
    let icons: Bool
    let columns: Int
    let pins: Set<MTApplication>
    let badges: [MTApplication: Int]
    let select: (MTApplication) -> Void
    let command: (MTApplication, MTLibraryCommand) -> Void
    let header: AnyView
    let footer: AnyView
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MTLibraryFrame {
        let table = MTLibraryTable(header: header)
        table.backgroundColor = .clear
        table.overrideUserInterfaceStyle = .dark
        table.keyboardDismissMode = .onDrag
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 80
        table.sectionIndexColor = .white
        table.sectionIndexBackgroundColor = .clear
        table.separatorInset = UIEdgeInsets(top: 0, left: 88, bottom: 0, right: 16)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.register(UITableViewCell.self, forCellReuseIdentifier: "app")
        return MTLibraryFrame(table: table)
    }
    func updateUIView(_ frame: MTLibraryFrame, context: Context) {
        frame.table.updateHeading(header)
        context.coordinator.update(self, table: frame.table)
    }
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: MTLibrarySearch
        private var signature: [String] = []
        init(_ parent: MTLibrarySearch) { self.parent = parent }
        private func section(_ index: Int) -> MTLibrarySection? {
            return parent.sections.indices.contains(index) ? parent.sections[index] : nil
        }
        private func app(at indexPath: IndexPath) -> MTApplication? {
            guard !parent.icons, let section = section(indexPath.section), section.apps.indices.contains(indexPath.row) else { return nil }
            return section.apps[indexPath.row]
        }
        func update(_ next: MTLibrarySearch, table: UITableView) {
            parent = next
            var key: [String] = [String(next.indexed), String(next.icons), String(next.columns), MTLanguage.locale.identifier]
            for section in next.sections {
                key.append(section.id)
                key.append(section.title)
                for app in section.apps {
                    key.append(app.rawValue)
                    key.append(app.title)
                    key.append(String(next.badges[app] ?? 0))
                    key.append(String(next.pins.contains(app)))
                }
            }
            guard key != signature else { return }
            signature = key
            if next.sections.isEmpty {
                let empty = UILabel()
                empty.text = String(localized: "No results", bundle: MTLanguage.bundle)
                empty.textColor = .secondaryLabel
                empty.textAlignment = .center
                empty.font = .preferredFont(forTextStyle: .body)
                empty.adjustsFontForContentSizeCategory = true
                table.backgroundView = empty
            } else { table.backgroundView = nil }
            table.reloadData()
        }
        func numberOfSections(in tableView: UITableView) -> Int { parent.sections.count + 1 }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            guard let group = self.section(section) else { return 1 }
            return parent.icons ? (group.apps.count + parent.columns - 1) / parent.columns : group.apps.count
        }
        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { self.section(section)?.title }
        func sectionIndexTitles(for tableView: UITableView) -> [String]? { parent.indexed ? parent.sections.map(\.title) : nil }
        func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
            (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = .white
        }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "app", for: indexPath)
            cell.backgroundColor = .clear
            guard let group = section(indexPath.section) else {
                cell.selectionStyle = .none
                cell.separatorInset = UIEdgeInsets(top: 0, left: tableView.bounds.width, bottom: 0, right: 0)
                let footer = parent.footer
                cell.contentConfiguration = UIHostingConfiguration { footer }.margins(.all, 0)
                return cell
            }
            if parent.icons {
                cell.selectionStyle = .none
                cell.separatorInset = UIEdgeInsets(top: 0, left: tableView.bounds.width, bottom: 0, right: 0)
                let columns = parent.columns
                let apps = Array(group.apps.dropFirst(indexPath.row * columns).prefix(columns))
                let pins = parent.pins, badges = parent.badges
                let select = parent.select, command = parent.command
                cell.contentConfiguration = UIHostingConfiguration {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(0..<columns, id: \.self) { column in
                            if apps.indices.contains(column) {
                                let app = apps[column]
                                MTLibraryTile(app: app, pinned: pins.contains(app), count: badges[app] ?? 0,
                                              select: { select(app) }, command: { command(app, $0) })
                            } else { Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                    .padding(.vertical, 8)
                }.margins(.horizontal, 16)
                return cell
            }
            guard let app = app(at: indexPath) else { return cell }
            cell.selectionStyle = .default
            cell.separatorInset = UIEdgeInsets(top: 0, left: 88, bottom: 0, right: 16)
            let count = parent.badges[app] ?? 0
            let pinned = parent.pins.contains(app)
            cell.contentConfiguration = UIHostingConfiguration {
                HStack(spacing: 16) {
                    MTApplicationIcon(app: app, side: 56)
                    Text(app.title).font(.title3).foregroundColor(.white)
                    Spacer(minLength: 0)
                    if pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                    MTCountBadge(count)
                }
                .padding(.vertical, 8)
            }.margins(.horizontal, 16)
            return cell
        }
        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            if let app = app(at: indexPath) { parent.select(app) }
        }
        func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
            guard let app = app(at: indexPath) else { return nil }
            return UIContextMenuConfiguration(identifier: app.rawValue as NSString, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                let pinned = self.parent.pins.contains(app)
                return UIMenu(children: MTLibraryCommand.allCases.map { command in
                    UIAction(title: command.title(pinned: pinned), image: UIImage(systemName: command.glyph(pinned: pinned))) { [weak self] _ in
                        self?.parent.command(app, command)
                    }
                })
            }
        }
    }
}


/// THE DRAWER CONTAINER IS THE PLATFORM'S (the author's word 17.09: «natively, no hand-written
/// physics»): the page and the drawer are two hosted screens; the system's screen-edge pan moves the
/// page by its transform on every touch event — one to one with the finger, held, dragged or
/// flicked — and the release is the system's spring animator carrying the finger's own velocity.
/// Nothing of the page is re-rendered while the finger moves; the SwiftUI state changes at the end.
struct MontanaDrawerHost<Page: View, Drawer: View>: UIViewControllerRepresentable {
    @Environment(UIState.self) private var ui
    let open: Bool   // the state's word, read by the host's parent: a change of it is a change of this value
    let page: Page
    let drawer: Drawer
    func makeUIViewController(context: Context) -> MontanaDrawerController {
        let c = MontanaDrawerController(page: AnyView(page), drawer: AnyView(drawer))
        c.onOpenChanged = { open in if ui.drawerOpen != open { ui.drawerOpen = open } }
        c.onTurn = { s, x, v, w in ui.turnStroke(s, x: x, vx: v, width: w) }
        c.turnAllowed = { ui.tabsMayTurn }
        c.atRowStart = { ui.turnAtRowStart }
        return c
    }
    /// THE HOSTED TREES ARE SET ONCE, NOT ON EVERY PASS OF THE OUTER BODY (the author's word
    /// 22.09: the globe thought before it opened). Handing a host a new root makes it evaluate and
    /// lay out that whole tree again, here and now; this body runs on every change of the UI state and
    /// the store, so one touch on the globe re-laid the whole chat list AND the whole drawer before the
    /// page it asked for could be built -- all in the one run of the loop the touch started. The hosted
    /// trees observe the state and the store themselves and need no handing over -- the same law the
    /// sliding host keeps since 18.09 (MontanaSlideHost.key); this host never got it.
    func updateUIViewController(_ c: MontanaDrawerController, context: Context) {
        c.setOpen(open)
    }
}

final class MontanaDrawerController: UIViewController, UIGestureRecognizerDelegate {
    let pageHost: UIHostingController<AnyView>
    let drawerHost: UIHostingController<AnyView>
    private let dim = UIView()
    private var isOpen = false
    private var drawerDragging = false
    private var animator: UIViewPropertyAnimator?
    var onOpenChanged: ((Bool) -> Void)?
    var onTurn: ((UIGestureRecognizer.State, CGFloat, CGFloat, CGFloat) -> Void)?   // the stroke: its state, translation, velocity, the page's width
    var turnAllowed: (() -> Bool)?                 // the state's word: nothing over the tabs, nothing held by the page
    var atRowStart: (() -> Bool)?                  // the state's word: the pane is the first of the row (a stroke to the right there is the drawer's)
    private var strokeIsDrawer: Bool? = nil        // whose the tabs' stroke is -- the drawer's or the pages' -- decided at its first move
    private var width: CGFloat { MontanaSideDrawer.width(of: view.bounds.width) }   // the drawer's own rule, one owner
    init(page: AnyView, drawer: AnyView) {
        pageHost = MontanaHost.make(page)
        drawerHost = MontanaHost.make(drawer)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("no coder") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        for h in [drawerHost, pageHost] {
            addChild(h)
            h.view.frame = view.bounds
            h.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            h.view.backgroundColor = .clear
            view.addSubview(h.view)
            h.didMove(toParent: self)
        }
        // Closed, the library ignores the chat keyboard. Open, its own search owns the keyboard room.
        drawerHost.safeAreaRegions = [.container]
        pageHost.view.layer.cornerCurve = .continuous
        dim.backgroundColor = .black; dim.alpha = 0; dim.isHidden = true
        dim.frame = view.bounds; dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageHost.view.addSubview(dim)
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(pan(_:)))
        edge.edges = .left; edge.delegate = self
        view.addGestureRecognizer(edge)
        dim.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapClose)))
        // THE TABS TURN UNDER THE FINGER (the author's word 24.09: «from any screen, swipes move between the time
        // panel's tabs — super carefully, nothing of the compound gestures inside the page may break; the reference
        // does it, on the chats tab too: the turn from the page's centre, a chat's own swipe a little from the edge,
        // along the chat»). The reference's own arbitration, its behaviour ported (MTTabPan): a pan that OWNS THE
        // CENTRE of the page and leaves its edge zones — a sixth of the width, 22 to 80 points — to the rows' own
        // swipes and to the drawer's edge; every other pan of the page waits for it to fail (shouldBeRequiredToFailBy
        // below), and it fails at once on a vertical stroke, on a touch in an edge zone, over a view that owns its
        // horizontal (the call pill, a sideways strip) and whenever the page holds (turnAllowed). Every event of the
        // stroke goes to the state (UIState.turnStroke): the pages follow the finger there and settle at the release.
        let tabs = MTTabPan(target: self, action: #selector(turn(_:)))
        tabs.allowed = { [weak self] in
            guard let self, !self.isOpen else { return false }
            return self.turnAllowed?() ?? false
        }
        tabs.delegate = self
        view.addGestureRecognizer(tabs)
    }
    @objc private func turn(_ g: MTTabPan) {
        let x = g.translation(in: view).x, v = g.velocity(in: view).x
        // THE ROW'S LEFT END OPENS THE DRAWER (the author's word 25.09: «a swipe past the contacts opens the side panel»): on
        // the first page of the row a stroke to the right is the drawer's -- the finger drags the page aside as the edge pan
        // does, with the same spring at the release -- instead of the pages' rubber band. The way is read once, at the
        // stroke's start (the tabs' pan begins after its first flat points, so the translation already says the way), and
        // kept for the whole stroke; the tabs see nothing of it.
        let over = g.state == .ended || g.state == .cancelled || g.state == .failed
        if g.state == .began { strokeIsDrawer = nil }
        var first = false
        if strokeIsDrawer == nil, x != 0 { strokeIsDrawer = x > 0 && (atRowStart?() ?? false); first = true }
        switch strokeIsDrawer {
        case true?:
            drag(first ? .began : g.state, x: x, v: v)   // the road's own start at the decision, whatever the pan's state then
            if over { MontanaP2PTrace.mark("drawer", "swipe dx=\(Int(x)) v=\(Int(v)) open=\(isOpen ? 1 : 0)") }   // every move of the drawer is a line
        case false?:
            onTurn?(first ? .began : g.state, x, v, view.bounds.width)   // the pages' stroke begins where the way was read
        case nil:
            if over { onTurn?(g.state, x, v, view.bounds.width) }   // a stroke that never moved: the pages settle where they stand
        }
    }
    /// The edge pan wins over the rows' own swipes and the scroll: THE PANS wait for it to fail — the
    /// platform's own rule for its back gesture; taps and presses wait for nothing (18.09, see the slide host).
    /// THE TABS' PAN OWNS THE CENTRE the same way (24.09, the reference's rule): the rows' swipes and the scroll
    /// wait for it too — and it fails at once wherever the page's own strokes live (MTTabPan). The edge pan waits
    /// for nothing: the tabs' pan is a pan and waits for it.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        (g is UIScreenEdgePanGestureRecognizer || g is MTTabPan) && other is UIPanGestureRecognizer && !(other is UIScreenEdgePanGestureRecognizer)
    }
    /// A SwiftUI gesture of the hosted tree (the music cover's drag, 19.09) is not a pan of the
    /// platform's: it neither waits for the edge pan nor yields to it, and whichever began first
    /// took the touch — the back swipe died on the cover. The edge pan recognises alongside it.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g is UIScreenEdgePanGestureRecognizer && !(other is UIPanGestureRecognizer)
    }
    private func apply(_ x: CGFloat) {
        let w = width, t = max(0, min(w, x))
        pageHost.view.transform = CGAffineTransform(translationX: t, y: 0)
        pageHost.view.layer.cornerRadius = t > 0 ? 34 : 0
        pageHost.view.layer.masksToBounds = t > 0
        dim.isHidden = t <= 0
        dim.alpha = 0.45 * t / w
    }
    @objc private func pan(_ g: UIPanGestureRecognizer) {
        let base: CGFloat = isOpen ? width : 0
        drag(g.state, x: base + g.translation(in: view).x, v: g.velocity(in: view).x)
    }
    /// THE DRAWER UNDER THE FINGER, one road for the edge pan and for the row's left end (25.09): the page slides by the
    /// finger, and at the release the way is read -- a moving finger says the way, a still one the distance.
    private func drag(_ state: UIGestureRecognizer.State, x: CGFloat, v: CGFloat) {
        switch state {
        case .began:
            drawerDragging = true
            MTFrameMeter.shared.moveBegan()   // the drawer under the finger, to the settle's end (25.09)
            animator?.stopAnimation(true); animator = nil
            apply(x)
        case .changed:
            apply(x)
        case .ended, .cancelled, .failed:
            drawerDragging = false
            let open = abs(v) > 300 ? v > 0 : x > width / 2
            settle(open, velocity: v, notify: true)
        default: break
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !drawerDragging, animator?.isRunning != true { apply(isOpen ? width : 0) }
    }
    @objc private func tapClose() { settle(false, velocity: 0, notify: true) }
    private func settle(_ open: Bool, velocity: CGFloat, notify: Bool) {
        if open { pageHost.view.endEditing(true) }
        else { drawerHost.view.endEditing(true) }
        drawerHost.safeAreaRegions = open ? .all : [.container]
        let target: CGFloat = open ? width : 0
        let distance = max(1, abs(target - pageHost.view.transform.tx))
        let spring = UISpringTimingParameters(dampingRatio: 0.9, initialVelocity: CGVector(dx: velocity / distance, dy: 0))
        let a = UIViewPropertyAnimator(duration: 0.35, timingParameters: spring)
        a.addAnimations { self.apply(target) }
        MTFrameMeter.shared.moveBegan()   // idempotent under a finger's stroke; the face's tap and the row begin here (25.09)
        a.addCompletion { _ in MTFrameMeter.shared.moveEnded("drawer:" + (open ? "open" : "close")) }
        a.startAnimation()
        animator = a
        if isOpen != open { isOpen = open; if notify { onOpenChanged?(open) } }
    }
    /// The SwiftUI side asks (the face top left, a row of the drawer): the same spring, no echo back.
    func setOpen(_ open: Bool) {
        guard open != isOpen, isViewLoaded else { return }
        settle(open, velocity: 0, notify: false)
    }
}

/// THE TABS' PAN (the author's word 24.09; the reference's folder pan, its behaviour ported and nothing of its
/// mechanism): it owns the centre of the page and gives way at the edges — a sixth of the width, 22 to 80 points,
/// where the rows' own swipes live and the drawer's edge stands — on a vertical stroke, over a view that owns its
/// horizontal, and whenever the page holds. It validates a stroke as the reference does: flat at once when the
/// first points run flat, down at once when they run down, the dominant way after ten points.
final class MTTabPan: UIPanGestureRecognizer {
    var allowed: () -> Bool = { true }
    private var validated = false
    private var first = CGPoint.zero

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        maximumNumberOfTouches = 1
    }
    override func reset() { super.reset(); validated = false }
    /// The edge zone the rows keep: a sixth of the width, 22 to 80 points (the reference's numbers).
    static func edge(_ width: CGFloat) -> CGFloat { max(22, min(width / 6, 80)) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard allowed(), let t = touches.first, let v = view else { state = .failed; return }
        let p = t.location(in: v), w = v.bounds.width
        if p.x < Self.edge(w) || p.x > w - Self.edge(w) { state = .failed; return }   // the rows' and the drawer's
        if Self.refuses(v.hitTest(p, with: event)) { state = .failed; return }
        super.touchesBegan(touches, with: event)
        first = p
    }
    /// What stands under the touch, up the responder chain -- one walk, the platform's own: a view that owns its
    /// horizontal (the call pill's drag, MTHorizontalOwner; a strip that scrolls sideways), and a page PUSHED over the
    /// tabs inside their own stack (the archive, a person's page from the contacts): the nearest navigation controller
    /// holds more than its root, and the reference turns its folders at the root alone (the critic's pass 24.09: the
    /// archive's rows lost their swipe to a turn of pages nobody saw).
    private static func refuses(_ hit: UIView?) -> Bool {
        var r: UIResponder? = hit
        while let x = r {
            if x is MTHorizontalOwning { return true }
            if let s = x as? UIScrollView, s.contentSize.width > s.bounds.width + 1 { return true }
            if let nav = x as? UINavigationController { return nav.viewControllers.count > 1 }
            r = x.next
        }
        return false
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touches.first, let v = view else { return }
        let p = t.location(in: v)
        let dx = abs(p.x - first.x), dy = abs(p.y - first.y)
        if !validated {
            let total = sqrt(dx * dx + dy * dy)
            if total > 10 {
                if dx >= dy { validated = true } else { state = .failed; return }   // the dominant way after ten points
            } else if dy > 2, dy > dx * 2 {
                state = .failed; return                                              // down at once: the list's
            } else if dx > 2, dy * 2 < dx {
                validated = true                                                     // flat at once: the tabs'
            }
        }
        if validated {
            super.touchesMoved(touches, with: event)
            if state == .possible { state = .began }
        }
    }
}

/// A VIEW THAT OWNS ITS HORIZONTAL (24.09, the reference's own mark on a view): the tabs' pan gives way over it and
/// over everything inside it — the call pill that is dragged where it pleases. THE MARK IS A PROTOCOL (29.09, the mini
/// player's plate): a platform control that is a horizontal by nature (the one slider of the app, MontanaSliderView) wears
/// it too, since it cannot descend from this view.
protocol MTHorizontalOwning: AnyObject {}
class MTHorizontalOwner: UIView, MTHorizontalOwning {}

/// THE PAGE UNDER THE BAR: the chats, one hosted tree, so the drawer host is handed a root once.
struct MTShellPage: View {
    var body: some View {
        let _ = MTFrameMeter.shared.body("shell")   // the page's passes while a motion is measured
        ChatsListView()
    }
}

struct MainTabView: View {
    /// THE QUESTION OF THE COPY WITH CONTACTS (the author's word 08.10.2026 23:2x MSK: «on by default, and a question at the
    /// opening»): asked once, in the platform's own alert, after the system's question of the notifications is settled.
    @State private var keepAsk = false
    // THE TABS DO NOT WATCH THE CALL (22.09): the minimized pill watches it where it is drawn
    // (MTMinimizedCallLayer). Watched from here, every second of a call ran this body -- and this body
    // carries the chat list, the drawer, the open chat and every page over them.
    /// The stale-send sweep runs exactly once per process life: onAppear comes with every
    /// screen appearance, and «nothing is in flight» is true only on the first pass.
    private static var staleSweepDone = false
    init() { MontanaP2PTrace.markOnce("tabs_init") }   // measure: when SwiftUI began building the tabs
    @State private var ui = UIState()
    @StateObject private var store = ChatStore.one()   // one store for every window (ChatStore.one)
    @ObservedObject private var vault = MTPasswordVault.shared   // a secret a correspondent shared, waiting to be saved
    @Environment(\.scenePhase) private var scenePhase
    // tick for sending scheduled messages (check once every 15s, on main)
    private let scheduleTick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        let _ = MTFrameMeter.shared.body("root")   // the page's passes while a motion is measured
        // THE WALLET IS THE ROOT (the author's word 09.10.2026 16:00 MSK: «in the wallet leave only the page of the time coins and
        // the wallet's management; take everything else out, chats and calls among them»): no drawer, no chats, no tabs -- the
        // coins' page, and over it the pages it opens: the settings and one more person.
        MTWalletPage()
        .montanaPage(item: $ui.overlayPage) { p in overlayPageView(p) }
        .montanaPage(item: $ui.passwordsPage) { _ in MTPasswordsPage() }
        .sheet(item: $vault.incoming) { secret in MTSecretSaveSheet(item: secret) }
        // THE DOCUMENT over everything — the whole screen; the edge swipe or the platform's close item.
        .montanaPage(item: $ui.docPage) { d in DocPreview(file: d.id, title: d.name) }
        // THE PLACE over everything: its own bar, its own cross, nothing of the chat above it.
        .montanaPage(item: $ui.placeAsk) { ask in
            MTLocationPicker { c, name, street in mtSendPlace(store, c, name: name, street: street, ask: ask) }
        }
        .montanaPage(item: $ui.placeOpen) { place in MTPlaceView(place: place) }
        .montanaPage(item: $ui.chatWall) { w in MTWallpaperPicker(task: .chat(w.id)) }
        .environment(ui)
        .environmentObject(store)
        // Exit is as instant as entry BY THE SAME MEANS: entry is a state change (overlayChat
        // is set the moment the row is tapped), so exit must ride the state too. onDisappear
        // of the dismissed overlay fires late or never (measured 26.08 22:03: T1 left the
        // chat, its heartbeats kept saying open=1) — the view's teardown is nobody's clock.
        .onChange(of: ui.overlayChat?.id) { _, newId in
            if newId == nil { store.openConv = nil }
        }
        .onChange(of: ui.pane) { old, new in MontanaP2PTrace.mark("tab_switch", "from=\(old) to=\(new)") }   // 15.25: the moment the pane changes, by name
        .onAppear {
            MontanaP2PTrace.mark("tabs_appear")
            // Insurance for when there is no history at all (first launch, empty archive):
            // the main pass lives where history is applied. Once per process — repeated
            // screen appearances would kill a RUNNING send (precedent 20.08 16:43:30).
            if !Self.staleSweepDone {
                Self.staleSweepDone = true
                store.markStaleSendsFailed(coldStart: true)
                // And the node store: chunks of letters the queue does not hold will never ride.
                MontanaDeliveryEngine.shared.sweepNodeOrphansOnLaunch()
            }
            // Cold launch does NOT emit «became active»: the screen appears already active,
            // and all the cleanup hanging on return-from-background never happened. Measured:
            // the app open, 1332 chunks, not a line in the journal. The cleanup is called
            // from here as well; it
            // is idempotent; a second call spoils nothing.
            MontanaHousekeeping.run()
            // THE BIO ON A COLD LAUNCH (24.09): the launch emits no «became active», so the words about myself waited for
            // the first return from the background — after an update that is the whole first session. The sender
            // itself repeats nothing a peer has receipted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { E2E.shared.broadcastAbout() }
            // The coin book too: read off the main thread from here, so the wallet opens on the frame of the touch (04.10 13:04).
            MTLocalCoinLedger.warm()
            askWhatIsUnasked()
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active { MTNotifyAllowed.shared.read("active") }   // the person may have changed it in Settings (06.10)
            if p == .active { MTCoinVault.shared.soon("active", after: 1) }   // the seed's other devices, gathered at the return (04.10)
            if p == .active { Task { await MTTimeChainTip.shared.gather(why: "active") } }   // their tips first, in one round trip (04.10 16:34)
        }
        .onChange(of: scenePhase) { _, p in if p == .active {
            store.retryPendingMedia(); MontanaDeliveryEngine.shared.drainAll()
            MontanaWakePush.fetchBoxKick()   // showed up at the node — collect everything waiting (delivery on appearance)
            store.markStaleSendsFailed(coldStart: false)   // return from background: only the provenly dead
            // Avatar: resend the unsent. Half-downloaded INCOMING faces live in the shared
            // completion store and are retried by retryPendingMedia one line above — there is no second head ([C-1]).
            E2E.shared.broadcastAvatar()
        } }
        .onReceive(NotificationCenter.default.publisher(for: .montanaOpenWallet)) { _ in ui.overlayPage = nil }   // the root itself: a page over it steps aside
        .onReceive(NotificationCenter.default.publisher(for: .montanaAddPerson)) { _ in ui.overlayPage = .birth }
        .onReceive(scheduleTick) { _ in store.fireDueScheduled() }
        .onChange(of: scenePhase) { _, p in   // the system's question answered and the app back: the copy's question follows
            if p == .active, MontanaSeed.hasSeed, !MTKeeping.told {
                MontanaNotifyGate.systemStatus { st in if st != .notDetermined { keepAsk = true } }
            }
        }
        .alert("Keep your copy with your contacts?", isPresented: $keepAsk) {
            Button("Keep") { MTKeeping.shared.answer(keep: true) }
            Button("Not now", role: .cancel) { MTKeeping.shared.answer(keep: false) }
        } message: {
            Text("Your copy is sealed with your 24 words and cut into parts. The people you write to keep the parts around a ring, each part with two of them: they see only its size and when it changes, and cannot open it. With your words on a new phone, the parts come back from them, and each of them gives back the conversation you share.")
        }
    }

    /// The page the slot shows for each name. Hosted screens inherit no environment: the state
    /// objects ride in by hand. A chat opening over a page closes the page (as the settings sheet did).
    @ViewBuilder private func overlayPageView(_ p: UIState.Page) -> some View {
        Group {
            switch p {
            case .settings: SettingsTabView(onClose: { ui.settingsShown = false })
            case .card: MTCardFromDrawer()   // the business card, the drawer's last row (the author's word 28.09)
            case .profile: MTMyPageFromDrawer()   // my page, the one «My profile» opens (the author's word 24.09)
            // ONE MORE PERSON (the second identity checklist, stage 1): the first screen as a page over the tabs; the node and
            // the questions that waited for a person are asked the moment the seed lands, as at a launch.
            case .birth: MTBirthPage {
                ui.overlayPage = nil
                askWhatIsUnasked()
            }
            // THE CROSSED SPEAKER'S PAGE (the author's word 06.10): the very page the menu's settings open, its cross top left.
            case .notifications: NavigationStack {
                NotificationsView()
                    .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaCloseMark { ui.overlayPage = nil } } }
            }
            // THE CROSSED GLYPH OF THE COPY'S PAGE (the author's word 08.10.2026 23:2x MSK): Data and Storage, where the copy with
            // contacts is switched, its cross top left.
            case .keeping: NavigationStack {
                DataStorageView()
                    .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaCloseMark { ui.overlayPage = nil } } }
            }
            }
        }
        .environment(ui).environmentObject(store)
        .onChange(of: ui.overlayChat?.id) { _, id in if id != nil { ui.overlayPage = nil } }
    }

    /// Two questions, one at a time, and each explained in our words before the system asks it.
    ///
    /// The direct link goes first because it is what the app is for; notifications wait for it to
    /// be settled either way. Raised together they explain each other away, and the person answers
    /// both by reflex — which is what happened when the system asked both at launch.
    private func askWhatIsUnasked() {
        guard MontanaSeed.hasSeed else { return }   // nobody is asked anything before they hold an identity
        // The core asks the system for nothing and starts first. Then exactly ONE question,
        // and it is the SYSTEM's own — notifications. Our explanatory pages are gone (the
        // author's word 27.08); the local network is not touched here at all: that prompt
        // belongs to the mesh switch and rises only when a person turns it on.
        MontanaP2PNode.shared.autoStart()
        MTNotifyAllowed.shared.read("entry")   // asks again while the system holds no answer, not once for ever (06.10)
        // The copy with contacts is asked after the system's own question, never beside it (two windows explain each other away).
        guard !MTKeeping.told else { return }
        MontanaNotifyGate.systemStatus { st in if st != .notDetermined { keepAsk = true } }
    }

}

// ── "Contacts" tab ──

struct ContactsTabView: View {
    @Environment(UIState.self) private var ui
    @EnvironmentObject private var store: ChatStore
    // Montana contact: a local address book (the address is the only identifier).
    struct MTContact: Codable, Identifiable, Equatable, Hashable {
        var id: String { ref }
        var firstName: String; var lastName: String
        var ref: String; var name: String
        var addedAt: Double
        // The stored keys stay as older builds wrote them; the fields carry the words of the set.
        enum CodingKeys: String, CodingKey { case firstName, lastName, ref = "address", name = "username", addedAt }
        var fullName: String { lastName.isEmpty ? firstName : "\(firstName) \(lastName)" }

        // ── System address book: the card IS the contact ─────────────────────────
        // The Montana address is written as an e-mail-shaped handle because that is the form the
        // system call machinery matches against its address book. With the card in place the system
        // Recents resolve the name themselves and follow every later rename — including for calls
        // already made, which a name passed at call time never could.
        // The address is a MESSENGER handle, so it lives in the instant-message field: the card then
        // reads «Montana» with the address under it. Writing it as an e-mail and a link showed the
        // same address twice and made the system label our calls «e-mail» / «social profile».
        static let systemService = "Montana"
        private static func matchingCard(_ ref: String, in store: CNContactStore,
                                         keys: [CNKeyDescriptor]) -> CNContact? {
            // Matching goes by @name: there is no address in the system card and cannot be.
            let key = MTNameBook.name( ref)
            guard let containers = try? store.containers(matching: nil) else { return nil }
            for container in containers {
                let pred = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
                guard let cards = try? store.unifiedContacts(matching: pred, keysToFetch: keys) else { continue }
                if let hit = cards.first(where: { card in
                    card.instantMessageAddresses.contains { MTNameBook.name( $0.value.username) == key }
                }) { return hit }
            }
            return nil
        }

        static var syncEnabled: Bool {
            let d = UserDefaults.standard
            return d.object(forKey: "syncContactsToPhone") == nil ? true : d.bool(forKey: "syncContactsToPhone")
        }

        static func upsertSystemCard(_ c: MTContact) {
            // Without a nick there is nothing to write: a private account has no public
            // identifier at all, and substituting the address is forbidden.
            guard syncEnabled, !c.name.isEmpty else { return }
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { ok, _ in
                guard ok else { return }
                let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor,
                                               CNContactFamilyNameKey as CNKeyDescriptor,
                                               CNContactInstantMessageAddressesKey as CNKeyDescriptor]
                // The @name goes into the phone book, not the wallet address: the address is
                // eternal, cannot be changed, and rides into cloud contact sync with the
                // card. A person's public name is the nick — that is what we write.
                let im = CNInstantMessageAddress(username: "@" + c.name, service: systemService)
                let req = CNSaveRequest()
                if let old = matchingCard(c.name, in: store, keys: keys),
                   let m = old.mutableCopy() as? CNMutableContact {
                    m.givenName = c.firstName; m.familyName = c.lastName
                    m.instantMessageAddresses = [CNLabeledValue(label: systemService, value: im)]
                    req.update(m)
                } else {
                    let m = CNMutableContact()
                    m.givenName = c.firstName; m.familyName = c.lastName
                    m.instantMessageAddresses = [CNLabeledValue(label: systemService, value: im)]
                    req.add(m, toContainerWithIdentifier: nil)
                }
                try? store.execute(req)
            }
        }

        /// THE PHONE'S CARDS OUTLIVED A SWEEP (20.09): a name the sweep of 1786 took from the rename book
        /// still stands on the phone's card written by upsertSystemCard; each card of the book that has
        /// a nick asks the phone for its name once and hands it to the one writer.
        static func restoreNamesFromPhone() {
            guard syncEnabled else { return }
            let list = (try? JSONDecoder().decode([MTContact].self, from: Data((MontanaLocalVault.getString("mtContacts") ?? "").utf8))) ?? []
            let carded = list.filter { !$0.name.isEmpty }
            guard !carded.isEmpty else { MontanaP2PTrace.mark("phone_names_restored", "cards=0"); return }
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { ok, _ in
                guard ok else { MontanaP2PTrace.mark("phone_names_restored", "denied"); return }
                let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor,
                                               CNContactFamilyNameKey as CNKeyDescriptor,
                                               CNContactInstantMessageAddressesKey as CNKeyDescriptor]
                var found: [(String, String, String)] = []
                for c in carded {
                    guard MTNameBook.mine(c.ref) == nil, let card = matchingCard(c.name, in: store, keys: keys) else { continue }
                    let g = card.givenName.trimmingCharacters(in: .whitespaces), f = card.familyName.trimmingCharacters(in: .whitespaces)
                    if !(g + f).isEmpty { found.append((c.ref, g, f)) }
                }
                DispatchQueue.main.async {
                    for (ref, g, f) in found {
                        MTNameBook.setManual(conv: ref, first: g, last: f)
                        MTNameBook.syncContact(conv: ref, first: g, last: f)
                    }
                    MontanaP2PTrace.mark("phone_names_restored", "cards=\(carded.count) names=\(found.count)")
                }
            }
        }

        static func deleteSystemCard(ref: String) {
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { ok, _ in
                guard ok else { return }
                let keys: [CNKeyDescriptor] = [CNContactInstantMessageAddressesKey as CNKeyDescriptor]
                guard let card = matchingCard(ref, in: store, keys: keys),
                      let m = card.mutableCopy() as? CNMutableContact else { return }
                let req = CNSaveRequest(); req.delete(m)
                try? store.execute(req)
            }
        }

    }
    private var contactsJSON: String { get { MontanaLocalVault.getString("mtContacts") ?? "" } nonmutating set { MontanaLocalVault.setString("mtContacts", newValue); MTNameBook.invalidateContacts() } }
    /// KEPT IN THE BOOK (the author's word 17.09): a person who came by the permanent link gets a
    /// card of the book at once — the card outlives the chat, so deleting the conversation leaves the
    /// person on this page. The name is the name book's, resolved at display time.
    static func keepInBook(ref: String) {
        var list = (try? JSONDecoder().decode([MTContact].self, from: Data((MontanaLocalVault.getString("mtContacts") ?? "").utf8))) ?? []
        guard !list.contains(where: { $0.ref == ref }) else { return }
        list.append(MTContact(firstName: "", lastName: "", ref: ref, name: "", addedAt: Date().timeIntervalSince1970))
        if let d = try? JSONEncoder().encode(list) {
            MontanaLocalVault.setString("mtContacts", String(data: d, encoding: .utf8) ?? "")
            MTNameBook.invalidateContacts()
        }
        MontanaP2PTrace.mark("book_keep", "ref=\(String(ref.prefix(10))) — by the permanent link")
    }
    /// A ROW OF THE TAB: a person as the chats tab lists them, and the card of the book behind
    /// them when there is one; a card not yet written to stands after the list.
    private struct MTPerson: Identifiable {
        let chat: Chat
        let contact: MTContact?
        var id: String { chat.id }
    }
    /// THE PEOPLE OF THE TAB (the author's word 16.09): the chats tab's people in the chats tab's
    /// order — the one list every screen reads (`ChatStore.listChats`) — then the cards of the
    /// book nobody has written to yet, by name.
    private var people: [MTPerson] { allPeople.filter { !store.archivedContacts.contains($0.chat.convRef) } }
    private var archivedPeople: [MTPerson] { allPeople.filter { store.archivedContacts.contains($0.chat.convRef) } }
    private var allPeople: [MTPerson] {
        let listed = store.listChats().filter { !$0.isGroup && $0.convId != nil }
        let book = contactsList
        var rows = listed.map { c in MTPerson(chat: c, contact: book.first { $0.ref == c.convRef }) }
        var seen = Set(listed.map { $0.convRef })
        var rest = book.filter { !seen.contains($0.ref) }.map { c in
            MTPerson(chat: Chat(name: c.ref, lastMessage: "", time: "", unread: 0, status: "Montana address", convId: c.ref), contact: c)
        }
        seen.formUnion(rest.map { $0.chat.convRef })
        // A PERSON OUTLIVES THE CHAT (1639, the author's word 16.09): deleting a conversation from the
        // chats tab takes its rows, not the person — every correspondence this device still holds a
        // pipe for and knows by name stands here, and «Write» opens the conversation anew. The pipe
        // and the name survive a delete-for-me by construction; only the tab's own delete drops a card.
        for ref in MTPipeBook.all() where !seen.contains(ref) && ref != savedMessagesKey && !MTPipeBook.isDying(ref) {
            guard let n = MTNameBook.known(ref), !n.isEmpty else { continue }
            seen.insert(ref)
            rest.append(MTPerson(chat: Chat(name: ref, lastMessage: "", time: "", unread: 0, status: "Montana address", convId: ref), contact: nil))
        }
        // THE FRESHEST PRESENCE FIRST (the author's word 17.09): a live word stands above every stamp,
        // then the stamps newest first; unknown last, by name.
        // The page's own pins first (the author's word 17.09), then the freshest presence.
        return (rows + rest).sorted { a, b in
            let pa = store.pinnedContacts.contains(a.chat.convRef), pb = store.pinnedContacts.contains(b.chat.convRef)
            if pa != pb { return pa }
            let sa = presenceStamp(a.chat), sb = presenceStamp(b.chat)
            if sa != sb { return sa > sb }
            return store.title(for: a.chat).localizedCaseInsensitiveCompare(store.title(for: b.chat)) == .orderedAscending
        }
    }
    /// The moment behind the presence line: the store's own ladder (presenceWord) as a number.
    private func presenceStamp(_ c: Chat) -> Double {
        let key = c.convRef
        guard let w = store.presenceWord(key) else { return 0 }
        if w.tier > 0 { return Date().timeIntervalSince1970 + Double(w.tier) }
        return store.peerGoneAt[key] != nil ? MontanaSeen.longAgo : (store.peerSeenAt[key] ?? 0)
    }
    /// THE COIN OPENS THE BAR HERE TOO (the author's word 17.09): the pull on the contacts is the
    /// pull on the chats — the same coin, the same refresh road, the same bar unfolding; both
    /// handed in by the page that owns the bar.
    /// THE TIME PANEL (the author's word 17.09): the coin, the bar and the search, written once by
    /// the chats page and handed in — see MontanaTimePanel.
    let panel: MontanaTimePanel
    @State private var openProfile: Chat?
    @State private var deletingChat: Chat?        // the one delete sheet — the chats tab's ([C-1])
    @State private var blockingChat: Chat?        // the one block sheet — the profile's ([C-1])
    @State private var personMenu: Chat?          // the row held: its menu cloud — the chat's own
    @State private var archiveRevealed = false    // the archive row is summoned by a pull-down and folds back, as on the chats
    @State private var showArchived = false
    private var contactsList: [MTContact] {
        (try? JSONDecoder().decode([MTContact].self, from: Data(contactsJSON.utf8))) ?? []
    }
    private func save(_ list: [MTContact]) {
        if let d = try? JSONEncoder().encode(list) { contactsJSON = String(data: d, encoding: .utf8) ?? "" }
        for c in list { MTContact.upsertSystemCard(c) }   // the card in the phone is kept in step
    }
    /// The card of the book goes with the conversation: a deleted person leaves the tab whole.
    private func dropCards(_ refs: Set<String>) {
        guard !refs.isEmpty else { return }
        save(contactsList.filter { !refs.contains($0.ref) })
        for a in refs {
            MTNameBook.setManual(conv: a, first: nil, last: nil)
            MTContact.deleteSystemCard(ref: a)       // removed here = removed from the phone
        }
    }
    /// DELETE — the chats tab's road (ChatStore.deleteChat) and the card with it.
    private func delete(_ chat: Chat, forBoth: Bool) {
        store.deleteChat(chat, forBoth: forBoth)
        dropCards([chat.convRef])
    }
    /// The row's print — the fields of MTChatListView.fieldNames, the ones a contact row draws.
    private func rowPrint(_ c: Chat) -> [Int] {
        func p<T: Hashable>(_ v: T) -> Int { var h = Hasher(); h.combine(v); return h.finalize() }
        return [p(c.name), p(c.order), p(store.title(for: c)), p(store.avatarFor(c) ?? ""),
                p(store.presenceWord(c.convRef)?.text ?? ""), p(""), p(""), p(0), p(false), p(false),
                p(store.pinnedContacts.contains(c.convRef)), p(false), p(false)]
    }
    /// The chats' shared line (28.09), including the anchor for the person menu.
    @ViewBuilder private func cell(_ chat: Chat) -> some View {
        // The presence line under the name, as the search draws it (the author's word 17.09): the
        // store's one presence word, bright when live, quiet when a stamp — never a yellow word (24.09).
        let word = store.presenceWord(chat.convRef)
        HStack(spacing: MTLibraryRow.gap) {
            MTChatAvatar(chat: chat, size: MTLibraryRow.face, showPresence: true)
                .overlay(MontanaHexagon().stroke(Color.white.opacity(0.45), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(MontanaAvatar.spokenName(store.title(for: chat))).font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white).lineLimit(1).truncationMode(.tail)
                Text(word?.text ?? "").font(.system(size: 16))
                    .foregroundColor(.gray)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if store.pinnedContacts.contains(chat.convRef) {
                Image(systemName: "pin.fill").font(.system(size: 12)).foregroundColor(.gray).rotationEffect(.degrees(45))   // pinned here — the chats' pin, one to one
            }
        }
        .frame(height: MTLibraryRow.face)
        .modifier(MTLibraryLine(place: "row:" + chat.id))
    }
    /// THE ONE «WRITE» GLYPH (the author's word 17.09: round, not square) — the menu, the row and the
    /// chats page's compose button draw the same one.
    static let writeGlyph = "square.and.pencil"
    /// «Write» walks the one road a conversation is opened by from outside the chats tab (a link, a
    /// scan): the deletion mark is lifted, the row is born, the chat opens (1639).
    private func write(_ c: Chat) {
        personMenu = nil
        NotificationCenter.default.post(name: .openChatRequest, object: nil, userInfo: ["address": c.convRef])
    }
    /// The deeds of the menu about a person (a hold on the row; a tap opens the profile itself).
    private func deeds(_ c: Chat) -> [MTPersonMenu.Deed] {
        [.init(title: "Write", icon: Self.writeGlyph) { write(c) },
         .init(title: "Profile", icon: "person.crop.circle") { personMenu = nil; openProfile = c },   // the page a tap used to open
         store.archivedContacts.contains(c.convRef)
            ? .init(title: "Unarchive", icon: "tray.and.arrow.up") { personMenu = nil; store.toggleArchiveContact(c.convRef) }
            : .init(title: "Archive", icon: "archivebox") { personMenu = nil; store.toggleArchiveContact(c.convRef) },   // this page's archive
         .init(title: "Delete", icon: "trash", destructive: true) { personMenu = nil; deletingChat = c },
         store.isBlocked(c.name)
            ? .init(title: "Unblock", icon: "hand.raised.fill") { personMenu = nil; store.toggleBlocked(c.name) }
            : .init(title: "Block", icon: "hand.raised", destructive: true) { personMenu = nil; blockingChat = c }]
    }
    /// The swipes (the author's word 17.09): right to left — pin, archive, delete; the pin and the archive are THIS page's own.
    /// NO CALLS ON A SWIPE (the author's word 26.09: «on the contacts tab remove the swipe for the calls to a contact»): the calls
    /// stand in the menu of a hold, and nothing is offered on the other side -- on the tab and in its archive alike.
    private func swipeTrailing(_ c: Chat) -> [SwipeTile] {
        [SwipeTile(icon: store.pinnedContacts.contains(c.convRef) ? "pin.slash.fill" : "pin.fill", color: SwipeTile.glass) { store.togglePinContact(c.convRef) },
         SwipeTile(icon: store.archivedContacts.contains(c.convRef) ? "tray.and.arrow.up.fill" : "archivebox.fill", color: SwipeTile.glass) { store.toggleArchiveContact(c.convRef) },
         SwipeTile(icon: "trash.fill", color: SwipeTile.glass) { deletingChat = c }]
    }
    /// The archive row — the chats page's, one to one: summoned by a pull-down, it opens this page's archive.
    private var archiveRow: some View {
        Button { showArchived = true } label: {
            HStack(spacing: MTLibraryRow.gap) {
                Circle().fill(Color(white: 0.15)).frame(width: MTLibraryRow.face, height: MTLibraryRow.face)
                    .overlay(Image(systemName: "archivebox.fill").font(.system(size: 24)).foregroundColor(.gray))
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Archive").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                    Text(verbatim: String(store.archivedContacts.count)).font(.system(size: 16)).foregroundColor(.gray)   // USER-DATA: a count
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14)).foregroundColor(.gray)
            }
            .modifier(MTLibraryLine())
            .overlay(alignment: .bottom) { MTLibraryHairline() }
            .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
        }
        .buttonStyle(.plain)
    }
    /// The archived people (the author's word 17.09): the same rows on the same container — the
    /// same swipes (the archive tile brings one back), the same menu on a hold, a tap opens the chat.
    private var archivedList: some View {
        ZStack(alignment: .top) {
            MTUnderBarGround()   // the pages' ground: my page's when one is chosen, the crest when none (26.09)
            MTChatListView(rows: archivedPeople.map { $0.chat }, headPrint: 0, fingerprint: rowPrint,
                           swipeLeading: { _ in [] }, swipeTrailing: swipeTrailing, swipesEnabled: true,   // no calls on a swipe (26.09)
                           onOpen: { write($0) },
                           rowContent: { AnyView(cell($0).environmentObject(store).environment(ui)) },
                           headContent: { AnyView(Color.clear.frame(height: 0)) },
                           onPull: { _ in }, onHold: { personMenu = $0 },
                           onRefresh: {}, onSettled: {}, pinTop: false, bottomReserve: 0, separatorRow: { _ in true })
        }
        .navigationTitle("Archive").navigationBarTitleDisplayMode(.inline)   // the chats' archive's bar, one to one
        .overlay { clouds(true) }   // pushed over the page, the archive stands above the page's clouds: it carries them
        .modifier(MTPushedMark(what: "archive"))
    }
    /// The archive row stands while it is summoned, there is an archive and the search does not hold the list — one
    /// condition, read by the column and by the list alike: while it stands the rows stop at the list's top
    /// (MTChatListFrame.headFloats), as on the chats.
    private var archiveShown: Bool { archiveRevealed && !store.archivedContacts.isEmpty && !panel.pinTop }
    var body: some View {
        let _ = MTFrameMeter.shared.body("contacts")   // the page's passes while a motion is measured
        // THE CONTACTS STAND AS THE CHATS AND THE CALLS (the author's word 23.09: «for the contacts too, at once, as the
        // chats and the calls»): the rows run on to the screen's edges by the time panel list's own law, and the ground
        // is the page's one crest. The page's navigation stack of its own is gone: laid over the chats page, it drew a
        // ground of its own over the page's and a second crest centred on the tab — the crest moved at every switch to
        // the contacts, and the rows would have stopped at the stack's edges. The archive and the profile are pushed on
        // the page's own stack now, as the chats' archive is.
        // THE PEOPLE ARE RECKONED ONCE A PASS (28.09): each reckoning unseals the book (MontanaLocalVault), decodes it, walks the
        // chats and the pipes and sorts by presence and name -- and the pass asked for it twice, at every word of the page's
        // state: ten to seventeen times in one turn of the panes on T1 (motion pane:contacts worst_ms=85-98, fires=ui:10-17).
        let shown = people
        VStack(spacing: 0) {
            // Drawn over the rows that run on under it: the order of drawing, as the chats' bar and archive row; it
            // rides in from the top as theirs does.
            if archiveShown {
                archiveRow.zIndex(1)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack(alignment: .top) {
                MontanaTimePanelList(panel: panel, rows: shown.map { $0.chat }, fingerprint: rowPrint,
                                     swipeLeading: { _ in [] }, swipeTrailing: swipeTrailing,   // no calls on a swipe (26.09)
                                     onOpen: { write($0) },               // a tap opens the chat itself (the author's word 17.09)
                                     rowContent: { AnyView(cell($0).environmentObject(store).environment(ui)) },
                                     onPull: { dy in
                                         // As on the chats: a pull-down summons the archive row, a pull-up folds it.
                                         if dy < -25 { withAnimation(.easeInOut(duration: 0.3)) { archiveRevealed = false } }
                                         else if dy > 25, !store.archivedContacts.isEmpty { withAnimation(.easeInOut(duration: 0.3)) { archiveRevealed = true } }
                                     },
                                     onHold: { personMenu = $0 },         // a hold opens the menu about the person
                                     headFloats: archiveShown, page: "contacts",
                                     // The chats' native lines and separators (28.09).
                                     separatorRow: { _ in true })
                if shown.isEmpty {
                    Text("No contacts yet").foregroundColor(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // THE «+», bottom right (the author's word 17.09): the chats page's compose button one to
        // one — the plate, the size, the line between the last two rows — with the plus on it; and, as
        // that button, it steps aside while the search holds the list (its results stand there).
        .mtPageAction(shown: !panel.pinTop) {
            MontanaCardShare {
                Image(systemName: "square.and.arrow.up").font(.system(size: 27, weight: .medium))   // share, the plus's size (the author's word 17.09)
                    .foregroundColor(MontanaOctagon.barGlyph)
            }
            .buttonStyle(.montanaOctagon(square: true, bar: true))
        }
        .navigationDestination(isPresented: $showArchived) { archivedList }
        .navigationDestination(item: $openProfile) { c in MontanaPeerInfoScreen(chat: c).modifier(MTPushedMark(what: "profile")) }
        .overlay { clouds(!showArchived) }
        // THE ARCHIVE'S CLOUDS LEAVE WITH IT (the critic 23.09): swiped back with a menu or a sheet standing over it,
        // the archive left and the cloud rose again over the page, at the place of a row the page does not hold.
        .onChange(of: showArchived) { _, on in if !on { personMenu = nil; deletingChat = nil; blockingChat = nil } }
    }
    /// THE CLOUDS AND SHEETS ABOUT A PERSON, over the rows they are about: over the page, and over its archive while
    /// the archive is pushed — the page's stack draws the archive above the page, so clouds drawn on the page would
    /// stand under it. One writing for both, drawn at one place at a time.
    @ViewBuilder private func clouds(_ here: Bool) -> some View {
        // The menu about a person — the chat's own cloud (MTPersonMenu).
        if here, let c = personMenu {
            MTPersonMenu(chat: c, anchor: MTBubbleFrames.shared.rect("row:" + c.id), deeds: deeds(c), onClose: { personMenu = nil })
        }
        // The one delete sheet — the chats tab's, face and all ([C-1]).
        if here, let c = deletingChat {
            MontanaDeleteChatSheet(
                title: store.title(for: c),
                photoURL: store.avatarFor(c), color: c.color, initial: store.initial(for: c),
                canDeleteForBoth: MontanaConv.holds(c.convRef),
                coinsTravel: store.coinsTravel(c),
                onBoth: { delete(c, forBoth: true); deletingChat = nil },
                onMine: { delete(c, forBoth: false); deletingChat = nil },
                onCancel: { deletingChat = nil })
        }
        // The one block sheet — the profile's ([C-1]).
        if here, let c = blockingChat {
            MontanaBlockSheet(chat: c,
                              onBlock: { store.toggleBlocked(c.name); blockingChat = nil },
                              onCancel: { blockingChat = nil })
        }
    }
}

/// A PAGE PUSHED OVER THE CONTACTS SAYS WHEN IT IS ON THE SCREEN AND WHEN IT LEAVES IT (the critic 23.09). The pages
/// ride the chats page's stack and leave it when the contacts page, which declares them, leaves the tree (a «Write»,
/// a banner): the platform's own rule, and this is its measure — a switch of the tab not followed by «off» is a
/// page left standing in the stack.
private struct MTPushedMark: ViewModifier {
    let what: String
    func body(content: Content) -> some View {
        content
            .onAppear { MontanaP2PTrace.mark("contacts_page", "\(what)=on") }
            .onDisappear { MontanaP2PTrace.mark("contacts_page", "\(what)=off") }
    }
}

// ── "Calls" tab — call log ──
struct CallRecord: Identifiable {
    let mid: String; let peer: String; let video: Bool; let incoming: Bool
    let dur: Int; let missed: Bool; let time: String; let at: Double
    /// A CALL'S NAME IS ITS CONVERSATION AND ITS LETTER (09.10): a letter's name is one within its conversation, not across
    /// them -- the archive names a restored letter by its second, side and text, so a transcript and its live twin hold the
    /// same «arc:» letter, and the list that took the letter's name alone met it twice and died (T1 07:49:41Z, Wallet 10:
    /// «Duplicate identifiers: call:arc:baf0637d…, call:arc:234a31f6…» the moment the Calls page opened).
    var id: String { peer + "/" + mid }
}

// ════════════════════════════════════════════════════════════
// MESSAGE MODEL
// ════════════════════════════════════════════════════════════
// Delivery status of my message.
// sending(clock) → sent(✓) → delivered(✓✓) → read(✓✓ golden)
enum DeliveryStatus: String, Codable { case sending, sent, delivered, read, failed }

/// THE ONE WORD of a letter's state (15.47.1, the author's word 08.09: «a crystal-clean function»):
/// a pure map from the ladder's rung to the word under the last own bubble. The rung itself has
/// one door (ChatStore.advance: forward only, «read» only from «delivered», back only by hand);
/// the word has one map (here); the drawing has one place (MTDeliveryLine).
/// EVERY RUNG CARRIES ITS WORD (the author's word 13.09: the dots and the word are one
/// construction): the map is total. The clock left the bubble on 08.09, so a letter on its way
/// stood under three dim dots with no word at all — the person read the dots and found no line.
extension DeliveryStatus {
    /// The rung of the ladder, one reading for the door (ChatStore.advance), the word and the
    /// dots: 0 — not yet or fallen back, 1 — sent, 2 — delivered, 3 — read.
    var rung: Int {
        switch self {
        case .sending, .failed: return 0
        case .sent: return 1
        case .delivered: return 2
        case .read: return 3
        }
    }
    var word: String {
        switch self {
        case .sending: return "Sending…"
        case .sent: return "Sent"
        case .delivered: return "Delivered"
        case .read: return "Read"
        case .failed: return "Not sent"
        }
    }
}

/// THE RED MARK NEEDS A WORD, NOT A CLOCK (the author's words 07.10.2026 18:4x MSK: «I don't want to see an error if I in fact sent
/// and the other one just did not read it -- let it hang on my device as sent for at least 30 days, not an error, I did send»; «we
/// have a TimeChain: online or in cold storage, what difference -- they must leave; the same for letters; build a guard»). T1's two
/// letters and its one coin to a second account of the same phone stood red -- the first one 26 hours, 2084 tries -- while the node
/// answered 200 to every doorbell that boxed them (wakepush_rdv, nineteen times in ten minutes): thirty seconds of silence painted
/// them red, and the red gave the coin back. A row of mine turns red now only by one of these words -- a keeper's refusal or a thing
/// this phone cannot do -- through ChatStore.putOut, the one door into red; none of them is a span of time, and
/// tools/mt-red-word-check.py freezes the list.
enum MTRefusal: String {
    /// The letter has no road: no conversation key or no pipe secret -- it cannot be sealed for anyone.
    case noRoad = "no road"
    /// The stored queue cannot be read: the letter did not enter it, and nothing will carry it.
    case notQueued = "not queued"
    /// Nothing carries the row: no queued letter and no living upload stands behind it.
    case nothingCarries = "nothing carries it"
    /// The node said the letter's cargo is gone.
    case cargoGone = "the node lost the cargo"
    /// The card a first letter knocks at was spent by another: the node's gravestone, said twice.
    case cardSpent = "the card is spent"
    /// The file the letter carries cannot be read or kept on this phone.
    case fileUnreadable = "the file cannot be read"
    /// The person stopped the send by hand.
    case byHand = "stopped by hand"
    /// The room's radio cannot carry a file this size.
    case pastTheRadio = "past the radio's measure"
    /// No member of the group could be handed a copy.
    case nobodyToCarry = "nobody to carry to"
    /// A copy of a group letter was refused by one of the words above.
    case copyRefused = "a copy was refused"
    /// The carriage ended (MontanaDeliveryEngine.carryDays) and no node ever took the letter: it never left this phone -- a fact of
    /// this phone, not the receiver's silence; a letter the node took ends its carriage as «sent».
    case neverLeft = "never left this phone"
}

/// THE MONTANA ROOM (the author's word 29.09): the room without an address where Montana itself speaks -- a new build in
/// TestFlight, what changed, the button to update. The key is English and is not translated; the crown beside the name
/// and the logo for a face are the room's dress (MTMontanaCrownMark, MTChatAvatar).
let montanaRoomKey = "Montana"
/// NO BANNER WHILE A PERSON PLAYS (the author's words 03.10: «Apple's notifications during the games and the minting fully off;
/// only in the ordinary mode; in the games nowhere»). A game is what the screen shows: the open chat's own Money Flow or a chess
/// board. Only the banner judge asks, and the system asks the judge only while the app stands in front, so a phone in the
/// background or locked rings every letter. A fact kept in the shared keychain read «a flow is on in some chat» for the extension
/// too: it stood for days and held 4 479 banners of the fleet on 04.10 (the author's word 23:46: «notifications come only when
/// Montana is opened»).
enum MTPlayQuiet {
    static var held: Bool { MTMoneyFlow.isOn(ChatStore.openConvNow ?? "") || MTChessGameScreen.shownGame != nil }
}
/// THE ROOM'S NAME ON THE SCREEN AND IN ITS BANNER (the author's word 03.10: «Montana with the crown emoji in front»): the one
/// name a crown stands before by right -- every person's name loses a typed or sent crown (MTCrown).
let montanaRoomTitle = "\u{1F451} " + montanaRoomKey
/// THE ROOM'S FACE IS THE APP'S ICON (the author's word 03.10: «the icon of the Montana updates chat as our app's icon»): the
/// glass icon of the first screen, in the list, the chat's head and the banner alike.
let montanaRoomFace = "IconGlassPreview"
/// THE MESH WALL (the author's word 29.09: «the common mesh chat, pinned at the very top of the chats; everyone on the mesh is in it
/// at once; it is called the Mesh wall and appears the moment the switch of visibility on the mesh is on»): the room of
/// everyone on the mesh -- no address, no pipe; its words ride the radio (MTMeshRoom). The key is English and never translated.
let meshRoomKey = "Mesh wall"   // COMPAT-LOCAL: a key of this device's list, never a word on the wire

// The audio session for media playback. The app NEVER configured it, so the system default
// mode applied — and that one is muted by the ring/silent switch: video and voice played
// silently though the file's track is there.
// During a call the session is untouched: the call has its own mode (playAndRecord/voiceChat),
// and overriding it would break the conversation's audio routing.
enum MontanaAudioSession {
    /// THE ONE RECORDING SESSION: a voice tape and a video note record through the same door — THE
    /// REFERENCE'S ROAD (read 22.09 in ManagedAudioSession / ManagedAudioRecorder: the record type takes
    /// the plain mode and a raw RemoteIO microphone; no voice processing on a tape). The voice-chat mode
    /// was measured on 1855 (T1, voice_rec stop peak=49 mean=29 thousandths): the platform's level
    /// control held a twenty-second tape at −26 dBFS — a quiet tape. The plain microphone at its own
    /// level, the loudspeaker beside it, a headset when one is connected, the input gain at the top where
    /// the device lets it be set (the author's word 22.09: loud and clean, the voice and the note alike).
    /// Written here once; nobody else sets a recording category.
    ///
    /// A NOTE KEEPS THE MUSIC PLAYING (the author's word 24.09: «when I record a round note and music plays, it must
    /// not stop, and everything must record well»). A recording session that does not mix stops every other app's
    /// sound the moment it wakes; one that mixes lets it play on. A headset's call road (HFP) would keep the music
    /// too -- as a telephone, in one narrow channel, and the note's sound with it; so while music plays the headset
    /// keeps its full road (A2DP) and the note hears through the phone's own microphone at its full rate. With no
    /// music the tape keeps its road as it was: the headset's microphone when one is connected.
    @discardableResult
    static func record(_ what: String, keepMusic: Bool = false) -> Bool {
        precondition(!Thread.isMainThread, "Recording activation belongs to the recorder's worker queue")
        // MAIN-SAFE-SYNC: both recorders enter on their worker queues; the precondition rejects the main thread.
        return ledger.sync {
        holders[what] = true
        let s = AVAudioSession.sharedInstance()
        let opts: AVAudioSession.CategoryOptions = keepMusic ? [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]
                                                             : [.defaultToSpeaker, .allowBluetooth]
        let mode = mtAudioTry(what + " recording mode") { try s.setCategory(.playAndRecord, mode: .default, options: opts) }
        let active = mode && mtAudioTry("activating the audio session for " + what) { try s.setActive(true) }
        if s.isInputGainSettable { mtAudioTry("input gain") { try s.setInputGain(1.0) } }
        if keepMusic { MontanaP2PTrace.mark("vnote_music", "the music plays on: the session mixes, a headset keeps its full road") }
        return active
        }
    }
    /// Music is playing now: another app's, or a track of our own (a voice message is a word, not music).
    static var musicPlays: Bool {
        if AVAudioSession.sharedInstance().isOtherAudioPlaying { return true }
        let v = VoicePlayer.shared
        return v.playingFile != nil && !v.paused && !v.isVoice
    }
    static func activatePlayback() {
        ledger.async {
            guard !holders.values.contains(true) else { return }
            activatePlaybackLocked()
        }
    }
    @discardableResult
    private static func activatePlaybackLocked() -> Bool {
        let s = AVAudioSession.sharedInstance()
        let mode = mtAudioTry("video playback mode") { try s.setCategory(.playback, mode: .moviePlayback, options: []) }
        mtAudioTry("dropping the post-call earpiece route") { try s.overrideOutputAudioPort(.none) }
        return mode && mtAudioTry("activating the audio session for video") { try s.setActive(true, options: []) }
    }

    /// A track of our own: the playback mode and the movie session.
    static func playMusic(then: @escaping (Bool) -> Void) {
        ledger.async {
            guard !holders.contains(where: { $0.key != "play" && $0.value }) else {
                DispatchQueue.main.async { then(false) }; return
            }
            holders["play"] = false
            let ready = activatePlaybackLocked()
            DispatchQueue.main.async { then(ready) }
        }
    }
    /// A voice message: plain playback on a headset, a speaker or a car; the ear and the loudspeaker on the phone alone.
    static func playVoice(external: Bool, then: @escaping (Bool) -> Void) {
        ledger.async {
        guard !holders.contains(where: { $0.key != "play" && $0.value }) else {
            DispatchQueue.main.async { then(false) }; return
        }
        holders["play"] = !external
        let s = AVAudioSession.sharedInstance()
        let mode: Bool
        if external {
            mode = mtAudioTry("voice playback mode (external output)") { try s.setCategory(.playback, mode: .default, options: []) }
        } else {
            mode = mtAudioTry("voice playback mode") { try s.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP]) }
        }
        let ready = mode && mtAudioTry("activating the audio session for playback") { try s.setActive(true) }
        DispatchQueue.main.async { then(ready) }
        }
    }
    /// A CLIP WITHOUT SOUND TAKES NOTHING FROM ANYBODY (the feed's playing tiles, 25.09): while nothing of ours sounds, the
    /// session mixes with every other app's — a person's own music goes on under a feed of playing videos. A call or a
    /// track of ours holds the session as it does; a silent clip under them changes nothing.
    static func playSilentClip() {
        guard VoicePlayer.shared.playingFile == nil else { return }
        ledger.async {
        guard holders.isEmpty else { return }
        let s = AVAudioSession.sharedInstance()
        mtAudioTry("a silent clip: mixing with the others") { try s.setCategory(.ambient, mode: .moviePlayback, options: [.mixWithOthers]) }
        }
    }
    /// A paused track or voice goes on THROUGH ITS KIND'S OWN DOOR (26.09): a tape or a voice between the pause and the resume left
    /// the sound in their own mode -- the recording's, the ear's -- and waking the session as it stood played the music into a
    /// headset's call road; the door its kind first played through opens it again.
    static func wake(voice: Bool, external: Bool, then: @escaping (Bool) -> Void) {
        if voice { playVoice(external: external, then: then) } else { playMusic(then: then) }
    }
    /// A playing voice at the ear or on the loudspeaker, as the proximity sensor says.
    static func routeVoice(near: Bool) {
        ledger.async {
        guard holders["play"] == true,
              !holders.contains(where: { $0.key != "play" && $0.value }) else { return }
        mtAudioTry(near ? "routing the voice to the ear" : "routing the voice to the loudspeaker") {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(near ? .none : .speaker)
        }
        }
    }

    // -- THE SOUND HAS HOLDERS, AND THE LAST ONE CLOSES THE MICROPHONE ROAD (28.09) --
    // The author's word 28.09: «I recorded a voice message and sent it -- in the car, connected over Bluetooth --
    // and the minutes keep running; the same after a call». A hands-free car shows a CALL for exactly as long as a
    // session in the playAndRecord category stands. This app raised that session at every tape, every note and every
    // voice at the ear -- and lowered it never; the background audio mode then kept it alive after the app folded, so
    // the car counted the talk until the process died.
    // THE REFERENCE'S ROAD (read 28.09, the reference implementation's audio session manager: `holders`, `updateHolders`, `applyNoneDelayed`,
    // and `applyNone` -- setActive(false, [.notifyOthersOnDeactivation]), overrideOutputAudioPort(.none),
    // setPreferredInput(nil), one repeat after a pause): the session's users are HOLDERS. Every door that opens the
    // microphone road takes a NAMED hold in the same call that opens it -- a road cannot be opened past the ledger
    // ([C-1]) -- and the last such hold to go closes the road in that same moment: the category returns to plain
    // playback (the car's call ends with it), and when nothing of ours sounds the session is lowered with the word
    // that lets every other app go on.
    private static let ledger = DispatchQueue(label: "montana.audio.ledger")
    private static var holders: [String: Bool] = [:]   // the door's name -- and whether it opened the microphone road
    /// The door is done with the sound. Whether anything of ours still sounds is asked HERE, on the caller's own
    /// thread, of the owners themselves -- one question at one moment, never a patrol over somebody else's objects.
    static func release(_ who: String) {
        let stillSounds = !quiet
        ledger.async {
            guard holders.removeValue(forKey: who) != nil else { return }
            let micLeft = holders.values.contains(true)
            MontanaP2PTrace.mark("audio_hold", "let go \(who) held=\(holders.isEmpty ? "-" : holders.keys.sorted().joined(separator: "+")) sounds=\(stillSounds ? 1 : 0)")
            guard !micLeft else { return }
            closeMicRoad(lower: holders.isEmpty && !stillSounds)
        }
    }
    private static func closeMicRoad(lower wholly: Bool) {
        let s = AVAudioSession.sharedInstance()
        // THE SESSION IS LOWERED FIRST, THE CATEGORY SET AFTER. A NOTE KEEPS THE MUSIC PLAYING (the author's word
        // 24.09), which the recording session does by mixing; a category change on a LIVE session that mixes would
        // cut that music dead, where lowering it with «notify others» is the very word that lets it go on.
        if wholly { lowerSession(again: true) }
        mtAudioTry("closing the microphone road") { try s.setCategory(.playback, mode: .default, options: []) }
        mtAudioTry("dropping the route override") { try s.overrideOutputAudioPort(.none) }
        mtAudioTry("letting the input go") { try s.setPreferredInput(nil) }
        if !wholly { MontanaP2PTrace.mark("audio_hold", "the road is closed; the session stays -- something of ours sounds") }
    }
    /// Nothing of ours sounds -- asked of the owners: the player in hand, the video in the dock.
    private static var quiet: Bool {
        (VoicePlayer.shared.playingFile == nil || VoicePlayer.shared.paused)
            && MontanaVideoDock.shared.file == nil
    }
    private static func lowerSession(again: Bool) {
        let ok = mtAudioTry("lowering the session") {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        MontanaP2PTrace.mark("audio_hold", "session " + (ok ? "down" : "refused"))
        guard !ok, again else { return }
        // A session whose input is still winding down answers «busy»: the reference waits and asks once more.
        ledger.asyncAfter(deadline: .now() + 2) {
            guard holders.isEmpty else { return }
            lowerSession(again: false)
        }
    }
}

/// THE SCREEN STAYS AWAKE WHILE THE APP HAS ITS HANDS FULL (the author's word 18.09): a voice tape,
/// a video note, a video recorded through the app, a call, the scanner's camera — every such work
/// holds the screen by its name, and the system's idle timer is off while anyone holds it. One door
/// ([C-1]): nobody else touches the idle timer. A holder that forgets to let go is named in the diary.
enum MontanaScreenAwake {
    private static var holders = Set<String>()
    static func hold(_ who: String) { DispatchQueue.main.async { holders.insert(who); apply() } }
    static func release(_ who: String) { DispatchQueue.main.async { holders.remove(who); apply() } }
    private static func apply() {
        let on = !holders.isEmpty
        guard UIApplication.shared.isIdleTimerDisabled != on else { return }
        UIApplication.shared.isIdleTimerDisabled = on
        MontanaP2PTrace.mark("screen_awake", on ? "on " + holders.sorted().joined(separator: ",") : "off")
    }
}

// The «already transcoded by our encoder» mark. THE NAME GIVEN AT BIRTH NEVER CHANGES (the critic
// 22.09): the mark used to live in the name itself (.mov becoming _mtc.mp4), and that rename bit three
// times (20.08 the sweep put out a living send, 29.08 the ring died, 22.09 the send refused itself)
// -- every mirror keyed by the file broke at the boundary, and «the one rename point» had to know
// them all. The transcoded bytes now sit under the name the letter was born with (the player and the
// poster read the container, not the suffix -- measured), and the mark is a file beside the poster.
// The suffix stays readable: the round note is born with it, and rows of the older builds wear it.
enum MontanaVideoMark {
    static let suffix = "_mtc"
    private static func markURL(_ name: String) -> URL { MontanaPictures.url(name + ".mtc") }
    static func isCompressed(_ name: String) -> Bool {
        (name as NSString).deletingPathExtension.hasSuffix(suffix) || marked(name)
    }
    static func marked(_ name: String) -> Bool { FileManager.default.fileExists(atPath: markURL(name).path) }
    static func mark(_ name: String) { try? Data().write(to: markURL(name)) }
    static func unmark(_ name: String) { try? FileManager.default.removeItem(at: markURL(name)) }
}

// The current connection type — so autodownload obeys the «Data and Storage» setting.
// A standing observer, not an on-the-spot check: the channel type changes on the go.
final class MontanaNet {
    static let shared = MontanaNet()
    private let monitor = NWPathMonitor()
    private(set) var isCellular = false
    /// THE FAMILIES THIS PHONE ACTUALLY HAS. A road of a family the phone does not hold is not a
    /// slow road — it is a wall, and every packet sent at it burns its whole retransmission budget
    /// before anything else is tried (13.09: twenty of a call's twenty-four seconds went into two
    /// IPv6 addresses of our own relay on a cellular network that had no IPv6 at all).
    private(set) var hasV4 = true
    private(set) var hasV6 = false
    private init() {
        monitor.pathUpdateHandler = { [weak self] p in
            self?.isCellular = p.usesInterfaceType(.cellular)
            self?.hasV4 = p.supportsIPv4
            self?.hasV6 = p.supportsIPv6
        }
        monitor.start(queue: DispatchQueue(label: "montana.net.path"))
    }
    /// A relay address of a family this phone does not hold is dropped before the media engine ever
    /// sees it. A relay named by NAME is left alone: a name is resolved by the system, which knows
    /// what it can reach — only a literal address can be judged here, and only a literal address
    /// can be handed to the engine as a wall.
    func reachableRelay(_ urls: [String]) -> [String] {
        urls.filter { u in
            guard let hostPart = u.split(separator: ":").dropFirst().first.map(String.init) else { return true }
            if u.contains("[") {   // «turn:[2a03:...]:3478» — a literal IPv6
                return hasV6
            }
            let host = hostPart.split(separator: "?").first.map(String.init) ?? hostPart
            let literalV4 = host.split(separator: ".").count == 4
                && host.split(separator: ".").allSatisfy { Int($0) != nil }
            return literalV4 ? hasV4 : true
        }
    }
    var autoDownloadAllowed: Bool {
        let d = UserDefaults.standard
        let key = isCellular ? "autoDownloadCellular" : "autoDownloadWiFi"
        return d.object(forKey: key) == nil ? true : d.bool(forKey: key)   // on by default
    }
}

// The media send queue: one attachment per peer at a time. The reference achieves the same
// with one predicate — «is there an unfinished upload ahead of me» — which yields both order
// in the correspondence and a memory bound without a separate counter. Without the queue two
// videos start compressing and uploading at once, and the system kills the app over memory.

// A SEND DOES NOT DIE OF A SHORT TRIP TO BACKGROUND. Three times on 20.08 the process was
// killed by the system at second 10-13 of video compression, each time 1-2s after going
// background: compression holds memory, and a background process is not forgiven for it. The
// background-time request lives exactly as long as the work does and retires itself; the
// system limit's expiry is marked in the trace, not swallowed.
// Stage 8.4: a compression killed by the background window is not a failure — it is work
// waiting for the next foreground moment. The expiry hook flags the file; the send flow
// registers a resume; scenePhase.active runs it. The .piece intent stays on disk throughout,
// so nothing turns red and nothing is lost — «deliver, not blush» (the author's word).
// One FILE — one living encode, and the encode has an OWNER able to kill it. The previous
// guard was keyed by the letter and killed nothing: a red retry re-minted the letter, the
// key changed, and encode number two of the same file queued behind the first; deleting the
// letter cleaned files and registrations while the LIVING task kept the encoder gate (trace
// 23.08: a START with no END, later STARTs of the same file with no send_dup, durations
// never shrinking). The attachment name is stable across re-mints — a retry JOINS the
// living job — and cancel(letter:) reaches the task itself, which compress() now honours.
final class MTEncodeRegistry {
    static let shared = MTEncodeRegistry()
    private struct Entry { let letter: String; var task: Task<Void, Never>? }
    private var live: [String: Entry] = [:]
    private let lock = NSLock()
    func begin(file: String, letter: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if live[file] != nil { return false }
        live[file] = Entry(letter: letter, task: nil)
        return true
    }
    func adopt(file: String, task: Task<Void, Never>) {
        lock.lock(); if live[file] != nil { live[file]?.task = task }; lock.unlock()
    }
    func end(file: String) { lock.lock(); live.removeValue(forKey: file); lock.unlock() }
    func cancel(letter mid: String) {
        lock.lock()
        let hits = live.filter { $0.value.letter == mid }
        lock.unlock()
        for (file, e) in hits {
            e.task?.cancel()
            MontanaP2PTrace.mark("encode_owner", "cancelled with the letter \(mid.prefix(8)) file=\(file.prefix(24))")
            try? FileManager.default.removeItem(
                at: FileManager.default.temporaryDirectory.appendingPathComponent("mt-seg-\(file)"))
        }
    }
}

final class MTCompressResume {
    static let shared = MTCompressResume()
    private var pending: [String: () -> Void] = [:]
    private var flagged = Set<String>()
    private let lock = NSLock()
    func flag(_ key: String) { lock.lock(); flagged.insert(key); lock.unlock() }
    func isFlagged(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return flagged.contains(key) }
    func register(_ key: String, _ run: @escaping () -> Void) {
        lock.lock(); pending[key] = run; flagged.remove(key); lock.unlock()
        MontanaP2PTrace.mark("compress_resume", "queued \(key.prefix(24)) — continues on next open")
    }
    func runAll() {
        lock.lock(); let jobs = pending; pending = [:]; lock.unlock()
        for (k, run) in jobs { MontanaP2PTrace.mark("compress_resume", "re-run \(k.prefix(24))"); run() }
    }
    // The letter died (delivered, deleted by hand, dropped) — its resume dies with it. Without
    // this a ghost job resurrected on every foreground, monopolised the encoder gate, and every
    // fresh video queued behind it forever (precedent 23.08 23:07: «frozen on the word»).
    func cancel(letter mid: String) {
        lock.lock()
        let had = pending.removeValue(forKey: mid) != nil
        flagged.remove(mid)
        lock.unlock()
        if had { MontanaP2PTrace.mark("compress_resume", "cancelled with the letter \(mid.prefix(8))") }
        // The segment dir is keyed by FILE and owned by MTEncodeRegistry.cancel now.
    }
}

final class MTSendAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid
    // Stage 8.3: the moment the system window expires is the moment the remaining work is
    // handed to the background upload session — the expiry hook is where that handoff fires.
    var onExpire: (() -> Void)?
    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MontanaP2PTrace.mark("bg_expired", "system background window expired: \(name)")
            self?.onExpire?()
            self?.end()
        }
    }
    func end() {
        if id != .invalid { UIApplication.shared.endBackgroundTask(id); id = .invalid }
    }
    deinit { end() }
}

// A small holder for passing a value between parallel tasks.
final class MTBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ v: T) { stored = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// The invisible marker a call signal carries: a letter that is not shown, and the only
/// thing that tells the two apart on arrival.
let callSignalMark = "\u{2063}mtcall:"
let convDelMark = "\u{2063}mtconvdel:"

/// A letter owed a receipt: ordinary words and attachments, but not service marks — those
/// need no receipt, the action itself shows them.
func isDurableInbound(_ text: String) -> Bool {
    // The tombstone («delete for both») is durable: its receipt settles the sender's queue and
    // buries their dying pipe. Without the receipt the pipe would live out the letter's term.
    !text.hasPrefix(callSignalMark) && !text.hasPrefix(draftSignalMark)
        && !text.hasPrefix(deliveryReceiptMark)
}

let draftSignalMark = "\u{2063}mtdraft:"

/// A media row as the archive keeps it (15.10.4): kind, the file's name in the correspondence
/// store, the document's name, the caption, the voice's length. Sorted keys — one byte shape.
struct ArchivedMedia: Codable {
    let k: String; let f: String; let n: String?; let cap: String?; let d: Double?
}

/// THE ONE NAME OF A LETTER (15.52.9, the author's word 08.09): «mid:t<ms>-uuid», minted at
/// birth for every row — a letter, a note to oneself, a call record — and never a second one.
/// The row's identity on screen, the name on the wire, the target of a quote, a pin, a receipt:
/// one string. A local UUID beside it used to be a second truth, and every place that looked a
/// row up by the other name was a shadow waiting to happen.
typealias MID = String

struct Message: Identifiable, Codable {
    var mid: MID
    var id: MID { mid }
    var legacyId: String? = nil        // read from an old history only: the pre-15.52.9 local UUID, resolved once at load
    var legacyReplyTo: String? = nil   // read from an old history only: a quote by that old UUID
    var text: String
    let isFromMe: Bool
    let time: String
    var reactions: [String] = []     // emoji reactions under the message (multiple allowed)
    // WHOSE REACTION IS WHOSE. The wire says only "add this emoji" / "drop this emoji", as it
    // always has, and old builds keep speaking it unchanged. These two live on this device only,
    // so a person may hold ONE answer at a time: a new one replaces his previous, and the peer's
    // replaces the peer's. Optional by design — a letter stored before them decodes as having none.
    var myReact: String? = nil
    var peerReact: String? = nil
    var replyText: String? = nil     // text of the message being replied to
    var isRead: Bool = false         // whether it is read (for the check marks)
    var imageFile: String? = nil     // photo file name (for image messages)
    var videoFile: String? = nil     // video file name (for video messages)
    var audioFile: String? = nil     // voice message file name
    var audioDuration: Double = 0    // voice message duration, sec
    var docFile: String? = nil       // document file name on disk
    var docName: String? = nil       // original document name (for display)
    var deliveryStatus: DeliveryStatus = .sent   // delivery stage (for my messages)
    /// THE MOMENT OF THE RUNG (the author's word 11.09): when the letter reached the stage it
    /// stands on — written in the one door (ChatStore.advance) and nowhere else; 0 = born there.
    var statusAt: Double = 0
    var statusMoment: Double { statusAt > 0 ? statusAt : createdAt }
    var edited: Bool = false         // whether the message was edited
    /// The wire spelling of the same name — read everywhere the envelope is handled. Never nil.
    var msgId: String? { get { mid } set { if let v = newValue, !v.isEmpty { mid = v } } }
    var senderRef: String? = nil      // Montana address of the sender
    var createdAt: Double = 0        // creation time (sec, Unix) — for date separators
    var replyToId: MID? = nil        // the quoted letter, by its one name
    var transport: String? = nil     // P2P transport (MontanaTransport rawValue) — glyph left of the time
    var linkPreview: String? = nil   // link preview card (MTLinkPreview json) under the text
    var fwdFrom: String? = nil       // the chat a forward came from — local only; Saved Messages groups by it (15.51)
    /// A FORWARDED LETTER, of any kind (the author's word 16.09): stored with the row, carried in
    /// a media manifest as «fw», and — for older readers of a text letter — as the quote below.
    var forwarded: Bool = false
    /// A MEDIA GROUP (19.09): pictures and videos picked together travel as separate letters that
    /// share one key; the feed folds the neighbours with one key into one plate and puts the one
    /// caption under it. The key, the place inside the group and the group's size are the sender's
    /// word, carried in the manifest as «gk / gi / gn»; a build that does not know them draws the
    /// letters one by one and the caption once. Absent = a letter on its own.
    var groupKey: String? = nil
    var groupIndex: Int = 0
    var groupCount: Int = 0
    /// A LONG LETTER WHOSE WORDS NEVER CAME (the author's word 25.09: «do not try to fetch what is not there, and do not ask
    /// again once it is known to be absent»): every door answered «no such cargo» until the verdict held, or the letter
    /// outlived the box's term. Local only: the row says so, and its reference is never asked for again.
    var lost: Bool = false
    /// PLAYED (25.09): a voice or a round note — of mine, played by the correspondent (their «played» word came); of theirs,
    /// played here and said to them once.
    var heard: Bool = false
    /// The wire spelling every build understands: a text forward rides with this quote; a
    /// reader that knows the mark draws the mark and never the quote.
    static let forwardedQuote = "↪︎ Forwarded message"
    /// THE ONE ANSWER «is this a forward» ([C-1]): the field, the local source, or the wire quote.
    var isForwarded: Bool { forwarded || fwdFrom != nil || replyText == Message.forwardedQuote }

    init(text: String, isFromMe: Bool, time: String, reactions: [String] = [],
         replyText: String? = nil, isRead: Bool = false, imageFile: String? = nil,
         videoFile: String? = nil, audioFile: String? = nil, audioDuration: Double = 0,
         docFile: String? = nil, docName: String? = nil,
         deliveryStatus: DeliveryStatus = .sent, edited: Bool = false,
         msgId: String? = nil, senderRef: String? = nil,
         createdAt: Double = Date().timeIntervalSince1970, replyToId: MID? = nil, transport: String? = nil,
         fwdFrom: String? = nil, forwarded: Bool = false) {
        self.mid = msgId ?? ("mid:" + ChatStore.mintMid().mid)
        self.text = text; self.isFromMe = isFromMe; self.time = time
        self.reactions = reactions; self.replyText = replyText
        self.isRead = isRead; self.imageFile = imageFile
        self.videoFile = videoFile
        self.audioFile = audioFile; self.audioDuration = audioDuration
        self.docFile = docFile; self.docName = docName
        self.deliveryStatus = deliveryStatus; self.edited = edited
        self.senderRef = senderRef
        self.createdAt = createdAt
        self.replyToId = replyToId
        self.transport = transport
        self.fwdFrom = fwdFrom
        self.forwarded = forwarded
    }

    // safe reading of saved messages (new fields may be absent)
    enum CodingKeys: String, CodingKey { case id, text, isFromMe, time, reactions, replyText, isRead, imageFile, videoFile, audioFile, audioDuration, docFile, docName, deliveryStatus, edited, msgId, senderRef = "senderAddress", createdAt, replyToId, transport, linkPreview, statusAt, forwarded, groupKey, groupIndex, groupCount, myReact, peerReact, lost, heard }
    init(from c0: Decoder) throws {
        let c = try c0.container(keyedBy: CodingKeys.self)
        legacyId = (try? c.decode(UUID.self, forKey: .id))?.uuidString
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        isFromMe = (try? c.decode(Bool.self, forKey: .isFromMe)) ?? false
        time = (try? c.decode(String.self, forKey: .time)) ?? ""
        reactions = (try? c.decode([String].self, forKey: .reactions)) ?? []
        replyText = try? c.decode(String.self, forKey: .replyText)
        isRead = (try? c.decode(Bool.self, forKey: .isRead)) ?? false
        imageFile = try? c.decode(String.self, forKey: .imageFile)
        videoFile = try? c.decode(String.self, forKey: .videoFile)
        audioFile = try? c.decode(String.self, forKey: .audioFile)
        audioDuration = (try? c.decode(Double.self, forKey: .audioDuration)) ?? 0
        docFile = try? c.decode(String.self, forKey: .docFile)
        docName = try? c.decode(String.self, forKey: .docName)
        // old messages without status: treat as read if isRead, otherwise as sent
        deliveryStatus = (try? c.decode(DeliveryStatus.self, forKey: .deliveryStatus)) ?? (isRead ? .read : .sent)
        edited = (try? c.decode(Bool.self, forKey: .edited)) ?? false
        statusAt = (try? c.decode(Double.self, forKey: .statusAt)) ?? 0
        mid = (try? c.decode(String.self, forKey: .msgId)) ?? ("mid:" + ChatStore.mintMid().mid)   // an old nameless row gets its name here, once
        senderRef = try? c.decode(String.self, forKey: .senderRef)
        createdAt = (try? c.decode(Double.self, forKey: .createdAt)) ?? Date().timeIntervalSince1970
        if let r = try? c.decode(String.self, forKey: .replyToId) { replyToId = r }
        else { legacyReplyTo = (try? c.decode(UUID.self, forKey: .replyToId))?.uuidString }
        transport = try? c.decode(String.self, forKey: .transport)
        linkPreview = try? c.decode(String.self, forKey: .linkPreview)
        forwarded = (try? c.decode(Bool.self, forKey: .forwarded)) ?? false
        groupKey = try? c.decode(String.self, forKey: .groupKey)
        groupIndex = (try? c.decode(Int.self, forKey: .groupIndex)) ?? 0
        groupCount = (try? c.decode(Int.self, forKey: .groupCount)) ?? 0
        // WHOSE ANSWER SURVIVES THE RELOAD (the author's word 20.09: «after re-entering, my reaction
        // was marked as the correspondent's»): the names were kept in memory only and every reload
        // lost them — a nameless plate could only be drawn as somebody else's. Absent = a letter
        // stored before the names, and an older reader of the store skips the keys.
        myReact = try? c.decode(String.self, forKey: .myReact)
        peerReact = try? c.decode(String.self, forKey: .peerReact)
        lost = (try? c.decode(Bool.self, forKey: .lost)) ?? false
        heard = (try? c.decode(Bool.self, forKey: .heard)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text); try c.encode(isFromMe, forKey: .isFromMe); try c.encode(time, forKey: .time)
        try c.encode(reactions, forKey: .reactions); try c.encodeIfPresent(replyText, forKey: .replyText)
        try c.encode(isRead, forKey: .isRead); try c.encodeIfPresent(imageFile, forKey: .imageFile)
        try c.encodeIfPresent(videoFile, forKey: .videoFile); try c.encodeIfPresent(audioFile, forKey: .audioFile)
        try c.encode(audioDuration, forKey: .audioDuration); try c.encodeIfPresent(docFile, forKey: .docFile)
        try c.encodeIfPresent(docName, forKey: .docName); try c.encode(deliveryStatus, forKey: .deliveryStatus)
        try c.encode(edited, forKey: .edited); try c.encode(mid, forKey: .msgId)
        try c.encodeIfPresent(senderRef, forKey: .senderRef); try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(replyToId, forKey: .replyToId); try c.encodeIfPresent(transport, forKey: .transport)
        try c.encodeIfPresent(linkPreview, forKey: .linkPreview); try c.encode(statusAt, forKey: .statusAt)
        if forwarded { try c.encode(forwarded, forKey: .forwarded) }   // absent = false: older readers of the store see no new key on their own rows
        try c.encodeIfPresent(myReact, forKey: .myReact); try c.encodeIfPresent(peerReact, forKey: .peerReact)
        if lost { try c.encode(lost, forKey: .lost) }   // absent = false: older readers of the store see no new key
        if heard { try c.encode(heard, forKey: .heard) }
        if let groupKey {   // absent = a letter on its own; older readers of the store skip the keys
            try c.encode(groupKey, forKey: .groupKey)
            try c.encode(groupIndex, forKey: .groupIndex)
            try c.encode(groupCount, forKey: .groupCount)
        }
    }

    // «Is this my message» — determined by the sender (senderRef).
    // Reliable across devices: on someone else's phone the same message
    // has a different senderRef → it goes on the left. If there's no senderRef (old/demo) —
    // we fall back to the isFromMe flag.
    /// A letter is mine because this device wrote it. It used to be decided by comparing a string
    /// inside the letter against a string about me — which required a public name for a person to
    /// exist, and none does. An envelope names no sender now, so there is nothing to compare and
    /// nothing to get wrong.
    var isMine: Bool { isFromMe }
}

// ════════════════════════════════════════════════════════════
// CHAT MODEL (one row in the conversation list)
// ════════════════════════════════════════════════════════════
struct Chat: Identifiable, Codable, Equatable, Hashable {
    /// WHO THIS ROW IS - the address of the conversation, the same key the pins, the read marks
    /// and the order are kept by.
    ///
    /// It used to be a `UUID` minted afresh inside every decode of the stored list. The list is
    /// reread whenever it changes from elsewhere, so to the renderer a reread was never "the same
    /// rows in another order": it was a full replacement of every row. Nothing kept its identity,
    /// so nothing could move - everything was redrawn. Identity is a meaning, not a number handed
    /// out at birth, and with a meaning a reread becomes an ordinary difference of two lists.
    var id: String { convId ?? name }
    /// WHERE THIS ROW STANDS - filled at list build from the one owner of order
    /// (`ChatStore.orderSeq`), and deliberately absent from the stored form: a saved copy of a
    /// derived value always wins the first frame and always shows the past.
    var order: Int = 0
    var name: String          // the contact's name / chat title
    let lastMessage: String   // last message (preview)
    let time: String          // time of the last message
    let unread: Int           // number of unread
    var status: String = ""   // label for the header (groups/labels); presence is NEVER stored here
    var photoURL: String? = nil             // photo avatar (temporary)
    var isGroup: Bool = false               // group/channel?
    var isAdmin: Bool = false               // am I the creator/admin?
    var members: [String] = []              // members (for a group)
    var convId: String? = nil             // Montana address this conversation belongs to
    var displayName: String? = nil          // name (rename); we don't touch the name key
    var lastName: String? = nil             // last name
    var note: String? = nil                 // note about the contact

    // A STORAGE LABEL, not a person's name: the attachment folder is named by it and renames
    // migrate by it, so it has no right to change because the peer renamed themselves. The
    // ON-SCREEN name is asked of `ChatStore.title(for:)` ([C-1]).
    var title: String {
        let f = (displayName ?? "").trimmingCharacters(in: .whitespaces)
        let l = (lastName ?? "").trimmingCharacters(in: .whitespaces)
        let full = (f + " " + l).trimmingCharacters(in: .whitespaces)
        if full.isEmpty && name == savedMessagesKey { return String(localized: "Saved Messages", bundle: MTLanguage.bundle) }
        if full.isEmpty && name == montanaRoomKey { return montanaRoomTitle }   // a name, not a word: the app's own
        if full.isEmpty && name == meshRoomKey { return String(localized: "Mesh wall", bundle: MTLanguage.bundle) }
        // No name yet, and there is nothing else to fall back to: the key of a correspondence is
        // not a name of a person and is never shown as one. A neutral caption says exactly what is
        // known — somebody is there, and they have not said who.
        return full.isEmpty ? String(localized: "Correspondent", bundle: MTLanguage.bundle) : full
    }

    // first letter of the name — for the avatar
    var initial: String { String(title.prefix(1)).uppercased() }

    var convRef: String { convId ?? name }
    var isMontanaChat: Bool { convId != nil }

    // avatar color — deterministic from the name (FNV-1a, stable across launches and in the extension)
    var color: Color {
        Color(montanaHexString: MontanaAvatar.colorHex(name))
    }

    // The stored form, named out loud: identity is computed and order is derived, so neither is
    // written down. Everything else is exactly what the file already holds.
    enum CodingKeys: String, CodingKey {
        case name, lastMessage, time, unread, status, photoURL, isGroup, isAdmin
        case members, convId, displayName, lastName, note
    }
}

// found message (for global search): in which chat and which one. Its identity is the letter's own name in its
// conversation, not a UUID minted at every pass: a list keyed by fresh ids could never diff and rebuilt every row
// of the results on every key (T1, 16:04Z, build 1949 -- three deaths on screen).
struct MessageHit: Identifiable {
    var id: String { chat.id + "/" + message.mid }
    let chat: Chat
    let message: Message
}

// ════════════════════════════════════════════════════════════
// A SINGLE MESSAGE BUBBLE
// ════════════════════════════════════════════════════════════
// Stickers are transmitted as plain text with a HIDDEN (invisible) marker — we don't touch the E2E protocol.
// In the chat list/preview it just shows the emoji (the marker is not visible).
let stickerMark = "\u{2063}\u{2063}"
let readReceiptMark = "\u{200B}\u{2063}"   // hidden "read" marker (sent over E2E as text)
let deliveryReceiptMark = "\u{200B}\u{2064}"   // hidden "delivered" receipt (+ message mid)
let voiceMark = "\u{200B}\u{200B}VC:"      // voice message inside the message (base64 m4a) — sent over E2E
// mediaMark (photo/video/document letter mark) lives in MontanaMediaKit — one owner ([C-1])
let reactionMark = "\u{200B}\u{200B}RC:"   // reaction to the peer's message — synced over E2E
let typingMark = "\u{200B}\u{200B}TY:"     // "typing…" signal — over E2E, not shown as a message
let watchMark = "\u{200B}\u{200B}WA:"     // live-chat presence: "1" = this chat is open on the peer's screen, "0" = left
let appMark = "\u{200B}\u{200B}AP:"       // app-level presence: "1" = the app is on the peer's screen, "0" = left it
let avatarMark = "\u{200B}\u{200B}AV:"      // user avatar (base64 jpeg) — over E2E, the server does not see it
let nameMark = "\u{200B}\u{200B}NM:"        // user display name — over E2E, exchanged exactly like the avatar
// THE PERSON'S OWN WORDS ABOUT THEMSELVES, AS STATE (24.09): JSON {b,l,at} — the bio, the link and the moment. It rides
// exactly like the name: one silent letter of kind «about» in the one queue, receipted by the peer, and only the receipt
// writes the «announced» mark. The bio used to ride the draft word with the mark written before the send and no receipt
// back: a peer that missed that one word never saw it again until the person edited it. An older build buries the
// unknown word unread ([P2P-COMPAT]); the draft word's «ab/al» keys still ride for 1919-1921 until they die out.
let aboutMark = "\u{200B}\u{200B}AB:"
// MY PAGE'S GROUND, AS STATE (25.09, the author's word: «from T3 I opened T1's page and see no background»): JSON {g, at} —
// "" none, "n:" + a drawn ground's name, "p:" + the picture as JPEG — riding exactly like «about»: one silent letter of kind
// «ground», receipted, sent only to a peer whose presence word speaks the «G» tag; every older build buries it unread.
let groundMark = "\u{200B}\u{200B}PG:"   // COMPAT-GATED: only to a peer proven to read it (E2E.groundCapable)
let ringMark = "\u{200B}\u{200B}RG:"        // a call AS A LETTER: the whole guaranteed letter road summons the callee
// The peer's @username — by the same conveyor as the name and the photo. Without it a nick is
// learned only on a by-name introduction, and whoever wrote first stays nickless forever.
let cardMark = "\u{200B}\u{200B}QC:"        // the card of MY queue for THIS peer — over E2E, mutual (checklist B-5/C-7)
let deleteMark = "\u{200B}\u{200B}DL:"      // delete message for everyone (payload = serverId) — over E2E
// A LETTER'S WORDS CHANGE ON BOTH SCREENS. The edit used to live on the editor's phone alone: one
// person read one text, their correspondent another, and nothing on either screen said so. JSON
// {sid,tx} — the letter's own wire name and its new words; it rides the ONE delivery road, silent.
let editMark = "\u{200B}\u{200B}ED:"      // the new words of a letter already sent — over E2E, never a row
// A LETTER PINNED FOR BOTH (the author's word 22.09): JSON {sid,txt,op} — the letter's wire name (its
// words as the fallback) and «pin» / «unpin». It rides the one delivery road SILENT: an older build
// buries the unknown word unread ([P2P-COMPAT]); the new build pins the same letter and tells the person.
let pinMark = "\u{200B}\u{200B}PN:"
let draftMark = "\u{200B}\u{200B}DF:"       // peer's unsent draft checkpoint (durable layer of live typing) — JSON {ep,tx}
let callMark = "\u{200B}\u{200B}CL:"        // call log entry (local, each side logs its own) — JSON {v,inc,dur,miss}
let releaseMark = "\u{200B}\u{200B}RL:"     // a new build's word in the Montana room (local, 29.09) — JSON {b,v,n,u}
let missedCallMark = "\u{200B}\u{200B}MC:"  // missed-call letter (guaranteed leg) — JSON {v,s}; lands as a call row, never rings
let wakeHandleMark = "\u{200B}\u{200B}WH:"    // peer's wake-handle for the notifications server — rides ONLY inside the pipe, never shown
// THE LETTER'S CARGO IS GONE FOR GOOD, AND THE SENDER MUST LEARN IT. The receiver says this
// exactly when the node is ALIVE and honestly answered «no» — knowledge, not a guess. Without
// this signal the sender forever resends a letter whose cargo no longer exists, and a person
// waits for a file that will never come (precedent 24.08: the node store torn down by hand).
let cargoLostMark = "\u{200B}\u{200B}CG:"    // payload = the name of the letter whose cargo is lost
// A VOICE OR A ROUND NOTE WAS PLAYED (the author's word 25.09: «Listened instead of Read, only upon the actual playing»):
// the listener's phone tells the sender once, silently; payload = the letter's wire name. An older build buries the unknown
// service word unread ([P2P-COMPAT]); never a row.
let playedMark = "\u{200B}\u{200B}PL:"
/// The external punch-through address: «here is where to hit to reach me directly». Rides
/// ONLY inside the pipe, lives minutes (on cellular the address changes tower to tower) and
/// never enters the feed.
let punchEndpointMark = "\u{200B}\u{200B}PA:"    // peer's wake-handle for the notifications server — rides ONLY inside the pipe, never shown
// THE DOOR WORD OF THE VPN-NODES FEATURE, removed by the author's word 30.09: no build of this line sends it; an older
// build that still names its exit is buried unread by this token, never shown ([P2P-COMPAT]).
let exitDoorMark = "\u{200B}\u{200B}EX:"
// ONE PERSON, ONE CONVERSATION (24.09, the author's word «do it»; MTSamePair): right after a meeting by card the scanner asks
// over the NEW pipe whether the two phones already share an older one — JSON {"t": [hex…]}: a fixed count of tags, each the
// first 16 bytes of SHA-256("mt-same-ask", 0, an older secret, the new secret), filled with noise — and the card's owner,
// holding one of them too, answers with a proof only a holder can make — JSON {"p": hex}, the same over "mt-same-yes". Both
// fold the new conversation into the older one. An older build buries both words unread ([P2P-COMPAT]).
let sameAskMark = "\u{200B}\u{200B}SM:"
let sameYesMark = "\u{200B}\u{200B}SY:"
// THE PIPE CLOSED AT THE OTHER END (24.09, the author's word «do it»): the orphan sweep buries a pipe that has no
// conversation here and no life for three days, and says so to the other side over that very pipe instead of vanishing:
// the other side's history stays readable and its composer gives way to a note. An older build buries the word unread
// ([P2P-COMPAT]) and the pipe dies by the word's term, as by a tombstone's.
let pipeClosedMark = "\u{200B}\u{200B}PX:"
// THE COPY KEPT BY THE PEOPLE ONE WRITES TO (the author's word 08.10.2026 20:3x, MTKeeping; Network «A copy kept by the people one
// speaks with»): one word, JSON with «w» -- a question, a yes, a part, a keeper's «held», a release -- riding the correspondence,
// and a call and its answer riding the pipe of a slot. Never a row; an older build buries it unread.
let keepMark = "\u{200B}\u{200B}KP:"
/// The words a pipe is buried with: the tombstone of «delete for both» and the orphan sweep's closing word. Each rides
/// past the conversation's death, and its receipt — or its term — buries the pipe.
func isBurialWord(_ text: String) -> Bool { text.hasPrefix(convDelMark) || text.hasPrefix(pipeClosedMark) }
// [P2P-COMPAT] The complete vocabulary of THIS build's "\u{200B}\u{200B}XX:" service words. A word
// with the invisible prefix whose token is not here belongs to a NEWER build — it is buried
// unread, never rendered (build 1013 drew the then-unknown WA:/AP: as bubbles every second).
let knownServiceTokens: Set<String> = ["VC:", "MD:", "RC:", "TY:", "WA:", "AP:", "AV:", "NM:",
                                       "RG:", "QC:", "DL:", "DF:", "CL:", "MC:", "WH:", "CG:", "PA:", "EX:",
                                       "ED:", "PN:", "SP:", "AB:", "WL:", "SM:", "SY:", "PX:", "PG:",
                                       "GR:",   // a group's invitation and letter (MTGroup, 05.10)
                                       "KP:"]   // the copy kept by the people one writes to (MTKeeping, 08.10)
func mtUnknownServiceWord(_ text: String) -> Bool {
    if text.hasPrefix("\u{200B}\u{200B}") {
        return !knownServiceTokens.contains(String(text.dropFirst(2).prefix(3)))
    }
    if text.hasPrefix("\u{2063}"), !text.hasPrefix(stickerMark) {
        let rest = text.dropFirst(1)
        return !(rest.hasPrefix("mtcall:") || rest.hasPrefix("mtconvdel:")
                 || rest.hasPrefix("mtdraft:") || rest.hasPrefix("LB:"))
    }
    return false
}

/// A CALL LETTER'S WORDS ARE READ ONCE (23.09). The call log is built again at every change of the letters, and each
/// build parsed every call letter of the history as JSON again. The reading is a pure function of the words, so it is
/// kept by the words, in the platform's own cache, safe from any thread. MEASURED, NOT BELIEVED (the critic 24.09, an
/// optimised build on a Mac): three hundred call letters parse in under a millisecond, so this keeping is a small saving
/// and not the badge's cost (the recount names its parts: MontanaMainProbe «badge:…»). The words do not repeat — each
/// carries its length in seconds — so the keeping is bounded by its count alone: past 4096 call letters a full walk
/// evicts what it reads, and the saving is gone.
private final class MTCallInfoKept { let v: (video: Bool, incoming: Bool, dur: Int, missed: Bool)?; init(_ v: (video: Bool, incoming: Bool, dur: Int, missed: Bool)?) { self.v = v } }
private let callInfoKept: NSCache<NSString, MTCallInfoKept> = { let c = NSCache<NSString, MTCallInfoKept>(); c.countLimit = 4096; return c }()
/// A new build's word, as the Montana room keeps it: the build, the version, what changed, the TestFlight link. What changed
/// speaks the phone's language when the road brought that language (the author's word 03.10: «in the language of the
/// phone»), else as the road wrote it; the row keeps every language, so a phone switched later reads its own.
func releaseInfoOf(_ text: String) -> (build: Int, version: String, notes: [String], url: String)? {
    guard text.hasPrefix(releaseMark),
          let d = String(text.dropFirst(releaseMark.count)).data(using: .utf8),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let b = o["b"] as? Int else { return nil }
    let own = ((o["l"] as? [String: [String]]) ?? [:])[MTLanguage.code] ?? []
    return (b, (o["v"] as? String) ?? "", own.isEmpty ? ((o["n"] as? [String]) ?? []) : own, (o["u"] as? String) ?? "")
}

// Parse a call log entry from the message text.
func callInfoOf(_ text: String) -> (video: Bool, incoming: Bool, dur: Int, missed: Bool)? {
    guard text.hasPrefix(callMark) else { return nil }
    if let kept = callInfoKept.object(forKey: text as NSString) { return kept.v }
    var v: (video: Bool, incoming: Bool, dur: Int, missed: Bool)? = nil
    if let d = String(text.dropFirst(callMark.count)).data(using: .utf8),
       let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
        v = ((o["v"] as? Bool) ?? false, (o["inc"] as? Bool) ?? false,
             (o["dur"] as? Int) ?? 0, (o["miss"] as? Bool) ?? false)
    }
    callInfoKept.setObject(MTCallInfoKept(v), forKey: text as NSString)
    return v
}

// Control message (receipts/typing/reaction/avatar/media/voice/sticker) —
// NOT user text. Don't store in history, don't display, don't send to preview.
func isControlMarker(_ text: String) -> Bool {
    text.hasPrefix(readReceiptMark) || text.hasPrefix(deliveryReceiptMark)
        || text.hasPrefix(typingMark) || text.hasPrefix(reactionMark)
        || text.hasPrefix(avatarMark) || text.hasPrefix(nameMark) || text.hasPrefix(aboutMark) || text.hasPrefix(groundMark)
        || text.hasPrefix(cardMark) || text.hasPrefix(voiceMark)
        || text.hasPrefix(deleteMark) || text.hasPrefix(convDelMark) || text.hasPrefix(draftMark)
        || text.hasPrefix(mediaMark) || text.hasPrefix(stickerMark) || text.hasPrefix(wakeHandleMark)
        || text.hasPrefix(punchEndpointMark) || text.hasPrefix(exitDoorMark)
        || text.hasPrefix(cargoLostMark) || text.hasPrefix(watchMark) || text.hasPrefix(playedMark)
        || text.hasPrefix(appMark) || text.hasPrefix(editMark) || text.hasPrefix(pinMark)
        || text.hasPrefix(MontanaStickerWire.mark)   // the set's word: machinery between two phones, never a row
        || text.hasPrefix(MTBoard.mark)              // the wall's word (24.09): a post, a mark, a page — never a row
        || text.hasPrefix(sameAskMark) || text.hasPrefix(sameYesMark)   // one person, one conversation (24.09): never a row
        || text.hasPrefix(pipeClosedMark)            // the pipe closed at the other end (24.09): never a row
        || text.hasPrefix(keepMark)                  // the keeping of a copy (08.10): never a row
}
// A service letter never rings: receipts, typing, drafts, profile (name/avatar/nick/card),
// deletions, wake-handles ride SILENT pushes by construction — the server model sent them
// exactly so, and a banner saying «New message» over a receipt is a lie to the person.
// Media, voice, stickers and calls stay loud: they ARE messages.
//
// LIVE TYPING was added 25.08 and is the ONLY change: the ⁣mtdraft: mark was not in the list,
// so every keystroke left as a LOUD push with a fresh id — the node's dedup by id is helpless
// there — and the receiver got a second textless banner. The edit is surgical by the author's
// word: the list stays a list, the extra notification goes.
/// THE FACE OF A LOUD PUSH — the ONE place that names it ([C-1], 13.09). A push carries a fallback
/// alert for the moment the receiver's extension does not run; the node cannot read the letter, so
/// the sender names its KIND and nothing else: a call, a missed call, or an ordinary letter. Apple
/// learns no more than the voip wake of the same call, to the same token, already told it seconds
/// earlier; the words themselves are resolved from the RECEIVER's own catalog, in their language.
func mtPushLook(for text: String) -> String {
    if text.hasPrefix(missedCallMark) { return "missed" }
    if text.hasPrefix(ringMark) { return "call" }   // only the bell rides loud; a plain ring letter is silent
    return ""
}
/// ONE CALL, ONE SLOT ON THE SCREEN (13.09). Apple replaces a notification with a newer one of the
/// same collapse name. A call has at most two loud letters — the bell («tap to answer») and the
/// word that it was missed — and they are two faces of ONE fact in time: once the call is over the
/// bell is a lie. Both ride under the call's own short name, so the second replaces the first and a
/// phone can never hold two banners for one call, even when its extension never ran to sweep them.
/// THE WALLET RINGS NOTHING (the author's word 09.10.2026 16:00 MSK): it sends neither a bell nor a missed call, so no letter of
/// its own names a call's slot.
func mtPushSlot(for text: String) -> String { "" }
func isSilentLetter(_ text: String) -> Bool {
    (isControlMarker(text) || text.hasPrefix(draftSignalMark))
        && !text.hasPrefix(mediaMark) && !text.hasPrefix(voiceMark) && !text.hasPrefix(stickerMark)
}
func stickerOf(_ text: String) -> String? {
    text.hasPrefix(stickerMark) ? String(text.dropFirst(stickerMark.count)) : nil
}

// Chat photo MESSAGE — in tmp (ephemeral); the permanent copy — the chat's sealed vault.
func saveChatPhotoTmp(_ data: Data) -> String? {
    let name = "att_\(UUID().uuidString).jpg"
    return MontanaMediaStore.put(name, data: data) ? name : nil
}

func avatarsDirURL() -> URL {
    let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Avatars")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}
func saveChatAvatar(_ data: Data) -> String? {
    // Application Support (outside Files): we keep the Documents root clean — only "Montana/"
    let name = "chatav_\(UUID().uuidString).jpg"
    do {
        try data.write(to: avatarsDirURL().appendingPathComponent(name)); MTNameBook.forgetPictures()
        _ = MontanaSmallPicture.image(name)   // the row's small copy is born with the file (16.09)
        return name
    }
    catch { MontanaLog.event("AVATAR write FAILED \(data.count)B: \(error.localizedDescription)"); return nil }
}

// the app's documents folder (where we store photos, voice, etc.)
func docsURL() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
}
func voiceFileURL(_ name: String) -> URL { attachmentURL(name) }

/// THE CHAT'S OWN GROUND — the dark gradient and the faint pattern of the logo — drawn once
/// here: the conversation stands on it, and so does every page of the links and photos feeds ([C-1]).
var montanaDarkGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.07),
                Color(red: 0.09, green: 0.08, blue: 0.06),
                Color(red: 0.13, green: 0.10, blue: 0.05)
            ],
            startPoint: .top, endPoint: .bottom
        )
}

// a small screen: enter the peer's wallet address and open a chat with them
struct StartByNameView: View {
    var onStart: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ref = ""
    @State private var checking = false
    @State private var error = ""

    private var normalized: String { ref.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("@name", text: $ref)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .foregroundColor(.white)
                } footer: {
                    // A name resolves through the plane of names (24.09): whoever holds one is reached by it,
                    // met before or not.
                    Text("Anyone who holds a name can be written to by it.")
                }
                .listRowBackground(MTGlassRowPlate())
                if !error.isEmpty {
                    Section { Text(LocalizedStringKey(error)).font(.caption).foregroundColor(.red) }
                        .listRowBackground(MTGlassRowPlate())
                }
            }
            .scrollContentBackground(.hidden).montanaPageGround()   // my page's ground, as every page wears it (26.09)
            .navigationTitle("Message by @username").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // The platform's own mark, not a word (the role, 22.09); the wait is the platform's spinner.
                    if checking { ProgressView() } else { MontanaDoneMark { check() }.disabled(normalized.isEmpty) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    func check() {
        error = ""
        // The nick only. No address is parsed here at all: a string resembling nothing used
        // to pass address parsing and the wrong conversation opened — exactly what happened.
        let name = normalized.hasPrefix("@") ? String(normalized.dropFirst()) : normalized
        let n = name.lowercased()
        guard !n.isEmpty else { error = "Enter a username"; return }
        // What looks like an address is told straight: addresses are no longer exchanged. A
        // silent refusal hides the reason, and the person keeps typing what is no longer accepted.
        if MontanaConv.looksLikeFormerRef(name) {
            error = "Addresses are no longer exchanged — ask for a username or a one-time card."
            return
        }
        guard NameSheet.rejection(n) == nil, NameSheet.normalized(n) == n else {
            error = "This username does not fit the rules."
            return
        }
        checking = true
        // THE ONE MEETING RESOLVER (24.09): this screen met a name by its own copy of the road — resolve and
        // encapsulate — and a second search for the same name wove a second rope to the same person. The name
        // goes to the resolver every entrance uses; its book by root answers with the chat already born.
        Task {
            let out = await MontanaMeeting.meet(n)
            await MainActor.run {
                checking = false
                switch out {
                case .opened(let ref): onStart(ref)
                case .nameless: error = "Nobody holds this name."
                case .ownName: error = "This is your own name."
                case .spent, .refused: error = "The name could not be checked right now. Try again."
                }
            }
        }
    }
}

// ═══ Message context menu: a separate window ON TOP of everything ═══
// A regular .overlay lives in the main window — under the keyboard. Here the menu is raised into
// its own UIWindow over the whole screen; the keyboard is put down by the opener first.
/// THE WINDOW SAYS WHERE THE FINGER LANDED (20.09): every touch that begins in the menu window is one
/// diary line — its point in window coordinates and the class of the view the platform hit-tested it
/// to. «The row is not tappable» is then read against menu_open's row frame: the finger was on the
/// row and a foreign view took it, or the finger was never on the row. The platform's own door
/// (sendEvent) — no gesture of ours stands on any control.
final class MTTouchWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
        if let t = event.allTouches?.first(where: { $0.phase == .began }) {
            let p = t.location(in: self)
            let on = t.view.map { String(describing: type(of: $0)) } ?? "nil"
            MontanaP2PTrace.mark("menu_touch", "x=\(Int(p.x)) y=\(Int(p.y)) on=\(on.prefix(40))")
        }
        super.sendEvent(event)
    }
}

final class MontanaOverlayWindow {
    static let shared = MontanaOverlayWindow()
    private var window: UIWindow?
    private weak var previousKey: UIWindow?
    func show<C: View>(@ViewBuilder _ content: () -> C) {
        if let w = window {   // the window already exists → just replace the content (no "not called")
            if let h = w.rootViewController as? UIHostingController<AnyView> {
                MontanaHost.reroot(h, content().environment(\.mtWindowSize, w.bounds.size), why: "overlay", replaces: true)   // each menu is a tree of its own
            }
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive })
                  ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let w = MTTouchWindow(windowScene: scene)
        MontanaTextSize.pin(w)   // a window of its own is outside the main window's pin: the same step here
        // The keyboard's window stands above ANY level of ours (measured 14.09, MTHoldOverlayWindow):
        // whoever opens this window puts the keyboard down first; the level only orders our own.
        w.windowLevel = UIWindow.Level(rawValue: 20_000_000)
        w.backgroundColor = .clear
        // THE WINDOW'S OWN SIZE goes into the tree (the author's word 16.09: the round note stood
        // crooked in its menu): a window of its own is outside the main root's measure, and every
        // bubble sized from the measure — the note's circle, a photo's box — was sized from zero.
        let host = MontanaHost.make(content().environment(\.mtWindowSize, w.bounds.size))
        host.view.backgroundColor = .clear
        // THE MENU STANDS ON THE DEVICE'S VIEWPORT, NOT ON A KEYBOARD'S (23.09, the call's buttons of the same day): the
        // menu has no field, yet its host took the keyboard's region, so a keyboard of the chat below -- or the bar the
        // platform leaves docked when the keys fold (the frame at 832) -- shrank the viewport the cloud is placed on.
        host.safeAreaRegions = [.container]
        w.rootViewController = host
        // The menu window becomes THE key window while it stands. Showing a window is enough for
        // a finger to reach it, but not for anything inside to become first responder — and text
        // selection is exactly that: the system's own selection needs the responder chain, and the
        // chain runs through the key window. The same modifier selects text elsewhere in the app
        // because everything else lives in the main window; here it did not, and nothing said why.
        // When the menu goes, the key goes back to the window it was taken from.
        previousKey = scene.windows.first(where: { $0.isKeyWindow })
        w.isHidden = false
        w.makeKey()
        window = w
    }
    func hide() {
        window?.isHidden = true
        window = nil
        previousKey?.makeKey()
        previousKey = nil
    }
}


/// The invite screen. Shows what the address lacks: a one-time node with a cell behind it.
/// The address takes part in not a single byte here — neither in the code nor in the link.
struct InviteView: View {
    var onClose: () -> Void
    @State private var invite: String = ""
    @State private var copied = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if !invite.isEmpty {
                    MontanaQRCode(payload: Data((MontanaCard.qrText(invite) ?? invite).utf8), side: 240, logo: true)
                        .padding(12).background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    Text("One-time invitation. It changes as soon as it is used.")
                        .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button {
                        UIPasteboard.general.string = invite
                        withAnimation { copied = true }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline.bold()).foregroundColor(copied ? .green : Color.accentColor)
                    }
                    Button { MTShare.present([MTShare.web(invite).map { $0 as Any } ?? invite]) } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline.bold()).foregroundColor(.black)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Color.accentColor).clipShape(Capsule())
                    }
                    Button("New invitation") { make() }
                        .font(.caption).foregroundColor(.gray)
                } else if busy {
                    ProgressView()
                    Text("Preparing an invitation…").foregroundColor(.gray).font(.caption)
                } else {
                    Text("The node is starting. An invitation appears as soon as it is up.")
                        .foregroundColor(.gray).font(.caption).multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                Spacer()
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .montanaPageGround()   // my page's ground, as every page wears it (26.09)
            .navigationTitle("Invite").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MontanaDoneMark { onClose() }
                }
            }
            .onAppear { make() }
        }.preferredColorScheme(.dark)
    }

    private func make() {
        busy = true; copied = false
        DispatchQueue.global().async {
            let inv = MontanaFirstContact.invitation() ?? ""
            DispatchQueue.main.async { invite = inv; busy = false }
        }
    }
}

/// The introduction, step two: who I am, what to encrypt me with, where to put my mail.
struct InviteHello: Codable {
    var v: Int
    var conv: String
    var dev: E2EPeerDevice
    var card: String
}

// The single «Copy link» button (SSOT): the SAME string the on-screen code carries is copied.
// The button used to copy the invite BY NAME while the code showed the card — two different
// values under one action, and a private account has no name at all: emptiness went to the
// clipboard.
struct CopyLinkButton: View {
    let link: String
    @State private var copied = false
    var body: some View {
        Button {
            UIPasteboard.general.string = link
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
        } label: {
            Label(copied ? "Link copied" : "Copy Link", systemImage: copied ? "checkmark" : "link")
                .font(.caption.bold()).foregroundColor(copied ? .green : Color.accentColor)
        }
    }
}

// ═══ Montana meeting code: name or one-time card — copy/share/scan (qrSheet style) ═══
// Shown on an EMPTY chat list (a single entry point instead of a separate address page).

/// The code screen — ONE per app: in the menu, on the empty chats screen, and full screen.
/// Three copies of one screen diverge by construction, and they did: the nick stood now on
/// top, now below; the avatar was not everywhere. Here it is one, so there is nothing to
/// diverge ([C-1]).
struct MontanaCodeView: View {
    let name: String
    var onScan: () -> Void
    /// THE NAME IS TAKEN RIGHT HERE (24.09): the button under the code opens the name's own page, and the page
    /// answers back with the name the keeper recorded — the code turns into the name's link at once.
    @State private var naming = false
    @State private var mine: String?
    private var shownName: String { mine ?? name }
    /// The column scrolls by itself where it stands in a plate (the settings, the empty chats);
    /// the full page owns the one scroll and centres the column in it (19.09) — a scroll inside
    /// a scroll is two owners of one finger.
    var scrolls = true
    /// THE PAGE CLOSES WHEN THE ONE WHO SCANNED IT WRITES (23.09, the author's word): the code has done its work the
    /// moment a first letter came through this very card. The page that holds the code closes itself here; a card
    /// standing inline (the empty chat list) passes nothing — the list stops being empty by itself.
    var onMet: (() -> Void)? = nil

    @AppStorage("avatarData") private var avatarData: Data = Data()
    /// PERMANENT OR TEMPORARY (the author's word 17.09): the permanent link stands for good and keeps
    /// whoever comes by it in the book; the temporary one is the daily code. Permanent by default;
    /// the share button hands out the same kind (MontanaCardShare).
    @AppStorage("cardKind") private var kind: String = "perm"
    private var permanent: Bool { kind == "perm" }
    /// The card is drawn only when the person asks for one: a card standing on the screen unasked
    /// is a key handed to whoever walks past.
    @State private var card: String?
    private func draw() { card = permanent ? MontanaCard.offerStanding() : MontanaCard.offerShort() }

    var body: some View {
        // The column scrolls: with a large system font the neighbouring text grows, and
        // without scrolling the layout has to crush the content — the code slides off the edge.
        Group {
            if scrolls {
                ScrollView { column }.scrollBounceBehavior(.basedOnSize)
            } else {
                column
            }
        }
        .onAppear {
            // ONE daily code per device: neither showing nor a meeting changes it — only the
            // day running out (the author's decision 22.08). The code used to be a match:
            // «one meeting = spent», and the spending begot a carousel of twin chats.
            draw()
        }
        .onChange(of: kind) { _, _ in draw() }
        .onReceive(NotificationCenter.default.publisher(for: .montanaCardSpent)) { _ in
            // The day ran out — rotation begot the next code, the screen draws it.
            draw()
        }
        .onReceive(NotificationCenter.default.publisher(for: .montanaNameChanged)) { _ in
            mine = MontanaSelf.name
            draw()
        }
        .sheet(isPresented: $naming) {
            NameSheet(onTaken: { n in
                naming = false
                mine = n
                draw()
            }, onClose: { naming = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: .montanaCardMet)) { n in
            // Only a letter through THE CARD ON THIS SCREEN closes it: a letter by another card or yesterday's
            // code says nothing about the person standing in front of this one.
            guard let onMet, let inv = n.userInfo?["inv"] as? String, !inv.isEmpty,
                  let c = card, MontanaCard.invite(inShort: c)?.base64urlNoPad == inv else { return }
            MontanaP2PTrace.mark("code_page", "closed: the first letter came through the card on it")
            onMet()
        }
    }
    private var column: some View {
        VStack(spacing: 14) {
            // THE ONE FACE (19.09, [C-1]): the same view the Time Panel and the drawer wear — the
            // photo, or the black face with the initial when there is none. This card used to draw
            // a photo or NOTHING: on a phone without a photo the face was simply gone (T3, measured:
            // no code_face frame, a column 84 points shorter).
            MTSelfFace(size: 84)
                .frame(width: 84, height: 84).clipShape(MontanaHexagon())
                .background(MTFrameMark("code_face"))
            if !shownName.isEmpty {
                // The name opens its own page: its term, and the road to change it (the critic's noticed point 8).
                Button { naming = true } label: {
                    Text("@" + shownName).font(.title3.bold()).foregroundColor(.white)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            // ONE view, whatever this person holds. The screen used to fork on the name: with a
            // name it drew the code, without one it drew a button to press first — so an identity
            // restored from its words, which has no name by construction, met a dead end where the
            // code belongs. What the code carries is the same in both cases: a card. A name says
            // who is offering it and changes nothing about the offer.
            Text(shownName.isEmpty
                 ? "This code opens one correspondence with you and nothing else."
                 : "Your name says who you are; the code opens the conversation.")
                .font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            // The code's size is a number of points (258) and the same under every text size:
            // the image is drawn at that side and never scaled with the font.
            ZStack {
                MontanaQRCode(payload: Data((MontanaCard.qrText(card ?? "") ?? (card ?? "")).utf8), side: 258)
                    .padding(16).background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                if let lp = Bundle.main.url(forResource: "SymbolOfTime", withExtension: "jpg"),
                   let li = UIImage(contentsOfFile: lp.path) {
                    RoundedRectangle(cornerRadius: 9).fill(Color.white)
                        .frame(width: 54, height: 54)
                        .overlay(Image(uiImage: li).resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 7)))
                }
            }
            // The two kinds as tabs under the code — the voice look's own picker (the author's word 17.09).
            Picker("", selection: $kind) {
                Text("Permanent").tag("perm")
                Text("Temporary").tag("temp")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 36)
            // The author's word 22.08: the link is UNDER the code, white, large, selectable,
            // and byte-for-byte equal to what the QR carries: both are one variable `card`,
            // there is no second source ([C-1]).
            // The exact moment the link renews (the author's word 07.09): the day's code was born
            // at a known second, and a day later the next one is — the person reads the date
            // and the time in their own format instead of «one code for a day».
            if let c = card, permanent, c.hasPrefix(MontanaFirstContact.webNamePrefix) {
                Text("The link stays yours while you hold the name: whoever holds it can write to you.")
                    .font(.caption).foregroundColor(.gray)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            } else if card != nil, permanent {
                Text("The link does not expire: whoever holds it can always write to you.")
                    .font(.caption).foregroundColor(.gray)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            } else if card != nil, let born = MontanaCard.currentShortWithBorn()?.born {
                let when = Date(timeIntervalSince1970: born + MontanaCard.cardLifetimeSeconds)
                    .formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: MTLanguage.locale))
                Text("The link renews on \(when)")
                    .font(.caption).foregroundColor(.gray)
            }
            if let c = card {
                Text(linkify(c))   // the link under the code is a link: a tap opens it, a long press selects it
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            CopyLinkButton(link: card ?? "")
            HStack(spacing: 10) {
                MontanaCardShare {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.accentColor).clipShape(RoundedRectangle(cornerRadius: 11))
                }
                Button(action: onScan) {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                        .font(.subheadline.weight(.semibold)).foregroundColor(.white)   // no gold word (the role, 22.09)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(white: 0.12)).clipShape(RoundedRectangle(cornerRadius: 11))
                }
            }.padding(.horizontal, 36)
            if shownName.isEmpty {
                Button { naming = true } label: {
                    Label("Take a name", systemImage: "at")
                        .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.padding(.top, 2)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}

/// The conversation-deletion sheet: the peer's face, the question
/// about them by name, actions in order of descending consequence, and «Cancel» as its own
/// group. One look for every place a conversation is deleted from — because two sheets about
/// one action never stay together without diverging ([C-1]).
struct MontanaDeleteChatSheet: View {
    let title: String
    let photoURL: String?
    let color: Color
    let initial: String
    let canDeleteForBoth: Bool
    /// A coin letter of mine is on its way in this chat (ChatStore.coinsTravel): the sheet says so and offers no deletion -- the
    /// erasure would take the letter off the wire with its coins (the coin audit's first point, 05.10.2026 21:4x MSK).
    var coinsTravel = false
    var onBoth: () -> Void
    var onMine: () -> Void
    var onCancel: () -> Void

    var body: some View {
        MontanaFaceSheet(photoURL: photoURL, color: color, initial: initial,
                         question: "Permanently delete the chat with \(title)?",
                         note: coinsTravel ? LocalizedStringKey("A coin letter in this chat is on its way. The chat can be deleted once it is delivered or its coins come back.") : nil,
                         actions: coinsTravel ? [] : (canDeleteForBoth ? [MontanaFaceSheet.Action(title: "Delete for me and them", destructive: true, act: onBoth)] : [])
                             + [MontanaFaceSheet.Action(title: "Delete for me only", destructive: false, act: onMine)],
                         onCancel: onCancel)
    }
}

/// THE BLOCK QUESTION — one sheet for the profile and the contacts tab ([C-1]): the face, the
/// consequence in small type, the deed in red.
struct MontanaBlockSheet: View {
    @EnvironmentObject private var store: ChatStore
    let chat: Chat
    var onBlock: () -> Void
    var onCancel: () -> Void
    var body: some View {
        MontanaFaceSheet(photoURL: store.avatarFor(chat), color: chat.color, initial: store.initial(for: chat),
                         question: "Block this person?",
                         note: "You will not receive messages, calls, typing or presence from this person. They will see neither your photo nor when you were last seen.",
                         actions: [MontanaFaceSheet.Action(title: "Block contact", destructive: true, act: onBlock)],
                         onCancel: onCancel)
    }
}

/// THE ONE SHEET FOR A QUESTION ABOUT A PERSON (the author's word 15.09: the block's confirmation
/// wears the same look as the deletion's): the face, the question by name, an optional note in
/// small type, the actions in order of descending consequence, «Cancel» as its own group.
struct MontanaFaceSheet: View {
    struct Action { let title: LocalizedStringKey; let destructive: Bool; let act: () -> Void }
    let photoURL: String?
    let color: Color
    let initial: String
    let question: LocalizedStringKey
    let note: LocalizedStringKey?
    let actions: [Action]
    var onCancel: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(shown ? 0.45 : 0).ignoresSafeArea()
                .onTapGesture { close(onCancel) }
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        AvatarCircle(photoURL: photoURL, color: color, initial: initial, size: 72)
                        Text(question)
                            .font(.subheadline).foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        if let note {
                            Text(note)
                                .font(.footnote).foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, a in
                        divider
                        action(a.title, destructive: a.destructive) { close(a.act) }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                action("Cancel", destructive: false, bold: true) { close(onCancel) }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
            .offset(y: shown ? 0 : 40).opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { shown = true } }
    }

    private func close(_ then: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.15)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: then)
    }
    private var divider: some View { Divider().overlay(Color.white.opacity(0.12)) }
    private func action(_ t: LocalizedStringKey, destructive: Bool, bold: Bool = false,
                        _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t)
                .font(bold ? .body.weight(.semibold) : .body)
                .foregroundColor(destructive ? .red : Color.accentColor)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .contentShape(Rectangle())
        }
    }
}

/// THE ONE SHARE OF ONE'S CARD ([C-1], the author's word 16.09): the QR page's «Share» and the
/// contacts tab's «+» hand out the same message from the same daily code — the system share
/// sheet, nothing between the tap and it.
struct MontanaCardShare<Content: View>: View {
    @ViewBuilder var label: () -> Content
    @AppStorage("cardKind") private var kind: String = "perm"   // the kind the code page chose
    @State private var card: String?
    private func draw() { card = kind == "perm" ? MontanaCard.offerStanding() : MontanaCard.offerShort() }
    var body: some View {
        // THE LINK ALONE (MTShare.web, 07.10): the invitation's page on the web names the person and offers the app.
        Button {
            if let link = card, let u = MTShare.web(link) { MTShare.present([u]) } else { MTShare.present([MontanaConv.inviteMessage(permanent: kind == "perm")]) }
        } label: { label() }
            .onAppear { draw() }
            .onChange(of: kind) { _, _ in draw() }
            .onReceive(NotificationCenter.default.publisher(for: .montanaCardSpent)) { _ in draw() }
            .onReceive(NotificationCenter.default.publisher(for: .montanaNameChanged)) { _ in draw() }
    }
}

struct MontanaQRCard: View {
    let name: String
    var onExpand: () -> Void
    var onScan: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("No chats yet").font(.title3.bold()).foregroundColor(.white)
            Button(action: onExpand) {
                MontanaCodeView(name: name, onScan: onScan)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 20).padding(.horizontal, 8)
    }
}

struct MontanaQRFullView: View {
    let name: String
    var onScan: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.montanaClose) private var montanaClose
    private func leave() { mtLeavePage(montanaClose, dismiss) }
    var body: some View {
        // THE DOCUMENT PAGE'S ROW, ONE TO ONE ([C-1], 19.09): a page in the sliding slot carries its
        // bar as a 52-point row inside the safe area — the mark on the right — and the content under
        // it. A SwiftUI navigation bar hosted in the slot stood right on iOS 26 and wrong on iOS 18
        // (T3: the face under the bar, then off the top) — the only page of the slot built so. The
        // safe area is the platform's one measure on every device; the row is the bar's line.
        VStack(spacing: 0) {
            HStack { Spacer(); MontanaDoneMark { leave() } }.padding(.horizontal, 4).frame(height: 52)
                .background(MTFrameMark("code_row"))
            ScrollView {
                MontanaCodeView(name: name, onScan: onScan, scrolls: false, onMet: { leave() })
                    .padding(.top, 8)
                    .background(MTFrameMark("code_column"))
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(MTFrameMark("code_scroll"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MTFrameMark("code_page"))
        .montanaPageGround()   // my page's ground, as every page wears it (26.09)
        .preferredColorScheme(.dark)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}
