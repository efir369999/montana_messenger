//
//  MontanaMessageMenu.swift
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



// A self-contained message context menu (lives in a separate window: its own @State,
// no dependencies on the parent's state — it does not update in another window).
// THE ANSWERS UNDER A LETTER ARE DRAWN FROM A LIVE BOARD, AND THE ROW IS NOT REBUILT.
//
// A reaction used to change the row's fingerprint, and the container answered the only way it
// knows: it rebuilt the whole cell — the letter measured again, the media made again, everything
// — for one small plate. On a long letter that rebuild is what a person sees as slowness: the
// answer was already in the model within milliseconds, and the drawing came later.
//
// The reference client does not rebuild the message for this: it keeps the reaction node and only
// lays it out again. This is the same thing in our shape, and the same shape the transfer ring
// already uses — the cell is not reconfigured per tick, the part that changed redraws itself.
//
// The store stays the one truth of what a letter holds; the board is its living face, written in
// the SAME move as the store by one writer, so the two cannot drift.
final class MTReactionBoard: ObservableObject {
    static let shared = MTReactionBoard()
    @Published var of: [MID: [String]] = [:]
    @Published var mine: [MID: String] = [:]
    @Published var peer: [MID: String] = [:]
    /// The one writer: the store first, its face in the same move.
    func show(_ m: Message) {
        of[m.id] = m.reactions
        mine[m.id] = m.myReact
        peer[m.id] = m.peerReact
    }
    /// The answer the correspondent is named on — the same first-sight rule as `shown`.
    func peerOf(_ m: Message) -> String? { peer[m.id] ?? m.peerReact }
    /// THE ONE DECISION POINT for what stands under a letter and whose it is. A letter the board
    /// has not met yet is answered from the letter itself — that is not a second truth, it is this
    /// same rule reading the store on first sight. Two such rules written in two places would
    /// differ on the first answer and agree on the second, which is exactly how a defect looks.
    func shown(_ m: Message) -> (plates: [String], mine: String?) {
        (of[m.id] ?? m.reactions, mine[m.id] ?? m.myReact)
    }
}

// FROM THE FINGER TO THE PIXEL — one clock, so "slow" becomes a number. The change of the letter
// is already measured and takes single milliseconds; what is not measured is the distance between
// that change and the moment the feed shows it. This holds the instant of the tap until the feed
// applies, and the journal says how long it was and whether the feed thought nothing had changed.
enum MTReactClock {
    static var tapAt: Double = 0
    static var tapId: MID? = nil   // the letter reacted to — the feed measures its cell (react_cell)
    /// THE LAST ACT ON THE MENU, by name (20.09): «react», «row:Reply»… — set by the act itself,
    /// read once by the close, so the diary tells a reaction from a row from a tap on the dim.
    static var act: String = ""
    static func closedAfter() -> String { let a = act.isEmpty ? "dim" : act; act = ""; return a }
    static func tapped(_ id: MID) { tapAt = CACurrentMediaTime(); tapId = id; act = "react" }
    static func seen(_ what: String) {
        guard tapAt > 0 else { return }
        let ms = Int((CACurrentMediaTime() - tapAt) * 1000)
        tapAt = 0; tapId = nil
        MontanaP2PTrace.mark("react_seen", "\(what) ms=\(ms)")
    }
}

// WHAT A PERSON REACHES FOR FIRST — one place, and it learns.
//
// The seven answers written into the row were a guess about everybody. What a person actually
// uses is a fact about him, and it is kept here: every answer he sends is counted, and the row
// offers what he reaches for most, filled out with the common ones while he has no history yet.
// The full set is never written out beside this — it is the vocabulary the emoji panel speaks.
enum MTReactions {
    private static let key = "reactionUse"
    static let common = ["👍","❤️","🔥","😂","😮","😢","🎉","🙏","👏"]

    static func note(_ e: String) {
        var use = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        use[e, default: 0] += 1
        UserDefaults.standard.set(use, forKey: key)
        vocabulary = []   // the nine in front are about to stand in another order
    }

