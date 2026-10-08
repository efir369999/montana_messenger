//
//  MontanaChatsList.swift
//  Montana — a Montana messenger
//
//  Cut out of ContentView.swift whole, declaration by declaration (the author's word 10.09):
//  nothing here was renamed or rewritten; the file holds one screen and what only it reads.
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



struct MTSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var placeholder = String(localized: "Search", bundle: MTLanguage.bundle)
    /// THE BAR'S OWN HEIGHT (26.09): measured once from the platform's bar in its minimal style -- the system's field with the
    /// system's room around it -- never below the finger's 44; the search row, the results under it and the head read this number.
    static let height: CGFloat = {
        let b = UISearchBar()
        b.searchBarStyle = .minimal
        b.sizeToFit()
        return max(montanaTouchTarget, b.bounds.height)
    }()
    /// THE SEARCH ROW'S SIDE PADDING (the pages' search row, searchBar): with the platform's own inset of the capsule (below) it names
    /// where the field's edge stands -- the edge the chat list's lines stand under (MTLibraryRow).
    static let rowPad: CGFloat = 12
    /// WHERE THE PLATFORM STANDS THE CAPSULE INSIDE ITS BAR (28.09): measured once from the platform's own bar in its minimal style,
    /// laid out at a phone's width; a bar the platform would not lay out without a window answers with its own margin.
    static let capsuleInset: CGFloat = {
        let b = UISearchBar(frame: CGRect(x: 0, y: 0, width: 390, height: 56))
        b.searchBarStyle = .minimal
        b.layoutIfNeeded()
        let f = b.searchTextField.convert(b.searchTextField.bounds, to: b)
        return f.width > 1 ? max(0, f.minX) : b.layoutMargins.left
    }()
    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.overrideUserInterfaceStyle = .dark   // the pages are dark on every phone: the bar is the dark platform's own
        bar.placeholder = placeholder
        bar.delegate = context.coordinator
        bar.searchTextField.autocorrectionType = .no
        bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return bar
    }
    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        // THE KEYBOARD IS ASKED FOR AFTER THE PASS, NEVER INSIDE IT (25.09). A first responder taken inside SwiftUI's update raised
        // the keyboard inside the layout transaction, and the platform answered on the main thread for 8 to 16 s until the watchdog
        // ended the run (T1 19:03Z three times, the 15 Pro Max 19:05Z and 19:11Z, 0x8BADF00D). The ask is a turn of the main queue
        // later, reads the field's latest wish from its coordinator, and asks only a field that stands in a window. ONE PANE OWNS
        // THE KEYBOARD (25.09): a page's field wants the keys only while its own pane holds the focus (searchFocusBinding).
        let co = context.coordinator
        DispatchQueue.main.async {
            guard bar.window != nil else { return }
            let field = bar.searchTextField
            let wants = co.parent.focused
            if !wants, field.isFirstResponder { field.resignFirstResponder() }
            if wants, !field.isFirstResponder { field.becomeFirstResponder() }
        }
        if bar.text != text { bar.text = text }
        if bar.placeholder != placeholder { bar.placeholder = placeholder }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: MTSearchField
        init(_ p: MTSearchField) { parent = p }
        func searchBar(_ b: UISearchBar, textDidChange t: String) { parent.text = t }
        func searchBarTextDidBeginEditing(_ b: UISearchBar) { parent.focused = true }
        func searchBarTextDidEndEditing(_ b: UISearchBar) { parent.focused = false }
        func searchBarSearchButtonClicked(_ b: UISearchBar) { b.searchTextField.resignFirstResponder() }
    }
}

/// THE PULL (the author's word 10.09; its own pull 11.09): a pull on the whole feed, as on a web
/// page, refreshes — and what turns while it does is the platform's refresh glyph on a round of glass,
/// the size of a row's avatar (08.10.2026: the coins left for their own app, Montana Wallet). The list measures the pull itself, so everything about the feel of it lives in
/// the numbers below and nowhere else. NATIVE-CHECKED: the system's refresh control fires at a
/// distance it does not name and appears from the first point; the author asked for a longer pull.
struct MontanaPullSpinner: View {
    static let side: CGFloat = 58          // the row's avatar circle
    static let pullStart: CGFloat = 40     // the glyph is not there before the feed is drawn this far
    static let pullTrigger: CGFloat = 140  // let go past this and the feed refreshes; short of it, nothing
    static let hold: CGFloat = 82          // the gap the feed keeps open while the round completes
    static let pullFull: CGFloat = 240     // drawn this far the glyph has made its whole round — never more than one
    static let finish: TimeInterval = 0.35 // let go: the round it has begun completes this fast

    /// How far the feed is drawn down, in points.
    var pull: CGFloat
    /// The moment of letting go past the trigger and the angle the glyph stood at; nil while the
    /// finger still holds it.
    var released: (at: Date, angle: Double)?

    /// 0 at `pullStart`, 1 at `pullTrigger`: the glyph fills in along the way.
    var fraction: CGFloat { min(1, max(0, (pull - Self.pullStart) / (Self.pullTrigger - Self.pullStart))) }
    /// THE ROUND IS THE PULL (the author's word 11.09): how far the glyph turns is how hard it was
    /// drawn — half a round at the trigger, the whole round at `pullFull`, and never a second one.
    static func angle(forPull p: CGFloat) -> Double {
        360 * Double(min(1, max(0, (p - pullStart) / (pullFull - pullStart))))
    }

    var body: some View {
        TimelineView(.animation(paused: released == nil)) { ctx in
            // In the hand the angle is the pull; let go, the round it has begun completes at
            // once. The angle is a number the body sees on every frame, so the face it shows is
            // the face that is really up.
            let angle: Double = released.map { r in
                min(360, r.angle + (360 - r.angle) * ctx.date.timeIntervalSince(r.at) / Self.finish)
            } ?? Self.angle(forPull: pull)
            face(angle)
                .scaleEffect(released == nil ? 0.6 + 0.4 * fraction : 1)
                .opacity(released == nil ? Double(fraction) : 1)
        }
    }

    /// The platform's refresh glyph on a round of the system's glass, turned in the plane by the pull.
    private func face(_ angle: Double) -> some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.primary)
            .rotationEffect(.degrees(angle))
            .frame(width: Self.side, height: Self.side)
            .background(.ultraThinMaterial, in: Circle())
            .accessibilityHidden(true)
    }
}

/// THE TIME PANEL (the author's word 17.09): ONE law for every page under the bar — the chats, the
/// contacts, the calls, the music. The coin's pull walks the activation road and unfolds or folds the bar; the
/// search row is the list's head; its results stand over the rows; the list is pinned while the
/// search holds focus. The chats page writes it once (ChatsListView.timePanel); every page hands it
/// to its list and draws nothing of it itself.
struct MontanaTimePanel {
    let head: () -> AnyView
    let headPrint: Int
    let onRefresh: () async -> Void
    let onSettled: () -> Void
    let pinTop: Bool
    let overlay: () -> AnyView
}

/// A BAR THAT FLOATS OVER A LIST NEVER GOES UNDER THE KEYS (the author's word 21.09): the lift is
/// MEASURED — the keyboard's height (the one owner, MTKeyboard) less the room that already lies
/// between this bar's bottom and the screen's edge (the tab bar, the home strip) — on every device
/// and system, and zero when the keys are down or already clear of the bar.
struct MTKeyboardLift<Content: View>: View {
    @ObservedObject private var kb = MTKeyboard.shared
    @ViewBuilder var content: () -> Content
    @State private var below: CGFloat = 0   // room under the bar's bottom, measured
    var body: some View {
        content()
            .background(GeometryReader { g -> Color in
                // Measured with the keys DOWN only: the lift itself moves this frame, and a measure
                // taken while lifted would chase its own padding.
                let b = max(0, MTScene.size().height - g.frame(in: .global).maxY)
                if !kb.isUp, abs(b - below) > 0.5 { DispatchQueue.main.async { below = b } }
                return Color.clear
            })
            .padding(.bottom, kb.isUp ? max(0, kb.height - below) : 0)
            .animation(.easeOut(duration: 0.25), value: kb.isUp)
    }
}

/// THE GLOBE READS THE NODE ITSELF (23.09, the critic on T3's list): the page above watched the whole node for these two
/// bits, and every publication of it — the neighbours' scan alone publishes twice every twenty seconds — drew the chat
/// list again, its every row's print and its plate.
struct MTBarGlobe: View {
    @ObservedObject private var node = MontanaP2PNode.shared
    var body: some View {
        MontanaTransportIcon(transport: .internet, on: node.p2pUp, size: 22, known: node.p2pKnown)
    }
}

/// THE RESULTS STAND ON THE KEYS BY THEMSELVES (23.09): the page watched the keyboard for this one padding, and every move
/// of the keys — the chat open over the list raises and lowers them — drew the chat list again.
struct MTSearchResultsFrame<Results: View>: View {
    @ObservedObject private var kb = MTKeyboard.shared   // the ONE source of keyboard facts
    @ViewBuilder var results: () -> Results
    var body: some View {
        GeometryReader { g in
            let below = MTScene.size().height - g.frame(in: .global).maxY
            results()
                .background { MTUnderBarGround(still: true) }   // the page's own ground at its window's place: the rows hidden, no seam (26.09)
                .padding(.top, MontanaOctagon.searchRowHeight)   // under the field, over the rows
                .padding(.bottom, kb.isUp ? max(0, kb.height - below) : 0)   // above the keyboard by the measured overlap
        }
    }
}

/// A list under the time panel: the container with the panel's head, coin and pin, and the panel's
/// results over its rows — the one way a page stands under the bar. THE ROWS RUN ON TO THE SCREEN'S EDGES on every
/// page under the bar (the author's word 23.09: the chats, then the calls, then the contacts «as the chats and the
/// calls»): the way's own law, said here once and not by each page — see MTChatListFrame.
struct MontanaTimePanelList: View {
    let panel: MontanaTimePanel
    let rows: [Chat]
    let fingerprint: (Chat) -> [Int]
    let swipeLeading: (Chat) -> [SwipeTile]
    let swipeTrailing: (Chat) -> [SwipeTile]
    var swipesEnabled = true
    let onOpen: (Chat) -> Void
    let rowContent: (Chat) -> AnyView
    var onPull: (CGFloat) -> Void = { _ in }
    var onHold: ((Chat) -> Void)? = nil   // a page with nothing to do on a hold gives no haptic either
    var holdsRow: ((Chat) -> Bool)? = nil   // the rows a hold may begin on; nil -- every row (see MTChatListView)
    var bottomReserve: CGFloat = 0
    var headFloats = false   // a row of the page stands between the bar and the list with no plate (the archive row)
    var page = ""             // the page's name for the diary
    var fieldNames: [String]? = nil   // the names of the page's own print, for the diary; nil — by their places
    var numbered = false      // the rows' numbers beside the bar while the list scrolls (MTRowNumber)
    var endFirst = false      // the list opens at its end (the gallery: the newest at the bottom, as the platform's photos)
    var canvasRow: ((Chat) -> Bool)? = nil   // the rows as one canvas, as the settings' sections (MTChatListView.canvasRow)
    var separatorRow: ((Chat) -> Bool)? = nil   // the rows that wear the platform's separator (MTChatListView.separatorRow)
    var focus: MTListFocus? = nil               // a row asked to the middle (MTChatListView.focus)
    @Environment(\.mtPaneLive) private var live   // the page is looked at: its list applies (25.09)
    var body: some View {
        MTChatListView(rows: rows, headPrint: panel.headPrint, fingerprint: fingerprint,
                       swipeLeading: swipeLeading, swipeTrailing: swipeTrailing, swipesEnabled: swipesEnabled,
                       onOpen: onOpen, rowContent: rowContent, headContent: panel.head,
                       onPull: onPull, onHold: onHold, holdsRow: holdsRow, onRefresh: panel.onRefresh, onSettled: panel.onSettled,
                       pinTop: panel.pinTop, bottomReserve: bottomReserve,
                       runsToEdges: true, headFloats: headFloats, page: page, fieldNames: fieldNames, numbered: numbered, live: live,
                       endFirst: endFirst, canvasRow: canvasRow, separatorRow: separatorRow, focus: focus)
            // The list's frame never follows the keyboard (the author's word 10.09): the container is a
            // scroll view of its own; the results take the keyboard into account themselves.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .overlay(alignment: .top) { panel.overlay() }
    }
}

// ════════════════════════════════════════════════════════════
// CHATSLISTVIEW — MAIN SCREEN: CHAT LIST
// ════════════════════════════════════════════════════════════
// Connection status to the messenger network (relay/WS) for the chats header.
// connecting → spinner + status text; connected → uptime ticks next to «Montana Chats».
/// What the header says about the network, and it says exactly what the node measures.
///
/// This used to be a state of its own with two cases, born as «connecting…» and moved to
/// «connected» by whoever opened the websocket. When the server left, the caller left with it and
/// nothing was left to move it: the spinner turned for as long as the app was open, on a phone that
/// might well have been delivering letters the whole time. A measure nobody sets is not a measure —
/// it is a picture of a measure, and it lies in whichever direction it was drawn.
///
/// So there is one definition of «the network is up» in this tree — a node this device can hand a
/// message to right now ([I-10]) — and this reads it rather than keeping a second opinion.
final class ConnectionStatus: ObservableObject {
    static let shared = ConnectionStatus()
    private init() {}

    static var firstFrameLogged = false
    static func uptime(_ since: Date) -> String {
        let t = Int(max(0, Date().timeIntervalSince(since)))
        let d = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60, sec = t % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}

struct ChatsListView: View {
    @ObservedObject private var playerGate = MontanaPlayerBar.Gate.shared   // the one bit; never the player's clock (the critic 22.09)
    private var musicPlayer: VoicePlayer { VoicePlayer.shared }              // the folded page over the list (15.35): called, not observed
    @State private var playerBarSize: CGSize = .zero   // the floating player's height — the rows' reserve
    /// THE FEED AT A MOMENT (25.09): the gallery is a page under the bar (GalleryTabView) and its moments have one builder
    /// (ChatStore.mediaLibrary); a tap on a tile, or the dock's ask, names a moment, and this page hosts the feed at it over
    /// everything (montanaPage). The chats page walked every letter twice for the clips on every pass of its body while the
    /// gallery stood -- that walk is the store's now, kept until the letters change.
    @State private var viewing: MTMediaView?
    /// The conversation a clip lies in — visible or archived.
    private func chatNamed(_ name: String) -> Chat? {
        orderedChats.first(where: { $0.name == name }) ?? archivedChats.first(where: { $0.name == name })
    }
    /// The bar's way back to its bubble (the author's word 15.09): the chat opens at the letter
    /// that carries the file — from the bar here, and from a chat that plays another chat's voice.
    private func goToLetter(chat c: String, file f: String) {
        guard let ch = chatNamed(c), let mid = store.letterId(of: f, in: c) else { return }
        ui.showLetter(ch, mid)   // the one road («show in chat»)
    }
    // THE PAGE WATCHES WHAT IT DRAWS (23.09, the critic on T3's list): the node is read by the globe (MTBarGlobe) and
    // the keys by the search's results (MTSearchResultsFrame), each where it is drawn; watched from here, every scan of
    // the neighbours and every move of the keys under the chat open above drew the whole list again.
    /// Above the list: the bar, the stories strip and the archive row. Siblings of the list in
    /// one column — the list under the bars as a stack (1436–1439) died of a layout recursion
    /// inside UIKit on every launch (five signal-5 crashes, one stack), so the proven column
    /// stands; the rows run on under the bar inside the list's own UIKit view (MTChatListFrame,
    /// 23.09) and the column is drawn over them — the page's layout is the column's, unchanged.
    @ViewBuilder private var chatsFloating: some View {
        VStack(spacing: 0) {
            chatsTopBar
            // stories — ABOVE the search; hidden by swipe; hidden during search
            if storiesShown {
                storiesStrip
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if archiveShown {
                archiveRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    /// What stands between the bar and the rows with no plate of its own — the stories, the archive
    /// row. While one stands the rows stop at the list's top (MTChatListFrame.headFloats): one
    /// condition each, read by the column and by the list alike. BOTH ARE THE CHATS PAGE'S OWN (the critic 23.09):
    /// the column stands over every page under the bar, and the chats' archive row stayed there when the contacts or
    /// the calls were chosen — their rows, running on under the bar since 1913, showed through its words.
    private var storiesShown: Bool { ui.pane == .chats && testMode && !searchActive && !storiesCollapsed }
    private var archiveShown: Bool { ui.pane == .chats && !archivedChats.isEmpty && archiveRevealed && !searchActive }
    private var chatsTopBar: some View {
        MTGlassGroup {
        chatsTopBarPlate
        }
    }
    private var chatsTopBarPlate: some View {
        // ── TOP BAR (the author's word 10.09, reshaped 17.09): ONE plate, the mirror of the tab
        // bar below — the same glass and the same capsule under the native skin, the long octagon
        // under Geometric, the bar height — and on it seven glyphs with equal shares of the width,
        // left to right (the author's word 19.09): the face, contacts, calls, THE LOGO AT THE CENTRE,
        // chats, the dynamic glyph — the last opened of the player and the gallery — and the globe. The switching is the
        // tab bar's: a glass puck under the chosen glyph flows to the one tapped next; the puck
        // follows the pane, so the drawer's choice moves it too. The selection lives in the row's
        // own menu («Select»), not as a glyph; the settings moved up here from the tab bar.
        HStack(spacing: 0) {
            // THE DRAWER'S GLYPH, top left (the author's word 25.09: «the leftmost button — native, like the example, the size of
            // the other glyphs»): the system's list glyph opens the side drawer, the unfolded plate's first glyph; one's own
            // face left the plate for the drawer. THE FIRST SLOT LIVES ONLY ON THE UNFOLDED PLATE (the author's word 17.09):
            // the first of seven equal slots; folded, every slot but the logo has no width, so the logo stands at the centre
            // folded and takes the fourth slot unfolded — the centre of seven (the author's word 19.09).
            // THE CROSSED SPEAKER UNDER THE CLOCK (the author's word 06.10 20:5x: on the left, in the menu's place while the
            // notifications are off): the system said no, so the first slot says it too and opens the notifications' page;
            // the drawer stays one stroke from the screen's left edge (MontanaDrawerHost).
            barSlot(0) { if MTNotifyAllowed.shared.refused { openNotifications() } else { openDrawer() } } label: {
                // No badge here (the author's word 18.09): unfolded, the unread stand on the chats glyph and the missed calls
                // on the calls glyph — where the thing itself lives.
                Image(systemName: MTNotifyAllowed.shared.refused ? "speaker.slash" : UIState.Glyph.drawer).font(.system(size: 22, weight: .semibold))
                    .foregroundColor(MontanaOctagon.barGlyph)
            }
            // The contacts, left of the logo (the author's word 19.09).
            barSlot(Self.contactsSlot) { withAnimation(.easeInOut(duration: 0.2)) { ui.pane = .contacts } } label: {
                Image(systemName: UIState.Glyph.contacts).font(.system(size: 22, weight: .semibold))
                    .foregroundColor(MontanaOctagon.barGlyph)
            }
            // THE CALLS, left of the logo (the author's word 19.09): the log is a page, the puck follows.
            barSlot(Self.callsSlot) { withAnimation(.easeInOut(duration: 0.2)) { ui.pane = .calls } } label: {
                Image(systemName: UIState.Glyph.calls).font(.system(size: 22, weight: .semibold))
                    .foregroundColor(MontanaOctagon.barGlyph)
                    .overlay(alignment: .topTrailing) { if barOpen { glyphBadge(store.missedCallsUnseen) } }   // the missed calls, where the calls live
            }
            // THE LOGO IS ALWAYS THE CENTRE OF THE PANEL (the author's word 19.09): the fourth of seven
            // slots, three glyphs on either side — whatever the order of the others; folded, the plate is the logo.
            // THE LOGO OPENS THE FEED OF MY PEOPLE'S WALLS (the author's word 25.09: «a tap on the logo opens the feed of the
            // posts on the walls of all my contacts, by time, instead of the chats; folding and unfolding stay only with the
            // pull down and the coin»): the panel folds by the coin's pull alone (onSettled). FOLDED, THE LOGO UNFOLDS IT AND
            // THE PAGE STAYS (the author's word 25.09, later: «if the time panel is folded, a tap unfolds it, keeping the page
            // you are on»).
            barSlot(Self.logoSlot) {
                if barOpen { withAnimation(.easeInOut(duration: 0.2)) { ui.pane = .feed } } else { turnPanel(open: true, by: "logo") }
            } label: {
                MTFeedGlyph(side: 36)   // the feed's glyph is the logo, one drawing for the bar and the drawer
                    // THE BADGE ON THE TIME PANEL (the author's word 17.09): the unread chats and the
                    // missed calls, the platform's own corner badge — on the logo while folded, on
                    // the chats and the calls glyphs while unfolded.
                    .overlay(alignment: .topTrailing) { if !barOpen { glyphBadge(panelBadge) } }
                    // NO SENDING MARK ON THE LOGO (the author's word 29.09: «and on the time logo's icon hung a blue send icon,
                    // remove it altogether»): a letter on its way shows its state on its own bubble (DeliveryStatus), never
                    // on the panel.
            }
            // The chats, right of the logo (the author's word 19.09): an outline, as every page's glyph (UIState.Glyph).
            barSlot(Self.chatsSlot) { withAnimation(.easeInOut(duration: 0.2)) { ui.pane = .chats } } label: {
                Image(systemName: UIState.Glyph.chats).font(.system(size: 20, weight: .semibold))
                    .foregroundColor(MontanaOctagon.barGlyph)
                    .overlay(alignment: .topTrailing) { if barOpen { glyphBadge(store.unreadCounts.count) } }   // the unread, where the chats live
            }
            // THE DYNAMIC GLYPH, between the chats and the globe (the author's word 19.09): the last opened of the
            // player and the gallery; a tap opens that one again. Both are pages under the bar (the music 23.09, the
            // gallery 25.09), one of them in the row at a time, and the puck goes under the glyph for either.
            barSlot(Self.mediaSlot) { ui.mediaIsMusic ? ui.askMusic() : ui.askGallery() } label: {
                Image(systemName: ui.mediaIsMusic ? UIState.Glyph.music : UIState.Glyph.gallery)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(MontanaOctagon.barGlyph)
            }
            // THE GLOBE CHOOSES THE NETWORK PAGE (the author's word 25.09: «a full page under the time panel, as the chats, the
            // calls, the contacts and the feed»): a page of the finger's row, chosen as every glyph chooses its page, the puck
            // under the globe -- the P2P wall since the VPN left for its own app (the author's word 08.10.2026).
            barSlot(Self.globeSlot) { withAnimation(.easeInOut(duration: 0.2)) { ui.pane = .p2p } } label: {
                MTBarGlobe()
            }
        }
        // THE PUCK IS BORN UNDER EVERY GLYPH (the author's word 24.09: «now and then the tab's selection circle turns
        // darker, lies over the tab's glyph, and what is under it cannot be seen»). The puck was the background of its
        // own slot: a row draws its slots in order, so a puck carried toward the LEFT neighbour — by the finger's drag,
        // by a spring from a slot on the right, by a home one pass stale — was drawn after that neighbour's glyph and lay
        // over it, and its glass over glass darkened and blurred it. One puck now stands in the row's own background,
        // under all seven glyphs by construction, placed by the frames the slots name; no glyph can be drawn beneath it.
        .backgroundPreferenceValue(MTBarSlotKey.self) { slots in
            GeometryReader { g in
                // THE PUCK'S HOME IS THE PANE'S SLOT AND NOTHING ELSE (the critic 25.09: «a tap on a tab turns the page and the
                // puck stays now and then»): a state of this page named the home beside the pane — written by every glyph's tap
                // and again by the pane's change, in two transactions of their own. One owner now, the pane (UIState.pane), read
                // where the puck is drawn; every move of the home is a line in the diary (puck).
                // THE PUCK RIDES THE UNFOLD WITH ITS GLYPH (the author's word 25.09: «it jumps out; on 1916 it unfolds right»).
                // Born at the unfold, the puck stood at its slot at once while the glyph still flew from the centre. It stands
                // in the row's background folded too, at the folded slot — no width — and its place and width change in the
                // turn's own transaction, so they spring with the glyph, as they did when the puck was the slot's own (1916).
                // The anchors name the geometry as drawn (the diaries of 1941: the slot's width crosses one point 26–68 ms
                // after the turn and falls under it 300–416 ms after a fold), so the puck rides the spring frame by frame.
                if let home = Self.slot(of: ui.pane), slots[home] != nil {
                    MTPuckSlide(drag: ui.turnDrag, slotOf: Self.slot(of:), frames: slots.mapValues { g[$0] }) {
                        MTBarPuck().padding(.vertical, 6).padding(.horizontal, 3)
                    }
                }
            }
            .allowsHitTesting(false)   // a light under the glyphs: every touch belongs to the glyph above it
        }
        .montanaOctagonFace(bar: true)
        // THE BADGE IS THE PLATE'S, NOT THE BUTTON'S (the author's word 18.09): drawn on a button, it
        // was cut by the button's own clip and covered by the neighbour drawn after it. The button
        // only names its corner through a preference anchor; the plate draws the badge over all
        // seven glyphs, at that corner, untouched by any clip — the platform's own anchor road.
        .frame(maxWidth: .infinity)   // folded, the plate hugs the logo at the screen's centre
        .padding(.horizontal, 12)
        .padding(.top, MontanaOctagon.barTopPad)
        .padding(.bottom, MontanaOctagon.barBottomPad)
    }
    /// The pages warmed up after the launch (25.09): the two beside the pane, built one by one while the person still reads
    /// the first page, so the first stroke finds its neighbour standing.
    @State private var warmed = 0
    @State private var paneKeep = MTPaneKeep()
    // UNFOLDED BY DEFAULT, AND THE LAST CHOICE IS KEPT (the author's word 21.09): the panel opens as
    // the person left it — the platform's own store (AppStorage), one key, read at birth.
    @AppStorage("timePanelOpen") private var barOpen = true   // the coin's pull unfolds the six glyphs and folds them back (the logo opens the feed, 25.09)
    /// THE BADGE LIVES IN THE GLYPH'S OWN LAYER (the author's word 18.09, twice): the plate is a
    /// glass group, and the glyphs' glass composes over anything laid on the plate from outside —
    /// a badge drawn by the plate stood behind the buttons. So the badge is the glyph's overlay,
    /// as the platform's tab bar draws its own: at the glyph's top-trailing corner, inside the
    /// plate's height, and no slot clips it (barSlot). Unfolded: the unread on the chats glyph,
    /// the missed calls on the calls glyph; folded: their sum on the logo.
    private func glyphBadge(_ count: Int) -> some View {
        // SOLID (the author's word 18.09): the glass draws its content vibrant — the red capsule came
        // out translucent. Rasterised into its own image, the badge keeps its own colour on the glass.
        MTCountBadge(count).drawingGroup().offset(x: 10, y: -4)
    }
    private func openDrawer() { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { ui.drawerOpen = true } }
    private func openNotifications() { ui.overlayPage = .notifications }
    /// THE PANEL FOLDS AND UNFOLDS IN ONE PLACE (the author's word 25.09: «the folding and unfolding of the time panel has one
    /// owner, as everywhere — smooth, as with the coin»): the coin's pull, the logo on the folded panel and the search's hairline
    /// all turn it here, with the coin's own spring.
    private func turnPanel(open: Bool, by: String) {
        guard open != barOpen else { return }
        // Every turn is a line (25.09: «the panel still unfolds wrong» — and the diary of 1938 held no word of any fold).
        MontanaP2PTrace.mark("panel", "open=\(open ? 1 : 0) by=\(by) pane=\(ui.pane)")
        MTFrameMeter.shared.moveBegan()   // the fold, to the platform's own end (25.09)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82), completionCriteria: .logicallyComplete) { barOpen = open } completion: {
            MTFrameMeter.shared.moveEnded("panel:" + (open ? "open" : "fold"))
        }
    }
    /// WHAT OF THIS PAGE STANDS OPEN (24.09): the search, the selection, a row's menu, the gallery, the code page,
    /// the music's page, the deletion's sheet — the tabs do not turn under the finger while any of them does.
    private var pageHolds: Bool {
        searchActive || selecting || personMenu != nil || viewing != nil || showQrFull || deletingChat != nil
    }
    /// What the panel's badge counts: the chats with something unread and the missed calls unseen.
    private var panelBadge: Int { store.unreadCounts.count + store.missedCallsUnseen }
    private static let contactsSlot = 1
    private static let callsSlot = 2
    private static let logoSlot = 3   // the centre of seven — always (the author's word 19.09)
    private static let chatsSlot = 4
    private static let mediaSlot = 5
    private static let globeSlot = 6
    /// The pages whose search narrows their own rows (the music, 24.09; the feed and the network, 25.09): no results over
    /// them, no pin.
    private static func searchesItself(_ p: UIState.Pane) -> Bool { p == .music || p == .feed || p == .mesh || p == .p2p || p == .gallery }
    /// The slot the pane stands under — the puck's home when the page is chosen elsewhere (the drawer, the logo).
    private static func slot(of pane: UIState.Pane) -> Int? {
        switch pane {
        case .chats: return chatsSlot; case .contacts: return contactsSlot; case .calls: return callsSlot
        case .music, .gallery: return mediaSlot; case .feed: return logoSlot; case .p2p: return globeSlot
        case .mesh, .groups, .channels: return nil   // opened from the drawer: no glyph of the bar is theirs
        }
    }
    /// One slot of the bar: the glyph, its action, and under it the puck when it is the chosen one.
    /// Folded, every slot but the logo has no width; the logo keeps one square, so the plate hugs it.
    private func barSlot<L: View>(_ i: Int, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        let logo = i == Self.logoSlot
        return Button(action: action) { label() }
        .buttonStyle(MTBarGlyphStyle())
        .frame(maxWidth: barOpen ? .infinity : (logo ? MontanaOctagon.barHeight : 0))
        // The slot names its frame; the ONE puck of the row stands under it (MTBarSlotKey, the row's background).
        .anchorPreference(key: MTBarSlotKey.self, value: .bounds) { [i: $0] }
        .opacity(logo || barOpen ? 1 : 0)
        // No clip on a slot (the author's word 18.09): it cut the glyph's badge. A folded slot has no
        // width and no opacity; its glyph fades into the logo instead of being curtained, and it takes
        // no touch while folded.
        .allowsHitTesting(logo || barOpen)
    }
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui

    // Real chats: come from E2E conversations; the shelves are the store's (ChatStore.saveStored), this is a copy.
    @State private var searchText = ""
    @State private var searchHits = SearchHits()      // the results of the query, computed once per query (refreshSearchHits)
    @State private var searchFocused = false          // the field reports its focus itself (MTSearchField): it lives in a hosted cell
    /// ONE PANE OWNS THE KEYBOARD (25.09). Every page under the bar draws the same search row, and every row's field read the
    /// one flag: a tap on the chats' search set it, and the fields of the pages kept beside it -- built once, standing off the
    /// screen -- each asked to be the first responder too, taking the keyboard from one another every 60 ms (1426 begin/end
    /// marks in 16 s on the 15 Pro Max, 911 in 11 s on 1943, three deaths on T1 at 19:03Z) until the watchdog ended the run.
    /// The flag now names its pane: only the pane that owns the focus reads true; the others read false and never ask.
    @State private var focusPane: UIState.Pane? = nil
    private func searchFocusBinding(_ pane: UIState.Pane) -> Binding<Bool> {
        Binding(get: { searchFocused && focusPane == pane && !ui.drawerOpen },
                set: { on in
                    if on, !ui.drawerOpen { focusPane = pane; searchFocused = true }
                    else if focusPane == pane { searchFocused = false }
                })
    }
    private func searchFocusedHere(_ pane: UIState.Pane) -> Bool { searchFocused && focusPane == pane }
    @State private var endpointHit: String?          // a new user found by address (global search)

    private var myStoryMedia: String { get { MontanaLocalVault.getString("myStoryMedia") ?? "" } nonmutating set { MontanaLocalVault.setString("myStoryMedia", newValue) } }
    @AppStorage("avatarData") private var avatarData: Data = Data()
    @State private var storyPickers: [PhotosPickerItem] = []
    @State private var viewingStory: StoryItem?
    private var viewedStoriesJSON: String { get { MontanaLocalVault.getString("viewedStories") ?? "" } nonmutating set { MontanaLocalVault.setString("viewedStories", newValue) } }
    @AppStorage("storiesSeededAt") private var storiesSeededAt: Double = 0   // when friends' stories were «posted»

    let friendStories: [StoryItem] = []

    @State private var chats: [Chat] = []
    @State private var archivedChats: [Chat] = []
    @State private var deletingChat: Chat?
    @State private var personMenu: Chat?         // the row held: its menu cloud
    @State private var showScan = false
    @State private var showQrFull = false
    @State private var showInvite = false
    @State private var creatingGroup = false          // the group's two steps, opened by the compose menu (05.10)
    @State private var creatingChannel = false        // the channel's three steps, opened by the compose menu (05.10)
    @State private var startByName = false            // the «write by address» sheet
    @State private var selecting = false             // selection mode (the «Edit» button)
    @State private var selectedChats: Set<String> = [] // which chats are selected (by address)
    @State private var storiesCollapsed = false      // the stories strip is collapsed (while scrolling)
    @State private var archiveRevealed = false       // the archive row is summoned by a pull-down and folds back
    private let testMode = false
    @State private var loaded = false

    /// THE ROWS OF THE TAB — built by the store's one builder (`ChatStore.listRows`), the same
    /// one the share mirror is written from: what the tab shows is what the sheet shows.
    var visibleChats: [Chat] { testMode ? chats : store.listRows(stored: chats) }
    /// The order of the rows, decided by one strict comparison of fields the rows already carry:
    /// pinned first, then the newest event, then the address so that two equal numbers still have
    /// one answer. There is nothing here to disagree with and nothing to search linearly for.
    var orderedChats: [Chat] { MTListWork.build { ChatStore.listOrder(visibleChats, pinned: store.pinnedChats) } }
    /// The rows of the Groups app or of the Channels app: the groups of the kind, in the chats' one order.
    private func groupRows(channel: Bool) -> [Chat] {
        orderedChats.filter { c in MTGroup.isKey(c.name) && (MTGroup.shared.kind(c.name) == .channel) == channel }
    }

    // filtering chats by the search string
    /// THE NAME A PERSON IS FOUND BY IS THE NAME ON THE SCREEN (the author's word 19.09: the search
    /// did not find contacts). `Chat.name` is a storage label — for a person, the address; the shown
    /// title comes from the name book. Both are searched, so a person is found as they are seen.
    private func shownName(_ c: Chat) -> String { store.title(for: c).lowercased() + " " + c.name.lowercased() }

    // ── GLOBAL SEARCH ──
    // whether search mode is active (has focus or text entered)
    var searchActive: Bool { searchFocused || !searchText.isEmpty }

    // recent contacts (people only — no groups or «Favorites»)
    func recentContacts(in ordered: [Chat]) -> [Chat] {
        Array(ordered.filter { !$0.isGroup && $0.name != "Saved Messages" }.prefix(12))
    }

    // chats/groups/contacts matched by name
    func chatHits(in ordered: [Chat], _ q: String) -> [Chat] { ordered.filter { shownName($0).contains(q) } }

    /// PEOPLE OF THE BOOK (the author's word 19.09: the one search finds contacts, not only chats):
    /// the cards whose name matches and who have no conversation row yet — a tap opens the conversation.
    /// The same field and the same results stand on the chats, the contacts and the calls pages ([C-1]).
    func contactHits(in ordered: [Chat], _ q: String) -> [Chat] {
        let book = (try? JSONDecoder().decode([ContactsTabView.MTContact].self,
                                              from: Data((MontanaLocalVault.getString("mtContacts") ?? "").utf8))) ?? []
        let known = Set(ordered.compactMap(\.convId))
        return book
            .filter { c in !known.contains(c.ref) && (c.fullName.lowercased().contains(q) || c.name.lowercased().contains(q)) }
            .map { c in Chat(name: c.fullName.isEmpty ? MTNameBook.display(conv: c.ref) : c.fullName,
                             lastMessage: "", time: "", unread: 0, status: "", convId: c.ref) }
    }

    /// THE SEARCH IS A COMPUTATION, NOT A BODY (T1, 16:03-16:04Z, build 1949: three deaths on screen within a minute --
    /// hang_s=14, 10 and 8, mem_mb=646, the hang's stack in Array<Chat>.== under AttributeGraph, MetricKit's frames in
    /// TextInputUI, the watchdog's 0x8BADF00D). The results were computed inside the page's body: every letter of every
    /// conversation lowercased and scanned on every pass of the page -- and the page passes on every key and on every
    /// letter that arrives -- then drawn unbounded, every hit a row with a face and a fresh UUID for its id, so the list
    /// could never diff and rebuilt thousands of rows each pass. The hits are computed ONCE per query, after the keys
    /// settle, off the main thread over a snapshot of the history, bounded to the newest sixty letters, keyed by the
    /// letter's own name (MessageHit.id); the body only draws them. The words are asked without a copy
    /// (range(of:options:)), the marker checked first, so a service letter is never read as a person's words.
    struct SearchHits {
        var query = ""
        var chats: [Chat] = []
        var contacts: [Chat] = []
        var found: [MessageHit] = []
    }
    private static let searchHitCap = 60

    @MainActor
    func refreshSearchHits() async {
        let q = searchText.lowercased()
        guard !q.isEmpty else { searchHits = SearchHits(); return }
        try? await Task.sleep(nanoseconds: 120_000_000)   // the keys settle: a word typed through is scanned once
        guard !Task.isCancelled, q == searchText.lowercased() else { return }
        let ordered = orderedChats
        let chats = chatHits(in: ordered, q)
        let contacts = contactHits(in: ordered, q)
        let messages = store.messages   // a snapshot: the scan walks it off the main thread
        let cap = Self.searchHitCap
        let scan = Task.detached(priority: .userInitiated) { () -> [MessageHit] in
            var hits = MTNewestMatches<MessageHit>(limit: cap)
            for chat in ordered {
                for m in messages[chat.name] ?? [] {
                    guard !Task.isCancelled else { return [] }
                    guard !isControlMarker(m.text), !m.text.hasPrefix(callMark),
                          m.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
                    hits.insert(MessageHit(chat: chat, message: m), time: m.createdAt)
                }
            }
            return hits.values
        }
        let found = await withTaskCancellationHandler {
            await scan.value
        } onCancel: {
            scan.cancel()
        }
        guard !Task.isCancelled, q == searchText.lowercased() else { return }
        searchHits = SearchHits(query: q, chats: chats, contacts: contacts, found: found)
    }

    // searching for a new user by address on the server (those without a chat yet)
    @MainActor
    func runEmailSearch() async {
        let raw = searchText.trimmingCharacters(in: .whitespaces)
        endpointHit = nil
        // Input — an @name. No address is parsed: address exchange is over.
        guard let n = MontanaNames.normalize(raw), NameSheet.rejection(n) == nil else { return }
        try? await Task.sleep(nanoseconds: 350_000_000)   // typing debounce
        // TYPING ASKS NOBODY AND BEGETS NOTHING (24.09). Names now resolve at the keeper of the order, and a
        // search that asked it at every pause in typing would hand the keeper every name a person spells, and
        // meet each one — a new pipe per keystroke pause. The search answers from this device alone: a name
        // already met opens its chat; meeting a new name is the explicit road («Message by @username»).
        guard let root = MontanaNamePlane.known(n),
              let conv = MontanaMeeting.cardMet(root: root), MTPipeBook.holds(conv) else { return }
        guard conv != (MontanaSeed.twin ?? ""), !orderedChats.contains(where: { $0.name == conv }) else { return }
        guard !Task.isCancelled,
              raw == searchText.trimmingCharacters(in: .whitespaces) else { return }
        if MontanaConv.holds(conv) {
            endpointHit = conv
        }
    }

    /// WHAT THE CONTAINER IS TOLD ABOUT A ROW, in one number. The row draws a name, a face, a
    /// preview, a time and a badge; if none of them changed there is nothing to reconfigure, and
    /// the cell is left exactly as it stands. The preview and the time are asked of the one owner
    /// (`ChatStore.rowPreview` / `rowTime`) - the same answer the row itself draws ([C-1]).
    private func rowPrint(_ c: Chat) -> [Int] {
        func p<T: Hashable>(_ v: T) -> Int { var h = Hasher(); h.combine(v); return h.finalize() }
        // THE PRINT IS THE ROW'S OWN VALUES (ChatRowModel, 23.09): each value named for the diary, and the whole model
        // last — a value the row draws that has no name here still moves the print («field=model» says which).
        let m = store.rowModel(c)
        return [p(c.name), p(c.order),
                p(m.title),
                p(m.local ? String(m.selfFace) : (m.face ?? "")),
                p(m.preview),
                p(m.reaction.map { $0 + (m.reactionMine ? "/me" : "") } ?? ""),   // the answer in the row is part of the row
                p(m.picture),   // the picture's presence is part of the row
                p(m.time),
                p(m.status?.rawValue ?? ""),
                p(m.unread),
                p(m.forced),
                p(m.muted),
                p(m.pinned),
                p(selecting),
                p(selectedChats.contains(c.id)),
                p(m.blocked),
                p(m.draft ?? ""),
                p(m)]   // the order of MTChatListView.fieldNames
    }
    /// The same, for the one cell above the conversations.
    private func headPrint(listEmpty: Bool, pane: UIState.Pane) -> Int {
        var h = Hasher()
        h.combine(listEmpty && archivedChats.isEmpty)
        h.combine(MontanaSelf.name)
        h.combine(searchText.isEmpty); h.combine(searchFocusedHere(pane))   // the field's dress (placeholder, clear, cancel)
        h.combine(barOpen || searchActive)                        // folded with the bar: a hairline instead of the field
        return h.finalize()
    }

    /// The archive row: a full chat-row of its own, and FOLDABLE — a pull-down on the list
    /// summons it, a pull-up folds it away. It stays in the SwiftUI tree above the container,
    /// because the road it opens is a navigation push and a push needs the stack it belongs to.
    @ViewBuilder private var archiveRow: some View {
        NavigationLink {
            ArchivedChatsView(archived: $archivedChats, chats: $chats)
        } label: {
            HStack(spacing: MTLibraryRow.gap) {
                Circle().fill(Color(white: 0.15))
                    .frame(width: MTLibraryRow.face, height: MTLibraryRow.face)
                    .overlay(Image(systemName: "archivebox.fill")
                        .font(.system(size: 20)).foregroundColor(.gray))
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Archive").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                    Text("\(archivedChats.count)").font(.system(size: 16)).foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14)).foregroundColor(.gray)
            }
            .modifier(MTLibraryLine())   // a line of the list, in the App Library's measure (28.09)
            .overlay(alignment: .bottom) { MTLibraryHairline() }   // the list's separator, where the list cannot draw it
        }
    }

    /// The one cell above the conversations: the search row — the first row of the list — and,
    /// for a list with nothing in it, the card that stands in for the conversations.
    @ViewBuilder private func listHead(listEmpty: Bool, pane: UIState.Pane) -> some View {
        VStack(spacing: 0) {
            if barOpen || searchActive {
                searchBar(pane)
            } else {
                // FOLDED WITH THE BAR (the author's word 10.09): the logo folds its glyphs and the
                // search alike; what stays under the logo is the search's own hairline, and a tap
                // on it unfolds both.
                // The very hairline that parts two rows, at the head's own bottom edge — so the
                // first row stands from it exactly as every row stands from the one above.
                MTRowHairline()
                    .frame(maxWidth: .infinity).padding(.top, 20)
                    .contentShape(Rectangle())
                    .onTapGesture { turnPanel(open: true, by: "hairline") }
            }
        }
    }
    /// THE CODE PAGE UNDER SAVED MESSAGES (the author's word 17.09): while the list holds nothing but
    /// the local room, the card stands as the last row — below the room, not above it.
    private static let qrRow = "qr-card"

    /// One conversation, drawn exactly as it was drawn inside the lazy stack. The container
    /// decides WHERE it goes and WHETHER it is touched at all; this decides only how it looks.
    /// The tiles of a row's swipe — the same actions the context menu offers; the container
    /// draws them as the platform's swipe actions (15.26).
    /// Left to right — the two calls; right to left — unread, pin, mute, archive, delete. Every tile
    /// on the same glass as the compose button (the author's word 17.09).
    private func swipeLeading(_ chat: Chat) -> [SwipeTile] {
        guard !chat.isGroup, chat.convId != nil, chat.name != Self.qrRow else { return [] }
        return [SwipeTile(icon: "phone.fill", color: SwipeTile.glass) { MontanaCall.shared.startCall(peer: chat.convRef, device: "", video: false) },
                SwipeTile(icon: "video.fill", color: SwipeTile.glass) { MontanaCall.shared.startCall(peer: chat.convRef, device: "", video: true) }]
    }
    private func swipeTrailing(_ chat: Chat) -> [SwipeTile] {
        guard chat.name != Self.qrRow else { return [] }
        // THE MARK BOTH WAYS (the author's word 23.09): read where something is unread, the dot where nothing is.
        return [SwipeTile(icon: store.hasUnread(chat.name) ? "checkmark.message.fill" : "circle.fill", color: SwipeTile.glass) { store.toggleUnread(chat.name) },
         SwipeTile(icon: store.pinnedChats.contains(chat.name) ? "pin.slash.fill" : "pin.fill", color: SwipeTile.glass) { store.togglePinChat(chat.name) },
         SwipeTile(icon: muteIcon(chat), color: SwipeTile.glass) { toggleMute(chat) },
         SwipeTile(icon: "archivebox.fill", color: SwipeTile.glass) { archive(chat) }]
        + (ChatStore.isLocalRoom(chat.name) ? [] : [SwipeTile(icon: "trash.fill", color: SwipeTile.glass) { deletingChat = chat }])   // the local room has no delete
    }
    /// A tap on a row: the container's selection reports it (15.26) — in selection mode it
    /// toggles the mark, otherwise it opens the chat.
    private func rowTapped(_ chat: Chat) {
        guard chat.name != Self.qrRow else { return }
        if selecting { toggleSelect(chat) } else { ui.openChat(chat) }
    }

    /// THE ROW IS A BUBBLE, AND NO LINE PARTS TWO (the author's word 26.09, after the hairline of 11.09): the row sits centred in
    /// its bubble of one-tone glass (MTRowBubble), a breath from the next one.
    @ViewBuilder private func chatRowCell(_ chat: Chat) -> some View {
        Group {
            if chat.name == Self.qrRow {
                MontanaQRCard(name: MontanaSelf.name, onExpand: { showQrFull = true }, onScan: { showScan = true })
                    .padding(.top, 30)
            } else if selecting {
                // selection mode: circle on the left; the tap is the container's selection
                HStack(spacing: 10) {
                    Image(systemName: selectedChats.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(selectedChats.contains(chat.id) ? Color.accentColor : .gray)
                    ChatRow(model: store.rowModel(chat), library: true)
                }
                .modifier(MTLibraryLine())
            } else {
                // EVERY CONVERSATION A BUBBLE OF ONE-TONE GLASS, NO LINE BETWEEN TWO (the author's word 26.09): the tree's row
                // plate (MTRowBubble); the row's place on the screen, the bubble's, is where the menu's cloud rises.
                // THE LINE OF THE APP LIBRARY'S LIST (the author's words 28.09): no plate -- the platform's plain line on the softened
                // ground, the separator under it; the line's place on the screen is where the menu's cloud rises.
                ChatRow(model: store.rowModel(chat), library: true)
                    .modifier(MTLibraryLine(place: "row:" + chat.id))
                    // THE MENU ABOUT A PERSON on a hold — the container's own recognizer reports the
                    // row (onHold); a gesture here took the tap away from the selection (1617).
            }
        }
    }

    /// THE PULL IS THE WHOLE ACTIVATION ROAD, FORCED (the author's word 11.09: «the coin checks the
    /// box itself, not tied to notifications, and refreshes chats and letters if anything did not
    /// arrive»): the push stash into the chats, the node box walked NOW (not the 8-second kick), the
    /// node raised anew in the mesh, every waiting outgoing letter attempted, the media retried. All
    /// of it in the background: to the person the coin is only a way to open the bar. ONE road for
    /// the chats and the contacts ([C-1]).
    private func pullRefresh() async {
        MontanaWakePush.drainInbox()
        MontanaP2PNode.shared.onForeground()
        MontanaDeliveryEngine.shared.drainAll()
        await MontanaWakePush.fetchBox()
        await MontanaWakePush.sweepPresence()
        store.retryPendingMedia()
    }

    /// THE TIME PANEL, written once (the author's word 17.09) — see MontanaTimePanel: the search at
    /// the head, the coin's road, the bar's toggle, the pin, the results over the rows. A page that searches its own
    /// rows (the music, the author's word 24.09) takes neither the results over them nor the pin: its list narrows itself,
    /// and the results' own name lookup in the network is never drawn there.
    private func timePanel(_ pane: UIState.Pane, listEmpty: Bool = false, ownSearch: Bool = false) -> MontanaTimePanel {
        MontanaTimePanel(head: { AnyView(listHead(listEmpty: listEmpty, pane: pane).environmentObject(store).environment(ui)) },
                         headPrint: headPrint(listEmpty: listEmpty, pane: pane),
                         // The coin fetches what the network holds for us.
                         onRefresh: { await pullRefresh() },
                         onSettled: { turnPanel(open: !barOpen, by: "coin") },
                         pinTop: ownSearch ? false : searchActive,
                         overlay: { ownSearch ? AnyView(EmptyView()) : AnyView(searchOverlay) })
    }

    /// THE ONE FLOATING PLAYER OF THE PAGES UNDER THE BAR (the author's words 14.09 and 24.09): the chat's own bar,
    /// floated over the rows' bottom — the rows reserving its height and showing through its material — on the chats
    /// page and the music page alike; the height is measured once, by the one bar that stands.
    private var playerReserve: CGFloat { playerGate.standing ? playerBarSize.height : 0 }
    private var playerBar: some View {
        // ABOVE THE KEYS HERE TOO (the author's word 21.09): the list ignores the keyboard
        // on purpose, so its bottom-aligned overlay sat under the search's keys; the player
        // now stands on the measured cover — the keys' height less the room already under it.
        MTKeyboardLift {
            VStack(spacing: 0) {
                MontanaPlayerBar(onPlace: { t in showPlace(t) }, onSearch: { showMusic(search: true) },
                                 onGoTo: { c, f in goToLetter(chat: c, file: f) })
            }
                .mtMeasureSize($playerBarSize)
        }
    }

    /// THE UNFOLDED MINI'S NUMBER AND SEARCH (the author's word 01.10 00:13): the music page, where the track stands in its list, and
    /// the page's own search with the keys.
    private func showMusic(search: Bool = false) {
        withAnimation(.easeInOut(duration: 0.2)) { ui.askMusic() }
        if search { focusPane = .music; searchFocused = true }
    }
    /// The page where the track plays, its row at the middle: a post's track on the feed, every other on the music page.
    private func showPlace(_ t: MusicTrack) {
        if t.inPost { withAnimation(.easeInOut(duration: 0.2)) { ui.pane = .feed }; return }
        showMusic()
        MTMusicFocus.shared.show(t)
    }

    /// The search's results over the rows — the chats', the contacts' and the calls' alike ([C-1]).
    @ViewBuilder private var searchOverlay: some View {
        if searchActive {
            MTSearchResultsFrame { searchResults }
        }
    }

    /// The chat list's content. Separated from the modifier stack: the same picture is drawn,
    /// but type inference runs piecewise instead of one three-hundred-line expression.
    private var chatsContent: some View {
            VStack(spacing: 0) {
                // THE BAR STANDS OVER THE ROWS (23.09): the column is laid out as ever and the rows run on
                // under it (MTChatListFrame), so it is drawn after them — the order of drawing, not of layout.
                chatsFloating.zIndex(1)
                // THE SEARCH IS THE FIRST ROW OF THE LIST: it lives in the list's head cell and
                // rides with the conversations. While it holds focus the list is pinned to its
                // top and the results stand over the rows, under the field.
                // ONE build of the rows per pass of the body (15.16): the container, the head
                // print and the head cell each asked orderedChats separately — three filters,
                // three sorts and three passes over the feed on every pass of the page.
                // THE PANE FOLLOWS THE FINGER (the author's word 24.09): the pages of the row are built here and moved by the
                // slide alone (MTPaneSlide): the finger moves nothing else.
                // A PAGE ONCE BUILT STAYS BUILT (the critic 25.09, the diaries of 1938 — T1: 59 to 131 ms of the main thread at
                // the start of every stroke, the neighbour born anew each time, and 62 to 102 ms at every settle's end, the one
                // that left torn down; T3: «the chats page flickers when I swipe» — the page slid in as a list born empty, its
                // rows landing frames later). The reference keeps its pages; so do we: a page is built the first time it is
                // looked at — or warmed up after the launch — and kept in the row, off the screen when not looked at; a stroke
                // moves what stands and builds nothing that stands; a settle tears nothing down. A page not looked at keeps the
                // pass it was last built by (MTPaneKeep) — nothing of it is diffed again — and its list applies nothing until it
                // is looked at (mtPaneLive).
                // THE STROKE IS NOT READ HERE (30.09): the neighbour and the offset are the slide's alone (MTPaneSlide), so no move
                // of the finger runs this body; every page is handed as a promise (MTLazyPane), built only when its box is drawn.
                let pages = ui.turnOrder.contains(ui.pane) ? ui.turnOrder : ui.turnOrder + [ui.pane]
                MTPaneSlide(drag: ui.turnDrag, keep: paneKeep, pass: paneKeep.renew(), panes: pages.map { p in
                    MTPaneSlide.Item(pane: p, view: AnyView(MTLazyPane { AnyView(paneView(p)) }))
                })
            }
    }

    /// Every page under the bar takes the one time panel (the author's word 17.09).
    @ViewBuilder private func paneView(_ p: UIState.Pane) -> some View {
        switch p {
        case .contacts:
            ContactsTabView(panel: timePanel(.contacts))
        case .calls:
            CallsTabView(panel: timePanel(.calls))
        case .feed:
            // THE FEED SEARCHES ITSELF (the author's word 25.09), as the music does: the word at the head narrows its posts.
            // THE MINI PLAYER STANDS ON THE FEED (the author's word 26.09: «on the feed the mini player must appear if something
            // plays»): the chats page's one floating bar, floated the same way -- the posts reserving its height, «Write» above it.
            MTFeedTabView(panel: timePanel(.feed, ownSearch: true), query: searchText, writes: !searchActive, reserve: playerReserve)   // the feed of my people's walls, the logo's page (25.09)
                .overlay(alignment: .bottom) { playerBar }
        case .music:
            // THE MINI PLAYER STANDS ON THE MUSIC PAGE TOO (the author's word 29.09: «the mini player there must come up, our
            // native one, and everything pinned at the bottom as on every page»; it replaces the word of 24.09 that kept the bar
            // off this page): the chats page's one floating bar, floated the same way, the rows reserving its height.
            MusicTabView(panel: timePanel(.music, ownSearch: true), query: searchText, reserve: playerReserve)
                .overlay(alignment: .bottom) { playerBar }
        case .gallery:
            // THE GALLERY UNDER THE BAR (the author's word 25.09): the dynamic glyph's other page; it searches itself by the
            // conversations' names; a tile asks the feed at its moment, hosted by this page over everything (viewing).
            GalleryTabView(panel: timePanel(.gallery, ownSearch: true), query: searchText, stories: currentMedia(),
                           onView: { viewing = MTMediaView(id: $0) }, onAdd: { storyPickers = $0 },
                           // The tile's menu (25.09): the conversation at the letter, the forward by the conversation's own
                           // executor (ui.pendingForward), my story deleted -- the deeds the feed carried, on the platform's menu.
                           onOpen: { c, mid in
                               guard let ch = chatNamed(c) else { return }
                               ui.openChat(ch, jump: mid)
                           },
                           onForward: { c, mid in
                               guard let ch = chatNamed(c) else { return }
                               ui.pendingForward = mid
                               ui.openChat(ch, jump: mid)
                           },
                           onDelete: { deleteStoryMedia(file: $0) })
        case .mesh, .p2p:
            // THE WALLS SEARCH THEMSELVES (25.09), as the music and the feed do: the word at the head narrows their rows. A
            // neighbour found on the mesh opens the normal chat, over the tabs.
            NetworkTabView(panel: timePanel(p, ownSearch: true), wall: p, query: searchText, onOpenChat: { ref in
                ui.openChat(Chat(name: ref, lastMessage: "", time: nowHHMM(), unread: 0,
                                 status: "Montana address", convId: ref))
            })
        case .groups, .channels:
            // THE GROUPS AND THE CHANNELS ARE APPS OF THEIR OWN (the author's words 06.10.2026 11:5x-12:0x MSK: «in the side panel,
            // under Chats, separate apps Groups and Channels -- whole apps of their own, where groups and channels are created and
            // where they live; the chats list does not show them; their own TimeChain and their own app»): the page lists the rows of
            // its kind alone, and its corner creates one of its kind.
            let channel = p == .channels
            MontanaTimePanelList(panel: timePanel(p, listEmpty: false), rows: groupRows(channel: channel),
                                 fingerprint: rowPrint,
                                 swipeLeading: swipeLeading, swipeTrailing: swipeTrailing,
                                 swipesEnabled: !selecting,
                                 onOpen: rowTapped,
                                 rowContent: { AnyView(chatRowCell($0).environmentObject(store).environment(ui)) },
                                 onPull: { _ in },
                                 onHold: { c in if !selecting { personMenu = c } },
                                 holdsRow: { _ in !selecting },
                                 bottomReserve: playerReserve,
                                 headFloats: false, page: channel ? "channels" : "groups", fieldNames: MTChatListView.fieldNames,
                                 separatorRow: { _ in true })
                .mtPageAction(reserve: playerReserve, shown: !selecting && !searchActive) { createButton(channel: channel) }
                .overlay(alignment: .bottom) { playerBar }
        case .chats:
            VStack(spacing: 0) {
                let bare = orderedChats.filter { c in !MTGroup.isKey(c.name) }   // the groups and the channels live in their own apps (06.10)
                // The list is empty while it holds nothing but the local room (the author's word 17.09):
                // Saved Messages stands, and the code page stands under it as the last row.
                let empty = bare.allSatisfy { ChatStore.isLocalRoom($0.name) } && archivedChats.isEmpty
                let rows = empty ? bare + [Chat(name: Self.qrRow, lastMessage: "", time: "", unread: 0, status: "", convId: Self.qrRow)] : bare
                MontanaTimePanelList(panel: timePanel(.chats, listEmpty: false), rows: rows,
                               fingerprint: rowPrint,
                               // A cell is hosted by the container, not by the page, so the
                               // shared state a row reads is handed to it by name: outside the
                               // SwiftUI tree nothing is inherited.
                               swipeLeading: swipeLeading, swipeTrailing: swipeTrailing,
                               swipesEnabled: !selecting,
                               onOpen: rowTapped,
                               rowContent: { AnyView(chatRowCell($0).environmentObject(store).environment(ui)) },
                               onPull: { dy in
                                   // The same two directions as before, now reported by the
                                   // container that owns the scroll: pull down summons the
                                   // archive row, pull up folds it; stories ride along.
                                   if dy < -25 {
                                       withAnimation(.easeInOut(duration: 0.3)) {
                                           storiesCollapsed = true
                                           if archiveRevealed { archiveRevealed = false }
                                       }
                                   } else if dy > 25 {
                                       withAnimation(.easeInOut(duration: 0.3)) {
                                           storiesCollapsed = false
                                           if !archivedChats.isEmpty { archiveRevealed = true }
                                       }
                                   }
                               },
                               onHold: { c in if !selecting, c.name != Self.qrRow { personMenu = c } },
                               // A hold begins on a conversation alone (25.09): the code's card and a row being selected have no deed
                               // for it, and a hold that begins there gave the haptic of a deed that never came.
                               holdsRow: { c in !selecting && c.name != Self.qrRow },
                               bottomReserve: playerReserve,
                               // The rows run on to the screen's edges, as the chat's letters: the panel list's own law (23.09).
                               headFloats: storiesShown || archiveShown, page: "chats", fieldNames: MTChatListView.fieldNames,
                               // THE CHATS AS THE APP LIBRARY'S LIST (the author's words 28.09): the platform's plain list, every
                               // conversation a line with the platform's separator under it; the code's card stands alone, bare.
                               separatorRow: { c in c.name != Self.qrRow })
                // «Write» hangs over the rows, not over the bars below them: a player that
                // appears pushes the button up with the rows (the author's word 14.09).
                // ON THE LINE between the last two rows (the author's word 17.09): the pages' one corner (MTPageCorner), the reference.
                .mtPageAction(reserve: playerReserve, shown: !selecting && !searchActive) { composeButton }
                // The same player bar as in the chat, floated the same way (the author's word
                // 14.09): over the rows' bottom, the rows reserving its height and showing through
                // its material; leaving the chat does not lose the track (15.35).
                .overlay(alignment: .bottom) { playerBar }
                // ── BOTTOM selection bar (Read all / Archive / Delete) ──
                if selecting { selectionBar }
            }
        }
    }

    /// The chat list's sheets and dialogs — as their own layer: the same screen, but type
    /// inference runs piecewise.
    private var chatsSheets: some View {
        chatsContent
            .background { MTUnderBarGround() }   // under the bar, the rows and the tab bar alike: every glass blurs it -- my page's ground when one is chosen, the crest when none (26.09)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(MTOpaqueChatBar())   // the rows run on under the bar (23.09): it keeps no ground of its own, as the chat's
            .sheet(isPresented: $showScan) {
                NavigationStack {
                    ScanMeetingView { conv in
                        showScan = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(name: .openChatRequest, object: nil, userInfo: ["address": conv])
                        }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { showScan = false } } }
                }.preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showInvite) {
                InviteView { showInvite = false }
            }
            // The code's page in the sliding slot, closed by the edge swipe like every page (the author's word 19.09).
            .montanaPage(isPresented: $showQrFull, key: "qr") {
                MontanaQRFullView(name: MontanaSelf.name) { showQrFull = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showScan = true } }
            }
            // THE SETTINGS AND THE PROFILE are pages over the tabs now (the author's word 19.09): the
            // tabs' own slot shows them — see MainTabView.overlayPageView.
            // The puck follows the pane wherever the page was chosen — by a tap, the drawer or a stroke's release — from the
            // pane alone (MTPuckSlide reads UIState.pane): this page keeps no home of its own for it (the critic 25.09).
            .onChange(of: ui.pane) { was, p in
                // THE MUSIC'S SEARCH IS THE MUSIC'S (the author's word 24.09): a word typed over the tracks does not follow
                // the person to the chats, and a word typed over the chats does not narrow the tracks — the feed's is the
                // feed's too (25.09): a page that searches itself keeps its word to itself.
                if was != p, Self.searchesItself(was) || Self.searchesItself(p), searchActive { searchText = ""; searchFocused = false }
            }
            // WHAT OF THIS PAGE STANDS OPEN (24.09): the tabs do not turn under the finger while it does (UIState.tabsMayTurn);
            // the page alone knows these, and says so.
            .onChange(of: pageHolds, initial: true) { _, h in ui.pageHolds = h }
            // THE NEIGHBOURS ARE WARMED UP AFTER THE LAUNCH (25.09): one and a half seconds after the tabs appear the page to one
            // side of the pane is built, the one to the other side a moment later — each build in a turn of its own, off the
            // screen — so the first stroke finds its neighbour standing. Two one-shot waits, never a timer.
            .onAppear {
                let order = ui.turnOrder
                guard let i = order.firstIndex(of: ui.pane) else { return }
                for (n, step) in [(1, 1.5), (-1, 1.9)] where order.indices.contains(i + n) {
                    let p = order[i + n]
                    DispatchQueue.main.asyncAfter(deadline: .now() + step) { if paneKeep.built.insert(p).inserted { warmed += 1 } }
                }
            }
            // The menu about a person — the chat's own cloud over the list (MTPersonMenu).
            .overlay {
                if let c = personMenu {
                    MTPersonMenu(chat: c, anchor: MTBubbleFrames.shared.rect("row:" + c.id), deeds: [
                        .init(title: store.pinnedChats.contains(c.name) ? "Unpin" : "Pin",
                              icon: store.pinnedChats.contains(c.name) ? "pin.slash" : "pin") { personMenu = nil; store.togglePinChat(c.name) },
                        .init(title: store.mutedChats.contains(c.name) ? "Unmute" : "Mute",
                              icon: store.mutedChats.contains(c.name) ? "bell" : "bell.slash") { personMenu = nil; toggleMute(c) },
                        // «Select» is the row's own word (the author's word 17.09): the three dots left the bar.
                        .init(title: "Select", icon: "checkmark.circle") { personMenu = nil; withAnimation { selecting = true; selectedChats.removeAll() }; toggleSelect(c) },
                        .init(title: store.hasUnread(c.name) ? "Mark as read" : "Mark as unread",
                              icon: store.hasUnread(c.name) ? "checkmark.message" : "circle") { personMenu = nil; store.toggleUnread(c.name) },
                        .init(title: "Archive", icon: "archivebox") { personMenu = nil; archive(c) },
                    ] + (ChatStore.isLocalRoom(c.name) ? [] : [
                        .init(title: "Delete", icon: "trash", destructive: true) { personMenu = nil; deletingChat = c }]),
                    onClose: { personMenu = nil })
                }
            }
            // The conversation-deletion sheet is our own, not the system's: it shows the FACE
            // of the person whose correspondence is about to be erased. The system sheet
            // carries no face, and people confirmed deletion by a single name in a row — names
            // are alike, conversations sit side by side, and a miss here cannot be undone.
            // The send queue is cleaned by deleteChat itself (QUEUE-CHECKED: MontanaDeliveryEngine.clearChat).
            .overlay {
                if let c = deletingChat {
                    MontanaDeleteChatSheet(
                        title: store.title(for: c),
                        photoURL: store.avatarFor(c), color: c.color, initial: store.initial(for: c),
                        canDeleteForBoth: MontanaConv.holds(c.convId ?? c.name),
                        // The tombstone-first order and the erasing live in the store's one road (ChatStore.deleteChat).
                        onBoth: { store.deleteChat(c, forBoth: true); deletingChat = nil },
                        onMine: { store.deleteChat(c, forBoth: false); deletingChat = nil },
                        onCancel: { deletingChat = nil })
                }
            }
    }

    private var chatsEvA1: some View {
        chatsSheets
            .onChange(of: storyPickers) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var list = currentMediaRaw()
                    let now = Date().timeIntervalSince1970
                    for item in items {
                        if let movie = try? await item.loadTransferable(type: MovieFile.self) {
                            list.append(StoryMedia(type: "video", file: movie.url.lastPathComponent, created: now))
                        } else if let data = try? await item.loadTransferable(type: Data.self),
                                  let ui = UIImage(data: data),
                                  let jpeg = ui.avatarResized(1200).jpegData(compressionQuality: 0.85) {
                            let name = "img_\(UUID().uuidString).jpg"
                            try? jpeg.write(to: storyFileURL(name))
                            list.append(StoryMedia(type: "image", file: name, created: now))
                        }
                    }
                    saveMedia(list)
                    storyPickers = []
                }
            }
    }