    /// THE WHOLE CHOICE AS ONE LIST, EACH NAME ONCE: the nine this person reaches for most stand
    /// first, then everything the emoji panel of the field speaks ([C-1] — not a second copy of
    /// what a person may feel). It is ONE list on purpose: a grid drawn from two lists holds names
    /// that stand in both, and for a lazy grid the same name is the same cell — the second place it
    /// lands stays EMPTY. That is where the holes in the opened reactions came from: the nine in
    /// front, six more repeated between the categories, and one repeated inside a category.
    private static var vocabulary: [String] = []
    /// A copy laid (23.09): the reactions reached for most are counted again from the store.
    static func forgetOrder() { vocabulary = [] }
    static var all: [String] {
        if vocabulary.isEmpty {
            var seen = Set<String>()
            vocabulary = (top(9) + emojiCategories.flatMap(\.emojis)).filter { seen.insert($0).inserted }
        }
        return vocabulary
    }

    /// HOW MANY ANSWERS THE ROW HOLDS ON THIS SCREEN (20.09): the row is the one the reference
    /// draws — a capsule hugging its answers — and it never leaves the screen. Seven at 30 pt with
    /// their room are wider than a 375-point window, so the count is what fits the cloud's width:
    /// the glyph measured by the platform, the row's own spacing and padding, the chevron. Never
    /// fewer than five, never more than seven.
    static func fitCount(width: CGFloat) -> Int {
        let glyph = ceil(("😀" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 30)]).width)
        let room = width - 32 - 32 - 13 - 10   // the cloud's side margins, the capsule's padding, the chevron and its spacing
        return max(5, min(7, Int(floor((room + 10) / (glyph + 10)))))
    }

    /// The most used first, then the common ones — never fewer than asked for, never a repeat.
    static func top(_ n: Int) -> [String] {
        let use = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        let mine = use.sorted { l, r in l.value == r.value ? l.key < r.key : l.value > r.value }.map(\.key)
        var out: [String] = []
        for e in mine + common where !out.contains(e) {
            out.append(e)
            if out.count == n { break }
        }
        return out
    }
}

// 14.4 — THE LETTER IS LIFTED FROM WHERE IT STANDS.
//
// A menu that drops the letter into the middle of the screen makes the eye look for it again: the
// thing a person just held moves out from under his finger. The letter keeps its place, and only
// the picture around it is fitted: if the block runs past the bottom it is moved up as a whole,
// and if it then runs past the top it rests on the top edge. Where the block cannot keep the place
// at all — the letter is not in the registry — the picture stands in the middle, as before.
// One place answers where the top of the picture goes, so the answer cannot differ by path.
struct MTMenuPlace {
    static let spacing: CGFloat = 12
    let viewportH: CGFloat
    let topEdge: CGFloat
    let bottomEdge: CGFloat
    let bubbleTopOnScreen: CGFloat?   // nil: the letter's place is unknown
    let reactionsH: CGFloat
    let cloudH: CGFloat

    var top: CGFloat? {
        guard let letterTop = bubbleTopOnScreen, cloudH > 0 else { return nil }
        var t = letterTop - reactionsH - Self.spacing
        if t + cloudH > viewportH - bottomEdge { t = viewportH - bottomEdge - cloudH }
        return max(topEdge, t)
    }
}

struct MTMenuPartHeight: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, b in b }
    }
}

extension View {
    func mtMenuPart(_ name: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: MTMenuPartHeight.self, value: [name: g.size.height])
        })
    }
}

struct MessageContextOverlay: View {
    let message: Message
    /// WHERE THE LETTER STOOD WHEN IT WAS HELD — the top of its bubble in window points, taken once
    /// at the hold (20.09). The menu used to read the live registry at every redraw, and its own
    /// bubble wrote that registry too: on the first touch of the row the cloud recomputed its place
    /// from its own bubble and moved under the finger. A value cannot move.
    var letterTop: CGFloat? = nil
    var faces: MTReactionFaces? = nil   // who answered — the plates under the bubble in the menu wear the faces too
    let isPinned: Bool
    let canEdit: Bool
    @ObservedObject var player: VoicePlayer
    var onReact: (String) -> Void
    var onReply: () -> Void
    var onCopy: () -> Void
    var onEdit: () -> Void
    var onPin: () -> Void
    var onForward: () -> Void
    var onSelect: () -> Void
    /// THE STICKER'S OWN ROWS (the author's word 22.09): «edit sticker» opens the editor and sends
    /// a NEW sticker -- another's letter is never touched -- and «view sticker set» opens the set
    /// this phone keeps. Both stand only when the letter is a sticker; a plain letter never sees them.
    var onEditSticker: (() -> Void)? = nil
    var onViewSet: (() -> Void)? = nil
    /// The set's link: the set's own name and its title, and not one address of anybody (22.09).
    var onCopyLink: (() -> Void)? = nil
    var onReport: () -> Void = {}   // Guideline 1.2: the peer's letter can be reported from its menu
    /// The profile's menu (the author's word 15.09): the SAME cloud as the chat's, other rows —
    /// show in chat, forward, delete, select. Set = profile mode.
    var onShowInChat: (() -> Void)? = nil
    /// Deletion is asked RIGHT HERE, under the bubble, not with a system sheet at the bottom.
    /// The sheet led the eye away from the message it asked about and arrived in a foreign
    /// style — the person chose blindly. The question stands where the long-press answer stood.
    let canDeleteForEveryone: Bool
    let ladder: Bool
    /// A row its caller keeps is offered no deletion.
    var canDelete = true
    var onDeleteMine: () -> Void
    var onDeleteEveryone: () -> Void
    var onClose: () -> Void
    /// The letters of a media group under the menu: the bubble is drawn as the plate it is in the feed.
    var members: [Message] = []
    @State private var shown = false
    @State private var confirmingDelete = false
    @State private var parts: [String: CGFloat] = [:]
    @State private var reactionsOpen = false
    @State private var placeSaid = false
    @State private var rowFrame: CGRect = .zero   // the reactions row in window points — the diary compares the finger with it
    @State private var rowSize: CGSize = .zero    // the row's own size — the cloud reserves exactly this
    /// THE ROW AS THE REFERENCE DRAWS IT (the author's word 20.09: «put the row back as it was»): a
    /// capsule hugging its answers, ten points apart, the chevron last. It never leaves the screen by
    /// construction — the count of answers is what fits this window (MTReactions.fitCount). It is a
    /// node of its own beside the scrolling cloud, at the place the cloud reserves (see the cloud).
    private var reactionsRow: some View {
        HStack(spacing: 10) {
            ForEach(MTReactions.top(MTReactions.fitCount(width: MTScene.size().width)), id: \.self) { e in
                Button { onReact(e) } label: { Text(e).font(.system(size: 30)) }
            }
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { reactionsOpen = true }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .montanaFingerRoom(layout: 17)   // the row keeps the chevron's 17 points, the finger gets 44
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .background(GeometryReader { g -> Color in
            let sz = g.size
            if sz != rowSize { DispatchQueue.main.async { rowSize = sz } }
            return Color.clear
        })
        .mtOnScreen("menu-reactions", axes: .horizontal)   // the cloud scrolls under the finger; the row answers for its sides
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

            // 14.1 — THE WHOLE CLOUD IN ONE SCROLLING CONTAINER. Reactions, the bubble and the
            // list of actions are one picture: taller than the screen, it travels under the
            // finger instead of being cut off at both ends. The area that closes the menu lives
            // INSIDE the container and under the cloud, exactly as the reference client keeps
            // its dismiss node inside the scrolling node — otherwise the container would eat
            // every tap meant for the dim.
            // 14.3 — THE PICTURE STANDS ON THE VIEWPORT, NOT ON THE WINDOW, AND KEEPS ITS EDGES.
            // The window is the whole glass, notch and home line included; the viewport is what a
            // person can actually see. Measuring the empty ground by the window made it taller
            // than the place it lives in, so the picture rode a few points under the notch and the
            // home line and could never quite come to rest. It is measured by the viewport now,
            // and the two edges are named once, here, in the numbers the reference client keeps:
            // eight points below the status bar, ten above the home line.
            GeometryReader { geo in
                let place = MTMenuPlace(viewportH: geo.size.height,
                                        topEdge: 8, bottomEdge: 10,
                                        bubbleTopOnScreen: letterTop.map { $0 - geo.frame(in: .global).minY },
                                        reactionsH: parts["reactions"] ?? 0,
                                        cloudH: parts["cloud"] ?? 0)
                ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .top) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { onClose() }
                        if let t = place.top {
                            cloud.padding(.top, t)
                        } else {
                            cloud.frame(maxHeight: .infinity)   // place unknown — the middle, as before
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .id("menu-cloud")
                }
                .scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(MTMenuPartHeight.self) { parts = $0 }
                // A LETTER TALLER THAN THE SCREEN OPENS ON ITS BOTTOM (the author's word 22.09): the actions
                // are what the hold asked for — the cloud comes to rest with its end in view, the letter's
                // bottom above the list, at once and without a transition; a short letter keeps its place.
                .onChange(of: parts) { _, p in
                    guard let cloudH = p["cloud"], cloudH > 0, (p["reactions"] ?? 0) > 0 else { return }
                    let room = geo.size.height - 8 - 10
                    if (place.top ?? 0) + cloudH > room {
                        var tx = Transaction(); tx.disablesAnimations = true
                        withTransaction(tx) { reader.scrollTo("menu-cloud", anchor: .bottom) }
                    }
                }
                }
                // Where the cloud stands, in numbers — once the parts are measured (20.09).
                .onChange(of: parts) { _, p in
                    guard !placeSaid, (p["cloud"] ?? 0) > 0, (p["reactions"] ?? 0) > 0 else { return }
                    placeSaid = true
                    let kind = message.imageFile != nil ? "img" : message.videoFile != nil ? "vid" : message.audioFile != nil ? "aud" : message.docFile != nil ? "doc" : "text"
                    let letter = letterTop.map { Int($0 - geo.frame(in: .global).minY) } ?? -1
                    let r = rowFrame
                    MontanaP2PTrace.mark("menu_open", "kind=\(kind) mine=\(message.isMine ? 1 : 0) caption=\(message.text.isEmpty ? 0 : 1) top=\(Int(place.top ?? -1)) letter_top=\(letter) reactions_h=\(Int(p["reactions"] ?? 0)) cloud_h=\(Int(p["cloud"] ?? 0)) viewport=\(Int(geo.size.height)) row=\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height)) win=\(Int(MTScene.size().width))x\(Int(MTScene.size().height))")
                }
            }
            .scaleEffect(shown ? 1 : 0.94, anchor: message.isMine ? .trailing : .leading)
            .opacity(shown ? 1 : 0)