    private var chatsEvA2: some View {
        chatsEvA1
            // The rendered order changes with every letter; the share sheet mirrors the RENDERED
            // list ([C-1]), so it is remirrored on the order itself, not only on the list's roster.
            .onChange(of: orderedChats.map { $0.name }) { _, _ in store.mirrorChatsToShare(visibleChats) }
            .onReceive(NotificationCenter.default.publisher(for: .montanaGoToLetter)) { n in
                guard let c = n.userInfo?["chat"] as? String, let f = n.userInfo?["file"] as? String else { return }
                goToLetter(chat: c, file: f)
            }
            // THE PLATFORM'S VIEWER AT A MOMENT, OVER EVERYTHING (the author's word 25.09: «take the feed out of the gallery;
            // viewing as native as it gets, as the phone's photos»): the gallery is a page under the bar, so its viewer rises
            // here, over the whole chats page, the chat's way -- the edge swipe closes it like every page. The viewer reads the
            // one builder's list, oldest first, as the page shows it, and opens at the tapped moment.
            .montanaPage(item: $viewing) { v in
                MTMomentsViewer(moments: store.mediaLibrary(stories: currentMedia()), initial: v.id)
            }
            .fullScreenCover(item: $viewingStory) { s in
                StoryViewer(story: s,
                            uploadedAt: s.isOwn ? (currentMedia().last?.created ?? 0) : storiesSeededAt,
                            onClose: { viewingStory = nil },
                            onPin: { file in pinStory(file: file) },
                            onDelete: { file in deleteStoryMedia(file: file) },
                            onSend: { text in
                                store.seedIfNeeded(s.name)
                                store.append(s.name, Message(text: text, isFromMe: true,
                                                             time: nowHHMM(), replyText: "📷 Story",
                                                             senderRef: nil))
                                // reply/reaction to a story → automatically create a chat with the author
                                ensureChatForStory(s, lastText: text)
                            })
            }
    }