            // The row stands here, outside the scroll, at the place the cloud reserved for it —
            // the window names where every finger lands (MTTouchWindow) and menu_open names the row.
            if !reactionsOpen {
                GeometryReader { og in
                    let o = og.frame(in: .global)
                    reactionsRow
                        .position(x: rowFrame.midX - o.minX, y: rowFrame.midY - o.minY)
                        .opacity(rowFrame == .zero ? 0 : 1)
                }
                .scaleEffect(shown ? 1 : 0.94, anchor: message.isMine ? .trailing : .leading)
                .opacity(shown ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) { shown = true }
        }
    }

    private var cloud: some View {
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: MTMenuPlace.spacing) {
                // 14.9 — THE REACTIONS OPEN INTO THE WHOLE CHOICE. Seven answers cover most of
                // what a person means, and the eighth key opens every one of them. The full set is
                // NOT written out again here: it is the same vocabulary the emoji panel of the
                // input field speaks ([C-1]) — a second list of what a person may feel would drift
                // from the first.
                Group {
                    if reactionsOpen {
                        let choice = MTReactions.all
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9),
                                      spacing: 6) {
                                // ONE list, each name once (MTReactions.all): the nine he uses stand
                                // in the first row, then the whole choice. A cell is addressed by its
                                // PLACE, so no name can be asked to stand in two places at once.
                                ForEach(choice.indices, id: \.self) { i in
                                    Button { onReact(choice[i]) } label: {
                                        Text(choice[i]).font(.system(size: 28))
                                    }
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 1))
                    } else {
                        // THE ROW'S PLACE, NOT THE ROW (the author's word 20.09: «a reaction from the quick row
                        // does not land on media with a caption — only from the opened choice»). A captioned
                        // letter makes a cloud taller than the screen; the cloud then scrolls, and a button
                        // that is a child of a scrolling container answers only once the container has come
                        // to rest — the diary showed every tap in the first three seconds swallowed and the
                        // fourth taken, while the opened choice (a scroll of its own) answered at once. The
                        // reference keeps its reaction strip as a node of its own beside the scrolling
                        // content, moved with it: so here — the cloud reserves the row's size, the row stands
                        // outside the scroll at that place (reactionsRow), and follows the place as it moves.
                        Color.clear
                            .frame(width: max(rowSize.width, 1), height: max(rowSize.height, 56))
                            .background(GeometryReader { g -> Color in
                                let f = g.frame(in: .global)
                                if f != rowFrame { DispatchQueue.main.async { rowFrame = f } }
                                return Color.clear
                            })
                    }
                }
                .mtMenuPart("reactions")

                // The letter whole, at its own height. The author's word: a bubble is not cut into
                // a window of its own — the whole picture travels together, reactions and actions
                // with it. One thing moves, not three.
                MessageBubble(message: message, player: player, faces: faces, textIsSelectable: true, members: members)

                // the action menu — BELOW the bubble (order)
                VStack(spacing: 0) {
                    if confirmingDelete {
                        Text("Delete message?")
                            .font(.footnote).foregroundColor(.gray)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                        divider
                        if canDeleteForEveryone {
                            row("Delete for everyone", "trash", destructive: true, action: onDeleteEveryone)
                            divider
                        }
                        row("Delete for me", "trash", destructive: true, action: onDeleteMine)
                        divider.padding(.vertical, 2)
                        row("Cancel", "xmark") { withAnimation(.easeOut(duration: 0.15)) { confirmingDelete = false } }
                    } else if let show = onShowInChat {
                        row("Show in chat", "text.bubble", action: show)
                        divider
                        row("Forward", "arrowshape.turn.up.right", action: onForward)
                        if canDelete {
                            divider
                            row("Delete", "trash", destructive: true) {
                                withAnimation(.easeOut(duration: 0.15)) { confirmingDelete = true }
                            }
                        }
                        divider.padding(.vertical, 2)
                        row("Select", "checkmark.circle", action: onSelect)
                    } else {
                        if ladder {
                            // THE RUNG AND ITS MOMENT over the actions (the author's word 11.09): the
                            // same ladder line as under the bubble, with the time the rung was reached; a plate's
                            // rung and moment are its slowest letter's (MTLadder, 29.09).
                            let lead = 1 < members.count ? (MTLadder.lead(members) ?? message) : message
                            MTDeliveryLine(status: lead.deliveryStatus, at: lead.statusMoment, played: MTPlayed.of(lead))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 11)
                            divider
                        }
                        row("Reply", "arrowshape.turn.up.left", action: onReply)
                        if let onEditSticker {
                            divider; row("Edit sticker", "pencil.tip.crop.circle", action: onEditSticker)
                        }
                        if let onViewSet {
                            divider; row("View sticker set", "square.grid.2x2", action: onViewSet)
                        }
                        if let onCopyLink {
                            divider; row("Copy link", "link", action: onCopyLink)
                        }
                        if !message.text.isEmpty {
                            divider; row("Copy", "doc.on.doc", action: onCopy)
                        }
                        if canEdit { divider; row("Edit", "pencil", action: onEdit) }
                        divider
                        row(isPinned ? "Unpin" : "Pin", "pin", action: onPin)
                        if !MTRowLetter.ownRow(message.text) {   // a post's card, the money flow's row: this phone's own, nothing to pass on (30.09)
                            divider
                            row("Forward", "arrowshape.turn.up.right", action: onForward)
                        }
                        if canDelete {
                            divider
                            row("Delete", "trash", destructive: true) {
                                withAnimation(.easeOut(duration: 0.15)) { confirmingDelete = true }
                            }
                        }
                        if !message.isMine {
                            divider
                            row("Report", "exclamationmark.bubble", destructive: true, action: onReport)
                        }
                        divider.padding(.vertical, 2)
                        row("Select", "checkmark.circle", action: onSelect)
                    }
                }
                .frame(width: 250)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .mtMenuPart("cloud")
    }

    private var divider: some View { MTMenuDivider() }
    private func row(_ title: String, _ icon: String, destructive: Bool = false,
                     action: @escaping () -> Void) -> some View {
        MTMenuRow(title: title, icon: icon, destructive: destructive, action: { MTReactClock.act = "row:" + title; action() })
    }
}

/// ONE ROW OF A MENU CLOUD ([C-1], the author's word 16.09): the message menu's row — the
/// title left, the glyph right, red for a deed that cannot be undone — drawn by every menu of
/// the client, so a menu about a person reads exactly as a menu about a letter.
struct MTMenuRow: View {
    let title: String
    let icon: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(LocalizedStringKey(title)).foregroundColor(destructive ? .red : .white)
                Spacer()
                Image(systemName: icon).foregroundColor(destructive ? .red : .white.opacity(0.8))
            }
            .font(.system(size: 16))
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
    }
}
struct MTMenuDivider: View {
    var body: some View { Divider().overlay(Color.gray.opacity(0.3)) }
}

/// THE MENU ABOUT A PERSON (the author's word 16.09): the chat's own cloud — the same material,
/// the same rows, the same spring and the same place-keeping as the menu about a letter — for a
/// row of a list. The row keeps its place on the screen and the deeds stand under it; the chats
/// tab opens it by a hold, the contacts tab by a tap. The system's context menu stood here
/// before, slower than the chat's own and foreign in style.
struct MTPersonMenu: View {
    struct Deed: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        var destructive = false
        let action: () -> Void
    }
    let chat: Chat
    let anchor: CGRect?          // the row's frame on the screen; nil — the middle
    let deeds: [Deed]
    var onClose: () -> Void
    @State private var shown = false
    @State private var parts: [String: CGFloat] = [:]

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            GeometryReader { geo in
                let place = MTMenuPlace(viewportH: geo.size.height, topEdge: 8, bottomEdge: 10,
                                        bubbleTopOnScreen: anchor.map { $0.minY - geo.frame(in: .global).minY },
                                        reactionsH: 0, cloudH: parts["cloud"] ?? 0)
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .top) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { close(onClose) }
                        if let t = place.top { cloud.padding(.top, t) } else { cloud.frame(maxHeight: .infinity) }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    .padding(.top, 8).padding(.bottom, 10)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(MTMenuPartHeight.self) { parts = $0 }
            }
            .scaleEffect(shown ? 1 : 0.94, anchor: .leading)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) { shown = true } }
    }
    private func close(_ then: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.15)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: then)
    }
    private var cloud: some View {
        VStack(alignment: .leading, spacing: MTMenuPlace.spacing) {
            // The person as the row showed them — the thing the finger held keeps its place.
            MontanaChatFace(chat: chat, size: 44)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
            VStack(spacing: 0) {
                ForEach(Array(deeds.enumerated()), id: \.element.id) { i, d in
                    if i > 0 { MTMenuDivider() }
                    MTMenuRow(title: d.title, icon: d.icon, destructive: d.destructive) { close(d.action) }
                }
            }
            .frame(width: 250)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .mtMenuPart("cloud")
    }
}