    private var chatsEvA3: some View {
        chatsEvA2
            .sheet(isPresented: $creatingGroup) {
                MTGroupPickStep { title, face, people in
                    // THE GROUP IS BORN AND OPENED (the author's word 05.10.2026): its row stands at once, the invitations ride to
                    // every person chosen, and the sheet closes onto the group's own chat.
                    guard let row = MTGroup.shared.create(.group, title: title, face: face, people: people, store: store) else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ui.openChat(row) }
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $creatingChannel) {
                MTChannelIntroStep { title, about, face, people in
                    // THE CHANNEL IS BORN AND OPENED: a group whose owner alone posts (MTGroup, kind channel) -- its row stands at
                    // once, the invitations ride to every subscriber chosen, and the sheet closes onto the channel's own chat.
                    guard let row = MTGroup.shared.create(.channel, title: title, about: about, face: face, people: people, store: store) else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ui.openChat(row) }
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $startByName) {
                StartByNameView { ref in
                    startByName = false
                    let e = ref.trimmingCharacters(in: .whitespaces)
                    guard !e.isEmpty else { return }
                    let existing = row(for: e)
                    let chat = existing ?? Chat(name: e, lastMessage: "", time: nowHHMM(),
                                                unread: 0, status: "Montana address", convId: e)
                    if existing == nil { chats.insert(chat, at: 0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ui.openChat(chat) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatMetaUpdated)) { note in
                guard let u = note.userInfo, let id = u["id"] as? String else { return }
                updateChat(id, u["first"] as? String ?? "", u["last"] as? String,
                           (u["note"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                           (u["photo"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                           u["members"] as? [String] ?? [])
            }
    }


    private var chatsEvB1: some View {
        chatsEvA3
            .onAppear { MontanaMainProbe.run("chats-tab"); MontanaMainProbe.crumb = "chats-appear"; cleanupStories(); seedStoriesIfNeeded(); loadChats(); MontanaMainProbe.crumb = "" }
            // The three-second loop that asked a server for chats is gone (15.16): the server left
            // long ago and the stub answered an empty list — a timer that woke the page for nothing.
    }

    private var chatsEvB2: some View {
        chatsEvB1
            .onChange(of: chats) { _, _ in saveChats() }
            .onChange(of: archivedChats) { _, _ in saveChats() }
            .onReceive(NotificationCenter.default.publisher(for: .montanaChatsRestored)) { _ in rereadShelves() }   // rows rebuilt from the archive (15.10)
    }

    private var chatsEvB3: some View {
        chatsEvB2
            .onReceive(NotificationCenter.default.publisher(for: .montanaInbound)) { note in
                guard let ref = note.userInfo?["address"] as? String else { return }
                if row(for: ref) == nil {
                    let text = note.userInfo?["text"] as? String ?? ""
                    chats.insert(Chat(name: ref, lastMessage: text, time: nowHHMM(),
                                      unread: 1, status: "", convId: ref), at: 0)
                }
                // The order of a conversation has ONE writer — the landing itself (append → bump).
                // A second bump here, on the same event, was a second writer of the same number ([C-1]).
            }
            .onAppear {
                if let pend = UserDefaults.standard.string(forKey: "pendingOpenChat"), !pend.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "pendingOpenChat")
                    // The next turn of the run loop, not a 0.3 s clock (the author's word 21.09): the
                    // list is on screen and subscribed the moment this body has appeared.
                    DispatchQueue.main.async {
                        MontanaP2PTrace.mark("outside_open", "cold start — the pending chat opens")
                        NotificationCenter.default.post(name: .openChatRequest, object: nil, userInfo: ["address": pend])
                    }
                }
            }
    }

    private var chatsEvB4: some View {
        chatsEvB3
            .onReceive(NotificationCenter.default.publisher(for: .openChatRequest)) { note in
                // A by-name link: the conversation key comes from resolving the name; the
                // link does not carry it. Parsed by the ONE resolver: an earlier copy of this
                // code did not remember the first letter's ciphertext, and a correspondence
                // started by link could not open.
                if let atName = note.userInfo?["username"] as? String, !atName.isEmpty {
                    Task {
                        guard case .opened(let ref) = await MontanaMeeting.meet(atName) else { return }
                        await MainActor.run {
                            NotificationCenter.default.post(name: .openChatRequest, object: nil,
                                                            userInfo: ["address": ref])
                        }
                    }
                    return
                }
                guard let asked = note.userInfo?["address"] as? String else { return }
                let ref = MTSamePair.root(asked)   // a folded pipe opens the conversation it speaks for (24.09)
                UserDefaults.standard.removeObject(forKey: "pendingOpenChat")
                store.deletedChats.remove(ref)   // reopening/scanning clears the deletion (otherwise the chat is hidden and incoming doesn't arrive)
                MontanaDeliveryEngine.shared.drainAll()   // whatever already arrived lands in the store before the conversation opens
                let existing = row(for: ref)
                // A GROUP'S ROW IS THE GROUP'S OWN (MTGroup): a banner tapped before its invitation landed opens the list, never a
                // bare row wearing the group's key for a person's.
                if existing == nil, MTGroup.isKey(ref) {
                    MontanaP2PTrace.mark("outside_open", "group not held yet -- the list stays")
                    return
                }
                let room = ChatStore.isLocalRoom(ref)
                let c = existing ?? Chat(name: ref, lastMessage: "", time: nowHHMM(), unread: 0, status: "", convId: room ? nil : ref)
                if existing == nil, !room { chats.insert(c, at: 0) }
                store.traceRows(c.name)
                if c.name != ref { store.traceRows(ref) }   // a split feed key shows itself at once
                ui.openChat(c)
            }
            .onReceive(NotificationCenter.default.publisher(for: .peerAvatarUpdated)) { note in
                guard let ref = note.userInfo?["address"] as? String,
                      let file = note.userInfo?["file"] as? String else { return }
                _ = ref; _ = file   // the resolver reads the store directly; no copy is kept
            }
            // in search / selection mode we hide the bottom bar (the tab bar)
    }


    var body: some View {
        let _ = MTFrameMeter.shared.body("chats")   // the page's passes while a motion is measured
        NavigationStack {
            chatsEvB4
        }
    }

    // ── FLOATING "COMPOSE" BUTTON ──
    var composeButton: some View {
        // The only public identifier is the nick. The «by address» item is gone: two items
        // led to one screen, and choosing «by nick» landed the person in address parsing.
        // The compose button opens the ONE screen of the code and the link (the author's word
        // 07.09): the same MontanaQRFullView the empty-list card opens — one screen, one door.
        // The same face as the bar's buttons above (the author's word 10.09): the bar tier's glass
        // and size, the bar's grey glyph, centred by the plate itself.
        // The glyph is the system's compose button's size (the author's word 17.09): a large glyph
        // on the 60-point plate, as the platform draws its own.
        // THE BUTTON OPENS THE PLATFORM'S MENU (the author's word 05.10.2026): «Chat» is the screen of the code and the link it
        // always opened, then «Group» and «Channel», in the author's order from the top (a fixed order: the platform would turn
        // a menu rising from the bottom upside down). «Group» opens its two steps -- the people, then the name -- and its
        // letters ride the owner's pipes (MTGroup); «Channel» opens its three steps -- what it is, its face and words, the
        // subscribers -- and is the same group whose owner alone posts.
        // THE GROUPS AND THE CHANNELS ARE APPS OF THEIR OWN (the author's words 06.10.2026 11:5x-12:0x MSK): «Group» and «Channel»
        // are born in the apps of their own (createButton), and this button opens the screen of the code and the link again.
        Button { showQrFull = true } label: {
            Image(systemName: ContactsTabView.writeGlyph)   // the one write glyph of the tree (the author's word 17.09)
                .font(.system(size: 27, weight: .medium))
                .foregroundColor(MontanaOctagon.barGlyph)
        }
        .buttonStyle(.montanaOctagon(square: true, bar: true))
    }

    /// The corner of the Groups app and of the Channels app: one of the page's kind is born from it -- a group's two steps, a
    /// channel's three (MTGroupPickStep, MTChannelIntroStep).
    private func createButton(channel: Bool) -> some View {
        Button { if channel { creatingChannel = true } else { creatingGroup = true } } label: {
            Image(systemName: "plus")
                .font(.system(size: 27, weight: .medium))
                .foregroundColor(MontanaOctagon.barGlyph)
        }
        .buttonStyle(.montanaOctagon(square: true, bar: true))
        .accessibilityLabel(Text(channel ? "Channel" : "Group"))
    }

    // ── BOTTOM selection bar ──
    var selectionBar: some View {
        HStack(spacing: 10) {
            // The cross, bottom left (the author's word 17.09): out of the selection.
            Button { endSelecting() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            }
            .buttonStyle(.montanaOctagon(square: true))
            Group {
                selectPill("Read all") { markReadSelected() }
                selectPill("Archive") { archiveSelected() }
                selectPill("Delete", destructive: true) { deleteSelected() }
            }
            .opacity(selectedChats.isEmpty ? 0.5 : 1)
            .disabled(selectedChats.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    func selectPill(_ title: String, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        MTSelectPill(title: title, destructive: destructive, action: action)
    }

    // pull the conversation list from the server: new incoming chats appear on their own
    @MainActor
    func syncStoredChats() async {   // SILENT-OK: reading the local chat list, not a send path
        guard let serverChats = try? await store.channel.fetchChats() else { return }
        for sc in serverChats {
            guard let sid = sc.convId else { continue }
            if !chats.contains(where: { $0.convId == sid }) {
                chats.insert(sc, at: 0)      // a new incoming chat — to the top of the list
                store.bump(sc.name)
            }
        }
    }

    func toggleSelect(_ chat: Chat) {
        if selectedChats.contains(chat.id) { selectedChats.remove(chat.id) }
        else { selectedChats.insert(chat.id) }
    }
    func selectedList() -> [Chat] { chats.filter { selectedChats.contains($0.id) } }
    func markReadSelected() { for c in selectedList() { store.markRead(c.name, tellPeer: false) }; endSelecting() }
    func archiveSelected() { for c in selectedList() { archive(c) }; endSelecting() }
    func deleteSelected() { for c in selectedList() { deleteChat(c) }; endSelecting() }
    func endSelecting() { withAnimation { selecting = false; selectedChats.removeAll() } }

    // reply/reaction to a story: if there is no chat with the author yet — create it and move it to the top
    func ensureChatForStory(_ s: StoryItem, lastText: String) {
        if !chats.contains(where: { $0.name == s.name }) {
            let c = Chat(name: s.name, lastMessage: lastText, time: nowHHMM(), unread: 0,
                         photoURL: s.avatarAsset)
            chats.insert(c, at: 0)
        }
        store.bump(s.name)   // a chat with a fresh reply — to the top of the list
    }

    func toggleMute(_ chat: Chat) { store.toggleMuteChat(chat.name) }
    func muteIcon(_ chat: Chat) -> String {
        store.mutedChats.contains(chat.name) ? "bell.fill" : "bell.slash.fill"
    }

    /// The store's one road ([C-1]); the tab rereads the vault by the store's signal.
    func archive(_ chat: Chat) { store.archiveChat(chat) }
    func deleteChat(_ chat: Chat) { store.deleteChat(chat, forBoth: false) }

    // update the group (photo, title, members) — called from the profile
    func updateChat(_ id: String, _ first: String, _ last: String?, _ note: String?, _ photo: String?, _ members: [String]) {
        // A PERSON WITH NO ROW HERE IS RENAMED ALL THE SAME (the critic 23.09): the contacts page shows the book's
        // people and the people who outlived their chat, and their profile opens with no row of this list. A
        // person's name, face and card are the name book's, keyed by the address (Chat.id) — no row is needed.
        if !id.isEmpty, !chats.contains(where: { $0.id == id }) {
            MTNameBook.setManual(conv: id, first: first, last: last)
            MTNameBook.syncContact(conv: id, first: first, last: last)
            MTNameBook.setManualPhoto(conv: id, file: photo)
            return
        }
        if let i = chats.firstIndex(where: { $0.id == id }) {
            let oldTitle = chats[i].title
            if chats[i].isGroup {
                chats[i].displayName = first     // a group has no address: its title lives on the chat
                chats[i].lastName = last
            } else {
                // Person: the rename belongs to the name book keyed by ADDRESS, so the contacts
                // list, the calls log, the chat list and the header all show it at once.
                MTNameBook.setManual(conv: (chats[i].convId ?? ""), first: first, last: last)
                MTNameBook.syncContact(conv: (chats[i].convId ?? ""), first: first, last: last)
                chats[i].displayName = nil
                chats[i].lastName = nil
            }
            chats[i].note = note             // note
            // ALL historical folder names migrate: the former label, the displayed address, the raw address
            let newTitle = chats[i].title
            for src in [oldTitle, (chats[i].convId ?? "")] where src != newTitle {
                MontanaArchive.renameChatFolder(from: src, to: newTitle)
            }
            let oldPhoto = chats[i].photoURL
            if chats[i].isGroup { chats[i].photoURL = photo }
            else { MTNameBook.setManualPhoto(conv: (chats[i].convId ?? ""), file: photo) }
            // THE OWNER'S NEW TITLE AND FACE GO TO EVERY PHONE OF THE GROUP (MTGroup.renew); only the owner's page edits a group.
            if chats[i].isGroup, MTGroup.isKey(chats[i].name) {
                MTGroup.shared.renew(chats[i].name, title: (first + " " + (last ?? "")).trimmingCharacters(in: .whitespaces),
                                     faceFile: photo != oldPhoto ? photo : nil, about: note ?? "", store: store)   // the note is its description
            }
            chats[i].members = members
            if chats[i].isGroup { chats[i].status = "\(members.count + 1) members" }
        }
    }

    /// A conversation's row on either shelf: a conversation standing in the archive keeps its row there, and a bare
    /// second one on the standing shelf was a row twice (the critic 24.09: every letter of an archived conversation, an
    /// open from a banner or a link, and a start by name set one up).
    /// A conversation's row by its address -- a local room's by its key: the room has no address, and the release banner's tap
    /// asked to open «Montana», found no row and bore a second one with the key for an address (T1 03.10 17:12:01Z).
    private func row(for ref: String) -> Chat? {
        if ChatStore.isLocalRoom(ref) { return orderedChats.first { $0.name == ref } }
        return chats.first { $0.convId == ref } ?? archivedChats.first { $0.convId == ref }
    }
    // load/save the chat list (so created groups don't disappear)
    func loadChats() {
        // SILENT-OK: the chat list is read once per launch, and a second call has nothing to
        // report: it sends nothing, receives nothing and loses nothing — it is already done.
        guard !loaded else { return }
        loaded = true
        if let saved = store.chatsShelf() { chats = saved }
        if let savedA = store.archivedShelf() { archivedChats = savedA }
        store.mirrorChatsToShare(visibleChats)          // chat list for the «Share» menu
        NotificationCenter.default.addObserver(forName: .montanaRemirror, object: nil, queue: .main) { _ in
            store.mirrorChatsToShare(visibleChats)      // activation signal: the extension's mirrors are fresh
        }
        // The peer erased the conversation: the list changed from elsewhere, and the screen
        // must reread it — otherwise the row lives on screen after the conversation is nowhere.
        NotificationCenter.default.addObserver(forName: .montanaChatsChanged, object: nil, queue: .main) { _ in
            rereadShelves()
        }
    }
    /// THE SHELVES ARE THE STORE'S; THIS TAB HOLDS A COPY (the critic 24.09). Whatever the store wrote — a restore, a
    /// heal, an archive, a deletion — is read back here before anything of the tab is written over it: a restored row
    /// was written away by this copy's next save (T1: arc:d7f0fd, a week without a row). A shelf that does not read
    /// leaves the copy as it stands.
    func rereadShelves() {
        guard loaded else { loadChats(); return }
        if let saved = store.chatsShelf() { chats = saved }
        if let savedA = store.archivedShelf() { archivedChats = savedA }
        store.mirrorChatsToShare(visibleChats)
    }
    func saveChats() {
        guard loaded else { return }
        store.saveStored(chats: chats, archived: archivedChats, tell: false)   // the shelves' one writer; this copy is fresh
        store.mirrorChatsToShare(visibleChats)          // sync the mirror on every change
    }

    // all my stories (as saved)
    func currentMediaRaw() -> [StoryMedia] {
        (try? JSONDecoder().decode([StoryMedia].self, from: Data(myStoryMedia.utf8))) ?? []
    }
    // «live»: pinned or younger than 24 hours
    func isAlive(_ m: StoryMedia) -> Bool {
        if m.pinned { return true }
        if m.created == 0 { return true }   // don't touch old ones without a timestamp
        return Date().timeIntervalSince1970 - m.created < 24 * 3600
    }
    func currentMedia() -> [StoryMedia] { currentMediaRaw().filter(isAlive) }
    func saveMedia(_ list: [StoryMedia]) {
        if let d = try? JSONEncoder().encode(list), let s = String(data: d, encoding: .utf8) {
            myStoryMedia = s
        }
    }
    // pin a story by file name (won't disappear after 24h)
    func pinStory(file: String) {
        var list = currentMediaRaw()
        if let i = list.firstIndex(where: { $0.file == file }) {
            list[i].pinned = true
            saveMedia(list)
        }
    }
    // delete my own story
    func deleteStoryMedia(file: String) {
        var list = currentMediaRaw()
        list.removeAll { $0.file == file }
        saveMedia(list)
        try? FileManager.default.removeItem(at: storyFileURL(file))
    }
    // delete expired stories (older than 24h and not pinned)
    func cleanupStories() {
        let alive = currentMediaRaw().filter(isAlive)
        if alive.count != currentMediaRaw().count { saveMedia(alive) }
    }
    // viewed stories are remembered forever
    func isViewed(_ key: String) -> Bool {
        ((try? JSONDecoder().decode([String].self, from: Data(viewedStoriesJSON.utf8))) ?? []).contains(key)
    }
    func markViewed(_ key: String) {
        var arr = (try? JSONDecoder().decode([String].self, from: Data(viewedStoriesJSON.utf8))) ?? []
        guard !arr.contains(key) else { return }
        arr.append(key)
        if let d = try? JSONEncoder().encode(arr), let s = String(data: d, encoding: .utf8) {
            viewedStoriesJSON = s
        }
    }
    var ownStory: StoryItem {
        StoryItem(name: "Your Story", color: Color.accentColor, media: currentMedia(), isOwn: true)
    }

    // friends' stories live 24 hours — after that their circles disappear, only mine remains
    var liveFriendStories: [StoryItem] {
        guard storiesSeededAt > 0 else { return friendStories }   // not seeded yet — show all
        let age = Date().timeIntervalSince1970 - storiesSeededAt
        return age < 24 * 3600 ? friendStories : []
    }
    // record the «posting» time of friends' stories (once)
    func seedStoriesIfNeeded() {
        if storiesSeededAt == 0 { storiesSeededAt = Date().timeIntervalSince1970 }
    }
    // view key of my story = the last uploaded (a new story → «unviewed» again)
    var ownStoryKey: String { "own_" + (currentMedia().last?.file ?? "") }

    // ── STORIES STRIP: profile photo in the circle ──
    var storiesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Your story
                VStack(spacing: 5) {
                    ZStack(alignment: .bottomTrailing) {
                        if currentMedia().isEmpty {
                            PhotosPicker(selection: $storyPickers, maxSelectionCount: 10,
                                         matching: .any(of: [.images, .videos])) {
                                storyCircle(data: avatarData, asset: nil,
                                            color: Color.accentColor, initial: "Y", ring: false)
                            }
                        } else {
                            Button {
                                markViewed(ownStoryKey)   // count the view immediately on tap
                                viewingStory = ownStory
                            } label: {
                                storyCircle(data: avatarData, asset: nil,
                                            color: Color.accentColor, initial: "Y",
                                            ring: !isViewed(ownStoryKey))   // fades after viewing
                            }
                        }
                        // «+» — add (multiple allowed, photos and videos)
                        PhotosPicker(selection: $storyPickers, maxSelectionCount: 10,
                                     matching: .any(of: [.images, .videos])) {
                            Circle().fill(Color.accentColor).frame(width: 20, height: 20)
                                .overlay(Image(systemName: "plus")
                                    .foregroundColor(.black).font(.system(size: 11, weight: .bold)))
                        }
                    }
                    Text("You").font(.caption2).foregroundColor(.gray)
                }

                // friends' stories (their profile photo in the circle); live 24 hours
                ForEach(liveFriendStories) { s in
                    VStack(spacing: 5) {
                        Button {
                            markViewed(s.name)        // the view is remembered forever
                            viewingStory = s
                        } label: {
                            storyCircle(data: nil, asset: s.avatarAsset,
                                        color: s.color, initial: MontanaAvatar.initial(title: s.name, name: ""),   // the one derivation ([C-1], 20.09)
                                        ring: !isViewed(s.name))   // the ring only until the first view
                        }
                        Text(s.name).font(.caption2).foregroundColor(.gray).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // story circle: profile photo (from data or an asset) + ring
    func storyCircle(data: Data?, asset: String?, color: Color, initial: String, ring: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(ring
                        ? AnyShapeStyle(LinearGradient(colors: [.orange, .pink],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.gray.opacity(0.4)),
                        lineWidth: ring ? 2.5 : 2)
                .frame(width: 64, height: 64)
            Group {
                if let d = data, let ui = UIImage(data: d) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else if let a = asset, UIImage(named: a) != nil {
                    Image(a).resizable().scaledToFill()
                } else {
                    Circle().fill(Color.black)
                        .overlay(Text(initial)
                            .font(.system(size: 56 * MontanaAvatar.glyphScale(initial), weight: .bold))
                            .foregroundColor(Color.accentColor))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
        }
    }

    // ── SEARCH BAR (instead of the "Montana" title) ──
    func searchBar(_ pane: UIState.Pane) -> some View {
        HStack(spacing: 0) {
            // THE PLATFORM'S OWN SEARCH BAR (the author's word 26.09, the Files page's picture): its field, its fill, its magnifier,
            // its placeholder, its clear key and its microphone are the system's (MTSearchField). Its focus is THIS pane's alone
            // (searchFocusBinding): no other pane's field ever reads true, and the keyboard is asked for after the pass (P-131).
            MTSearchField(text: $searchText, focused: searchFocusBinding(pane))
                .frame(height: MTSearchField.height)
            // The cross — appears in search mode (no word on a button of ours, 22.09): a round of glass on the platform's 44.
            if searchActive {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MontanaOctagon.barGlyph)
                }
                .accessibilityLabel(Text("Cancel"))
                .buttonStyle(.montanaOctagon(square: true, bar: true, height: montanaTouchTarget))
            }
        }
        .padding(.horizontal, MTSearchField.rowPad)   // with the bar's own inset, the field stands where the platform's pages put it
        .padding(.vertical, MontanaOctagon.searchRowPad)
        .animation(.default, value: searchActive)
    }

    // ── SEARCH RESULTS (contacts, chats, groups, messages) ──
    var searchResults: some View {
        // NOTHING IS ASKED IN THE BODY (25.09, after the critic's 23.09 «one ask of each kind per pass»): the body draws
        // the hits of the query that has settled (refreshSearchHits) and nothing of a query still being scanned.
        let q = searchText.lowercased()
        let settled = searchHits.query == q
        let chats: [Chat] = settled ? searchHits.chats : []
        let contacts: [Chat] = settled ? searchHits.contacts : []
        let found: [MessageHit] = settled ? searchHits.found : []
        return List {
            if searchText.isEmpty {
                // nothing entered yet — show only contacts with status
                Section {
                    ForEach(recentContacts(in: orderedChats)) { chat in
                        NavigationLink(destination: ChatConversationView(chat: chat, onChatUpdate: updateChat)) {
                            contactRow(chat)
                        }
                        .modifier(MTResultBubble())
                    }
                } header: {
                    Text("CONTACTS").font(.caption).foregroundColor(.gray)
                }
            } else {
                if !chats.isEmpty {
                    Section {
                        ForEach(chats) { chat in
                            NavigationLink(destination: ChatConversationView(chat: chat, onChatUpdate: updateChat)) {
                                contactRow(chat)
                            }
                            .modifier(MTResultBubble())
                        }
                    } header: {
                        Text("CHATS, GROUPS AND CONTACTS").font(.caption).foregroundColor(.gray)
                    }
                }
                if !contacts.isEmpty {
                    Section {
                        ForEach(contacts) { chat in
                            NavigationLink(destination: ChatConversationView(chat: chat, onChatUpdate: updateChat)) {
                                contactRow(chat)
                            }
                            .modifier(MTResultBubble())
                        }
                    } header: {
                        Text("CONTACTS").font(.caption).foregroundColor(.gray)
                    }
                }
                if !found.isEmpty {
                    Section {
                        ForEach(found) { hit in
                            Button { ui.openChat(hit.chat, jump: hit.message.id) } label: {
                                messageHitRow(hit)
                            }
                            .modifier(MTResultBubble())
                        }
                    } header: {
                        Text("MESSAGES").font(.caption).foregroundColor(.gray)
                    }
                }
                if let e = endpointHit, !chats.contains(where: { $0.name.lowercased() == e }) {
                    Section {
                        NavigationLink(destination: ChatConversationView(chat: Chat(name: e, lastMessage: "", time: "", unread: 0, status: "Montana address", convId: e), onChatUpdate: updateChat)) {
                            HStack(spacing: 12) {
                                AvatarCircle(photoURL: nil, color: .blue, initial: MTNameBook.face(e, title: MTNameBook.display(conv: e)), size: 46)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(MTNameBook.display(conv: e)).font(.subheadline).bold().foregroundColor(.white)
                                    // NO YELLOW WORD (24.09, the noticed point 4 — the author's word «close it»): the accent is the
                                    // root's gold tint, and the line under the name wore it; it wears the platform's quiet colour.
                                    Text("Message on Montana").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .modifier(MTResultBubble())
                    } header: {
                        Text("GLOBAL SEARCH").font(.caption).foregroundColor(.gray)
                    }
                }
                if settled && chats.isEmpty && contacts.isEmpty && found.isEmpty && endpointHit == nil {
                    Text("Nothing found")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
        }
        // THE RESULTS AS THE SETTINGS' CANVAS (the author's word 26.09): the platform's inset grouped list, the settings' own,
        // the least margin off the sides (MTPageEdge.canvas); the rows' glass in MTResultBubble.
        .listStyle(.insetGrouped)
        .contentMargins(.horizontal, MTPageEdge.canvas, for: .scrollContent)
        .scrollContentBackground(.hidden)   // the results stand on the page's ground (MTSearchResultsFrame, 26.09)
        .task(id: searchText) { await refreshSearchHits(); await runEmailSearch() }
    }

    // contact row in search: avatar + name + status (was online / online)
    func contactRow(_ chat: Chat) -> some View {
        HStack(spacing: 12) {
            MTChatAvatar(chat: chat, size: 46, showPresence: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(MontanaAvatar.spokenName(store.title(for: chat))).font(.subheadline).bold().foregroundColor(.white)
                        .lineLimit(1).truncationMode(.tail)
                Text(chat.isGroup || chat.convId == nil
                        ? String(localized: String.LocalizationValue(chat.status), bundle: MTLanguage.bundle)
                        : (store.presenceWord(chat.convId ?? chat.name)?.text ?? ""))
                    .font(.caption)
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // found message row: chat avatar + name + message text
    func messageHitRow(_ hit: MessageHit) -> some View {
        HStack(spacing: 12) {
            MTChatAvatar(chat: hit.chat, size: 46)   // the one face of a chat
            VStack(alignment: .leading, spacing: 3) {
                Text(MontanaAvatar.spokenName(store.title(for: hit.chat))).font(.subheadline).bold().foregroundColor(.white)
                Text(hit.message.text).font(.caption).foregroundColor(.gray).lineLimit(2)
            }
            Spacer()
            Text(hit.message.time).font(.caption2).foregroundColor(.gray)
        }
        .padding(.vertical, 2)
    }
}

// ── ONE ROW IN THE CHAT LIST ──
// Action tile for the chat swipe
struct SwipeTile: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let action: () -> Void
    /// THE ONE GLASS OF EVERY TILE (the author's word 17.09): as the compose button's plate — a
    /// translucent grey under a white glyph, no colour telling one tile from another.
    static let glass = Color(white: 0.6, opacity: 0.32)
}

// Custom chat-row swipe: springs with the finger, separate rounded tiles with gaps.
struct SwipeChatRow<Content: View>: View {
    var leading: [SwipeTile] = []     // shown on swipe RIGHT
    var trailing: [SwipeTile] = []    // shown on swipe LEFT
    var onOpen: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var open: CGFloat = 0
    private let tileW: CGFloat = 52
    private let gap: CGFloat = 7

    private var trailingW: CGFloat { trailing.isEmpty ? 0 : CGFloat(trailing.count) * tileW + CGFloat(trailing.count + 1) * gap }
    private var leadingW: CGFloat { leading.isEmpty ? 0 : CGFloat(leading.count) * tileW + CGFloat(leading.count + 1) * gap }

    var body: some View {
        ZStack {
            HStack(spacing: gap) {           // right tiles (swipe left)
                Spacer(minLength: 0)
                ForEach(trailing) { tile($0) }
            }.padding(.horizontal, gap).opacity(offset < -1 ? 1 : 0)
            HStack(spacing: gap) {           // left tiles (swipe right)
                ForEach(leading) { tile($0) }
                Spacer(minLength: 0)
            }.padding(.horizontal, gap).opacity(offset > 1 ? 1 : 0)

            content()
                .background { MTPageGroundWindow() }   // the row covers its tiles with the page's own ground at its window's place (26.09)
                .contentShape(Rectangle())
                .onTapGesture { onOpen() }                 // closed: a tap opens the chat
                .offset(x: offset)
                .allowsHitTesting(open == 0)               // open: taps go to the tiles, not the row
        }
        .contentShape(Rectangle())
        .onTapGesture { if open != 0 { snap(0) } }         // tap on an open row — close
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    var nx = open + v.translation.width
                    if nx < -trailingW { nx = -trailingW + (nx + trailingW) * 0.3 }
                    if nx > leadingW { nx = leadingW + (nx - leadingW) * 0.3 }
                    if trailing.isEmpty, nx < 0 { nx = 0 }
                    if leading.isEmpty, nx > 0 { nx = 0 }
                    offset = nx
                }
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) || open != 0 else { return }
                    let f = open + v.translation.width
                    if f < -trailingW * 0.5 { snap(-trailingW) }
                    else if f > leadingW * 0.5 { snap(leadingW) }
                    else { snap(0) }
                }
        )
        .clipped()
    }
    private func snap(_ to: CGFloat) {
        open = to
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { offset = to }
    }
    @ViewBuilder private func tile(_ t: SwipeTile) -> some View {
        Button { snap(0); t.action() } label: {
            Image(systemName: t.icon)
                .font(.system(size: 19, weight: .semibold)).foregroundColor(.white)
                .frame(width: tileW, height: 46)   // TOUCH-OK: the tile is tileW (52) by 46 points, the capsule is the target
                .background(t.color.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(t.color.opacity(0.9), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

// The single media-message preview: chat list, quotes, replies (SSOT).
// The string is returned THROUGH A VARIABLE, so the catalog is attached here explicitly via
// String(localized:) — the Text(...) wrapper does not translate in that case.
// The caption under a photo/video matters more than the type label: show it, as familiar messengers do.
func mediaPreview(_ m: Message) -> String? {
    // One vocabulary with the letter's own words (MTRowLetter.mediaWords): a round note is a
    // video message, a voice a voice message — never a plain «video» or «media».
    if m.audioFile != nil { return MTRowLetter.mediaWords(kind: "aud") }
    // A STICKER IS A STICKER, NOT A PHOTO (the author's word 22.09): the row, the reply plate and
    // the banner all take their words here, and a sticker used to be called «Photo» in all three.
    if m.imageFile != nil, m.docName == MontanaCardPlate.stickerName { return String(localized: "Sticker", bundle: MTLanguage.bundle) }
    // A CARD'S PHOTO IS A BUSINESS CARD (the author's word 28.09): its caption is the card's words, not a caption to show.
    if m.imageFile != nil, m.text.hasPrefix(MontanaCardPlate.mark) { return String(localized: "Business card", bundle: MTLanguage.bundle) }
    if m.imageFile != nil { return MTRowLetter.mediaWords(kind: "img", caption: m.text) }
    if let v = m.videoFile { return MTRowLetter.mediaWords(kind: "vid", round: v.hasPrefix("vnote_"), caption: m.text) }
    // A MOVING PICTURE IS A GIF, NOT A FILE NAMED gif_a1b2 (23.09): the row, the reply plate and
    // the banner all take their word here, as the sticker does above.
    if let d = m.docFile, MontanaGif.isGif(m.docName ?? d) || MontanaGif.isGif(d) { return String(localized: "GIF", bundle: MTLanguage.bundle) }
    if m.docFile != nil { return MTRowLetter.mediaWords(kind: "doc", name: m.docName) }
    return nil
}

/// The row's words without the glyph the vocabulary puts first — when a thumbnail stands there.
enum MontanaRowWords {
    static func bare(_ p: String) -> String {
        for g in ["\u{1F3A4} ", "\u{1F4F9} ", "\u{1F4F7} ", "\u{1F4C4} ", "\u{1F4DE} "] where p.hasPrefix(g) { return String(p.dropFirst(g.count)) }
        return p
    }
}

/// ONE THUMBNAIL OF WHAT A LETTER CARRIES ([C-1], the author's word 16.09): the list row, the
/// reply bar and every place that shows a letter's media in small draw this one view, by the
/// store's one word for the kind (ChatStore.rowMediaKind) — the voice's round of glass (MTVoiceRound), the round note's
/// window with its poster, the photo, the video's poster, the music's note, the file's sheet.
struct MTLetterThumb: View {
    let kind: String
    let file: String?
    var mine = false
    var side: CGFloat = 20
    init(kind: String, file: String?, mine: Bool = false, side: CGFloat = 20) {
        self.kind = kind; self.file = file; self.mine = mine; self.side = side
    }
    init?(message m: Message, side: CGFloat = 20) {
        guard let k = ChatStore.rowMediaKind(m) else { return nil }
        self.init(kind: k, file: ChatStore.rowMediaFile(m), mine: m.isFromMe, side: side)
    }
    /// THE ONE PICTURE OF A LETTER IN SMALL (20.09, the author's word: one road on any phone and any
    /// iOS): a photo's small copy born from the file (16.09), else the poster the letter came with
    /// (cached) — never the whole photograph decoded for a row. The list row, the reply bar and the
    /// gallery's tile ask this one function; nothing chooses on its own.
    static func picture(kind: String, file: String?) -> UIImage? {
        guard let f = file else { return nil }
        var out: UIImage? = nil
        var src = "none"
        if kind == "img", let s = MontanaSmallPicture.image(f) { out = s; src = "small" }
        else if let p = videoThumbCached(f) { out = p; src = "poster" }
        // THE ROAD IS MEASURED (the author's word 20.09: a plate stood where the picture was, and the
        // picture came only after a relaunch): one line per file whenever the answer changes.
        seenLock.lock(); let was = seen[f]; if was != src { seen[f] = src }; seenLock.unlock()
        if was != src { MontanaP2PTrace.mark("row_thumb", "kind=\(kind) src=\(src) file=\(String(f.prefix(20)))") }
        return out
    }
    /// THE SAME CHOICE, FOR A PLATE-SIZED PICTURE (the critic 22.09): a video shows its poster, a
    /// picture shows the file. The small road above wears its own source (a 20-point copy born with
    /// the file); a plate wears the file itself, because a small copy blown up is a blur. What the
    /// KIND decides is one thing and lives here; what the SIZE decides stays where it was. The very
    /// line stood written out twice — the tile of a media group and the attachment waiting over the
    /// field — and a third copy was one careless paste away.
    static func plate(file: String, isVideo: Bool) -> UIImage? {
        if isVideo { return videoThumbCached(file) }
        return docImage(file)
    }

    private static var seen: [String: String] = [:]
    private static let seenLock = NSLock()
    /// WHETHER THE PICTURE IS THERE, in one number for the row's print: the file on disk, the poster
    /// on disk, or nothing yet. The cell used to be printed without it — a row configured before its
    /// picture existed kept the plate until something else about it changed (a relaunch, usually).
    static func stamp(kind: String, file: String?) -> Int {
        guard let f = file else { return 0 }
        if kind == "img" || kind == "vid" || kind == "vnote" {
            if FileManager.default.fileExists(atPath: attachmentURL(f).path) { return 2 }
            if FileManager.default.fileExists(atPath: posterURL(f).path) { return 1 }
        }
        return 0
    }
    private var poster: UIImage? { Self.picture(kind: kind, file: file) }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.22)
        Group {
            switch kind {
            case "aud":
                MTVoiceRound(side: side)   // the capsule's own round (one owner, the author's word 28.09), not a second drawing
            case "vnote":
                MontanaNoteFrame(badge: nil, side: side) {
                    if let t = poster { Image(uiImage: t).resizable().aspectRatio(contentMode: .fill) } else { Color.black }
                }
            case "img", "vid":
                if let t = poster {
                    Image(uiImage: t).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side).clipShape(shape)
                } else {
                    plate(kind == "img" ? "photo.fill" : "video.fill", shape)
                }
            // The shapes the person already knows (the author's word 16.09): the player's triangle for music, the
            // link for a link, the handset and the camera for the calls — drawn filled, as every glyph on a plate is
            // (the photo, the video, the document); the bar and the drawer wear the outlines (UIState.Glyph, 23.09).
            case "music":
                plate("play.fill", shape)
            case "acall":
                plate("phone.fill", shape)
            case "vcall":
                plate("video.fill", shape)
            case "link":
                plate("link", shape)
            default:
                plate("doc.fill", shape)
            }
        }
        .frame(width: side, height: side)
    }
    /// A glyph in the system's own gray (the author's word 16.09), on a quiet plate.
    private func plate(_ glyph: String, _ shape: RoundedRectangle) -> some View {
        shape.fill(Color(white: 0.16))
            .overlay(Image(systemName: glyph).font(.system(size: side * 0.5, weight: .semibold)).foregroundStyle(.secondary))
    }
}

/// WHAT A ROW OF THE CHAT LIST DRAWS, AS VALUES (23.09, the critic on T3's list). The row read the whole store
/// through its environment, so every change of the store — a presence word, a keystroke's draft in the chat open
/// above the list, a receipt of another conversation — drew every visible row again, while the container above
/// had just proven that nothing of theirs changed. The row draws these values and nothing else, and the
/// container's print is these values: a row is drawn again exactly when one of them moved, and a value the row
/// shows cannot slip past the print, because the row has no other source.
struct ChatRowModel: Hashable {
    // ONLY WHAT THE ROW DRAWS OF THE RECORD (1912, T1 22:13: nineteen rows reconfigured 26 ms after the first frame
    // with «field=model» and nothing on the screen changed): the whole record rode in the print, and the cold rows
    // giving way to the stored ones changed its words and time — values the row never draws.
    let ref: String              // the conversation's address — the handsets ask by it
    let color: Color             // the face's ground (Chat.color, from the name)
    let title: String            // the name as spoken (MontanaAvatar.spokenName)
    let face: String?            // the face's file; the local room wears one's own face instead
    let initial: String
    let local: Bool              // Saved Messages
    let montana: Bool            // the Montana room: the crown beside the name (29.09)
    let presenceActive: Bool
    let selfFace: Int            // one's own face's print, where the row wears it (the local room, my answer)
    let selfGlyph: String        // one's own letter, where my answer wears it
    let muted: Bool
    let blocked: Bool
    let status: DeliveryStatus?
    let time: String
    let draft: String?
    let reaction: String?
    let reactionMine: Bool
    let mediaKind: String?
    let mediaFile: String?
    let mediaMine: Bool
    let picture: Int             // whether the thumbnail's picture is on the device (MTLetterThumb.stamp)
    let preview: String
    let forced: Bool
    let unread: Int
    let pinned: Bool
}

extension ChatStore {
    /// THE ONE BUILDER OF A ROW'S VALUES ([C-1]): the chat list's rows and prints and the archive's rows ask here,
    /// from the store's own answers (rowPreview, rowTime, rowStatus, the name book).
    func rowModel(_ c: Chat) -> ChatRowModel {
        let montana = Self.isMontanaRoom(c.name)
        let local = Self.isLocalRoom(c.name) && !montana && !Self.isMeshRoom(c.name)   // the Montana room wears the logo, the mesh wall its antenna, not one's own face
        let media = rowMedia(c)
        let answer = rowReaction(c)
        let mine = answer?.mine == true
        let draft = listDrafts[c.name] ?? ""   // the list's own map (listDrafts): the open chat's words come when it is left
        return ChatRowModel(ref: c.convRef, color: c.color,
                            title: MontanaAvatar.spokenName(title(for: c)),
                            face: local ? nil : (montana ? montanaRoomFace : avatarFor(c)),
                            initial: initial(for: c),
                            local: local,
                            montana: montana,
                            presenceActive: !local && !c.isGroup && (presenceWord(c.convRef)?.tier ?? 0) > 0,
                            selfFace: local || mine ? MontanaSelfFace.tag : 0,
                            selfGlyph: mine ? E2E.myFaceGlyph() : "",
                            muted: mutedChats.contains(c.name),
                            blocked: blockedChats.contains(c.name),
                            status: rowStatus(c),
                            time: rowTime(c),
                            draft: draft.isEmpty ? nil : draft,
                            reaction: answer?.emoji,
                            reactionMine: mine,
                            mediaKind: media?.kind,
                            mediaFile: media?.file,
                            mediaMine: media?.mine ?? false,
                            picture: media.map { MTLetterThumb.stamp(kind: $0.kind, file: $0.file) } ?? -1,
                            preview: rowPreview(c),
                            forced: forcedUnread.contains(c.name),
                            unread: unread(for: c.name),
                            pinned: pinnedChats.contains(c.name))
    }
}

/// THE LIST'S OWN WORK, ONE LINE A WINDOW (the critic 23.09). The frame meter says whether the list scrolls
/// at the device's pace and nothing of what the list costs while it stands — and it stands alive under an
/// open chat, passing on every change of the store. Per window of thirty seconds or more with work: the
/// passes of the container, those that touched nothing, those made under an open chat, the rows it
/// reconfigured, the rows drawn, the builds of the ordered rows, and the milliseconds of each with the worst.
enum MTListWork {
    private static var since = 0.0, ms = 0.0, worst = 0.0, buildMs = 0.0
    private static var passes = 0, idle = 0, under = 0, changed = 0, builds = 0, drawnAt = 0
    static func build<T>(_ f: () -> T) -> T {
        let t0 = ProcessInfo.processInfo.systemUptime
        let r = f()
        builds += 1; buildMs += (ProcessInfo.processInfo.systemUptime - t0) * 1000
        return r
    }
    static func note(ms t: Double, rows: Int, changed c: Int, idle quiet: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if since == 0 { since = now; drawnAt = ChatRow.drawn }
        passes += 1; changed += c; ms += t; worst = max(worst, t)
        if quiet { idle += 1 }
        if ChatStore.openConvNow != nil { under += 1 }
        guard now - since >= 30 else { return }
        MontanaP2PTrace.mark("list_work", "passes=\(passes) idle=\(idle) under_chat=\(under) changed=\(changed) drawn=\(ChatRow.drawn - drawnAt) rows=\(rows) "
            + "ms=\(String(format: "%.1f", ms)) worst=\(String(format: "%.1f", worst)) builds=\(builds) build_ms=\(String(format: "%.1f", buildMs)) secs=\(Int(now - since))")
        since = now; drawnAt = ChatRow.drawn
        passes = 0; idle = 0; under = 0; changed = 0; builds = 0; ms = 0; worst = 0; buildMs = 0
    }
}

struct ChatRow: View {
    let model: ChatRowModel
    /// The line of the chats page: the App Library's measure (MTLibraryRow); other lists keep the row they had.
    var library = false
    /// How many rows were drawn — read and zeroed by the list's own measure (MTChatListView.Coordinator), so the
    /// price of a change of the store is a number in the diary.
    static var drawn = 0
    static func noteDrawn() { drawn += 1 }

    var body: some View {
        let _ = Self.noteDrawn()
        HStack(spacing: library ? MTLibraryRow.gap : 12) {
            // Saved Messages wears one's own face (the author's word 11.09) — the one face of a chat (MTChatFace).
            face(library ? MTLibraryRow.face : 58)
                .overlay(MontanaHexagon().stroke(Color.white.opacity(0.45), lineWidth: 1))   // the black face needs its rim on a black list

            // The two lines stand at fixed heights and the pair is centred on the avatar (the
            // author's word 11.09): the name line and the preview line keep one vertical seat
            // whatever a badge or a handset adds to them.
            VStack(alignment: .leading, spacing: 4) {
                // top row: name on the left, time on the right
                HStack(spacing: 5) {
                    CallInlineHandset(side: .green, peer: model.ref)   // 15.8
                    Text(model.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if model.montana { MTMontanaCrownMark(height: 18) }
                    if MTGroup.isKey(model.ref) { MTRoomRowMark(chat: model.ref) }   // a group's living room (07.10)
                    CallInlineHandset(side: .red, peer: model.ref)
                    if model.muted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Spacer()
                    // The ladder's dots, left of the hour, only when the last word was mine — the
                    // same view the chat draws under that letter; a letter that did not go wears
                    // the bubble's own red mark instead (the author's word 11.09).
                    if let st = model.status {
                        if st == .failed { MTFailedMark() } else { MTDeliveryDots(status: st) }
                    }
                    Text(model.time).font(.system(size: 14)).foregroundColor(.gray)
                }
                .frame(height: 22)
                .overlay(alignment: .bottomTrailing) {
                    // The blocked person's row wears the mark under the clock (the author's word 15.09).
                    if model.blocked {
                        Image(systemName: "nosign").font(.system(size: 11, weight: .semibold)).foregroundColor(.red).offset(y: 14)
                    }
                }
                // bottom row: the message on the left, the counter on the right
                HStack(alignment: .center, spacing: 6) {
                    // The voice's orb and the round note's poster stand in the row as in the player
                    // bar (the author's word 15.09); the words then carry no glyph of their own.
                    // A DRAFT STANDS UNDER THE NAME (the author's word 20.09): unsent words are what the
                    // person will see first on opening, so the row shows them first — the word «Draft:»
                    // in red and the text, in place of the last letter, the reference's own manner.
                    if let d = model.draft {
                        (Text("Draft:").foregroundColor(.red) + Text(verbatim: " " + d).foregroundColor(.gray))   // USER-DATA: the draft text
                            .font(.system(size: 16))
                            .lineLimit(1)
                    } else {
                    // The answer to a letter, the plate's way: the face of whoever answered, then the
                    // answer, then the letter's words (the author's word 20.09).
                    if let r = model.reaction {
                        if model.reactionMine {
                            MTSelfFace(size: 18, initial: model.selfGlyph)
                        } else {
                            face(18)
                        }
                        Text(verbatim: r).font(.system(size: 15))   // USER-DATA: the answer itself
                    }
                    if let k = model.mediaKind { MTLetterThumb(kind: k, file: model.mediaFile, mine: model.mediaMine, side: 20) }
                    Text(model.mediaKind == nil ? model.preview : MontanaRowWords.bare(model.preview))
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    }
                    Spacer()
                    if model.forced {
                        Circle().fill(Color.blue).frame(width: 11, height: 11)
                    } else if model.unread > 0 {
                        Text("\(model.unread)")
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.blue)
                            .clipShape(MontanaLongOctagon())
                    } else if model.pinned {
                        Image(systemName: "pin.fill")            // pinned chat — pin
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .rotationEffect(.degrees(45))
                    }
                }
                .frame(height: 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: library ? MTLibraryRow.face : 58)
        }
    }
    private func face(_ side: CGFloat) -> some View {
        MTChatFace(face: model.face, color: model.color, initial: model.initial, local: model.local, size: side)
            .modifier(MTPresenceBadge(active: model.presenceActive))
    }
}

/// THE HAIRLINE that parts two rows: 0.5 pt, from the face's line to the edge. ONE view — the
/// row's cell and the folded head draw the same one ([C-1]).
/// ONE PILL OF A SELECTION BAR ([C-1]): the chats tab's «Read all / Archive / Delete» and the
/// contacts tab's «Archive / Delete» are the same button.
struct MTSelectPill: View {
    let title: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.subheadline)
                .foregroundColor(destructive ? .red : .white)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.montanaOctagon())
    }
}

struct MTRowHairline: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(height: 0.5).padding(.leading, 29)
    }
}

/// THE CHAT LIST'S LINE IS THE PLATFORM'S OWN (the author's words 28.09, the picture of the App Library's search list: «the chats
/// page in the same native format as the App Library -- the lines in the same style, the page's ground blurred, the separators
/// between the lines and the width»). Measured on that picture (1284 x 2610 pixels at 3x): a line of 72 points; its icon 48 points,
/// centred in the line; the words 16 points after the icon; the separator from the words' edge to the margin on the right; the
/// icon's edge under the search field's edge. The field's edge here is ours (MTSearchField), measured, not copied.
enum MTLibraryRow {
    static let height: CGFloat = 72
    static let face: CGFloat = 48
    static let gap: CGFloat = 16
    /// The line's side margin: the search field's edge -- the search row's padding and the platform's inset of the capsule.
    static var side: CGFloat { MTSearchField.rowPad + MTSearchField.capsuleInset }
    /// Where the words -- and the separator under them -- begin.
    static var textLead: CGFloat { side + face + gap }
}

/// A line of the chat list in the App Library's measure: the side margins, the line's height, the whole line the target.
struct MTLibraryLine: ViewModifier {
    var place: String? = nil   // the name the line's place is kept under (MTBubbleFrames): where the menu's cloud rises
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, MTLibraryRow.side)
            .frame(height: MTLibraryRow.height)
            .background { if let place { MTBubbleFrameAnchor(id: place) } }
            .contentShape(Rectangle())
    }
}

/// The platform's separator under a line that stands outside the list (the archive row): its colour, one pixel, from the words'
/// edge to the margin on the right -- the list's own separator, drawn where the list cannot draw it.
struct MTLibraryHairline: View {
    @Environment(\.displayScale) private var scale
    var body: some View {
        Rectangle().fill(Color(uiColor: .separator)).frame(height: 1 / max(1, scale))
            .padding(.leading, MTLibraryRow.textLead).padding(.trailing, MTLibraryRow.side)
    }
}

/// A ROW IS A PLATE OF THE POSTS' GLASS (the author's words 26.09: «the chats', the contacts' and the calls' bubbles in system
/// one-tone liquid glass, without dividing lines», then «rectangular, of the style of the posts on the wall, with no gaps between
/// them»): the system's one-tone glass of a wall's post, in a rectangle -- the tree's row plate (MTGlassRowPlate) -- stood off the
/// screen's edges as the posts are (MTPageEdge.side), the words inside as a post's, and the rows adjoining: no gap, no line.
/// ON THE CANVAS (the author's words 26.09: «as the canvas in the settings, natively»): the list lays the rows in the platform's
/// inset grouped sections and wears the glass as the cell's own background (MTChatListView.canvasRow) -- the platform rounds it
/// and sets the margin, so the bubble draws no plate and keeps no side margin of its own.
/// `place`: the name the row's place on the screen is kept under (MTBubbleFrames) -- the plate's, where the menu's cloud rises.
struct MTRowBubble: ViewModifier {
    var place: String? = nil
    @Environment(\.mtRowOnCanvas) private var onCanvas
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background { if !onCanvas { MTGlassRowPlate() } }
            .background { if let place { MTBubbleFrameAnchor(id: place) } }
            .padding(.horizontal, onCanvas ? 0 : MTPageEdge.side)
            .contentShape(Rectangle())
    }
}

/// The row stands on its list's canvas (MTChatListView.canvasRow): its glass is the cell's own background, not its bubble's.
private struct MTRowOnCanvasKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var mtRowOnCanvas: Bool {
        get { self[MTRowOnCanvasKey.self] }
        set { self[MTRowOnCanvasKey.self] = newValue }
    }
}

/// THE SEARCH'S RESULTS AS THE SETTINGS' CANVAS (the author's words 26.09): the platform's inset grouped list (searchResults) --
/// each kind of result a section rounded by the platform, the least margin off the sides -- and every row on the posts' glass as
/// the row's background, as the settings' rows wear it, with no separator.
struct MTResultBubble: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(MTGlassRowPlate())
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowSeparator(.hidden)
    }
}

/// THE SLIDE OF THE PANES (the author's word 24.09): the pane at the finger's offset and the tab beside it one width
/// away on its side. It alone watches the offset and the neighbour, so it alone re-runs on every move of the finger; each
/// pane inside is compared by the pass that built it (MTPaneBox).
/// THE STROKE IS THE SLIDE'S ALONE (the author's word 30.09 ~23:13: «systemically, without hand-written stories, so that
/// everything works super fast, natively»; T1 30.09: 118 strokes, the median worst frame 62 ms and the tenth 95 ms; T3 73 and
/// 129 ms). The chats page read the neighbour to name the pages' pass and whether each was looked at: every change of the
/// stroke ran that page's body -- the chats sorted, every page handed anew -- and the neighbour, looked at from the stroke's
/// first point, was built again under the finger. Now the chats page hands the row its pages as promises (MTLazyPane) and a
/// pass once per pass of its own; the neighbour and the offset are read here only (UIState is observed by the fields a view
/// reads), and ONLY THE PAGE THAT STANDS IS LOOKED AT: the neighbour slides in with the rows it last applied and is built
/// again once it stands, after the spring (UIState.settle).
struct MTPaneSlide: View {
    struct Item { let pane: UIState.Pane; let view: AnyView }
    @Environment(UIState.self) var ui
    @ObservedObject var drag: MTTurnDrag
    let keep: MTPaneKeep
    let pass: UUID      // the chats page's last pass: the page that stands is drawn by it
    let panes: [Item]   // every page of the row, in the row's order (25.09)
    @State private var size: CGSize = .zero

    init(drag: MTTurnDrag, keep: MTPaneKeep, pass: UUID, panes: [Item]) {
        self.drag = drag; self.keep = keep; self.pass = pass; self.panes = panes
    }

    var body: some View {
        let w = 0 < size.width ? size.width : MTScene.size().width
        let pane = ui.pane, beside = ui.turnNeighbour?.pane
        let _ = keep.built.formUnion([pane] + (beside.map { [$0] } ?? []))
        let shown = panes.filter { keep.built.contains($0.pane) }
        // EVERY PAGE AT ITS PLACE IN THE ROW (25.09): the pane at the finger's offset, each other page a whole width away for
        // every step it stands from the pane -- the neighbour beside the finger, the rest off the screen. The spring carries
        // the offset to the neighbour's place; at its end the pane becomes the neighbour and the offset goes home in one still
        // transaction: nothing on the screen moves.
        let cur = shown.firstIndex { $0.pane == pane } ?? 0
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.pane) { i, item in
                let first = i == cur
                MTPaneBox(pass: keep.name(for: item.pane, live: first, of: pass), live: first, content: item.view)
                    .equatable()
                    .modifier(MTPaneShift(x: drag.x + CGFloat(i - cur) * w, drag: first ? drag : nil))
                    // A TAP SWITCHES WITHOUT A RIDE THROUGH THE ROW (25.09): the page chosen by a glyph or the drawer takes its place
                    // at once and shows itself, as it did when it was born there; only a stroke and its spring move the pages.
                    .transaction { t in if beside == nil { t.animation = nil } }
                    .opacity(first || item.pane == beside ? 1 : 0)
                    .allowsHitTesting(first)   // the page under the finger alone answers it
                    .accessibilityHidden(!first)
            }
        }
        .mtMeasureSize($size)
    }
}

/// A PAGE HANDED AS A PROMISE (30.09): the row's box (MTPaneBox) decides whether a page is drawn again, and the page's own
/// body -- the chats' sort, the tracks' rows -- runs only then, never in the pass of the chats page that hands the row its pages.
struct MTLazyPane: View {
    let build: () -> AnyView
    var body: some View { build() }
}

/// The name of the pages' last build: the chats page renews it at every pass of its own; the page that stands is drawn by the
/// newest, a page not looked at keeps the name it was last built by, so nothing of it is diffed again until it is looked at;
/// and a page once built stays built (25.09) -- `built` grows and never shrinks.
final class MTPaneKeep {
    var pass = UUID()
    var built: Set<UIState.Pane> = []
    private var held: [UIState.Pane: UUID] = [:]
    func renew() -> UUID { pass = UUID(); return pass }
    func name(for p: UIState.Pane, live: Bool, of current: UUID) -> UUID {
        if live { held[p] = current; return current }
        if let h = held[p] { return h }
        held[p] = current
        return current
    }
}

/// WHETHER A PAGE UNDER THE BAR IS LOOKED AT (25.09): the page that stands and the one sliding in beside the finger; every
/// other page of the row keeps its build and its list as they were, and its list applies nothing until it is looked at again
/// (MontanaTimePanelList reads it, MTChatListView obeys it). A list elsewhere is always looked at.
private struct MTPaneLiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var mtPaneLive: Bool { get { self[MTPaneLiveKey.self] } set { self[MTPaneLiveKey.self] = newValue } }
}

/// THE PANE'S SHIFT, DRAWN BY THE PLATFORM'S OWN INTERPOLATION (the critic's pass 24.09): the offset as before, and the
/// place it has reached this frame written back for the pane alone (MTTurnDrag.shown) -- the reference reads its
/// presentation layer for the same end: a stroke that lands mid-settle continues from where the pages stand.
struct MTPaneShift: GeometryEffect {
    var x: CGFloat
    let drag: MTTurnDrag?   // the pane's own; the neighbour writes nothing
    var animatableData: CGFloat { get { x } set { x = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        drag?.shown = x
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

/// A PANE THAT MOVES WITHOUT BEING BUILT AGAIN (24.09): the platform's own rule — a view equal to its last value is
/// not updated — with the pass that built the pane as the measure of equality.
struct MTPaneBox: View, Equatable {
    let pass: UUID
    let live: Bool   // looked at (25.09): handed down to the page's list (mtPaneLive)
    let content: AnyView
    static func == (a: MTPaneBox, b: MTPaneBox) -> Bool { a.pass == b.pass && a.live == b.live }
    var body: some View { content.environment(\.mtPaneLive, live) }
}

/// THE PUCK RIDES WITH THE FINGER (the author's word 24.09; the reference's tab strip): under the chosen glyph while the
/// page stands, and on its way to the neighbour's glyph by the pane's own progress while the finger drags — the distance
/// in slots, the progress the pane's offset over the page's width. Only this wrapper watches the offset; the bar does not.
/// The roles are read fresh here too (the critic 24.09): the bar hands over only the slot it draws the puck in, and the
/// puck stands where the pane and its neighbour say, even in the pass where the bar's home is one pass stale.
struct MTPuckSlide<Content: View>: View {
    @Environment(UIState.self) var ui
    @ObservedObject var drag: MTTurnDrag
    let slotOf: (UIState.Pane) -> Int?
    let frames: [Int: CGRect]              // every slot's frame in the row, named by the slots themselves
    @ViewBuilder let content: Content

    var body: some View {
        let w = MTScene.size().width
        let progress = w > 0 ? min(1, abs(drag.x) / w) : 0
        // The home is the pane's slot, the pane's alone (the critic 25.09); the bar draws the puck only while the pane has one.
        let from = slotOf(ui.pane) ?? 0
        let to = ui.turnNeighbour.flatMap { slotOf($0.pane) } ?? from
        let home = frames[from] ?? .zero
        let next = frames[to] ?? home
        // Every move of the home is a line: a puck that stays while the page turns is then a number, not a feeling.
        let _ = MontanaP2PTrace.markChanged("puck", "slot=\(from) pane=\(ui.pane) empty=\(home.width < 1 ? 1 : 0)")
        content
            .frame(width: home.width + progress * (next.width - home.width), height: home.height)
            .position(x: home.midX + progress * (next.midX - home.midX), y: home.midY)
    }
}

/// The frames of the bar's slots, each named by its slot (the row's one puck reads them).
struct MTBarSlotKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
