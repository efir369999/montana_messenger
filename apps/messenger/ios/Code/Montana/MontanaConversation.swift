//
//  MontanaConversation.swift
//  Montana — a Montana messenger
//
//  Cut out of ContentView.swift whole, declaration by declaration (the author's word 10.09):
//  nothing here was renamed or rewritten; the file holds one screen and what only it reads.
//

import SwiftUI
import Combine
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
import ContactsUI
import Contacts



// ════════════════════════════════════════════════════════════
// CHATCONVERSATIONVIEW — CONVERSATION INSIDE A SINGLE CHAT
// ════════════════════════════════════════════════════════════
// ── emoji set by category ──
struct EmojiCategory { let icon: String; let emojis: [String] }

let emojiCategories: [EmojiCategory] = [
    EmojiCategory(icon: "😀", emojis: [
        "😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃","🫠","😉","😊","😇","🥰","😍",
        "🤩","😘","😗","☺️","😚","😙","🥲","😋","😛","😜","🤪","😝","🤑","🤗","🤭","🫢",
        "🤫","🤔","🫡","🤐","🤨","😐","😑","😶","🫥","😏","😒","🙄","😬","🤥","😌","😔",
        "😪","🤤","😴","😷","🤒","🤕","🤢","🤮","🤧","🥵","🥶","🥴","😵","🤯","🤠","🥳",
        "🥸","😎","🤓","🧐","😕","🫤","😟","🙁","☹️","😮","😯","😲","😳","🥺","🥹","😦",
        "😧","😨","😰","😥","😢","😭","😱","😖","😣","😞","😓","😩","😫","🥱","😤","😡",
        "😠","🤬","😈","👿","💀","💩","🤡","👻","👽","🤖"
    ]),
    EmojiCategory(icon: "👍", emojis: [
        "👍","👎","👌","🤌","🤏","✌️","🤞","🫰","🤟","🤘","🤙","👈","👉","👆","👇","☝️",
        "🫵","✋","🤚","🖐️","🖖","👋","🤝","🙏","✍️","💅","🤳","💪","🦾","👏","🙌","🫶",
        "👐","🤲","🫱","🫲","🫳","🫴","👊","✊","🤛","🤜","🦵","🦶","👂","🦻","👃","🧠",
        "🫀","🫁","🦷","🦴","👀","👁️","👅","👄","🫦"
    ]),
    EmojiCategory(icon: "❤️", emojis: [
        "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕","💞","💓","💗","💖",
        "💘","💝","💟","♥️","💋","💌","💐","🌹","🌷","🌸","🌺","🌻","🌼","💮","🏵️","🌈",
        "✨","⭐","🌟","💫","⚡","🔥","💥","💯","🎉","🎊","🎁"
    ]),
    EmojiCategory(icon: "🐶", emojis: [
        "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐻‍❄️","🐨","🐯","🦁","🐮","🐷","🐸","🐵",
        "🙈","🙉","🙊","🐒","🐔","🐧","🐦","🐤","🐣","🦆","🦅","🦉","🦇","🐺","🐗","🐴",
        "🦄","🐝","🪲","🐛","🦋","🐌","🐞","🐜","🦗","🕷️","🦂","🐢","🐍","🦎","🐙","🦑",
        "🦐","🦀","🐡","🐠","🐟","🐬","🐳","🐋","🦈","🐊","🐅","🐆","🦓","🦍","🐘","🦛",
        "🐪","🐫","🦒","🦘","🐃","🐄","🐎","🐖","🐏","🐑","🐐","🦌","🐕","🐩","🐈","🐓",
        "🦃","🕊️","🐇","🐿️","🦔"
    ]),
    EmojiCategory(icon: "🍔", emojis: [
        "🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍈","🍒","🍑","🥭","🍍","🥥",
        "🥝","🍅","🍆","🥑","🥦","🥬","🥒","🌶️","🫑","🌽","🥕","🫒","🧄","🧅","🥔","🍠",
        "🥐","🥯","🍞","🥖","🥨","🧀","🥚","🍳","🧈","🥞","🧇","🥓","🥩","🍗","🍖","🌭",
        "🍔","🍟","🍕","🥪","🌮","🌯","🫔","🥙","🧆","🥗","🍝","🍜","🍲","🍛","🍣","🍱",
        "🍤","🍙","🍚","🍘","🍥","🥟","🦪","🍦","🍰","🎂","🧁","🍫","🍬","🍭","🍮","🍯",
        "☕","🍵","🧃","🥤","🍺","🍻","🥂","🍷","🥃","🍸","🍹","🍾"
    ]),
    EmojiCategory(icon: "⚽", emojis: [
        "⚽","🏀","🏈","⚾","🥎","🎾","🏐","🏉","🥏","🎱","🪀","🏓","🏸","🏒","🏑","🥍",
        "🏏","🥅","⛳","🪁","🎣","🤿","🥊","🥋","🎽","🛹","🛼","🛷","⛸️","🥌","🎿","⛷️",
        "🏂","🏋️","🤼","🤸","⛹️","🤾","🏌️","🏇","🧘","🏄","🏊","🤽","🚣","🧗","🚴","🚵",
        "🏆","🥇","🥈","🥉","🏅","🎖️","🎗️","🎫","🎟️","🎪","🤹","🎭","🎨","🎬","🎤","🎧",
        "🎼","🎹","🥁","🎷","🎺","🎸","🪕","🎻","🎲","♟️","🎯","🎳","🎮","🎰","🧩"
    ]),
    EmojiCategory(icon: "🚗", emojis: [
        "🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚐","🛻","🚚","🚛","🚜","🛵","🏍️",
        "🛺","🚲","🛴","🚨","🚔","🚍","🚘","🚖","✈️","🛫","🛬","🛩️","💺","🚁","🚀","🛸",
        "🚉","🚊","🚝","🚄","🚅","🚈","🚂","🚆","🚇","🚢","⛴️","🚤","🛥️","⛵","🚧","⛽",
        "🗺️","🗿","🗽","🗼","🏰","🏯","🏟️","🎡","🎢","🎠","⛲","⛱️","🏖️","🏝️","🏜️","🌋",
        "⛰️","🏔️","🗻","🏕️","⛺","🏠","🏡","🏘️","🏢","🏬","🏣","🏤","🏥","🏦","🏨","🌃",
        "🌆","🌇","🌉","🌁"
    ]),
    EmojiCategory(icon: "💡", emojis: [
        "⌚","📱","💻","⌨️","🖥️","🖨️","🖱️","💽","💾","💿","📀","📷","📸","📹","🎥","📞",
        "☎️","📟","📠","📺","📻","🧭","⏰","⏱️","⌛","⏳","🔋","🔌","💡","🔦","🕯️","🧯",
        "💸","💵","💴","💶","💷","🪙","💰","💳","💎","⚖️","🧰","🔧","🔨","⚙️","🧲","🔫",
        "💣","🧨","🔪","🛡️","🚬","⚰️","🔮","🧿","🪬","💈","🔭","🔬","🩺","💊","💉","🩸",
        "🌡️","🧹","🧺","🧻","🚽","🚿","🛁","🧼","🪥","🔑","🗝️","🚪","🛋️","🛏️","🖼️","🎁",
        "🎈","🎀","🎊","🎉","📦","📫","✉️","📝","📚","📖","🔖","📌","📍","✂️","🖊️","📎"
    ]),
    EmojiCategory(icon: "🔣", emojis: [
        "❤️","💯","✅","❌","⭕","🚫","❗","❓","❕","❔","‼️","⁉️","💢","♨️","🔅","🔆",
        "✔️","☑️","🔘","⚪","⚫","🔴","🟠","🟡","🟢","🔵","🟣","🟤","🔺","🔻","🔸","🔹",
        "🔶","🔷","🔳","🔲","▪️","▫️","◾","◽","◼️","◻️","⬛","⬜","🟥","🟧","🟨","🟩",
        "🟦","🟪","🟫","🔈","🔉","🔊","🔇","📢","📣","🔔","🔕","➕","➖","➗","✖️","♾️",
        "💲","💱","™️","©️","®️","🔝","🔚","🔙","🔛","🔜","✳️","✴️","❇️","🔟","🆗",
        "🆕","🆒","🆓","🆙","🆖","🅰️","🅱️","🆎","🅾️","🔠","🔡","🔢","🔣","🔤"
    ]),
]

/// The places kept for pictures being read at once: each thread fills its own, all filling is done
/// on the screen's thread, and the field is told once, when the last one has landed.
final class MTStageOrder {
    var slots: [ChatConversationView.MTPasted?]
    var done = 0
    init(_ n: Int) { slots = Array(repeating: nil, count: n) }
}

// bottom sheets (attachment picker / forwarding) — a single .sheet modifier for everything
enum ChatSheet: Identifiable {
    case forward(Message)
    case forwardMany([Message])
    case attach
    /// THE GALLERY OF THE ROW (the author's word 22.09): the phone's latest pictures, picked into
    /// the field rather than sent — one page, one owner, wherever the gallery is touched from.
    case gallery
    /// A set as a page (22.09): this phone's own when the name is empty, another's otherwise.
    case stickerSet(String)
    /// A picture on its way to becoming a sticker: the file in the media store.
    case stickerEdit(String)
    var id: String {
        switch self {
        case .forward(let m): return "fwd:\(m.id)"
        case .forwardMany(let ms): return "fwdmany:\(ms.count):\(ms.first?.id ?? "")"
        case .attach: return "attach"
        case .gallery: return "gallery"
        case .stickerSet(let p): return "stickerset:" + p
        case .stickerEdit(let f): return "stickeredit:" + f
        }
    }
}

// what we show over the chat full-screen (a single modifier for everything — otherwise SwiftUI gets confused)
/// A document to open: the stored file and the name the person gave it.
struct MTDocOpen: Identifiable, Equatable { let id: String; let name: String }
enum ChatModal: Identifiable {
    case camera
    case contact
    case card
    case fullVideo(String)
    var id: String {
        switch self {
        case .camera: return "camera"
        case .contact: return "contact"
        case .card: return "card"
        case .fullVideo(let f): return "vid:\(f)"
        }
    }
}


struct MTNoEdgeBlur: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}

extension UIScrollView {
    /// The same for a scroll view of UIKit (23.09: the feed and the chat list that runs to the screen's edges draw
    /// their own edge, MTEdgeWash): the newest system's blur is hidden on every edge, or given back.
    func mtHideEdgeEffects(_ hidden: Bool = true) {
        if #available(iOS 26.0, *) {
            topEdgeEffect.isHidden = hidden
            bottomEdgeEffect.isHidden = hidden
            leftEdgeEffect.isHidden = hidden
            rightEdgeEffect.isHidden = hidden
        }
    }
}

// Reference arrangement (the chat node: insets.top += navigationBarHeight, and the bar draws
// its own background): the conversation ENDS under the bar instead of sliding beneath it, and the
// bar is opaque. Nothing shows through, so the system has nothing to blur at the scroll edge — the
// wash-out disappears by construction, identically on every system.
struct MTOpaqueChatBar: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        // ON iOS 26 THE BAR IS THE SYSTEM'S (the author's word 18.09, the Files app and the peer profile
        // as the reference): an opaque bar of ours turned the bar's marks flat — the platform draws its
        // glass circles only on its own bar. The scroll-edge wash-out is hidden there by the edge effect
        // itself (MTNoEdgeWash); the opaque bar stays for the older systems that have no glass.
        // NOTHING BEHIND THE BAR EITHER (the author's word 21.09, as the compose panel): the feed runs
        // on to the window's top (MTFeedFrame.overlapTop) and shows through the bar on every system;
        // the marks stand on their own glass. The opaque bar of the older systems is gone with it.
        content.toolbarBackground(.hidden, for: .navigationBar)
    }
}

// ── SSOT of a peer's display name ────────────────────────────────────────────
// The reference resolves a title in ONE place (displayTitle) from ONE stored peer. We had two
// resolvers over three stores with different priorities — a rename landed in one of them and the
// other kept showing the old text. This is now the single resolver; every consumer calls it and
// nobody copies a name into another entity.
// Priority, most explicit first: local rename of this chat -> address book -> the name the peer
// declared over E2E -> short address.
/// One's own caption and circle letter. The address serves as no source: it is eternal and
/// ties together everything a person does, and a private account has no identifying marks at all.
enum MontanaSelf {
    /// A person's name is one across the whole tree: the one they CLAIMED by fixing it in the
    /// name layer. The profile field stores the same value for display, but the truth is one
    /// and it comes from here: two sources of one name diverge at the first change.
    static var name: String { MontanaNames.heldName ?? "" }   // a lapsed name is not the person's any more (24.09)
    static var initialSource: String { name.isEmpty ? "·" : name }
    /// WHAT I SAY OF MYSELF IS WHAT MY HAND LAST WROTE -- NEVER WHAT A READ FAILED TO FIND (30.09). A key that is not
    /// there is not knowledge: the phone not yet unlocked since it started, a seat parked, a restore whose picture has
    /// not landed. Read as «none», it went out as the person's own word and erased the living face on every peer's
    /// screen (T3 30.09 01:47: removed, removed, received seventeen seconds later). An empty value is the hand's «none»
    /// (MontanaSelfFace.clear, a bio wiped in the profile); no value at all is silence. A record that merely lacks a
    /// value never replaces the known one.
    static func holds(_ keys: String...) -> Bool {
        keys.contains { UserDefaults.standard.object(forKey: $0) != nil }
    }
}


// SSOT: the single name of the feed's bottom anchor — every scroll targets it, atBottom derives from it.
let chatBottomAnchor = "BOTTOM"
let chatTopAnchor = "CHAT-TOP"

// 10-L.1 The status-bar tap in an inverted feed: the system jump targets offset zero — the
// visual BOTTOM. The cure is a DECOY: the feed itself opts OUT of the system jump, and an
// invisible empty scroll view (with somewhere to scroll: content +1000, offset 1000) stays
// the only candidate — its shouldScrollToTop fires our own upward ride and returns false.
final class MTScrollToTopDecoy: UIScrollView, UIScrollViewDelegate {
    var action: () -> Void = {}
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        delegate = self
        scrollsToTop = true
        contentInsetAdjustmentBehavior = .never
        showsVerticalScrollIndicator = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var frame: CGRect {
        didSet {
            contentSize = CGSize(width: frame.width, height: frame.height + 1000)
            contentOffset = CGPoint(x: 0, y: 1000)
        }
    }
    // HONEST INTERIM (10-L.1). The upward ride demands EXACTLY ONE candidate, and the only
    // race-free way to have one is owning the birth of every scroll view — the engine that
    // owns its history container (~150 birth sites of scrollsToTop=false in the classic
    // model). Until the feed owns its container (10-L.6/10-L.8), this decoy stays a SECOND
    // permanent candidate: with two or more, the system gesture does nothing — documented
    // behavior, not luck. Deterministic silence beats a jump in the wrong direction; no
    // foreign view is ever mutated, no patrol runs.
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        action()
        contentOffset = CGPoint(x: 0, y: 1000)   // the decoy can always travel — stays a qualified candidate
        return false
    }
}
struct MTStatusBarTapCatcher: UIViewRepresentable {
    var onTap: () -> Void
    func makeUIView(context: Context) -> MTScrollToTopDecoy {
        let v = MTScrollToTopDecoy(frame: .zero)
        v.action = onTap
        return v
    }
    func updateUIView(_ v: MTScrollToTopDecoy, context: Context) { v.action = onTap }
}


// SSOT of the input text: the panel owns what is being typed. Only the
// input bar observes it, so a keystroke re-renders the bar alone — never the feed. Typing used
// to invalidate the whole conversation view ~16x/s, and each graph tick copies that view struct
// per visible row: that copy storm was the sender-side freeze.
final class ChatInputModel: ObservableObject {
    @Published var text: String
    @Published var caret: Int = 0        // caret offset: part of the input state, streamed with the text
    init(text: String = "") { self.text = text; caret = (text as NSString).length }
}

// The «scroll to bottom» button is the ONLY observer of the feed position.
// 10-C.3 Presence privacy BY CONSTRUCTION: what is not sent does not exist. One switch is
// the one door — beacons fall silent, a single farewell word with the "h" tail tells new
// clients to coarsen the stamp they already hold (old parsers read only the leading digit —
// the tail is invisible to them, verified against their code), and reciprocity applies:
// a hidden person sees others' stamps as coarse classes too.
enum MontanaPresencePrivacy {
    static var sharing: Bool { UserDefaults.standard.object(forKey: "presenceSharing") as? Bool ?? true }
    static func setSharing(_ v: Bool) {
        guard v != sharing else { return }
        UserDefaults.standard.set(v, forKey: "presenceSharing")
        MontanaTrace.mark("presence_privacy", "sharing=\(v ? 1 : 0)")
        if v { E2E.shared.appPresence(open: true, again: true) }   // step back into the light at once
        else { E2E.shared.presenceFarewell() }             // one honest word, then silence
    }
    static func peerHidesExact(_ ref: String) -> Bool { UserDefaults.standard.bool(forKey: "phide_" + ref) }
    /// The LATEST word says whether they hide (24.09): the live lane, the chat's word and the node's swept word all
    /// carry it, and an older word swept from the node used to lift a newer «hides» -- one phone then read the
    /// exact moment and another the coarse class. The moment travels with the flag; an older word changes nothing.
    static func notePeerHides(_ ref: String, _ hides: Bool, at moment: Double) {
        let held = UserDefaults.standard.double(forKey: "phideAt_" + ref)
        guard moment >= held else { return }
        UserDefaults.standard.set(moment, forKey: "phideAt_" + ref)
        guard peerHidesExact(ref) != hides else { return }
        UserDefaults.standard.set(hides, forKey: "phide_" + ref)
        MontanaTrace.mark("presence_privacy", "peer=\(String(ref.prefix(10))) hides=\(hides ? 1 : 0)")
    }
}

// 10-C.2 One-shot alarm exactly on the phrase boundary (one alarm per boundary): no per-second
// polling — the timer fires at the moment the line must change, re-renders, re-arms.
final class MTSeenRefresh: ObservableObject {
    @Published private(set) var beat = 0
    private var timer: Timer?
    private var ts: Double?
    func arm(_ ts: Double?) { self.ts = ts; schedule() }
    private func schedule() {
        timer?.invalidate(); timer = nil
        guard let ts else { return }
        let diff = Date().timeIntervalSince1970 - ts
        let wait: Double
        if diff < 60 { wait = 60 - diff + 0.5 }
        else if diff < 3600 { wait = 60 - diff.truncatingRemainder(dividingBy: 60) + 0.5 }
        else if let next = Calendar.current.nextDate(after: Date(),
                                                     matching: DateComponents(hour: 0, minute: 0),
                                                     matchingPolicy: .nextTime) {
            wait = next.timeIntervalSinceNow + 1
        } else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(1, wait), repeats: false) { [weak self] _ in
            self?.beat += 1
            self?.schedule()
        }
    }
}


/// The floating day. It observes the ONE place the feed speaks from (FeedPin) and draws nothing
/// of its own — the pill is the very same one the flow uses, so the two can never look like two
/// different dates.
struct MTDayHeader<Pill: View>: View {
    @ObservedObject var pin: ChatConversationView.FeedPin
    @ViewBuilder var pill: (String) -> Pill
    var body: some View {
        pill(pin.topDay)
            .opacity(pin.showDayHeader && !pin.topDay.isEmpty ? 1 : 0)
            .allowsHitTesting(false)   // the day is a sign, never a target — the finger goes on scrolling
            .animation(.easeInOut(duration: 0.18), value: pin.showDayHeader)
            .animation(.easeInOut(duration: 0.18), value: pin.topDay)
    }
}

/// The ONE observer of the keys' cover for the floating player (the same law as ScrollDownButton:
/// the conversation body never observes the pin, only this leaf re-renders as the keys move).
struct MTPlayerRider<Content: View>: View {
    @ObservedObject var pin: ChatConversationView.FeedPin
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(.bottom, pin.keyboardCover)
    }
}

struct ScrollDownButton<Label: View>: View {
    @ObservedObject var pin: ChatConversationView.FeedPin
    var top = false   // the turned feed: the newest end is the feed's top edge, under the field
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    var body: some View {
        label()
            .frame(width: montanaTouchTarget, height: montanaTouchTarget)   // the platform's least target around the tier-sized plate
            .contentShape(Rectangle())
            .onTapGesture { action() }
            .padding(top ? .top : .bottom, top ? 10 : 10 + pin.bottomInset)   // above the bar and the player: the feed's own visual bottom, rides with the keys
            .opacity(pin.showDownButton ? 1 : 0)
            .allowsHitTesting(pin.showDownButton)
            .animation(.easeInOut(duration: 0.18), value: pin.showDownButton)
    }
}

/// The stored name is the one it was born with (moneyFlow.), never renamed. Read from any thread; the screens observe the change.
@MainActor final class MTLiveChat: ObservableObject {
    static let shared = MTLiveChat()
    @Published private(set) var turns = 0
    nonisolated static func isOn(_ conv: String) -> Bool { !conv.isEmpty && UserDefaults.standard.bool(forKey: "moneyFlow." + conv) }   // a conversation's own key (SeedScope.dataPrefixes)
    func on(_ conv: String) -> Bool { Self.isOn(conv) }
    func set(_ conv: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "moneyFlow." + conv)
        turns += 1
    }
}

// SSOT of screen capture: recording, mirroring and screen sharing all report through here.
// Live typing is suspended while the screen is captured — the peer's unsent words can never
// end up in a recording or a shared screen.
final class MTScreenCapture: ObservableObject {
    static let shared = MTScreenCapture()
    @Published private(set) var isCaptured = MTScene.isCaptured
    // The live stream exists ONLY while our app is genuinely on screen and not being captured:
    // recording, mirroring, screen sharing, a screenshot, the app switcher, control centre or a
    // background state all withdraw it. Nothing to see anywhere but the two live screens.
    var streamAllowed: Bool { !isCaptured && UIApplication.shared.applicationState == .active }
    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            LiveDraftState.shared.dropAllLive()
            LiveDraftState.shared.dropAllLive()      // peer stops at the source
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.isCaptured else { return }
            LiveDraftState.shared.reloadDurable()     // durable drafts return from the encrypted vault
            LiveDraftState.shared.reloadDurable()
        }
        // A still screenshot is answered like a capture: the live layer is cleared and the peer
        // is told to stop, so a second press has nothing to catch.
        NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { _ in
            LiveDraftState.shared.dropAllLive()
            LiveDraftState.shared.dropAllLive()
        }
        NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let v = MTScene.isCaptured
            guard v != self.isCaptured else { return }
            self.isCaptured = v
            if v { LiveDraftState.shared.dropAllLive() } else { LiveDraftState.shared.reloadDurable() }
        }
    }
}


// SSOT owner of the high-frequency live-draft state: ONE publisher, observed ONLY by the small
// bubble subview (LiveDraftSection) — so ~8 frames/s never re-render the conversation body,
// chatRows or the chat list. ChatStore delegates here; durable copies persist via the vault.
final class LiveDraftState: ObservableObject {
    static let shared = LiveDraftState()
    @Published var drafts: [String: String] = ChatStore.peerDraftsAll()   // conv -> the peer's unsent draft
    /// The moment of the newest draft word already shown, per conversation. Words are ordered by
    /// when they were SAID, not by when they arrived — two roads do not keep order.
    var saidAt: [String: Int] = [:]
    private(set) var carets: [String: Int] = [:]   // caret offset per conversation (live only, never stored)
    private(set) var replyMids: [String: String] = [:]   // bare mid the draft answers (live only)
    func setCaret(_ chat: String, _ c: Int) { if c >= 0 { carets[chat] = c } else { carets[chat] = nil } }
    func setReplyMid(_ chat: String, _ m: String) { replyMids[chat] = m.isEmpty ? nil : m }
    func applyLive(_ chat: String, _ text: String) {
        if text.isEmpty { drafts[chat] = nil; replyMids[chat] = nil } else { drafts[chat] = text }
    }
    // Screen capture: everything visible from the live layer disappears at once. Durable drafts
    // stay on disk (encrypted) and reappear when the capture ends.
    /// One chat's live chat went off (MTLiveChat, 04.10): that peer's live words leave the screen, the other chats keep theirs.
    func dropLive(_ conv: String) { drafts[conv] = nil; carets[conv] = nil; replyMids[conv] = nil }
    func dropAllLive() { drafts.removeAll(); carets.removeAll(); replyMids.removeAll() }
    // Deleting a conversation must erase the unsent words too — they are the most private thing
    // in the chat. One operation, called from every deletion path: live state, the encrypted
    // durable copies (peer's and our own), and the epoch bookkeeping that could resurrect a
    // stale frame after the chat is re-created.
    static func purgeConversation(_ conv: String) {
        let s = LiveDraftState.shared
        s.drafts[conv] = nil; s.carets[conv] = nil; s.replyMids[conv] = nil
        var pd = ChatStore.peerDraftsAll(); pd[conv] = nil; ChatStore.savePeerDrafts(pd)
        ChatStore.setCkptSent(conv, "")
        ChatStore.setDraft(conv, "")
    }
    func reloadDurable() { drafts = ChatStore.peerDraftsAll() }
}

// Live bubble: the peer's unsent draft, streamed while they type. Ephemeral by design —
// rendered from LiveDraftState only, never enters messages/history/receipts.
func mtDraftThemeHex(_ k: String, _ d: String) -> Color {
    Color(montanaHexString: UserDefaults.standard.string(forKey: k) ?? d)
}
struct LiveDraftBubble: View {
    let text: String
    let caret: Int
    var quoteAuthor: String? = nil
    var quoteText: String? = nil
    // The caret sits exactly where the sender holds it (their input state travels with the text).
    // It does not blink: a periodic redraw of a hosted subtree is exactly the kind of per-OS
    // behaviour that froze the layout on one firmware and not the other.
    var body: some View { bubble() }
    private func bubble() -> some View {
        let montana = (UserDefaults.standard.string(forKey: "bubbleStyle") ?? "montana") == "montana"
        let color = montana ? Color.white : mtDraftThemeHex("cbPeerText", BT.pTx)
        let ns = text as NSString
        let idx = max(0, min(caret < 0 ? ns.length : caret, ns.length))
        let pre = ns.substring(to: idx), post = ns.substring(from: idx)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let qt = quoteText {
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.accentColor).frame(width: 3, height: quoteAuthor == nil ? 16 : 32)
                        VStack(alignment: .leading, spacing: 1) {
                            if let qa = quoteAuthor {
                                Text(qa).font(.system(size: 12, weight: .bold)).foregroundColor(.white).lineLimit(1)
                            }
                            Text(qt).font(.system(size: 12)).foregroundColor(color.opacity(0.7)).lineLimit(1)
                        }
                    }
                }
                (Text(pre)
                 // USER-DATA: a separator glyph.
                 + Text(verbatim: "\u{2502}").foregroundColor(color.opacity(0.9))
                 + Text(post))
                    .font(.system(size: 17))
                    .foregroundColor(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background {
                if montana {
                    BubbleShape(mine: false, tail: false).fill(Color(white: MontanaSkin.isNative ? 0.16 : 0.13))
                        .overlay(BubbleShape(mine: false, tail: false).stroke(Color.white.opacity(MontanaSkin.isNative ? 0 : 0.35), lineWidth: 1))
                } else {
                    BubbleShape(mine: false, tail: false)
                        .fill(LinearGradient(colors: [mtDraftThemeHex("cbPeerFill1", BT.pF1),
                                                      mtDraftThemeHex("cbPeerFill2", BT.pF2)],
                                             startPoint: .top, endPoint: .bottom))
                }
            }
            .opacity(0.82)
            Spacer(minLength: 44)
        }
        .padding(.horizontal, 10)
    }
}

// The ONLY observer of the live-draft stream: frame updates re-render just this subview —
// growth handling belongs to the scroll anchor, not to this view.
struct LiveDraftSection: View {
    @ObservedObject private var live = LiveDraftState.shared
    @ObservedObject private var capture = MTScreenCapture.shared
    @EnvironmentObject var store: ChatStore
    let conv: String
    var peerKey: String = ""   // displayName key (convId when the chat has one)
    var onGrow: () -> Void = {}
    @State private var lastH: CGFloat = 0
    @ObservedObject private var flows = MTLiveChat.shared   // the live chat of this chat: live words live there alone (03.10)
    var body: some View {
        if flows.on(conv), !capture.isCaptured, let d = live.drafts[conv], !d.isEmpty {
            let q: Message? = live.replyMids[conv]
                .flatMap { store.localId(forMid: $0, chat: conv) }
                .flatMap { rid in store.messages[conv]?.first(where: { $0.id == rid }) }
            Group {
                if d.hasPrefix(MontanaCardPlate.mark) {
                    // The card being written: the gold plate fills in as the peer types (15.43).
                    let body = String(d.dropFirst(MontanaCardPlate.mark.count))
                    let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    HStack {
                        MontanaCardFace(lines: lines)
                            .opacity(0.92)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                } else {
                    LiveDraftBubble(text: d, caret: live.carets[conv] ?? -1,
                                    quoteAuthor: q.map { $0.isFromMe ? E2E.myDisplayName() : store.displayName(for: peerKey.isEmpty ? conv : peerKey) },
                                    quoteText: q.map { ChatStore.listPreview($0) })
                }
            }
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { lastH = g.size.height; DispatchQueue.main.async { onGrow() } }
                        .onChange(of: g.size.height) { _, h in
                            // next runloop turn: scrolling from inside a layout pass can re-enter it
                            if h > lastH + 0.5 { DispatchQueue.main.async { onGrow() } }
                            lastH = h
                        }
                })
        } else if store.typingChats.contains(conv), let word = store.presenceWord(conv) {
            HStack {
                HStack(spacing: 6) {
                    MTPresenceDot()
                    Text(word.text).font(.caption).foregroundColor(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .montanaFieldGlass(maxCut: .greatestFiniteMagnitude)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
        }
    }
}



/// WHAT THE «+» HOLDS, AS ONE VALUE (the author word 22.09): from the second line the plate opens
/// flat — its actions stand in a line under the field — so the bar is handed every one of them.
struct MTComposeActions {
    var gallery: () -> Void = {}
    var card: () -> Void = {}
    var file: () -> Void = {}
    var location: () -> Void = {}
    var contact: () -> Void = {}
}

// The input panel: owns and observes the text, exactly keeps its input node
// separate from the message list. Everything it needs from the screen arrives as closures.
struct ChatInputBar: View {
    @ObservedObject var model: ChatInputModel
    @Binding var focused: Bool
    @Binding var showEmoji: Bool
    /// THE ROW IS FOLDED OR OPEN BY THE PERSON'S OWN CHOICE (the author's word 23.09), and the choice
    /// outlives the chat and the launch. ONE value, OWNED BY THE PAGE and handed here: the bar is a
    /// node the page sizes, and a shape kept inside the node was a change the page never heard of —
    /// the node kept its old height and the words and the buttons spilled out of it, up onto the
    /// player and down under the keys (the author's screenshots of 1894 and 1896). The finger is its
    /// only writer, never a measurement: the shape used to be decided by whether the text needed a
    /// second line, and that closed a circle — a finger cannot oscillate.
    @Binding var composeOpen: Bool
    let cap: CGFloat
    let panel: UIView?
    /// THE RECORDING IS ONE VALUE WITH ONE OWNER (MontanaRecording, the author's word 19.09): the
    /// bar asks it (begin / lock / send / cancel) and draws from it; it keeps no flag of its own.
    @ObservedObject var rec: MontanaRecording
    private var recording: Bool { rec.isRecording }                          // a voice or video message is being held
    private var recordingLevels: [Float] { rec.isNote ? [] : rec.voice.levels }   // the live wave of the voice (empty for a video)
    private var recordingSeconds: Double? { rec.isNote ? rec.note.elapsed : nil } // the video note's seconds, in the strip where the voice's wave stands
    private var recordingPaused: Bool { rec.paused }                         // the tape stands
    /// The plate, open: each action the «+» used to hide, by its own name (the author's word 22.09).
    var actions = MTComposeActions()
    // The button's mode (the author's word 10.09): a single tap switches microphone and camera,
    // a hold records in the current mode. Remembered across chats and launches.
    @AppStorage("composeMediaMode") private var mediaMode = "mic"
    var onSend: () -> Void
    var onSendLongPress: () -> Void = {}   // «send later» / «remind me» (15.52)
    var onTextChange: (String) -> Void
    var onPasteImages: ([UIImage]) -> Void = { _ in }   // pictures pasted into the field (the author's word 10.09)
    var hasAttachment = false               // something waits above the field: the arrow sends even an empty field
    var hint = false                        // a press too short for a tape: the field says how to record
    /// A BAR OF WORDS ALONE: no picture, file, voice or round note stands, and the arrow is the bar's end.
    var textOnly = false
    /// A GROUP'S BAR (the author's words 06.10.2026 14:2x-14:3x MSK: «groups and channels with the whole of a chat, every kind of data»): the pictures, the files, the voice and the round note
    /// ride the group's carrier (MTGroup.carryMedia); a place, a person's card and one's own card are words of the app a group does
    /// not carry, so their buttons do not stand.
    var groupRoom = false
    /// WHICH TIERS THIS NODE DRAWS (the author's word 03.10 13:35: the turned ribbon is the normal one mirrored -- the line
    /// of words on top under the bar, the buttons on the keys). The whole bar in normal mode; under the turned feed the page
    /// hosts the words at the top (.field) and the open bar's row of buttons on the keys (.row), two nodes of one model.
    enum Part { case whole, field, row }
    var part: Part = .whole
    /// THE LIVE CHAT IS ON IN THIS CHAT (the author's words 03.10.2026 16:45 MSK: «make the send button a little bigger, the
    /// finger's size, like the call button, in its style»; «the field with the system's highlight, and below all the buttons in
    /// the system's blue circle»): the send plate stands at the bar marks' 44 (MTBarRoundMark), and the field and every button of
    /// the row wear the platform's blue ring (MTMiniFace.playingRing).
    var live = false
    private static var liveScale: CGFloat { montanaTouchTarget / MontanaOctagon.composeHeight }
    @ViewBuilder private var liveRing: some View {
        if live {
            Circle().strokeBorder(MTMiniFace.playingRing, lineWidth: 1.5)
                .frame(width: MontanaOctagon.composeHeight, height: MontanaOctagon.composeHeight)
                .allowsHitTesting(false)
        }
    }
    @State private var holding = false
    @State private var held = false        // the hold outlived the tap threshold: recording
    @State private var slidAway = false
    @State private var tape = 0            // the number of the tape this hold began: a late verdict names it
    /// Locked = the machine says so; nothing here can lock or unlock on its own.
    private var isLocked: Bool { rec.isLocked }
    /// WHICH TAPE THE CROWN DRAWS IS THE TAPE'S OWN FACT ([C-1], the author's word 22.09: "listening to a
    /// voice message at the ear, the reply is recorded crookedly and calls up a video message instead of a
    /// voice one"). The crown read the BUTTON'S MODE — what the NEXT hold would record — and the reply at
    /// the ear is always a voice, whatever the button last stood on. So a person whose last tape was a round
    /// note heard the tone, spoke into a voice tape, and was shown the note's chrome with its camera over it:
    /// two owners of one fact, and the camera waking on the very audio session the voice tape was using. The
    /// rolling tape names itself; the button's mode speaks only while nothing rolls (the crown is prepared
    /// before the first hold and must open on the right face at once).
    private var crownIsNote: Bool { rec.kind.map { $0 == .note } ?? (mediaMode == "video") }
    private static let holdSide: CGFloat = MontanaOctagon.composeHeight
    @State private var lift: CGFloat = 0   // how far the finger has risen from the button, 0…1 of the lock's way
    private static let lockWay: CGFloat = 72   // the finger's way up to the lock, in points
    /// THE SWELL HAS A CEILING (the author's word 14.09): the breath (1.06) plus the loudest word
    /// (0.22) — the shape is clamped to it, so nothing stacked above can be reached by a shout.
    private static let holdMaxScale: CGFloat = 1.28
    /// The first free point above the swollen button's centre: its largest radius plus a gap.
    /// Every button stacked over it (the pause, the lock) measures its place from HERE —
    /// mt-layout-check §8 holds that no one measures from the resting size instead.
    private static let holdClear: CGFloat = holdSide / 2 * holdMaxScale + 12
    /// THE FINGER'S ROOM HANGS OUTSIDE THE LAYOUT (the author's word 23.09: «mirror the mini
    /// player, pixel for pixel, across and down»). Every plate of the bar is the tier (36) and
    /// every plate's touch is the platform's least target (44): the target is added as padding,
    /// taken by the touch shape, and then taken BACK from the layout — so the plate occupies
    /// exactly the tier, and the row measures exactly as the player's row does. One number, one
    /// owner: a second literal 4 anywhere in the bar is a second owner.
    private static let fingerRoom: CGFloat = (montanaTouchTarget - MontanaOctagon.composeHeight) / 2
    // The overlay draws with the same numbers: `MTHoldOverlayState.side/lockWay/maxScale` are set from these below.
    /// The voice's last reading, 0…1: the swollen button swells with it.
    private var voiceNow: CGFloat { CGFloat(VoiceRecorder.shown(recordingLevels.last ?? 0, peak: recordingLevels.max() ?? 0)) }   // the swell at the reference's scale, as the lines
    /// TWO TIERS, ALWAYS — SO THERE IS NOTHING TO CROSS (the author word 22.09: «make it so the
    /// buttons are below at once, and it all moves smoothly and exactly, with one owner»). The bar
    /// used to change its shape at the second line, and a change of shape is a change of tree: the
    /// platform buried the text view and made a new one, the first responder died with it, the keys
    /// fell and rose, and the field itself jumped sideways as its width changed under the words.
    /// Now the words stand on the upper tier across the whole width and the buttons on the lower
    /// one, from the first letter to the thirteenth line. Nothing appears, nothing leaves, nothing
    /// re-wraps: the field only grows downward with its own text, the way it always did.
    /// ONE TREE, ONE OWNER OF THE FIELD (the author word 22.09: «no jumping»). The field stands in
    /// ONE place of ONE tree and never changes identity; only what stands AROUND it comes and goes.
    /// Folded, the bar is the one line it has always been -- the down arrow in the left corner, the
    /// words, the microphone at the end. Open, the field takes the whole width and the line of buttons stands
    /// under it, the send at its end, the fold arrow at its head.
    var body: some View {
        VStack(spacing: MTInputField.tierGap) {
            if part != .row {
                HStack(alignment: .bottom, spacing: 10) {
                    fieldStack
                    if !composeOpen { sendColumn }
                }
            }
            if composeOpen, part != .field { actionRow }
        }
        .onChange(of: recording) { _, active in
            if !active { held = false; slidAway = false; lift = 0 }
        }
        // THE BAR IS AS TALL AS ITS SHAPE, STANDING ON THE KEYS (the author's word 23.09: «folded, the
        // line sits on the keyboard; unfolding rises up and moves the mini player away»). The page sizes
        // this node from what it holds, the feed ends at its top and the player stands at the feed's
        // bottom — so the row that unfolds lifts the field, and the field lifts the player, all by the
        // same number and in the same pass, and nothing can lie on anything.
    }

    /// THE FOLDED ROW IS OPENED BY ITS OWN ARROW, TURNED DOWN (the author's word 24.09: «replace the
    /// plus with a down arrow that opens the row as the plus did; draw it as the up arrow of the open
    /// row»). It is drawn exactly as rowGlyph draws the row's head -- the same weight, grey, glass and
    /// seat -- only pointing down. The one writer of that choice is the finger. While a tape rolls
    /// it answers nothing: a shape that changed under a rolling tape would move the swollen button's
    /// own coordinates out from under the finger. The seat keeps its measured name (`frame bar-plus`,
    /// P-126.3), so the diaries before and after the glyph read as one.
    private var unfoldKey: some View {
        Button {
            guard !recording else { return }
            showEmoji = false
            composeOpen = true
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 20, weight: .medium)).foregroundColor(MontanaOctagon.barGlyph)
        }
        .buttonStyle(.montanaOctagon(square: true, bar: true, height: MontanaOctagon.composeHeight))
        .overlay { liveRing }
        .frame(width: montanaTouchTarget, height: montanaTouchTarget)
        .contentShape(Rectangle())
        .padding(-Self.fingerRoom)   // the finger keeps its 44; the layout keeps the tier's 36
        .background(MTFrameMark("bar-plus"))   // measured, not eyeballed: it must stand where the player's play stands
    }

    /// The emoji key inside the plate, where it stood before the row opened: the field keeps its
    /// responder and only its inputView swaps, so the switch is one system animation.
    private var emojiKey: some View {
        Button {
            if !focused { focused = true }
            showEmoji.toggle()
        } label: {
            Image(systemName: showEmoji ? "keyboard" : "face.smiling")
                .font(.system(size: 20)).foregroundColor(MontanaOctagon.barGlyph)
                .frame(width: MTInputField.minH, height: MTInputField.minH)
                .montanaFingerRoom(layout: MTInputField.minH)   // the key keeps the line's 21 points, the finger its 44
        }
    }
    /// THE LOWER TIER (the author word 22.09): the very buttons of the bar — the same glass, the same
    /// 36 points, the same grey glyph as «+» and the microphone have always had — the emoji plate,
    /// the gallery, the card, the file, the place, the person, and the send or the microphone at the
    /// end. The FIRST and the LAST stand on the vertical of the player above: they are flush with the
    /// row's own edges, and the room each keeps for the finger (44 points, the platform least) hangs
    /// outside the row instead of pushing them inward. What is between is shared evenly.
    /// While a tape rolls the glyphs are hidden and take no touch — hidden, never removed: a removal
    /// is a change of tree, and the tree is what must not change.
    private var actionRow: some View {
        HStack(spacing: 0) {
            glyphRow
                .opacity(recording ? 0 : 1)
                .allowsHitTesting(!recording)
                .frame(maxWidth: .infinity)
                .overlay { if recording { recordingStrip } }
            sendColumn
        }
        // THE OUTER FACES KEEP THE PLAYER'S VERTICAL, AND THE ROW IS EVEN BETWEEN THEM (the author's
        // word 22.09: «the edge buttons on one vertical with the player — the microphone to the pixel
        // under the feed's arrow and the player's close, the first glyph under the player's play — and
        // the ones between spread evenly»; 23.09: «mirror it, pixel for pixel»). Both rows measure
        // the same way now: every plate is the tier (36), every touch is the platform's least target
        // (44) hung OUTSIDE the layout by each plate itself, so the outer plates land on the bar's
        // own 16 — where the player's play and close stand — and what is between is shared by equal
        // Spacers. The row hangs nothing of its own any more: a row that hung its own room pushed
        // its last plate four points past the player's close, and its plates four points high.
    }
    private var glyphRow: some View {
        HStack(spacing: 0) {
            // THE HEAD OF THE ROW FOLDS IT AWAY (the author's word 23.09): the row goes back into
            // the down arrow it came out of, and the bar is the one line of the screenshot again.
            rowGlyph("chevron.up") {
                guard !recording else { return }
                composeOpen = false
            }
            Spacer(minLength: 0)
            rowGlyph(showEmoji ? "keyboard" : "face.smiling") {
                if !focused { focused = true }
                showEmoji.toggle()
            }
            Spacer(minLength: 0)
            if !textOnly {
                rowGlyph("photo") { showEmoji = false; actions.gallery() }
                Spacer(minLength: 0)
            }
            if !textOnly && !groupRoom {
                rowGlyph("person.text.rectangle") { showEmoji = false; actions.card() }
                Spacer(minLength: 0)
            }
            if !textOnly {
                rowGlyph("doc") { showEmoji = false; actions.file() }
                Spacer(minLength: 0)
            }
            if !textOnly && !groupRoom {
                rowGlyph("location") { showEmoji = false; actions.location() }
                Spacer(minLength: 0)
                rowGlyph("person.crop.circle") { showEmoji = false; actions.contact() }
                Spacer(minLength: 0)
            }
        }
    }
    private func rowGlyph(_ glyph: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: glyph)
                .font(.system(size: 20, weight: .medium)).foregroundColor(MontanaOctagon.barGlyph)
        }
        .buttonStyle(.montanaOctagon(square: true, bar: true, height: MontanaOctagon.composeHeight))
        .overlay { liveRing }
        .frame(width: montanaTouchTarget, height: montanaTouchTarget)
        .contentShape(Rectangle())
        .padding(-Self.fingerRoom)   // the finger keeps its 44; the layout keeps the tier's 36
    }
    /// THE UPPER TIER IS THE WORDS, AND NOTHING ELSE STANDS IN IT. The field keeps its responder
    /// through everything that happens below it (14.09: a strip that REPLACED the field killed the
    /// text view, the responder with it, and the keyboard slid out from under the finger).
    private var fieldStack: some View {
        ZStack {
        HStack(alignment: .bottom, spacing: 10) {
                // THE BUTTONS STAND IN THE BOTTOM CORNERS (the author's word 21.09): as the field
                // grows, the down arrow and the microphone keep the bottom line — the platform's own way.
                if !composeOpen { unfoldKey }
                // THE WORDS STAND IN THE SAME ROOM ON EVERY LINE (the author's word 22.09: «it must
                // always look the way it looks on one line»). With the row unfolded the field is the
                // whole upper tier and the room on the right is given back to the words, because the
                // key stands on the lower tier then; folded, the key stands inside the plate.
                MTInputField(text: $model.text, caret: $model.caret, focused: $focused, panel: panel, cap: cap,
                             onPasteImages: onPasteImages,
                             extraRight: composeOpen ? MTInputField.inset.left - MTInputField.inset.right : 0,
                             restingBar: MTInputField.restingBar(open: composeOpen))   // the field answers its own height (sizeThatFits); its insets ARE the tier (MTInputField.inset)
                    .montanaFieldGlass(maxCut: 18)   // the plate's own glass (the author's word 21.09)
                    .overlay { if live { MontanaLongOctagon(maxCut: 18).stroke(MTMiniFace.playingRing, lineWidth: 1.5).allowsHitTesting(false) } }
                    .background(MTFrameMark("bar-field"))   // it must span the player's own plate
                    .overlay(alignment: .leading) {
                        if model.text.isEmpty {
                            // The hint stands where the placeholder stands (the reference's tooltip):
                            // a press that outlived the tap but not the tape is answered in words.
                            Text(hint ? "Hold to record" : "Message...").font(.system(size: 17)).foregroundColor(.gray)
                                .padding(.leading, MTInputField.inset.left).allowsHitTesting(false)   // where the words start
                                .animation(.easeOut(duration: 0.15), value: hint)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // Folded, the emoji key stands inside the plate; unfolded, it stands in the
                        // row below and the words take the room to the edge. One seat per shape.
                        if !composeOpen { emojiKey.padding(.trailing, 11).padding(.bottom, MTInputField.inset.bottom) }
                    }
                    .onChange(of: model.text) { _, val in onTextChange(val) }
        }
        .opacity(recording ? 0 : 1)
        // NOTHING BUT OPACITY TOUCHES THE FIELD during a recording: its hit testing, its frame and
        // its responder stay as they are — the strip over it takes every touch itself.
        // THE STRIP LIES OVER THE FIELD (14.09: a strip that REPLACED the field killed the text view,
        // the first responder with it, and the keyboard slid out from under the finger). It stands
        // here in BOTH shapes — the row below may be folded away, the field never is.
        if recording && !composeOpen { recordingStrip }
        }
    }

    /// The wave shares the send button's tier in both bar shapes. The input field keeps its identity.
    private var recordingStrip: some View {
            // The recording strip stands over the field; the microphone stays under the
            // finger — the release is what sends (the author's word 10.09). Slid up, the
            // recording is locked: the finger may leave, a tap on the button sends, the bin cancels.
            let note = recordingSeconds != nil   // a round note: its controls are drawn AND taken in the top window
            // THE WAVE'S OWN ROOM (the author's word 22.09): from the bin's column at the strip's head
            // to the swollen button's edge — and, locked, to the pause's column before it — never
            // under a button. The bin and the pause are the crown's, drawn on this very line.
            // THE WAVE'S ROOM MAKES WAY FOR THE EAR (the author's word 23.09): a standing voice
            // tape keeps TWO columns at the strip's head — the bin and the listen button — and the
            // wave begins after them, so nothing is drawn over the lines.
            let binColumn = montanaTouchTarget + 14 + ((isLocked && !note) ? montanaTouchTarget : 0)
            let swellEdge = Self.holdClear - 12 + 8 - (MontanaOctagon.composeHeight / 2 + 10)   // the swell at its loudest, a gap, less the row's own end
            let pauseColumn: CGFloat = isLocked ? montanaTouchTarget + 16 : 0
            return HStack(spacing: 10) {
                // The live wave of the voice (the author's word 14.09): the seconds stand under the circle.
                // The video note's strip holds only the way to cancel (drawn in the top window, MTNoteChrome).
                if !note {
                    MTLiveWave(levels: recordingLevels)
                        .frame(height: 30)
                }
            }
            .padding(.leading, binColumn)
            .padding(.trailing, swellEdge + pauseColumn)
            .frame(maxWidth: .infinity)
            .frame(height: MontanaOctagon.composeHeight)
            .contentShape(Rectangle())
            .background {
                Capsule().fill(.clear)
                    .montanaFieldGlass(maxCut: .greatestFiniteMagnitude)
                    .padding(.trailing, -(MontanaOctagon.composeHeight + (composeOpen ? 0 : 10)))
                    .allowsHitTesting(false)
            }
            // A video note's strip is DRAWN and TAKEN in the top window over the dim (MTNoteChrome —
            // its bin is a control there, as the flash and the flip); here only its place is measured.
            // Nothing of the bar is kept touchable under a near-zero opacity: the platform's own
            // threshold decided who got the touch (16.09: the pause did, the bin did not).
            .opacity(note ? 0 : 1)
            .allowsHitTesting(!note)
            .background(GeometryReader { g -> Color in
                let f = g.frame(in: .global)
                if MTHoldOverlayState.shared.strip != f { DispatchQueue.main.async { MTHoldOverlayState.shared.strip = f } }
                return Color.clear
            })
    }
    // THE RIGHT COLUMN: the send button or the microphone alone, in the bottom corner under the feed's
    // «down» arrow. It carries the same 44-point target as every glyph of the row (22.09) — the plate
    // inside it is the tier, and the target's overhang is what the row's negative side room takes back,
    // so the plate's right edge is the arrow's and the player's close to the pixel.
    private var sendColumn: some View {
        VStack(spacing: 6) {
        // empty → microphone, has text (or an attachment above) → send arrow
        if !textOnly && ((model.text.trimmingCharacters(in: .whitespaces).isEmpty && !hasAttachment) || recording) {
            // A single tap switches the mode (microphone ↔ camera); press and HOLD records in the
            // current mode — released to send, slid left to cancel (the author's word 10.09).
            let video = mediaMode == "video"
            // Press and HOLD records in the current mode — released to send, slid left to cancel,
            // carried up to the lock and let go to record hands-free (the author's word 10.09);
            // a single tap switches microphone and camera. LOCKED, the swollen button STAYS at
            // its size (the author's word 14.09) and becomes the send button: one tap ends and
            // sends; above it the pause at the bar's native tier.
            let big = held || isLocked
            // The swollen shape is drawn ABOVE THE KEYBOARD in a window of its own
            // (MTHoldOverlayWindow, the author's word 14.09): here stays the slot, the small
            // button when nothing is held, and the state the overlay reads.
            ZStack {
                if !big {
                    MTComposeMark(kind: video ? .video : .voice)
                        .scaleEffect((holding ? 0.94 : 1) * (live ? Self.liveScale : 1))
                }
            }
            .frame(width: MontanaOctagon.composeHeight, height: MontanaOctagon.composeHeight)   // the row keeps the button's slot; the swell overflows it
            // THE SLOT'S PLACE IS THE CONTROL'S TO TELL (21.09): MTHoldOverlayState.follow() reads it from the
            // hold control through the window — no layout-time snapshot here, which stood a keyboard's height
            // off once the bar's node was lifted by its layer without a layout.
            .onChange(of: big) { _, on in
                MTHoldOverlayState.shared.big = on
                if on { MTHoldOverlayWindow.show() } else { MTHoldOverlayWindow.hide() }
            }
            .onChange(of: isLocked) { _, v in MTHoldOverlayState.shared.locked = v }
            .onChange(of: slidAway) { _, v in MTHoldOverlayState.shared.away = v }
            .onChange(of: lift) { _, v in MTHoldOverlayState.shared.lift = v }
            .onChange(of: voiceNow) { _, v in MTHoldOverlayState.shared.voice = v }
            .onChange(of: crownIsNote) { _, v in MTHoldOverlayState.shared.video = v }
            .onChange(of: recordingPaused) { _, v in MTHoldOverlayState.shared.paused = v }
            .onAppear {
                let st = MTHoldOverlayState.shared
                st.video = crownIsNote; st.side = Self.holdSide; st.lockWay = Self.lockWay; st.maxScale = Self.holdMaxScale
                st.holdClear = Self.holdClear; st.paused = recordingPaused
                MTHoldOverlayWindow.prepare()   // born now, shown later: nothing is made under the finger (21.09)
            }
            .onDisappear { MTHoldOverlayWindow.hide(); MTHoldOverlayState.shared.big = false }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: big)
                // THE LOCK PLATE IS THE CROWN'S (the author's word 21.09): drawn in the top window at the
                // crown's seat, for the voice as for the note — the bar keeps only the slot.
                .overlay {
                    // THE CONTROL (MontanaHoldControl, the author's word 19.09): the platform's own
                    // touch tracking in the slot — 44 points at rest, as wide as the swell while a
                    // locked tape waits for its tap. The frame never changes under a tracked finger:
                    // a resize mid-hold would move the control's own coordinates under the touch.
                    MontanaHoldButton(enabled: !isLocked, lockWay: Self.lockWay,
                        onPressed: { down in holding = down; if down, !recording { rec.ready(video ? .note : .voice) } },   // readied under the finger (21.09)
                        onBegan: {
                            held = true; slidAway = false; lift = 0
                            MTHoldOverlayState.shared.previewFile = nil   // a new tape was never heard
                        tape = rec.begin(video ? .note : .voice, why: "hold")
                        },
                        onMove: { l, away in lift = away ? 0 : l; slidAway = away },
                        onVerdict: { v in
                            switch v {
                            case .tap:
                                if !recording { rec.standDown(); mediaMode = video ? "mic" : "video" }   // a tap mid-recording switches nothing
                            case .lock:
                                // Let go at the lock (or the system took the touch): the tape rolls on
                                // hands-free — the crown's arrow sends, its pause and bin stand by.
                                held = false; slidAway = false; lift = 0
                                rec.lock(tape: tape, why: "hold")
                            case .send:
                                held = false; slidAway = false; lift = 0
                                rec.send(why: "release")
                            case .cancel:
                                held = false; slidAway = false; lift = 0
                                rec.cancel(why: "slide")
                            }
                        })
                        .frame(width: MontanaHoldControl.target, height: MontanaHoldControl.target)   // wider than the platform's least: the finger at the edge lands (the author's word 22.09)
                }
        } else {
            // ONE TOUCH, ONE VERDICT (19.09): the platform's own «tap does it, a hold opens the
            // menu» — Menu with a primary action. A Button with a simultaneous long press gave two:
            // the hold opened «send later» AND the release sent the letter now.
            Menu {
                Button { MontanaTrace.mark("send_hold", "later"); onSendLongPress() } label: { Label("Send later", systemImage: "clock") }
            } label: {
                MTComposeMark(kind: .send)
                    .scaleEffect(live ? Self.liveScale : 1)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
                    .accessibilityLabel(Text("Send"))
            } primaryAction: {
                MontanaTrace.markFolded("send_tap", "now", window: 10)
                onSend()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        }
        .frame(width: montanaTouchTarget, height: montanaTouchTarget)   // the row's cell: the plate centred in the finger's target
        .contentShape(Rectangle())
        .padding(-Self.fingerRoom)   // the finger keeps its 44; the layout keeps the tier's 36
        .background(MTFrameMark("bar-send"))   // it must end where the player's close ends
    }
}

/// THE CHAT PAGE IS CARRIED LINK BY LINK IN A BOX (the author's word 03.10.2026 15:13 MSK: «find the cause of the crash at 15:12, fix
/// it and put it on T1»; 16:24: «the chats page crashes, most likely from the feed, keyboard, field and minting edits -- a deep
/// analysis»). T1 died of an exhausted main-thread stack (1008 KB, the kernel's own size) on 2069, 2070 and 2071 at the first chat
/// opened in a run. The whole chain counted on 2071: 329 frames, and eleven of ours held 840 KB of the 1008. A value of the chat page
/// weighs some 29 KB, and each getter of the body's chain (chatCoreL3 down to chatCoreL0, the feed, the bar) held every intermediate of
/// its modifiers in a stack slot sized at run time -- 72 such slots in nine frames. Boxed at the end of each link, the next link wraps
/// a pointer, not the page: a frame of the chain holds its own modifiers and nothing of the links below.
extension View {
    func mtBoxed() -> AnyView { AnyView(self) }
}

struct ChatConversationView: View {
    @Environment(\.mtWindowSize) private var mtWin
    let chat: Chat
    var onChatUpdate: (String, String, String?, String?, String?, [String]) -> Void = mtHandProfileEdit   // the profile's one road
    var jumpTargetId: MID? = nil          // open the chat directly at this message (from global search)
    var onBack: (() -> Void)? = nil      // the chat over the tabs closes by its own road: the back is the top row's first round
    @Environment(UIState.self) private var ui
    @EnvironmentObject private var store: ChatStore

    init(chat: Chat,
         onChatUpdate: @escaping (String, String, String?, String?, String?, [String]) -> Void = mtHandProfileEdit,
         jumpTargetId: MID? = nil,
         onBack: (() -> Void)? = nil) {
        self.chat = chat
        self.onChatUpdate = onChatUpdate
        self.jumpTargetId = jumpTargetId
        self.onBack = onBack
        // The draft travels WITH the chat (the panel gets the draft before
        // its first layout). Seeding text AND the saved field height here means the field opens
        // at its real size in the very first frame — no measure race, no one-line flash.
        let d = ChatStore.draft(chat.name)
        _input = State(initialValue: ChatInputModel(text: d))   // the height is the text's and the width's: the layout asks, nothing is stored

    }

    /// The newest own letter — the one row that carries the status word (15.47).
    /// The status word and dots stand under the LAST row of the feed only (the author's word
    /// 08.09): a reply from the peer below my letter takes the word with it.
    var lastRowId: MID? { msgs.last?.id }

    var msgs: [Message] {
        if rowCache.messageChat == chat.name, rowCache.messageRevision == store.messagesRev {
            return rowCache.messages
        }
        // A step of a chess game is not a row of the feed (29.09): the board reads those letters from the store itself. The letter
        // that closes a game is.
        // An older build's transfer letter is no row of the feed either (mtRetiredLetter, 08.10.2026).
        let a = (store.messages[chat.name] ?? []).filter { m in (!m.isChessStep || m.chessLetter?.end != nil) && !mtRetiredLetter(m.text) }
        var sorted = true
        for i in 1..<max(a.count, 1) where ChatStore.before(a[i], a[i - 1]) { sorted = false; break }
        rowCache.messages = sorted ? a : a.sorted(by: ChatStore.before)
        rowCache.messageChat = chat.name
        rowCache.messageRevision = store.messagesRev
        return rowCache.messages
    }
    @State private var input = ChatInputModel()          // held, NOT observed: typing must not re-render the feed
    private var newMessage: String {                     // imperative proxy for the screen's own logic
        get { input.text }
        nonmutating set { input.text = newValue }
    }
    @State private var callBackVideo: Bool? = nil
    @State private var replyingTo: Message?
    @State private var activeMessage: Message?
    @State private var pressedRow: MID?      // bubble compression while held (reset in onPressingChanged(false))
    // Feed position: an isolated owner. As @State on this screen, every scroll flipped it, which
    // re-rendered the WHOLE conversation (chatRows O(n) included) and moved the 1pt anchor again —
    // the self-feeding loop behind the freezes. Only the «down» button observes it now.
    final class FeedPin: ObservableObject {
        @Published var atBottom = true
        @Published var showDownButton = false   // hysteresis: on past 260pt, off under 60pt
        /// The feed's visual bottom as an inset (the keys' cover plus the player's room), told by
        /// the container: the «down» button stands on it and so rides with the bar (the author's
        /// word 21.09: the button never goes under the field).
        @Published var bottomInset: CGFloat = 0
        /// The keys' cover alone (the author's word 21.09): the floating player stands on it, so it
        /// rides above the keyboard on every device and system — never under it.
        @Published var keyboardCover: CGFloat = 0
        // 13.1 — WHERE THE PERSON STANDS IN TIME. The day of the row at the visual TOP, and
        // whether the finger is moving. The pill exists for movement: it comes while the feed
        // travels and leaves a second after it stops, so a still screen is never covered.
        @Published var topDay = ""
        @Published var showDayHeader = false
    }
    @State private var pin = FeedPin()
    @StateObject private var feedControl = MTFeedControl()   // stage 11: the container's command bridge
    @State private var highlightedId: MID?   // highlight the message after jumping to the quote
    @State private var firstUnreadId: MID?   // the first unread (for the separator)
    @State private var scrollProxy: ScrollViewProxy?
    @State private var pinningMessage: Message?
    @State private var pinnedIndex = 0        // which of the pinned ones is currently shown in the banner
    // pinned messages of the current chat (for the banner)
    private var pinnedList: [Message] { store.pinnedMessages(chat.name) }
    static var autofocusNextOpen = false   // opened the chat from a notification → keyboard and cursor immediately
    @State private var inputFocused: Bool = false   // input focus (MTInputField drives the real first responder)
    @State private var headerTop: CGFloat = 0   // the bar's lower edge in the window: the blurred strip above covers the bar and ends here
    @State private var topBarSize: CGSize = .zero   // the compose node at the top of the turned feed, as laid out: what the pinned plate stands under
    @State private var typing = false
    @State private var lastTypingSent = Date.distantPast
    final class DraftCoalescer {                               // reference holder: live-typing bookkeeping
        var caret = -1                                         // caret snapshot sent with the text
        var replyMid = ""                                      // bare mid of the bubble being answered
        var pending = ""                                       // must NOT be @State — its churn (16x/s while
        var task: Task<Void, Never>?                           // typing) invalidated the whole monolith view,
        var lastSent = Date.distantPast                        // and every graph tick copies the view struct
        var lastSave = Date.distantPast                        // per visible row (the 555 freeze/crash stack)
    }
    @State private var draft = DraftCoalescer()
    @State private var showGallery = false
    @State private var showFileImporter = false
    @State private var modal: ChatModal?      // what we show full-screen (camera/photo/video/file)
    @State private var chessGame: MTChessPush?   // a game opened from its invitation, on this chat's own stack (29.09)
    @State private var chessPlayed: String?      // the pair's game while it is played (MTChessSend.playedGame): the mark's ring
    @State private var askChess = false          // the platform's question before a new game
    @State private var roomAsk: MTRoomKind?      // a group's call chosen at the top: whom to invite (07.10)
    @State private var roomAskVideo = false
    @State private var askEraseGroup = false     // out of a group: «Delete and Exit» asks first (stage R)
    @AppStorage("composeMediaMode") private var composeMediaMode = "mic"
    @State private var wallPage: MTBoardRoute?   // the wall a post's card opens, on this chat's own stack (30.09)
    @State private var playerBarSize: CGSize = .zero   // the floating player's height — the feed's reserve
    /// The room the floating player takes at the feed's bottom — for the feed and for what hangs over it.
    private var playerReserve: CGFloat { playerGate.standing ? playerBarSize.height : 0 }

    /// The last voice ended at the ear: a tone in the ear, and the reply records at the ear.
    func beginEarReply() {
        guard !rec.isRecording else { return }
        earReply = true
        MTProximity.hold("ear-reply", true)   // the sensor stays with the chat now (its one owner, 24.09)
        MontanaEarTone.play()   // through the session: the receiver at the ear, silent switch or not
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard earReply else { return }   // SILENT-OK: the phone already left the ear
            if UIDevice.current.proximityState {
                MTHoldOverlayState.shared.previewFile = nil   // a new tape was never heard
                rec.begin(.voice, why: "ear"); MontanaTrace.mark("voice_ear_reply", "record")
            }
            else { endEarReply() }
        }
    }
    func endEarReply() {
        guard earReply else { return }
        earReply = false
        MTProximity.hold("ear-reply", false)
        MontanaTrace.mark("voice_ear_reply", rec.voice.isRecording ? "paused len=\(Int(rec.voice.elapsed))" : "nothing")
        guard rec.voice.isRecording else { rec.cancel(why: "ear-empty"); return }   // no tape rolled (permission, or the phone left before the start)
        rec.voice.pause()
        rec.lock(why: "ear")   // the send screen: the crown's arrow sends, its bin cancels, pause/record above the arrow
    }

    /// The chat's voices, oldest first, stand behind the one that starts: auto-next walks them.
    func playVoice(_ file: String) {
        let msgs = store.messages[chat.name] ?? []
        let queue: [(file: String, sender: String, mine: Bool)] = msgs.compactMap { m in
            guard let a = m.audioFile, fileOnDisk(a) else { return nil }
            let sender = m.isFromMe ? E2E.myDisplayName()
                                    : store.displayName(for: m.senderRef ?? chat.convId ?? chat.name)
            return (a, sender, m.isFromMe)
        }
        let sender = queue.first { $0.file == file }?.sender ?? ""
        player.playVoice(file, sender: sender, chat: chat.name, queue: queue)
    }

    /// The chat's notes, oldest first, stand behind the one that opens: the end of one opens the
    /// next (the author's word 18.09) — the voice's law, the same list built the same way.
    func openNote(_ file: String, from: CGRect?) {
        let dock = MontanaVideoDock.shared
        if dock.file == file { dock.toggle(); return }
        let msgs = store.messages[chat.name] ?? []
        let queue: [(file: String, caption: String)] = msgs.compactMap { m in
            guard let v = m.videoFile, v.hasPrefix("vnote_"), fileOnDisk(v) else { return nil }
            return (v, m.isFromMe ? E2E.myDisplayName() : store.displayName(for: m.senderRef ?? chat.convId ?? chat.name))
        }
        let caption = queue.first { $0.file == file }?.caption ?? ""
        dock.open(file: file, chat: chat.name, caption: caption, from: from, queue: queue)
    }

    /// The bar's way back to its bubble (the author's word 15.09): this chat's letter is scrolled
    /// to and lit as a reply jump lights; another chat's is opened by the list beneath.
    func goToLetter(chat c: String, file f: String) {
        if c == chat.name {
            if let id = store.letterId(of: f, in: c) { jumpTo(id) }
            return
        }
        NotificationCenter.default.post(name: .montanaGoToLetter, object: nil, userInfo: ["chat": c, "file": f])
    }

    // The chat's music, in feed order, becomes the player's queue; the tapped track leads.
    func openMusic(_ file: String) {
        let msgs = store.messages[chat.name] ?? []
        let tracks: [MusicTrack] = msgs.compactMap { m in
            guard let d = m.docFile, mtIsAudioName(m.docName ?? "") || mtIsAudioName(d) else { return nil }
            var t = MusicTrack(file: d, title: m.docName ?? d, msgId: m.id, chat: chat.name,
                               chatTitle: store.displayName(for: chat.convId ?? chat.name))
            if !fileOnDisk(d) {
                // A TRACK NOT YET WHOLE PLAYS FROM ITS FIRST PIECES (25.09), its pieces named by the letter's intent; a track with
                // no manifest in hand is not in the queue yet.
                guard let st = store.stream(forFile: d) else { return nil }
                t.stream = st.source
                t.whole = st.landed
            }
            return t
        }
        let vp = VoicePlayer.shared
        vp.queue = tracks
        vp.queueIndex = tracks.firstIndex { $0.file == file } ?? -1
        if vp.playingFile == file {
            if vp.paused { vp.resume() }
        } else {
            let name = tracks.first { $0.file == file }?.title ?? file
            vp.toggle(file, title: (name as NSString).deletingPathExtension)
        }
        MontanaTrace.mark("music_open", "i=\(vp.queueIndex + 1) n=\(tracks.count)")
        // NO PAGE ON PLAY (the author's word 22.09): the tap plays; the page opens from the mini plate.
    }
    @State private var showEmoji = false
    @State private var selectingMsgs = false               // multiple-message selection mode
    @State private var selectedMsgs: Set<MID> = []
    @State private var rowMidY: [MID: CGFloat] = [:]     // message id -> mid-Y (content space) for 2-finger select
    @State private var selStartId: MID? = nil
    @State private var selBase: Set<MID> = []            // selection snapshot at pan start (kept outside the range)
    @State private var selMode = true                    // this drag adds (true) or removes (false)
    @ObservedObject private var kb = MTKeyboard.shared    // the ONE source of keyboard facts
    @StateObject private var seenTick = MTSeenRefresh()   // 10-C.2: re-render on the phrase boundary
    @State private var confirmDeleteWholeChat = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSchedule = false
    @State private var scheduleDate = Date()
    @State private var emojiCat = 0          // the selected emoji category
    @StateObject private var emojiHolder = EmojiPanelHolder()

    @State private var sheet: ChatSheet?         // bottom sheet: attachments or forwarding
    @State private var pickerPage = false        // the choosing over the whole screen (23.09)
    @State private var pickerAsk = MTPickerAsk()  // its tab and whether its search wakes — as the keyboard asked
    /// THE BAR'S SHAPE — FOLDED ON THE KEYS OR UNFOLDED — OWNED HERE, BY THE PAGE THAT SIZES THE BAR
    /// (the author's word 23.09: one owner, and everything right against everything else). A fold is
    /// a change of this page: the bar's node is asked its size again, the feed ends at its new top,
    /// the player rides up or down with it, the ground behind the bar is drawn to the same number.
    @AppStorage(MTInputField.shapeKey) private var composeOpen = false
    @StateObject private var recent = RecentMedia()   // recent photos/videos from the gallery
    @State private var editingMessage: Message?      // the message currently being edited
    @State private var searching = false             // whether in-chat search is open
    @State private var chatSearchFocused = false     // the search field's own focus: the keys are asked for after the pass (26.09)
    @State private var searchText = ""
    @State private var tagFilter: String? = nil      // Saved Messages: a reaction used as a tag (15.50)
    @State private var sourceFilter: String? = nil   // Saved Messages: the chat a forward came from (15.51)
    @StateObject private var rec = MontanaRecording()   // the one state of a recording: the voice's recorder and the note's camera live in it
    @ObservedObject private var playerGate = MontanaPlayerBar.Gate.shared   // the one bit; never the player's clock (the critic 22.09)
    private var player: VoicePlayer { VoicePlayer.shared }                   // called, not observed
    @ObservedObject private var linkComposer = MTLinkPreviewBuilder.Compose.shared   // the plate above the field follows this one holder
    @ObservedObject private var mentions = MTMentionCompose.shared   // the «@» plate of a group follows its own holder (stage R)
    @AppStorage("chatBg") private var chatBg: String = "default"
    @AppStorage("chatBgPhoto") private var chatBgPhoto: Data = Data()
    @ObservedObject private var flows = MTLiveChat.shared   // the feed's turn of THIS chat (04.10): the newest letters on top
    private var newestFirst: Bool { flows.on(chat.name) }
    @AppStorage("bubbleStyle") private var bubbleStyleAS: String = "montana"
    @AppStorage("cbBgOn") private var cbBgOn = false
    @AppStorage("cbBgType") private var cbBgTypeAS = "gradient"
    @AppStorage("cbBg1") private var cbBg1 = "000000"
    @AppStorage("cbBg2") private var cbBg2 = "0A0A0A"
    @AppStorage("cbBgPhoto") private var cbBgPhotoData = Data()

    @Environment(\.mtChatKeyboardGeometry) private var pageKeyboard
    var body: some View {
        // Keyboard construction, split by ownership: UIKit's keyboardLayoutGuide owns WHERE the
        // keyboard is; the page is lifted by that number (MTChatKeyboardGeometry.lift) — in the
        // keyboard's own spring when the keys move by themselves, frame by frame under a dragging
        // finger — so the feed and the bar rise WITH the keys (the author's word 20.09); MTKeyboard
        // owns the FACTS (height, up/down) for the emoji panel and the field's ceiling.
        chatCore
    }

    /// This conversation's backbone in one row: the screen body reads it instead of recomputing
    /// it in every expression — otherwise type inference on a large body costs more than the screen.
    /// A self room has no remote end.  Treat a stale convId on its list row as absent until the
    /// store's archive reconciliation clears it, so no draft, letter or recovery banner can be
    /// addressed to the person who happened to occupy that row before a seat switch.
    private var convKey: String { ChatStore.isLocalRoom(chat.name) ? "" : (chat.convId ?? "") }

    // THE BIRTH OF A LETTER'S ROW IS THE CONTAINER'S (the author's word 18.09, stage 7): the feed
    // animates the newborn cell itself — see MTFeedListView.Coordinator.animateBirth. A SwiftUI
    // flight overlay aimed at a rect measured before the layout had settled, and jumped over the
    // last bubble; it left with this stage.
    private var chatCoreL0: some View {
        VStack(spacing: 0) {
            // The bar's lower edge in the window: the content begins here, the top strip ends here.
            Color.clear.frame(height: 0).background(GeometryReader { g -> Color in
                let top = g.frame(in: .global).minY
                if abs(headerTop - top) > 0.5 { DispatchQueue.main.async { headerTop = top } }
                return Color.clear
            })
            if searching { searchBar }
            // THE FIELD ON TOP OF THE TURNED FEED (the author's words 02.10 18:27 and 19:17 on T1 2064 17:56: «raise the input
            // field as in the picture»; «the chats with the input field on top, everything even, native and exact in the
            // keyboard's work»): with the newest letters on top the compose node stands at the feed's top edge, under the
            // navigation bar, over the newest letter -- the same node and the same tree (MTKeyboardRider, bottomGroup), riding
            // nothing (onKeys: false). The keys then cover the feed's visual bottom alone, as its inset (MTFeedFrame), and the
            // platform's interactive drag begins at the keys' own top (the accessory holds no room: MTInputField).
            if newestFirst, !channelWall {
                MTKeyboardRider(geometry: pageKeyboard, onKeys: false, content: bottomGroup)
                    .mtMeasureSize($topBarSize)
                    .background(alignment: .top) { topFieldGround }
                    // The field's node stands OVER the feed: a picture of a letter that reaches past the feed's top edge
                    // (a bubble born, a cell measured late) passes under the words, never over them.
                    .zIndex(1)
            }
            // The open note dims and blurs the feed as the recorder does (the author's word 15.09:
            // one to one) — and takes its touches: a tap outside the note closes it.
            let holding = rec.isRecording || (dock.file != nil && dock.chat == chat.name)
            feedOrWall
                .blur(radius: holding ? 10 : 0)
                .allowsHitTesting(!holding)   // what stands behind the blur takes no touches — the voice's and the note's alike
                .animation(.easeOut(duration: 0.25), value: holding)
                // The recorder's chrome lives in the top window (MTHoldOverlayWindow, the author's
                // word 15.09); it centres the note in the visible feed measured here.
                .background(GeometryReader { g -> Color in MTHoldOverlayState.shared.feed = g.frame(in: .global); return Color.clear })
                .onAppear { MTHoldOverlayState.shared.cam = rec.note; MTHoldOverlayState.shared.voiceTape = rec.voice }
                .onDisappear { MTHoldOverlayState.shared.cam = nil; MTHoldOverlayState.shared.voiceTape = nil }
                .overlay {
                    // The open note (the author's word 15.09): the note that plays in THIS chat rises
                    // to the visible feed's centre at the screen's width; the bar below keeps its
                    // controls, the letters behind stay in reach.
                    ZStack {
                        if dock.file != nil, dock.chat == chat.name {
                            // One instance per note (a second note opened over the first gets its
                            // own flight); it enters as it is — the flight from the bubble is the
                            // whole entrance — and fades out in place once the flight is back.
                            MontanaNoteOpen()
                                .id(dock.file)
                                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.85), value: dock.file)
                }
                // The voice hold (the author's word 14.09): the feed behind is blurred; the liquid orb and its
                // seconds are the crown's (MTHoldOverlayView, 21.09) — in the middle of the VISIBLE part, keys
                // up or down, from the one measure the note's circle stands by. Nothing of it is drawn here.
                // The player floats over the feed's bottom, above the message field (the author's
                // word 14.09): the letters scroll behind its material and show through; the feed
                // reserves the bar's height so the newest letter stands above it.
                .overlay(alignment: .bottom) {
                    // THE PLAYER STANDS ON THE KEYS' COVER (the author's word 21.09): the feed keeps its
                    // frame and takes the keyboard as an inset, so an overlay at the frame's bottom sat
                    // under the keys; it now rides pin.keyboardCover in the keys' own spring — the same
                    // number the «down» button rides — through the one small observer of the pin.
                    MTPlayerRider(pin: pin) {
                        VStack(spacing: 0) {
                            // The unfolded mini's number and search leave the chat for the music page (the author's word 01.10 00:13).
                            MontanaPlayerBar(onPlace: { t in ui.closeChat(); ui.askMusic(); MTMusicFocus.shared.show(t) },
                                             onSearch: { ui.closeChat(); ui.askMusic() },
                                             onGoTo: { c, f in goToLetter(chat: c, file: f) })
                        }
                            .mtMeasureSize($playerBarSize)
                    }
                }
                .onChange(of: scenePhase) { _, ph in
                    checkpointDraftIfBackground(ph)
                    // The app folded under a rolling tape: the finger is gone, the tape is not — it
                    // locks and waits (the reference's rule: only the person ends a tape).
                    if ph != .active, case .recording = rec.phase { rec.lock(why: "background") }
                    // Back on screen: what landed under the locked phone is read now — the letters, the count, the word (15.47.2, 23.09).
                    if ph == .active { store.markRead(chat.name) }
                }
            // Panels are SIBLINGS below the feed, never a safe-area inset of it: an inset applied
            // outside the flip lands in the scroll's own space and renders at the VISUAL TOP,
            // pushing the newest message under the panel and the keyboard. As siblings the feed
            // simply gets a shorter frame, and an inverted feed at offset zero keeps the newest
            // message glued to its visual bottom — no inset mapping, no pin, nothing to loop.
            // THE BOTTOM GROUP IS A NODE OF ITS OWN (the reference's input panel; the author's word 20.09):
            // the previews and the bar are hosted in a UIKit node the keyboard's transition moves by
            // its layer — the same spring the keys are drawn with — never laid out again for the move.
            if !newestFirst, !channelWall { MTKeyboardRider(geometry: pageKeyboard, content: bottomGroup) }
            // THE BUTTONS STAY ON THE KEYS (the author's word 03.10 13:35 and his drawing): turned, only the line of words goes
            // up; the open bar's row of buttons stands where it stands in normal mode, riding the keys in their spring.
            else if composeOpen, barWrites, !channelWall {
                MTKeyboardRider(geometry: pageKeyboard, row: true, content: rowGroup)
                    .zIndex(1)
            }
        }
        // THE BLURRED STRIPS (the author's word 21.09): from the buttons' top up to the screen's edge,
        // and from the field's bottom down to the screen's edge — the system's thin material over the
        // feed, the feed clean between them. The top strip's edge is measured at the buttons (headerTop);
        // the bottom strip hangs from the bar's node (inputBar) and rides with it.
        .overlay(alignment: .top) {
            // The reference's top edge: the wash runs to the bar's lower edge + 34 and fades over its last 80.
            // The ground drawn once more over the page (the wash is window-sized and so aligned with it).
            // With the field on top the strip runs on under the bar at rest -- the bottom strip's own number (restingBar), so
            // the ground is the same on the first line and on the thirteenth -- and never past the node as it stands (a room
            // nobody writes into lays no bar: the strip stays the navigation bar's own).
            // THE TURNED FEED'S STRIP IS THE FIELD'S OWN GROUND (03.10 13:35, the author's screenshot: the field on top read
            // half-clear, a photo of the feed lying over it): drawn over the page, this strip lay OVER the field too. Turned,
            // it hangs behind the field's node instead (topFieldGround), and the node stands over the feed.
            if !newestFirst {
                MTEdgeWash(edge: .top, fade: MTEdgeWash.topFade, solid: headerTop + MTEdgeWash.topReach - MTEdgeWash.topFade)
                    .ignoresSafeArea()
            }
        }
        // THE PINNED PLATE FLOATS OVER THE FEED (the author's word 22.09): under the bar at the top, centred,
        // over the letters and the media alike — the feed is not pushed by it; drawn over the wash.
        // A GROUP'S LIVING ROOM STANDS OVER ITS CHAT (MTRoomBar, the author's word 07.10.2026): above the pinned plate, the whole row
        // the way in.
        .overlay(alignment: .top) {
            if !selectingMsgs {
                VStack(spacing: 0) {
                    if chat.isGroup { MTRoomBar(chat: chat.name) }
                    if !pinnedList.isEmpty { pinnedBar(pinnedList) }
                }
                .padding(.top, newestFirst ? topBarSize.height : 0)   // under the field on top
            }
        }
        .safeAreaInset(edge: .top) { if selectingMsgs { selectionTopBar } }
        .sheet(item: $reportSheet) { r in
            MontanaReportSheet(report: r, onBlock: { if !store.isBlocked(chat.name) { store.toggleBlocked(chat.name) } })
        }
        .background(chatBackground.ignoresSafeArea())   // the ground reaches both edges of the screen
        .environment(\.mtWallpaperConv, chat.convId ?? chat.name)   // the edge washes draw this chat's ground (22.09)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(MTOpaqueChatBar())
        .mtBoxed()
    }

    /// A GAME ENTERED FROM THIS CHAT (29.09): the entry accepts an unanswered invitation (MTChessSend.join) and the board rises
    /// on this chat's own stack (MTChessPush) -- the invitation's tap, the banner's tap and the meeting (30.09) walk this one road.
    /// THE GAME'S BOARD OVER THE CHAT: it opens a game -- one answered, played or over -- and accepts nothing.
    private func enterGame(_ game: String) {
        guard !chat.isGroup else { return }
        chessGame = MTChessPush(game: game)
    }
    /// THE ACCEPT, AND ONLY THEN THE BOARD (the author's words 06.10.2026 23:5x MSK: «accept or not -- the buttons in the chat come
    /// before the chess board is shown»; «first the request is confirmed, then the decision»): the invitation's Accept is the one
    /// door of an acceptance from the chat; a refused one raises no board.
    private func acceptGame(_ game: String) {
        guard !chat.isGroup else { return }
        guard MTChessSend.join(game, in: chat, store: store) != nil else { return }
        chessGame = MTChessPush(game: game)
    }

    private var chatCoreL1: some View {
        chatCoreL0
        .onChange(of: store.peerSeenAt[chat.name]) { _, ts in seenTick.arm(ts) }   // 10-C.2: a new stamp re-arms
        // AN INVITATION LANDING IN THE OPEN CHAT RAISES NO BOARD (the author's words 06.10.2026 23:5x MSK, replacing «when both are
        // in the chat, let them get into the game at once» of 30.09): it stands in the feed with its Accept and Decline.
        // THE EMOJI PANEL IS THE FIELD'S INPUT VIEW, so it leaves whenever the field stops being
        // the responder — by a tap, by the interactive drag, by a screen on top — and the flag
        // reads that ONE fact (textViewDidEndEditing sets focused = false) instead of each gesture
        // of ours remembering to clear it. A flag left true opened the emoji instead of the keys.
        .onChange(of: inputFocused) { _, f in if !f, showEmoji { withAnimation { showEmoji = false } } }
        .onAppear {
            ChatConversationView.autofocusNextOpen = false
            store.healUnresolvedRows(chat.name)   // references left by older builds become words (15.45)
            seenTick.arm(store.peerSeenAt[chat.name])   // 10-C.2
            MontanaDeliveryEngine.shared.drainAll()   // instantly show what the notification decrypted
            // The keyboard does NOT rise automatically (SSOT, stable across all entries): only on tapping the field -- the one
            // exception is a chat of the money flow, below.
            if chat.convId == nil { store.seedIfNeeded(chat.name) }
            if MontanaConv.holds(chat.name) {
                E2E.shared.sendAvatarIfNeeded(to: chat.name)
                E2E.shared.sendNameIfNeeded(to: chat.name)
                E2E.shared.sendAboutIfNeeded(to: chat.name)   // my bio and link, until the peer receipts them (24.09)
            }
            store.openConv = chat.name   // open chat — don't mark incoming as unread
            if let t0 = MontanaOutsideOpen.tappedAt {
                let ms = Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
                let same = MontanaOutsideOpen.tappedFor == chat.name || MontanaOutsideOpen.tappedFor == (chat.convId ?? "")
                MontanaTrace.mark("chat_open", "why=banner ms=\(ms) same=\(same ? 1 : 0) "
                                     + "since_launch_ms=\(Int((ProcessInfo.processInfo.systemUptime - AppDelegate.launchedAt) * 1000))")
                MontanaOutsideOpen.tappedAt = nil
                MontanaOutsideOpen.openedAt = t0   // the feed's first frame closes the same clock
                MontanaMainProbe.run("chat-open")   // the main thread's worst stall of the next twelve seconds, named
            }
            // THE BANNER'S GAME RISES OVER THE CHAT (29.09): a tap on a chess banner enters the game itself -- unless it is an
            // invitation that waits for this phone's answer: the chat is its place then, with its two buttons (06.10).
            if let asked = MontanaOutsideOpen.pendingGame,
               asked.chat == chat.name || MTSamePair.root(asked.chat) == MTSamePair.root(chat.convRef) {
                MontanaOutsideOpen.pendingGame = nil
                if !MTChessSend.awaitsMe(asked.game, rows: store.messages[chat.name] ?? []) {
                    DispatchQueue.main.async { enterGame(asked.game) }
                }
            }
            store.traceRows(chat.name)   // display diagnostics: the feed's rows go to the journal on EVERY opening
            if let cid = chat.convId, cid != chat.name { store.traceRows(cid) }   // a split key shows itself at once
            // «unread» separator: the first letter of theirs not yet read — the letter's own word (23.09), taken
            // before the opening reads them all
            firstUnreadId = msgs.first(where: { !$0.isMine && !$0.isRead })?.id
            store.markRead(chat.name)   // opened the chat → hide the unread counter
            // restore the draft
            if newMessage.isEmpty {
                newMessage = ChatStore.draft(chat.name)
            }
            // THE KEYS RISE IN A CHAT OF THE MONEY FLOW (the author's word 03.10 20:29: «when a chat with the time flow on is
            // opened, let the keyboard be up by default»): the flow is a game of letters, so its chat opens ready to write -- the
            // field on top takes the keys as the chat stands. Every other chat keeps the rule above: the keys only on a tap.
            if ribbon, barWrites { DispatchQueue.main.async { inputFocused = true } }
        }
        .task(id: rowsKey) { await refreshMessageSearch() }
        .task(id: convKey) {
            store.retryPendingMedia()                       // unfinished media downloads — retry
            store.restoreMediaFromVault(chat.name, folderKey: convKey)   // tmp empty → restore from the sealed Media/ folder
            // live wire (polling for now): pull new messages every 2 seconds
            guard chat.convId != nil else { return }
            await refreshFromServer()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await refreshFromServer()
            }
        }
        .onDisappear {
            // The staged attachments die with the screen, so their files stop being held: a hold
            // that outlived its screen would keep bytes nobody can reach for the life of the run.
            MontanaMediaStore.release(pastedImages.map(\.name))
            if rec.isRecording { rec.cancel(why: "chat-left") }   // a tape left recording behind a closed chat is nobody's (T1 16.09 07:32: it rolled on, the next one was refused)
            rec.standDown()
            if store.openConv == chat.name { store.openConv = nil }   // closed the chat -> presence farewell via openConv
            draft.task?.cancel(); draft.task = nil
            // The disk is not written here (20.09): the field wrote it at every change, and a snapshot at
            // leaving was the second hand that put an old text back. Only the peer's bubble is frozen.
            // THE CHECKPOINT SPEAKS THE DISK, NOT THIS INSTANCE'S MEMORY (21.09): the field writes
            // the disk at every change and the send empties it; a second, stale instance of the
            // screen leaving later still remembered the words that had already become a letter,
            // and spoke them as a draft AFTER the ending — the ghost with a caret on the peer's screen.
            let onDisk = ChatStore.draft(chat.name)
            let d = onDisk.trimmingCharacters(in: .whitespaces)
            let saved = (d.isEmpty || editingMessage != nil) ? "" : onDisk
            // durable checkpoint: the peer's bubble freezes at exactly the field state
            if chat.convId != nil, !chat.isGroup { E2E.shared.sendDraftCheckpoint(to: convKey, text: saved, caret: input.caret) }   // a group has no pipe to freeze a bubble on
        }
        // THE WHOLE LIBRARY IS THE PLATFORM'S OWN PAGE (the author's word 22.09, given back after a page
        // of ours was tried and refused: «bring the system one back — there everything works»): its
        // collections, its search, its pinch, its ten at most — the same ceiling our own grid holds.
        // Ours does one thing to it: the tick and the chosen tile are asked to wear OUR gold, the
        // colour of the mark (the author's word 22.09); and what it hands back are the library's own
        // names, so the pictures walk the ONE road into the field our own grid walks (stagePicks) — and
        // what the library will not name under limited access is handed over by the page itself (24.09).
        .sheet(isPresented: $showGallery) {
            MTSystemPhotos(limit: MTGalleryPick.limit) { picks in stagePicks(picks) }
                .ignoresSafeArea()
        }
        .mtBoxed()
    }

    private var chatCoreL2: some View {
        chatCoreL1
        // WHAT THE COMPOSER HOLDS, SAID IN ONE PLACE (the critic 22.09). The array every staging
        // road appends to IS the truth of what waits above the field, so the hold is kept in step
        // with it here and nowhere else: the paste, the gallery and any road written later are
        // covered by the array they all share, and no road can forget to take a hold. Without it
        // the cleanup carried a staged photograph off while its caption was being typed, and the
        // send that followed died reading bytes that no longer existed (T1, 16:17:18).
        .onChange(of: pastedImages) { was, now in
            let before = Set(was.map(\.name)), after = Set(now.map(\.name))
            MontanaMediaStore.hold(Array(after.subtracting(before)))
            MontanaMediaStore.release(Array(before.subtracting(after)))
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let src = urls.first,
               let (stored, original) = copyToDocs(from: src, original: src.lastPathComponent) {
                store.append(chat.name, Message(text: "", isFromMe: true, time: nowHHMM(),
                                                docFile: stored, docName: original,
                                                deliveryStatus: .sending,
                                                senderRef: nil))
                sendMediaOverE2E(fileName: stored, kind: "doc", docName: original)
            }
        }
        .sheet(isPresented: $showSchedule) { scheduleSheet }
        // THE CHOOSING AS A PAGE (the author's word 23.09): the whole screen, our own glass, and the
        // field with its buttons covered by it — the arrow on the page gives the screen back.
        .fullScreenCover(isPresented: $pickerPage) {
            MTPickerPage(onEmoji: { input.text += $0 },
                         onSticker: { sendSticker($0) },
                         onStickerFile: { sendStickerFile($0) },
                         onGifFile: { sendGifFile($0) },
                         onGifFound: { sendGifFound($0) },
                         onOpenSet: { pickerPage = false
                             DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { sheet = .stickerSet("") } },
                         onSettings: { pickerPage = false
                             DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { sheet = .stickerSet("") } },
                         onClose: { pickerPage = false },
                         ask: pickerAsk)
        }
        .fullScreenCover(item: $modal) { m in
            switch m {
            case .camera:
                CameraPicker { img in sendCameraImage(img) } onVideo: { url in sendCameraVideo(url) }
                    .ignoresSafeArea()
            case .contact:
                ContactPicker { card in
                    let nm = [card.givenName, card.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                    let phone = card.phoneNumbers.first?.value.stringValue ?? ""
                    let text = "👤 " + (nm.isEmpty ? String(localized: "Contact", bundle: MTLanguage.bundle) : nm) + (phone.isEmpty ? "" : "\n" + phone)
                    store.append(chat.name, Message(text: text, isFromMe: true, time: nowHHMM(),
                                                    senderRef: nil))
                }
                .ignoresSafeArea()
            case .card:
                // THE BUSINESS CARD LEAVES AS A PHOTO (the author's word 28.09): the kept card drawn at the card's standard
                // proportions, down the picture road; its words ride as the caption under the card's mark.
                MontanaCardNoteView(onSend: { card in
                    sendCardPhoto(card)
                    E2E.shared.sendDraftClear(to: convKey)   // the live plate ends where the photo begins
                    modal = nil
                }, onCancel: {
                    E2E.shared.sendDraftClear(to: convKey)
                    modal = nil
                }, onDraft: { t in sendCardDraft(t) })
            case .fullVideo(let f):
                // The funnel into the one native viewer (SSOT): every old road through the
                // modal leads here and opens the system player.
                Color.clear
                    .onAppear {
                        VideoPresenter.present(f)
                        DispatchQueue.main.async { modal = nil }
                    }
            }
        }
        .onChange(of: activeMessage?.id) { _, _ in updateContextMenuWindow() }
        .mtBoxed()
    }

    private var chatCoreM1: some View {
        chatCoreL2
        .confirmationDialog("Delete entire chat?", isPresented: $confirmDeleteWholeChat, titleVisibility: .visible) {
            Button("Delete chat", role: .destructive) {
                store.purgeLocalCopies(convKey)   // the disk clears BEFORE the feed leaves memory
                store.messages[chat.name] = []
                store.deletedChats.insert(convKey)
                LiveDraftState.purgeConversation(convKey)
                LiveDraftState.purgeConversation(chat.name)
                selectingMsgs = false; selectedMsgs.removeAll()
                dismiss(); ui.closeChat()
            }
            Button("Cancel", role: .cancel) {}
        }
        .mtBoxed()
    }

    private var chatCoreM2: some View {
        chatCoreM1
        // THE QUESTION RISES FROM BELOW AS THE BLOCK'S DOES (the author's word 22.09): the one sheet about a
        // person — the face, the question, «for both» first, «for me» under it, «Cancel» apart. The old
        // dialog carried a Latin «Pin for …» built by hand, past the catalogue ([C-15]).
        .overlay {
            if let m = pinningMessage {
                MontanaFaceSheet(photoURL: store.avatarFor(chat), color: chat.color, initial: store.initial(for: chat),
                                 question: "Pin this message?",
                                 note: nil,
                                 // A group carries no pin yet: «for everyone» would pin on this phone alone, so a group pins for me.
                                 actions: chat.isGroup ? [
                                     MontanaFaceSheet.Action(title: "Pin for me", destructive: false) {
                                         store.pin(chat.name, m.id); pinningMessage = nil
                                     },
                                 ] : [
                                     MontanaFaceSheet.Action(title: "Pin for both", destructive: false) {
                                         store.pin(chat.name, m.id); tellPin(m, pin: true); pinningMessage = nil
                                     },
                                     MontanaFaceSheet.Action(title: "Pin for me", destructive: false) {
                                         store.pin(chat.name, m.id); pinningMessage = nil
                                     },
                                 ],
                                 onCancel: { pinningMessage = nil })
            }
        }
        .toolbar {
            // THE CHAT'S TOP IS ONE ROW THAT FITS ANY SCREEN (the author's words 04.10.2026 13:49 and 14:06 MSK: «align the buttons
            // with the name»; «make the buttons adaptive to the screen so the interlocutor's bubble is always seen»; T1 14:06: four bar
            // items of their own took the bar from its middle and pushed the face and the name out of it): the name's bubble with the
            // face in it and the marks close at its right stand in the bar's middle as one row (chatTop) -- in a chat pushed in a stack.
            if onBack == nil {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .principal) { chatTop }.sharedBackgroundVisibility(MTBarRoundMark<EmptyView>.shared)
                } else {
                    ToolbarItem(placement: .principal) { chatTop }
                }
            }
        }
        // THE CHAT'S TOP STANDS 8 FROM THE EDGES (the author's words 05.10.2026 14:04 and 18:11 MSK, T1 on 2116: «left and right 8,
        // and all the room that is left to the interlocutor's bubble»; the bar kept its own margins of 20 whatever was asked of it,
        // and the row stood 29 from the edge): the chat over the tabs draws its top itself as the bar beside its content -- the
        // platform's own bar of the newest system, with its edge effect -- 8 from each edge; a chat pushed in a stack keeps the bar.
        .toolbar(onBack == nil ? .automatic : .hidden, for: .navigationBar)
        .modifier(MTChatTopBar(shown: onBack != nil) { chatTop })
        // THE FIELD TAKEN IN THE FLOW BRINGS THE START (the author's word 05.10.2026 18:3x MSK: «on activating the field it must scroll
        // rightly to the start, at the top»): in the turned feed the newest stands at the top, under the field.
        .onChange(of: inputFocused) { _, on in if on, newestFirst { stickBottom() } }
        .mtBoxed()
    }

    /// The top's one row in the room the screen leaves (ViewThatFits takes the first that fits): the marks' rounds of the bar's 44 a
    /// gap apart where the name's bubble keeps 120 points, rounds of 40 with no gap where it keeps 96 -- every mark's target stays the
    /// bar's 44 points; the marks yield their glass, never the name its place.
    private var chatTop: some View {
        HStack(spacing: 0) {
            CallInlineHandset(side: .green, peer: nil)   // 15.8: return to the minimized call
            ViewThatFits(in: .horizontal) {
                chatRow(round: 44, gap: 6, room: 120)
                chatRow(round: 40, gap: 0, room: 96)
            }
            CallInlineHandset(side: .red, peer: nil)   // 15.8: end it
        }
        .frame(maxWidth: .infinity)
    }
    /// THE MARKS STAND CLOSE BESIDE THE NAME (the author's word 04.10.2026 13:06 MSK: «the buttons at the top of the chat closer to
    /// each other, and the name's bubble on the rest of the room»). The chess and the handset are separate buttons (30.09 23:29), the
    /// marks are one round of the platform's glass with the ring on that same circle (02.10 18:27, MTBarRoundMark).
    /// ONE STEP BETWEEN EVERY ROUND (the author's word 05.10.2026 14:04 MSK: «the step between all the buttons as between the handset
    /// and the chess; the room freed goes to the interlocutor's bubble»): the back, the bubble and the marks stand at one gap, and
    /// the bubble keeps the same room a round keeps around it inside its 44-point target, so every visible distance is the same.
    private func chatRow(round: CGFloat, gap: CGFloat, room: CGFloat) -> some View {
        HStack(spacing: gap) {
            if let onBack { backMark(round, onBack) }
            chatTitleDoor.frame(minWidth: room).padding(.horizontal, (44 - round) / 2)
            if spinnerStands {
                flipMark(round)
                chessMark(round)
                handsetMark(round)
            } else if chat.isGroup {
                MTRoomMark(chat: chat.name, side: round) { kind, video in roomAskVideo = video; roomAsk = kind }   // the kind, then whom (07.10)
            }
        }
    }
    /// The platform's back chevron on the marks' one round, the size of the chess and the rest.
    private func backMark(_ side: CGFloat, _ back: @escaping () -> Void) -> some View {
        Button(action: back) {
            MTBarRoundMark(ringed: false, side: side) { MontanaBarGlyph(glyph: "chevron.backward") }
        }
        .accessibilityLabel(Text("Back"))
    }
    /// THE FACE IS THE DOOR TO THE CHAT'S SETTINGS (the author's words 03.10 21:30 and 04.10 03:25 MSK: «the interlocutor's avatar at
    /// the top of the chat as a button into the chat's settings, as it was»): the whole bubble, the face in it, is the one button.
    private var chatTitleDoor: some View {
        NavigationLink(destination: MontanaPeerInfoScreen(chat: chat, onSave: onChatUpdate)) {
            chatTitleBubble.contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(MontanaAvatar.spokenName(store.title(for: chat))))
        // THE KEYBOARD GOES DOWN WITH THE CHAT (the author's word 18.09): the profile was pushed over
        // a focused field, the keyboard stayed up above the profile, and on the way back the chat
        // met a keyboard it did not own and a field it could not place. The field lets go here.
        .simultaneousGesture(TapGesture().onEnded { inputFocused = false; hideKeyboard() })
        .contextMenu {
            Button {
                UIPasteboard.general.string = store.title(for: chat)
            } label: { Label("Copy name", systemImage: "doc.on.doc") }
        }
    }

    /// THE NAME'S BUBBLE ON THE REST OF THE BAR (the author's word 04.10.2026 13:06 MSK: «the name's bubble on the rest of the room,
    /// so the name and the statuses are there and all of it is seen»): the face, the chat's name and the presence ladder, most alive
    /// first -- «typing…», «watching» (they read my draft as it appears), «in chat», «online» (app, other screen) -- in one capsule of
    /// the platform's glass, as wide as the row leaves it and never narrower than its room.
    private var chatTitleBubble: some View {
        HStack(spacing: 8) {
            MTChatAvatar(chat: chat, size: 36)   // the one face of a chat — Saved Messages wears one's own here too
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(MontanaAvatar.spokenName(store.title(for: chat))).font(.subheadline).bold().foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.tail)
                    if ChatStore.isMontanaRoom(chat.name) { MTMontanaCrownMark(height: 16) }
                }
                if chat.isGroup, let out = MTGroup.shared.outWords(chat.name) {
                    Text(out).font(.caption2).foregroundStyle(.secondary).lineLimit(1)   // the catalogue's words, read by MTGroup.outWords
                } else if chat.isGroup, let n = MTGroup.shared.people(chat.name) {   // a group has no presence of one person: its people's count
                    Text(String(localized: "\(n) members", bundle: MTLanguage.bundle)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if let w = store.presenceWord(chat.convId ?? chat.name) {   // the key every screen asks by (24.09)
                    HStack(spacing: 4) {
                        if let dot = w.dot { Circle().fill(dot).frame(width: 9, height: 9) }
                        Text(w.text).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .frame(minWidth: 0, idealWidth: 96, maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background {
            if #available(iOS 26.0, *), MontanaSkin.isNative {
                MTGlassPlate(shape: Capsule())
            } else {
                Capsule().fill(MontanaOctagon.barMaterial)
            }
        }
    }

    /// The handset as it was (the author's word 18.09): the calls' menu behind the one bar glyph, on the marks' one round.
    private func handsetMark(_ side: CGFloat) -> some View {
        Menu {
            Button {
                MontanaCall.shared.startCall(peer: chat.convId ?? chat.name, device: "", video: false,
                    displayName: MTNameBook.display(conv: chat.convId ?? chat.name,
                                                    localFirst: chat.displayName, localLast: chat.lastName))
            } label: { Label("Voice Call", systemImage: "phone.fill") }
            Button {
                MontanaCall.shared.startCall(peer: chat.convId ?? chat.name, device: "", video: true,
                    displayName: MTNameBook.display(conv: chat.convId ?? chat.name,
                                                    localFirst: chat.displayName, localLast: chat.lastName))
            } label: { Label("Video Call", systemImage: "video.fill") }
        } label: {
            MTBarRoundMark(ringed: false, side: side) { MontanaBarGlyph(glyph: "phone") }   // the one bar glyph (MontanaShapes) on the marks' one round
        }
    }

    /// THE CHESS MARK (the author's words 29.09, and 30.09 23:26 and 23:29: «the chess icon's system highlight only while a game is
    /// active; a finished one is not highlighted»; «a tap asks to start a new game when there is none, and enters the game when one
    /// is played»). The game's icon on the round glass the handset wears; the platform's blue ring (MTMiniFace.playingRing, the mini
    /// player's) only while the pair's game is played, drawn inside the plate's own circle (strokeBorder) -- one circle, even, never
    /// on the glass's rim. A tap enters the game that is played; with none, the platform's question asks first.
    private func chessMark(_ side: CGFloat) -> some View {
        Button {
            // An invitation waiting for my answer is answered in the feed: the mark leads to it, not to its board (06.10).
            if let id = chessPlayed, MTChessSend.awaitsMe(id, rows: store.messages[chat.name] ?? []),
               let invite = store.messages[chat.name]?.last(where: { m in m.chessLetter?.game == id && m.chessLetter?.kind == .invite }) {
                jumpTo(invite.id)
            } else if let id = chessPlayed { chessGame = MTChessPush(game: id) } else { askChess = true }
        } label: {
            MTBarRoundMark(ringed: chessPlayed != nil, side: side) { MTChessIcon().frame(width: 22, height: 22) }
        }
        .accessibilityLabel(Text("Chess"))
    }

    /// Off: the chat is as it was. On: the feed turns to the ribbon of time (the newest letters on top, every stamp with its seal
    /// and gematria) and the live words go both ways. The ring stands while it is on -- the sign that holds under Reduce Motion
    /// too.
    private func flipMark(_ side: CGFloat) -> some View {
        Button {
            // The field changes its place with the turn: the keys go down first, so no keyboard is left to a field reborn elsewhere.
            inputFocused = false
            hideKeyboard()
            flows.set(chat.name, !newestFirst)   // this chat's flow alone (04.10)
            E2E.shared.liveTypingSwitched(on: newestFirst, peer: chat.name)   // live chat lives in this chat's flow alone
            if newestFirst {
                store.appendLiveChat(peer: chat.name)   // its row in the chat
                // THE FLOW STANDS READY AT ONCE (the author's word 05.10.2026 18:3x MSK: «on switching the money flow on, everything
                // stands in its place at once: the feed scrolled to the top, the keyboard active, the panel of buttons unfolded by
                // default -- the field on top and the buttons under it»): the row unfolds now; once the turned feed and its field are
                // laid, the feed goes to its newest end (the top) and the field takes the keys.
                composeOpen = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    stickBottom()
                    inputFocused = true
                    MontanaTrace.mark("feed_turn", "flow ready open=1 focused=1")
                }
            }
            MontanaTrace.mark("feed_turn", "newest_first=\(newestFirst ? 1 : 0)")
        } label: {
            MTBarRoundMark(ringed: newestFirst, side: side) { MontanaBarGlyph(glyph: "text.bubble") }
        }
        .accessibilityLabel(Text("Live chat"))
        .accessibilityAddTraits(newestFirst ? .isSelected : [])
    }
    /// The chat that wears the live chat's switch: a pair's own conversation (the bar shows it there and nowhere else).
    private var spinnerStands: Bool { !chat.isGroup && MontanaConv.holds(chat.convId ?? chat.name) }
    /// The ribbon of time: the live chat of this chat is on.
    private var ribbon: Bool { newestFirst && spinnerStands }

    private var chatCoreM3: some View {
        chatCoreM2
        // The ring follows the pair's letters: read again when a letter lands in this chat, never on another pass.
        .task(id: store.messages[chat.name]?.last?.id) {
            chessPlayed = MTChessSend.playedGame(in: chat, store: store)
        }
        // WHOM TO INVITE INTO THE GROUP'S CALL (MTRoomMark chose the kind): the sheet hangs on the chat, never inside the bar's item
        .sheet(item: $roomAsk) { k in MTRoomInviteSheet(chat: chat.name, kind: k, video: roomAskVideo, opening: true) }
        .alert("Start a new game?", isPresented: $askChess) {
            Button("New game") {
                if let id = MTChessSend.invite(to: chat, seconds: MTChessSend.chatClock, store: store) { chessGame = MTChessPush(game: id) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Call back?", isPresented: Binding(
            get: { callBackVideo != nil }, set: { if !$0 { callBackVideo = nil } }),
            titleVisibility: .visible) {
            Button {
                let v = callBackVideo ?? false; callBackVideo = nil
                MontanaCall.shared.startCall(peer: chat.convId ?? chat.name, device: "", video: v,
                    displayName: MTNameBook.display(conv: chat.convId ?? chat.name,
                                                    localFirst: chat.displayName, localLast: chat.lastName))
            } label: { Label(callBackVideo == true ? "Video Call" : "Voice Call",
                             systemImage: callBackVideo == true ? "video.fill" : "phone.fill") }
            Button("Cancel", role: .cancel) { callBackVideo = nil }
        }
        .onChange(of: ui.pendingForward) { _, mid in consumePendingForward(mid) }
        // «Show in chat» — the one road (UIState.showLetter): the record names this chat's letter.
        .onChange(of: ui.letterAsk) { _, a in
            guard let a, a.chat == chat.name else { return }
            MontanaTrace.mark("jump_do", "found=\(msgs.contains { $0.id == a.mid } ? 1 : 0)")
            jumpTo(a.mid)
            ui.letterAsk = nil
        }
        .onAppear {
            consumePendingForward(ui.pendingForward); consumePendingForwardMany()
            // A SET A LINK ASKED FOR (22.09): the link entrance opened this very conversation --
            // the giver's -- and the set's page stands up on the first frame after it.
            if let pack = MontanaStickerOpen.take() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { sheet = .stickerSet(pack) }
            }
        }
        .onChange(of: ui.pendingForwardMany?.count) { _, _ in consumePendingForwardMany() }
        .sheet(item: $sheet) { s in
            switch s {
            case .forward(let m):
                ForwardPickerView(message: m) { target in
                    forwardMessage(m, to: target)
                    sheet = nil
                    // immediately go to the conversation with the forward recipient
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ui.openChat(target) }
                }
            case .forwardMany(let ms):
                ForwardPickerView(message: ms.first ?? Message(text: "", isFromMe: true, time: "")) { target in
                    for m in ms { forwardMessage(m, to: target) }
                    sheet = nil
                    selectingMsgs = false; selectedMsgs.removeAll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ui.openChat(target) }
                }
                .environmentObject(store)
            case .gallery:
                // THE GALLERY OF THE ROW (the author's word 22.09, his own screenshots): the phone's
                // latest pictures, picked into the field — never sent from here. It rises as the
                // platform's own half sheet and is dragged to the full screen; «All photos» hands
                // over to the platform's own picker with its collections and its ten.
                MTGalleryPick(recent: recent,
                              onPick: { picked in stagePicks(picked.map(MTPick.asset)) },
                              onCamera: {
                                  sheet = nil
                                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { modal = .camera }
                              },
                              onAllPhotos: {
                                  sheet = nil
                                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showGallery = true }
                              })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color.black)
            case .stickerSet(let pack):
                // A SET AS A PAGE (22.09): a tap sends a sticker into this conversation and closes.
                MontanaStickerSetPage(pack: pack, onPick: { file in
                    sheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { sendStickerFile(file) }
                }, onClose: { sheet = nil })
                .presentationDetents([.large])
            case .stickerEdit(let file):
                // EDIT STICKER (22.09): the picture of a letter opens in the editor, and what the
                // checkmark keeps is a NEW sticker -- the letter of another person is never touched.
                MontanaStickerEditor(source: docImage(file) ?? UIImage(),
                                     onDone: { data in
                                         sheet = nil
                                         guard let made = MontanaStickerBook.shared.add(png: data) else { return }
                                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { sendStickerFile(made) }
                                     },
                                     onCancel: { sheet = nil })
                .presentationDetents([.large])
            case .attach:
                AttachSheet(recent: recent,
                    initialCaption: editingMessage == nil ? newMessage : "",
                    onSend: { assets, caption in sheet = nil
                        consumeDraftAsCaption(caption)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { sendAssets(assets, caption: caption) } },
                    onCamera: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { modal = .camera } },
                    onGallery: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { sheet = .gallery } },
                    onFile: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showFileImporter = true } },
                    onLocation: { sheet = nil; ui.placeAsk = MTPlaceAsk(chat: chat.name, conv: convKey) },
                    onContact: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { modal = .contact } },
                    onCard: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { modal = .card } })
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .mtBoxed()
    }

    private var chatCoreL3: some View {
        chatCoreM3
            .navigationDestination(item: $chessGame) { push in
                MTChessGameScreen(seat: .correspondent(chat, game: push.game), inChat: true)
            }
            .navigationDestination(item: $wallPage) { r in
                // THE CARD OPENS THE WALL THE POST STANDS ON (the author's word 30.09): the friend's page for the post I wrote there,
                // my own page for the post they wrote on mine -- the very pages the header and My page open.
                switch r {
                case .person(let c): MontanaPeerInfoScreen(chat: c, onSave: onChatUpdate).montanaMotionMeter()
                default: MontanaMyProfileView().montanaMotionMeter()
                }
            }
            .mtBoxed()
    }

    private var chatCore: some View {
        chatCoreL3
    }

    // The context menu is in a SEPARATE window of ours. The keyboard's window stands above ANY level
    // of ours (measured 14.09, MTHoldOverlayWindow) — so the keyboard is put down first (below), and
    // the menu covers the whole screen.
    // The overlay is a SELF-CONTAINED view with its own state: the parent's @State doesn't update in a foreign window.
    func updateContextMenuWindow() {
        guard let m = activeMessage else {
            MontanaOverlayWindow.shared.hide()
            return
        }
        // dismiss the keyboard → the menu covers the ENTIRE screen (and the keyboard area) with dimming,
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        // closing: directly hide the window and reset the parent's state (a double guarantee)
        let close: () -> Void = {
            MontanaTrace.mark("menu_close", "after=\(MTReactClock.closedAfter())")
            MontanaOverlayWindow.shared.hide()
            activeMessage = nil
        }
        // A MEDIA GROUP IS ONE LETTER TO THE MENU (the author's word 19.09): the plate is shown whole,
        // and every action takes all of its letters; the caption is edited on the one letter that
        // carries it (or the first, when none does). A picture's or video's caption is a person's
        // words and can be edited like any letter.
        let letters = rowLetters(m.id)
        let group = letters.count > 1 ? letters : []
        let whole = group.isEmpty ? [m] : group
        let captionHolder = group.first { !$0.text.isEmpty } ?? group.first ?? m
        let canEdit = m.isMine && m.audioFile == nil && m.docFile == nil && !MTRowLetter.ownRow(m.text)   // a post's card, the flow's row: not letters
            && (!m.text.isEmpty || !group.isEmpty || m.imageFile != nil || m.videoFile != nil)
        MontanaOverlayWindow.shared.show {
            MessageContextOverlay(
                message: m,
                letterTop: MTBubbleFrames.shared.rect(m.id)?.minY,   // where the letter stood at the hold — a value, taken once
                faces: reactionFaces,
                isPinned: store.isPinned(chat.name, m.id),
                canEdit: canEdit,
                player: player,
                onReact: { e in MontanaTrace.mark("menu_react", "e=\(e)"); react(m, e); close() },
                onReply: { replyingTo = m; close() },
                onCopy: { let m = captionHolder; UIPasteboard.general.string = MTRowLetter.words(m.text); close() },
                onEdit: {
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        editingMessage = captionHolder; newMessage = captionHolder.text; inputFocused = true
                    }
                },
                onPin: {
                    if store.isPinned(chat.name, m.id) {
                        store.unpin(chat.name, m.id); tellPin(m, pin: false); close()
                    } else {
                        close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pinningMessage = m }
                    }
                },
                onForward: {
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { sheet = group.isEmpty ? .forward(m) : .forwardMany(group) }
                },
                onSelect: { close(); selectingMsgs = true; selectedMsgs = Set(whole.map(\.id)) },
                // THE STICKER'S OWN ROWS (the author's word 22.09): they stand only over a sticker --
                // a letter whose manifest carries the sticker's name and whose picture is on disk.
                onEditSticker: (m.docName == MontanaCardPlate.stickerName && m.imageFile != nil) ? {
                    let file = m.imageFile ?? ""
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { sheet = .stickerEdit(file) }
                } : nil,
                onViewSet: (m.docName == MontanaCardPlate.stickerName && m.imageFile != nil) ? {
                    // THE STICKER'S OWN SET: a letter of ours belongs to this phone's set; a letter
                    // of another carries its passport, and the passport names the set (22.09).
                    let pack = m.isMine ? "" : (MontanaStickerBook.shared.passport(forLetter: m.msgId ?? "")?.pack ?? "")
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { sheet = .stickerSet(pack) }
                } : nil,
                onCopyLink: (m.docName == MontanaCardPlate.stickerName && m.imageFile != nil) ? {
                    let book = MontanaStickerBook.shared
                    let port = m.isMine ? nil : book.passport(forLetter: m.msgId ?? "")
                    let pack = port?.pack ?? book.mineId
                    UIPasteboard.general.string = MontanaStickerPack.link(id: pack, title: port?.title ?? "Montana")
                    MontanaTrace.mark("sticker_link", "copied pack=\(pack.prefix(8))")
                    close()
                } : nil,
                onReport: {
                    close()
                    let who = m.senderRef ?? chat.convId ?? chat.name
                    let r = MontanaReport(peer: who, peerName: store.displayName(for: who), text: m.text, mid: m.msgId ?? "")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { reportSheet = r }
                },
                // ANY BUBBLE, MINE OR THEIRS (the author's word 18.09): the notice names the letter's
                // mid, and the mid is the same on both sides — every living build wipes the row by it.
                // A note to oneself has no «everyone» (the author's word 20.09): the row is not offered there.
                // In a group a speaker takes away their own letter for everyone (MTGroup.answered checks the seat on every phone).
                // the group's owner and the administrators it named take another's letter away too (stage R.6, MTGroup.moderates)
                canDeleteForEveryone: chat.isGroup ? (m.isMine || MTGroup.shared.moderates(chat.name))
                                                   : chat.convId != nil && (m.isMine || MontanaConv.holds(convKey)),
                ladder: m.isMine && chat.convId != nil && !MTRowLetter.ownRow(m.text),   // the rung and its moment over the menu; none for a note to oneself, nor a post's card
                onDeleteMine: { for x in whole { delete(x) }; close() },
                onDeleteEveryone: {
                    for x in whole {
                        delete(x)
                        if let sid = x.msgId, chat.isGroup {   // the group's carrier takes the deletion to every phone of it
                            store.deleteEverywhere(chat: chat.name, msgId: sid)
                            MTGroup.shared.signal(deleteMark + sid, in: chat.name, store: store)
                        } else if let sid = x.msgId, MontanaConv.holds(convKey) {
                            store.deleteEverywhere(chat: chat.name, msgId: sid)
                            let peer = convKey
                            MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer, mid: UUID().uuidString,
                                                                 text: deleteMark + sid, silent: true)
                        }
                    }
                    close()
                },
                onClose: close,
                members: group
            )
        }
    }



    /// 13.3 — WHICH EMPTINESS. Derived in ONE place and in the order the person meets it:
    /// a conversation still being read is not empty, a search with a query is about the query,
    /// and a chat that never had a word is different from one whose words cannot arrive.
    var feedEmptyKind: MTFeedEmpty.Kind? {
        guard chatRows.isEmpty else { return nil }
        if filtersHistory, searchResultKey != rowsKey { return .loading }
        if !store.historyLoaded { return .loading }
        if searching, !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return .noResults }
        if MontanaNodes.liveNodes == 0 && msgs.isEmpty { return .noNetwork }
        return .freshChat
    }

    // Search is open AND asked something: the feed shows the matches, and a tap on one of them
    // is a jump to its place, not a menu.
    var searchJump: Bool { searching && !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    // messages accounting for search
    @State private var visibleCount = 80   // the tail of the feed; earlier ones load via a button (no freeze on large chats)
    private struct SearchScope: Equatable {
        let chat: String
        let query: String
        let tag: String?
        let source: String?
    }
    private var searchScope: SearchScope {
        SearchScope(chat: chat.name, query: searchText, tag: tagFilter, source: sourceFilter)
    }
    @State private var searchedScope: SearchScope?
    @State private var searchResultKey = ""
    @State private var searchResultVersion = 0
    @State private var searchMessages: [Message] = []
    @State private var searchHasMore = false
    private var filtersHistory: Bool {
        searching && (!searchText.trimmingCharacters(in: .whitespaces).isEmpty || tagFilter != nil || sourceFilter != nil)
    }
    private var hasMoreRows: Bool { filtersHistory ? searchedScope == searchScope && searchHasMore : msgs.count > visibleCount }
    var shownMsgs: [Message] {
        if filtersHistory { return searchedScope == searchScope ? searchMessages : [] }
        return msgs.count > visibleCount ? Array(msgs.suffix(visibleCount)) : msgs
    }

    /// Search owns a cancellable snapshot, never a scan in the view's body. Keep one page plus a
    /// lookahead, so a common word in a large archive cannot allocate one row model per match.
    @MainActor private func refreshMessageSearch() async {
        guard filtersHistory else {
            searchMessages = []; searchHasMore = false; searchResultKey = ""; searchedScope = nil
            return
        }
        let key = rowsKey, scope = searchScope
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard !Task.isCancelled, key == rowsKey else { return }
        let snapshot = msgs, query = searchText.trimmingCharacters(in: .whitespaces)
        let tag = tagFilter, source = sourceFilter, limit = visibleCount
        let scan = Task.detached(priority: .userInitiated) { () -> [Message] in
            var matches: [Message] = []
            for message in snapshot.reversed() {
                guard !Task.isCancelled else { return [] }
                if let tag, !message.reactions.contains(tag) { continue }
                if let source, message.fwdFrom != source { continue }
                if !query.isEmpty,
                   message.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) == nil,
                   (message.docName ?? "").range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) == nil { continue }
                matches.append(message)
                if matches.count > limit { break }
            }
            return matches
        }
        let matches = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
        guard !Task.isCancelled, key == rowsKey else { return }
        searchHasMore = matches.count > limit
        searchMessages = Array(matches.prefix(limit).reversed())
        searchResultKey = key
        searchedScope = scope
        searchResultVersion &+= 1
    }
    // Precomputed row model: neighbor comparisons (day/tail/indent) are computed
    // ONCE in a linear pass, instead of indexing into a recomputed array on every
    // ForEach iteration (was O(n²) on a large chat). Gives smoothness.
    struct ChatRowVM: Identifiable {
        let message: Message
        let newDay: Bool
        let tail: Bool
        let topPad: Bool
        /// The letters of a media group folded into this row, in the sender's order; empty on a
        /// letter of its own. The row is named by its first letter in the feed.
        var members: [Message] = []
        var id: MID { message.id }
    }
    /// THE ROWS ARE BUILT ONCE PER CHANGE (the critic 22.09, T1 on 1859: 189 rebuilds of the screen in
    /// one 25-second drag under the keys — 840 ms of row building, 4 ms a time over 668 rows — with the
    /// letters unchanged). The rows derive from the letters, the window and the search alone; the
    /// store's revision names a change of the letters, so the rows are kept until one of those moves.
    final class RowCache {
        var messageChat = ""
        var messageRevision = -1
        var messages: [Message] = []
        var key = ""
        var rows: [ChatRowVM] = []
        var version = 0   // moves with every rebuild — the feed's stamp
    }
    @State private var rowCache = RowCache()
    private var rowsKey: String {
        "\(chat.name)|\(store.messagesRev)|\(visibleCount)|\(searching)|\(searchText)|\(tagFilter ?? "")|\(sourceFilter ?? "")|\(newestFirst)"
    }
    // Newest first: the list is inverted (scaleEffect y:-1), so index 0 sits at the VISUAL bottom
    // and the visual bottom is scroll offset ZERO — the rotated-list construction.
    var chatRows: [ChatRowVM] {
        let key = rowsKey + "/" + String(searchResultVersion)
        if rowCache.key == key { return rowCache.rows }
        let rows = buildRows()
        rowCache.key = key; rowCache.rows = rows; rowCache.version &+= 1
        return rows
    }
    private func buildRows() -> [ChatRowVM] {
        let list = shownMsgs
        var out: [ChatRowVM] = []
        out.reserveCapacity(list.count)
        var start = 0
        while start < list.count {
            let m = list[start]
            var end = start   // the last index of this row's letters
            var members: [Message] = []
            // A MEDIA GROUP IS ONE ROW (19.09): the neighbours sharing one key fold into the row of
            // their first letter and stand in the sender's order, not in the order of arrival. A
            // letter of another kind between them, or a stranger's key, ends the fold.
            if let key = m.groupKey, MTMosaic.folds(m) {
                var j = start
                while j < list.count, list[j].groupKey == key, MTMosaic.folds(list[j]),
                      list[j].isMine == m.isMine, j - start < MTMediaGroup.ceiling { j += 1 }
                if j - start >= 2 {
                    members = Array(list[start..<j]).sorted { $0.groupIndex < $1.groupIndex }
                    end = j - 1
                }
            }
            let last = list[end]
            let newDay = start == 0 || !sameDay(list[start - 1].createdAt, m.createdAt)
            let tail = end == list.count - 1 || list[end + 1].isMine != m.isMine
                || (list[end + 1].createdAt - last.createdAt) >= msgMergeGap
            let topPad = start == 0 || list[start - 1].isMine != m.isMine
                || (m.createdAt - list[start - 1].createdAt) >= msgMergeGap
            out.append(ChatRowVM(message: m, newDay: newDay, tail: tail, topPad: topPad, members: members))
            start = end + 1
        }
        // THE FEED'S TURN (the author's word 02.10 14:03): the inverted list puts its first row at the visual bottom, so the
        // newest on top is the same rows handed over oldest first -- the one owner of the order, the container untouched.
        return newestFirst ? out : out.reversed()
    }

    // in-chat search bar
    var searchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                // THE PLATFORM'S OWN SEARCH BAR (the author's word 26.09, the Files page's picture): the pages' search field one to
                // one (MTSearchField) -- its focus the chat's own, the keyboard asked for after the pass; the cross beside it, a round
                // of glass on the finger's 44, as the pages' cross.
                MTSearchField(text: $searchText, focused: $chatSearchFocused,
                              placeholder: String(localized: "Search in chat…", bundle: MTLanguage.bundle))
                    .frame(height: MTSearchField.height)
                Button { chatSearchFocused = false; searching = false; searchText = ""; tagFilter = nil; sourceFilter = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MontanaOctagon.barGlyph)
                }
                .accessibilityLabel(Text("Cancel"))
                .buttonStyle(.montanaOctagon(square: true, bar: true, height: montanaTouchTarget))
            }
            if chat.name == savedMessagesKey { savedChips }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)   // no strip of grey: the bar stands on the chat's ground, as the compose bar (26.09)
    }

    /// Saved Messages narrows by TAGS — the reactions the person put on their own notes — and by
    /// the CHAT a forward came from (15.50, 15.51). Nothing new is stored: the chips are read
    /// off the rows that already carry reactions and the forward source.
    private var savedChips: some View {
        let tags = Array(Set(msgs.flatMap { $0.reactions })).sorted()
        let sources = Array(Set(msgs.compactMap { $0.fwdFrom })).sorted()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { t in
                    // USER-DATA: the person's own reaction glyph.
                    chip(Text(verbatim: t), on: tagFilter == t) { tagFilter = tagFilter == t ? nil : t }
                }
                ForEach(sources, id: \.self) { s in
                    // USER-DATA: the source chat's name.
                    chip(Text(verbatim: store.displayName(for: s)), on: sourceFilter == s) { sourceFilter = sourceFilter == s ? nil : s }
                }
            }
        }
    }

    private func chip(_ label: Text, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.font(.system(size: 13, weight: .semibold))
                .foregroundColor(on ? .black : .white)
        }
        .buttonStyle(.montanaOctagon(prominent: on))
    }

    // THE PINNED PLATE (the author's word 22.09): the message row's own dress — the glass plate at the
    // tier's height with the pin and the words, the close apart on the right as a button of the tier —
    // the same room as the field and the mini player (the bar's side padding, the tier owner's pad).
    func pinnedBar(_ list: [Message]) -> some View {
        let idx = min(max(pinnedIndex, 0), list.count - 1)
        let m = list[idx]
        let h = MontanaOctagon.composeHeight
        return HStack(spacing: 10) {
            // A tap on the plate — the letter (scroll + highlight); with several pinned, the next one each tap.
            HStack(spacing: 8) {
                Image(systemName: "pin.fill").font(.system(size: 14, weight: .semibold)).foregroundColor(Color.accentColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pinned message").font(.caption2).foregroundColor(.secondary)
                    Text(previewText(m)).font(.footnote).foregroundColor(.white).lineLimit(1)   // USER-DATA: the letter's words
                }
                Spacer(minLength: 0)
                if list.count > 1 {
                    Text(verbatim: "\(idx + 1)/\(list.count)")   // USER-DATA: a count
                        .font(.caption2).monospacedDigit().foregroundColor(MontanaOctagon.barGlyph)
                }
            }
            .frame(maxWidth: .infinity)
            .montanaOctagonFace(bar: true, height: h)
            .contentShape(MontanaLongOctagon())
            .onTapGesture {
                jumpTo(m.id)
                if list.count > 1 { pinnedIndex = (idx + 1) % list.count }
            }
            Button {
                store.unpin(chat.name, m.id)
                tellPin(m, pin: false)   // unpinned on both screens, as it stood on both
                pinnedIndex = 0
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
            }
            .buttonStyle(.montanaOctagon(square: true, bar: true, height: h))
        }
        .padding(.horizontal).padding(.vertical, MTInputField.barPad)
    }
    private func tellPin(_ m: Message, pin: Bool) {
        guard chat.convId != nil else { return }
        let obj: [String: Any] = ["sid": m.msgId ?? "", "txt": m.text, "op": pin ? "pin" : "unpin"]
        guard let json = try? JSONSerialization.data(withJSONObject: obj), let body = String(data: json, encoding: .utf8) else { return }
        MontanaTrace.mark("pin_tx", "\(pin ? "pin" : "unpin") sid=\(String((m.msgId ?? "").prefix(12)))")
        MontanaDeliveryEngine.shared.enqueue(to: convKey, chat: convKey, mid: UUID().uuidString, text: pinMark + body, silent: true)
    }

    // the «Editing» banner above the input field
    func editPreview(_ m: Message) -> some View {
        barPlate(glyph: "pencil", title: Text("Editing"), words: m.text, thumb: nil,
                 onTap: { MontanaTrace.mark("plate_tap", "edit"); jumpTo(m.id) }) { editingMessage = nil; newMessage = "" }
    }
    /// THE PLATE ABOVE THE FIELD (the author's word 22.09): the pinned plate's own dress for the reply and
    /// the edit — the glass plate at the tier, the glyph in gold, the small title and the words, the close
    /// apart on the right as a button of the tier; the message row's room around it. One plate, one owner.
    /// A tap on the plate carries the eye to the letter it names (the author's word 22.09) — the pinned
    /// plate's own road (jumpTo: scroll + highlight), the keys staying up: a programmatic scroll is no drag.
    func barPlate(glyph: String, title: Text, words: String, thumb: MTLetterThumb?, onTap: (() -> Void)? = nil, onClose: @escaping () -> Void) -> some View {
        let h = MontanaOctagon.composeHeight
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: glyph).font(.system(size: 14, weight: .semibold)).foregroundColor(Color.accentColor)
                if let thumb { thumb.frame(width: h - 8, height: h - 8).clipShape(RoundedRectangle(cornerRadius: 6)) }
                VStack(alignment: .leading, spacing: 0) {
                    title.font(.caption2).foregroundColor(Color.accentColor).lineLimit(1)
                    Text(verbatim: words).font(.footnote).foregroundColor(.white).lineLimit(1)   // USER-DATA: the letter's words
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .montanaOctagonFace(bar: true, height: h)
            .contentShape(MontanaLongOctagon())
            .onTapGesture { onTap?() }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
            }
            .buttonStyle(.montanaOctagon(square: true, bar: true, height: h))
        }
        .padding(.horizontal).padding(.vertical, MTInputField.barPad)
    }

    // a short message preview (for banners and the list): voice/photo/text
    func previewText(_ m: Message) -> String {
        if let mp = mediaPreview(m) { return mp }
        return m.text
    }

    func toggleSelectMsg(_ id: MID) {
        let ids = rowLetters(id).map(\.id)   // a media group is marked and unmarked whole
        if selectedMsgs.contains(id) { selectedMsgs.subtract(ids) } else { selectedMsgs.formUnion(ids) }
        if selectedMsgs.isEmpty { withAnimation { selectingMsgs = false } }
    }
    private func msgIdAt(_ y: CGFloat) -> MID? {
        rowMidY.min(by: { abs($0.value - y) < abs($1.value - y) })?.key
    }
    private func panSelectBeganId(_ id: MID) {
        selBase = selectedMsgs                  // keep whatever is already selected outside the drag range
        selMode = !selectedMsgs.contains(id)    // starting on a selected message -> this drag DESELECTS
        selStartId = id
        if !selectingMsgs { withAnimation { selectingMsgs = true } }
        applyPanRange(to: id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func panSelectBegan(_ y: CGFloat) {
        guard let id = msgIdAt(y) else { return }
        selBase = selectedMsgs                  // keep whatever is already selected outside the drag range
        selMode = !selectedMsgs.contains(id)    // starting on a selected message -> this drag DESELECTS
        selStartId = id
        if !selectingMsgs { withAnimation { selectingMsgs = true } }
        applyPanRange(to: id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func panSelectChanged(_ y: CGFloat) {
        guard let b = msgIdAt(y) else { return }
        applyPanRange(to: b)
    }
    private func applyPanRange(to endId: MID) {
        guard let a = selStartId else { return }
        let rows = chatRows
        let ids = rows.map { $0.message.id }
        guard let ia = ids.firstIndex(of: a), let ib = ids.firstIndex(of: endId) else { return }
        var sel = selBase   // base preserved; only the start..current range is toggled by selMode
        for i in min(ia, ib)...max(ia, ib) {
            let letters = rows[i].members.isEmpty ? [rows[i].message.id] : rows[i].members.map(\.id)   // a group whole
            for id in letters { if selMode { sel.insert(id) } else { sel.remove(id) } }
        }
        selectedMsgs = sel
    }
    private func panSelectEnded() {
        selStartId = nil
        if selectedMsgs.isEmpty { withAnimation { selectingMsgs = false } }
    }
    // ONE row of the feed. Extracted so the inverted list can flip each row back (scaleEffect
    // y:-1 twice = upright — the rotated-list construction).
    @ViewBuilder
    func feedRow(_ row: ChatRowVM) -> some View {
        VStack(spacing: 0) {
                        let message = row.message
                        if row.newDay {
                            datePill(dayLabel(message.createdAt))   // new-day separator
                        }
                        if message.id == firstUnreadId { unreadDivider }   // unread separator
                        if chat.isGroup, let who = MTGroup.shared.speakerLine(message, in: chat.name) {
                            // USER-DATA: the name of the group's speaker above each letter of theirs (MTGroup.speakerName).
                            Text(verbatim: who).font(.caption.weight(.semibold)).foregroundColor(.secondary).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 18).padding(.top, 6)
                        }
                        if MTGroupEvent.of(message.text) != nil { groupEventRow(message) } else {   // a group's event: no bubble (stage R)
                        HStack(spacing: 6) {
                            if selectingMsgs {
                                Image(systemName: selectedMsgs.contains(message.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(selectedMsgs.contains(message.id) ? Color.accentColor : .gray)
                                    .padding(.leading, 6)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                            SwipeReplyRow(id: message.id, onReply: { replyingTo = message; inputFocused = true }) {
                                MessageBubble(message: message, player: player, onTapImage: { _ in
                                    // No file — the tap repeats the download instead of opening emptiness.
                                    if let f = message.imageFile, !fileOnDisk(f) {
                                        MontanaTrace.markFolded("media_tap", "no file -- the download is asked again", window: 5)
                                        store.retryOneMedia(message.msgId); return
                                    }
                                    if let f = message.imageFile {
                                        PhotoPresenter.present(f, among: store.pictures(in: chat.name))
                                    }
                                }, onTapVideo: {
                                    // No file — the tap starts the download, not an empty player.
                                    if let v = message.videoFile, !fileOnDisk(v) {
                                        // A VIDEO PLAYS FROM ITS FIRST PIECES (25.09): the player opens on the loader at once,
                                        // and the file, whole, lands as the download's would. No manifest in hand — the download.
                                        if let st = store.stream(forFile: v) { VideoPresenter.present(stream: st.source, whole: st.landed); return }
                                        store.retryOneMedia(message.msgId); return
                                    }
                                    // A VIDEO OPENS AT ONCE IN THE SYSTEM'S PLAYER (the author's word 28.09: «open at once; the
                                    // Montana albums -- remove them at the root; direct opening, the platform's own media controls
                                    // and folding away in any direction, with one owner»): the one road into viewing, VideoPresenter.
                                    if let v = message.videoFile { VideoPresenter.present(v) }
                                }, onTapNote: { f, from in
                                    // The round note's one road (primaryTap): no file — the download;
                                    // the note that is playing — play/pause (the reference); else open,
                                    // flying out of its bubble.
                                    if !fileOnDisk(f) { store.retryOneMedia(message.msgId); return }
                                    openNote(f, from: from)
                                    store.notePlayed(file: f)   // their round note opened with its sound: its sender learns it (25.09)
                                }, onTapDoc: {
                                    if let d = message.docFile, !fileOnDisk(d) {
                                        store.retryOneMedia(message.msgId); return
                                    }
                                    if let d = message.docFile { ui.docPage = MTDocOpen(id: d, name: message.docName ?? d) }   // tap on the file — the page over everything
                                }, onTapPlace: { place in ui.placeOpen = place },
                                   onTapMusic: { f in openMusic(f) },
                                   onTapChess: { game in
                                       // THE INVITATION OPENS ITS GAME OVER THE CHAT (the author's word 29.09): the invitee's tap
                                       // accepts and starts the clocks (MTChessSend.join); the game's page rises on this chat's
                                       // own stack, as a post opens whole, and the back leads home to the letters.
                                       enterGame(game)
                                   },
                                   chessOpen: message.chessLetter.map { c in c.kind == .invite && !message.isFromMe
                                       && MTChessSend.awaitsMe(c.game, rows: store.messages[chat.name] ?? []) } ?? false,
                                   onChessDecline: { game in MTChessSend.decline(game, in: chat, store: store) },
                                   onChessAccept: { game in acceptGame(game) },
                                   chessStatus: message.chessLetter.flatMap { c in c.kind != .invite ? nil
                                       : MTChessSend.state(c.game, rows: store.messages[chat.name] ?? []).flatMap { g in
                                           g.status == .invited ? nil : MTChessWords.status(g) } },
                                   onTapWallPost: { _ in wallPage = message.isFromMe ? .person(chat) : .mine },   // mine stands on their wall, theirs on mine
                                   onTapReply: { rid in jumpTo(rid) },
                                   tail: row.tail,
                                   quoteAuthor: message.replyToId.flatMap { rid in
                                       // The viewer's truth: the quoted row's own side names its author.
                                       guard let q = store.messages[chat.name]?.first(where: { $0.id == rid }) else { return nil }
                                       return q.isFromMe ? E2E.myDisplayName()
                                                         : store.displayName(for: chat.convId ?? chat.name)
                                   },
                                   voiceSender: message.isFromMe ? E2E.myDisplayName()
                                                                 : store.displayName(for: message.senderRef ?? chat.convId ?? chat.name),
                                   onPlayVoice: { f in playVoice(f) },
                                   onCancel: {
                                       for m in (row.members.isEmpty ? [message] : row.members) {
                                           if let f = m.videoFile ?? m.imageFile ?? m.audioFile ?? m.docFile {
                                               store.cancelUpload(f, chat: chat.name)
                                           }
                                       }
                                   },
                                   onResend: {
                                       if row.members.isEmpty { resendAny(message) }
                                       else { for m in row.members where m.deliveryStatus == .failed { resendAny(m) } }
                                   },
                                   onTapReaction: { e in react(message, e) },
                                   faces: reactionFaces,
                                   ladder: message.isFromMe && chat.convId != nil && !MTRowLetter.ownRow(message.text)   // no ladder under a note to oneself, nor a post's card: no letter rode
                                       && (message.id == lastRowId || row.members.contains { $0.id == lastRowId }),
                                   members: row.members,
                                   onTileTap: { m in tileTap(m) })
                                .equatable()
                            }
                            // Selection mode and search mode both hand the tap to the ROW: in the
                            // first it marks, in the second it carries the person to the letter's
                            // own place in the conversation. One construction, two uses.
                            .allowsHitTesting(!selectingMsgs && !searchJump)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectingMsgs { toggleSelectMsg(message.id) }
                            else if searchJump {
                                // Search shows the matches; the tap returns the letter to its
                                // day, its neighbours and its quotes, with a brief highlight so
                                // the eye finds it. The road is the proven one (P-65 window).
                                let target = message.id
                                searching = false; searchText = ""
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { jumpTo(target) }
                            } else {
                                // THE EMPTY PLACE BESIDE A LETTER IS THE ROW'S (measured T1 20.09 10:34:
                                // six taps beside bubbles named UIHostingContentView, the keyboard stood;
                                // only the gap between rows reached the feed). The row's shape is the
                                // whole width, so the tap that no control of the letter claimed — a
                                // Button inside wins, the platform's own rule — lets the field go, as the
                                // reference's history tap does.
                                hideKeyboard()
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: selectingMsgs)
                        .id(message.id)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: MsgRowMidYKey.self, value: [message.id: g.frame(in: .named("chatSel")).midY])
                        })
                        .padding(.top, row.topPad ? 8 : 0)   // extra gap between groups (author / >=10 min)
                        .background(highlightedId == message.id ? Color.accentColor.opacity(0.18) : Color.clear)
                        .animation(.easeInOut(duration: 0.25), value: highlightedId)
                        // iOS 26: on rows ONLY long-press (menu). Swipe-reply and taps are removed —
                        // they suppressed the vertical axis of the new scroll engine. onLongPressGesture with
                        // maximumDistance=10 cancels when the finger moves → scroll stays alive.
                        .contentShape(Rectangle())
                        .scaleEffect(pressedRow == message.id ? 0.965 : 1)
                        .animation(.easeOut(duration: 0.15), value: pressedRow)
                        // The menu opens at the same threshold at which the finger gets its
                        // response: the response used to come before the menu, and the hold
                        // felt «stuck». The long press now lives on the bubble itself
                        // (MessageBubble.onLongPress) — one road for text and media. The
                        // row's gesture is removed so two mechanisms do not compete.
                        }
        }
    }

    /// A CHANNEL IS A WALL (the author's words 06.10.2026 14:2x-14:4x MSK: «in channels posts as on the Wall of Thoughts; everything the wall publishes is published in a channel»): its posts stand as the Wall of Thoughts
    /// draws them -- the owner writes by the wall's own button (MTBoardRows), a subscriber reads; the field does not stand.
    private var channelWall: Bool { chat.isGroup && MTGroup.shared.kind(chat.name) == .channel }
    @ViewBuilder private var feedOrWall: some View {
        if channelWall {
            ScrollView { MTBoardPane(owner: chat.name) }
        } else {
            messagesList
        }
    }

    var messagesList: some View {
        MTFrameMeter.shared.rendered()   // the meter counts the screen's rebuilds under a gesture
        MTFrameMeter.shared.watch(chat.name) { [
            ("store", store.objectWillChange.eraseToAnyPublisher()),
            ("kb", kb.objectWillChange.eraseToAnyPublisher()),
            ("seen", seenTick.objectWillChange.eraseToAnyPublisher()),
            ("rec", rec.objectWillChange.eraseToAnyPublisher()),
            ("recent", recent.objectWillChange.eraseToAnyPublisher()),
            ("emoji", emojiHolder.objectWillChange.eraseToAnyPublisher()),
            ("feed", feedControl.objectWillChange.eraseToAnyPublisher()),
            ("gate", playerGate.objectWillChange.eraseToAnyPublisher())
        ] }
        let rowsBegan = CACurrentMediaTime()
        let rows = chatRows
        MTFrameMeter.shared.rowsBuilt(ms: (CACurrentMediaTime() - rowsBegan) * 1000)
        var stamp = Hasher()
        stamp.combine(rowCache.version); stamp.combine(highlightedId); stamp.combine(firstUnreadId)
        stamp.combine(selectingMsgs); stamp.combine(selectingMsgs ? selectedMsgs : [])
        let ribbonNow = ribbon   // read once per pass: every row's fingerprint and content take this one answer
        return MTFeedListView(
            rows: rows,
            stamp: stamp.finalize(),
            control: feedControl,
            pin: pin,
            hasMoreAbove: hasMoreRows,
            onReachTop: { if hasMoreRows { visibleCount += 200 } },
            onBackgroundTap: { hideKeyboard() },   // the emoji panel follows the responder (below), not this tap
            onHold: { id in
                guard !selectingMsgs, let m = chatRows.first(where: { $0.id == id })?.message else { return }   // SILENT-OK: selecting, or a row that is not a letter
                guard MTGroupEvent.of(m.text) == nil else { return }   // SILENT-OK: a group's event row is no letter -- no menu (stage R)
                activeMessage = m
            },
            fingerprint: { row in
                var h = Hasher()
                h.combine(row.message.text); h.combine(row.message.deliveryStatus)
                // THE ANSWERS UNDER A LETTER ARE CONTENT (20.09, the critic): a reaction changes the
                // row's fingerprint and the row is reconfigured like any other change — the cell is
                // measured again and grows under the plate by the one road every change takes. Drawn
                // from the live board alone, the plate appeared inside a cell whose height nobody
                // asked to grow (a tall photo with a caption: react_put added=true, feed saw nothing).
                h.combine(row.message.reactions); h.combine(row.message.myReact)
                h.combine(row.message.edited)
                h.combine(row.message.isRead); h.combine(row.message.imageFile)
                h.combine(row.message.videoFile); h.combine(row.message.audioFile)
                h.combine(row.message.docFile); h.combine(row.tail); h.combine(row.newDay)
                h.combine(row.message.replyText)
                for m in row.members {   // a group's plate changes with any of its letters
                    h.combine(m.id); h.combine(m.text); h.combine(m.deliveryStatus)
                    h.combine(m.imageFile); h.combine(m.videoFile)
                }
                h.combine(row.message.id == highlightedId)
                h.combine(row.message.id == firstUnreadId)
                h.combine(selectingMsgs)
                h.combine(selectingMsgs && selectedMsgs.contains(row.message.id))
                h.combine(ribbonNow)
                return h.finalize()
            },
            rowContent: { row in
                AnyView(feedRow(row)
                    .scaleEffect(x: 1, y: -1)   // flip back INSIDE our content — the layout owns the cell's transform
                    .environmentObject(store)
                    .environment(ui)
                    .environment(\.mtWindowSize, mtWin)
                    .environment(\.mtTimeRibbon, ribbonNow))
            },
            draftContent: {
                AnyView(LiveDraftSection(conv: chat.name, peerKey: chat.convId ?? chat.name)
                    .scaleEffect(x: 1, y: -1)
                    .environmentObject(store)
                    .environment(\.mtWindowSize, mtWin))
            },
            bottomReserve: playerReserve,
            newestOnTop: newestFirst,
            onAtBottom: { if !searching && visibleCount > 80 { visibleCount = 80 } },   // 11.5: the window narrows home
            onReplySwipe: { id in
                if let m = chatRows.first(where: { $0.id == id })?.message, m.msgId != nil {
                    replyingTo = m
                    inputFocused = true
                }
            },
            isSelecting: { selectingMsgs },
            onPanBegan: { panSelectBeganId($0) },
            onPanChanged: { applyPanRange(to: $0) },
            onPanEnded: { panSelectEnded() }
        )
        // 10-L.1: the decoy is the one scroll-to-top candidate — the status-bar tap rides UP.
        .overlay(alignment: .top) {
            MTStatusBarTapCatcher { feedControl.scrollToTop() }   // 11.4: the tap rides UP by our command
                .frame(height: 1)
        }
        .overlay {
            if let kind = feedEmptyKind {
                MTFeedEmpty(kind: kind) { inputFocused = true }   // the fresh chat invites the first word
                    .transition(.opacity)
            }
        }
        // 13.1 — THE DAY THE FINGER IS READING. A day separator travels away with its flow, and
        // on a long day the person loses the ground under the words entirely. This pill is OUR
        // layer above the feed: it names the day of the topmost row, changes at the border of a
        // day, and leaves a second after the movement stops — it is a companion of travel, never
        // a label on a still screen.
        .overlay(alignment: .top) {
            MTDayHeader(pin: pin) { datePill($0) }
                .padding(.top, 6)
        }
        // THE WAY TO THE NEWEST STANDS AT THE NEWEST END (02.10): under the field on top of the turned feed, pointing up.
        .overlay(alignment: newestFirst ? .topTrailing : .bottomTrailing) {
            ScrollDownButton(pin: pin, top: newestFirst, action: { stickBottom() }) {
                    // The compose tier (the author's word 21.09): the same size and glass as «+» and the microphone.
                    Image(systemName: newestFirst ? "chevron.up" : "chevron.down")
                        .font(.system(size: 20, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
                        .montanaOctagonFace(square: true, bar: true, height: MontanaOctagon.composeHeight)
                }
            // ON THE MICROPHONE'S OWN VERTICAL LINE (the author's word 21.09): the bar's side room is 16,
            // and the plate stands centred in its 44-point target — the target's overhang is taken off,
            // so the plate's right edge is the microphone's and the mini player's close.
            .padding(.trailing, 16 - (montanaTouchTarget - MontanaOctagon.composeHeight) / 2)
        }
        .onAppear {
            // THE GALLERY IS WARM BEFORE IT IS ASKED FOR (the author's word 22.09: «the first time it
            // shows no photographs»). Reading the library — the status, the fetch, six hundred picture
            // objects — began at the touch on the gallery and the page opened onto an empty grid.
            // It begins here instead, at the chat's own opening, and asks nobody for anything: the
            // permission is READ, never requested, so opening a conversation shows no dialog.
            recent.want(600)
            recent.warm()
            // Where the person lands on opening. A quote asked for a place — it wins, it was a
            // deliberate act. Otherwise, if there are unread letters, the person lands on the
            // FIRST of them, under the quiet «Unread messages» line, instead of at the bottom
            // with the last one and a blind climb upwards. The position is read from the same
            // record the counter is read from ([C-1]): the first incoming newer than the last
            // seen moment, which is what draws the line as well.
            // ONCE PER OPENING (the author's word 18.09: «show in chat» worked now and then): the
            // feed appears again when the profile above it pops, and this landing then pressed the
            // feed to the bottom a fifth of a second later — over the jump the person had just asked
            // for, or under it, as the timing fell. A return is no opening: the landing runs once.
            guard !landed else { return }
            landed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // THE CHAT OPENS AT THE VERY BOTTOM — whatever the last letter is (the author's
                // word 01.09: the last letter, whatever it is, must be scrolled all the way down).
                // This supersedes the landing of stage 13.4: standing on the first unread
                // left the newest letters below the edge, and a media row still filling grew there
                // out of sight — the person saw half a frame and had to scroll after it. The unread
                // LINE stays where it was: it marks the place in the feed, it no longer decides
                // where the feed stands. An explicit jump (a found letter) still wins over both.
                if let jt = jumpTargetId { jumpTo(jt) }
                else { stickBottom(animated: false) }
            }
        }
        .mtBoxed()
    }

    // The opening place for an explicit target. The chat's own opening no longer calls it (the
    // author's word 01.09: opening lands at the very bottom); a found letter and a quote-jump do.
    // No highlight — the person did not ask for this letter, the line above it already says
    // what it is. The same road as a jump, minus the flash ([C-1]).
    func openAt(_ id: MID) {
        // Nothing stands below the newest letter, so «on it» and «at the bottom» are one place —
        // and only the bottom shows the whole tail of a tall row. A banner opens exactly this case.
        if msgs.last?.id == id { feedControl.scrollToBottom(animated: false); return }
        if let idx = msgs.lastIndex(where: { $0.id == id }) {
            let fromEnd = msgs.count - idx
            visibleCount = max(visibleCount, min(msgs.count, fromEnd + 100))
        }
        feedControl.scrollTo(id, animated: false)
    }

    // jump to the message (tap on the quote-reply) + briefly highlight
    func jumpTo(_ target: MID) {
        let id = rowLead(target)   // a letter folded into a media group is reached by its group's row
        // 11.6: the window loads AROUND the target, never the whole history — a jump into a
        // thousands-deep chat costs one page, and the 11.5 shrink cleans up after the return.
        if let idx = msgs.lastIndex(where: { $0.id == id }) {
            let fromEnd = msgs.count - idx
            visibleCount = max(visibleCount, min(msgs.count, fromEnd + 100))
        }
        feedControl.scrollTo(id)
        highlightedId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            if highlightedId == id { withAnimation { highlightedId = nil } }
        }
    }

    // «unread messages» separator
    var unreadDivider: some View {
        Text("Unread messages")
            .font(.caption2).foregroundColor(.gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Color(white: 0.12))
            .padding(.vertical, 2)
    }

    // hide keyboard (tap on chat / scroll the list)
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    // quote banner above the input field (when replying to a message)
    /// THE PASTED PICTURES (the author's word 10.09): pasted into the field, they stand above it as
    /// attachments — a tap opens one full screen, the cross drops it, the arrow sends them as
    /// photos by the one road every photo takes (photoForSend → the temp file → the letter).
    /// THE PASTE KEEPS BOTH FACES (the author's word 22.09): the picture as it was pasted, and its
    /// subject on a transparent ground when the platform found one. What rides is what the person
    /// pointed at (asSticker), and the name follows that choice -- so every road below still reads
    /// one name and one answer «is this a sticker», exactly as before.
    struct MTPasted: Identifiable, Equatable {
        let photo: String              // the picture as it was pasted
        var cut: String? = nil         // its subject, lifted by the platform, on a transparent ground
        var asSticker: Bool
        var video: Bool = false
        var name: String { asSticker ? (cut ?? photo) : photo }
        var sticker: Bool { asSticker }
        var id: String { photo }
    }
    @State private var pastedImages: [MTPasted] = []
    func attachPasted(_ imgs: [UIImage]) {
        // THE ENCODE IS NOT THE SCREEN'S (18.09, the author's word: everything instant). The JPEG
        // re-encode and the outgoing shape of a big pasted photo used to run on the main thread,
        // and the field stood frozen for seconds. The bytes are made off the screen; the names land on it.
        let t0 = Date()
        Task.detached(priority: .userInitiated) {
            var made: [MTPasted] = []
            for ui in imgs {
                if MontanaMedia.hasTransparency(ui) {
                    // See-through: a sticker, kept as PNG — the card-sticker road (15.42), not the photo's.
                    guard let png = ui.pngData() else { continue }
                    let name = "att_\(UUID().uuidString).png"
                    guard MontanaMediaStore.put(name, data: png) else { continue }
                    made.append(MTPasted(photo: name, asSticker: true))
                } else {
                    guard let raw = ui.jpegData(compressionQuality: 0.95),
                          let jpeg = MontanaMedia.photoForSend(raw),   // the one shape of a photo on its way out
                          let name = saveChatPhotoTmp(jpeg) else { continue }
                    // THE SUBJECT OF AN OPAQUE PASTE (the author's word 22.09): a region copied out of a
                    // photograph carries no transparency, so the rule above calls it a photo and it stood
                    // in a bubble. The platform is asked for its subject here, off the screen; when it
                    // finds one the attachment grows a miniature of it and the person points at what
                    // rides. Nothing is decided for them -- the letter is a photograph until the
                    // miniature is touched.
                    var cut: String? = nil
                    if let subject = MontanaStickerCut.subject(of: ui), let png = subject.pngData() {
                        let cutName = "att_\(UUID().uuidString).png"
                        if MontanaMediaStore.put(cutName, data: png) { cut = cutName }
                    }
                    made.append(MTPasted(photo: name, cut: cut, asSticker: false))
                }
            }
            let done = made
            await MainActor.run {
                pastedImages.append(contentsOf: done)
                MontanaTrace.mark("paste_images", "n=\(done.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
            }
        }
    }
    /// WHAT WAITS ABOVE THE FIELD (the author word 22.09, by his own screenshot): the pictures
    /// themselves, at the size of his example — three hundred and forty-eight pixels by two hundred
    /// and thirty-four at three points to the point, so 116 by 78 — the corner rounded, the cross in
    /// the top corner of each, and NOT A WORD beside them. The row grows the bar upward; more than
    /// three of them travel sideways. A picture whose subject the platform lifted still carries the
    /// miniature of that subject beside it, and the finger points at the one that rides (22.09).
    var pastedPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pastedImages) { item in
                    let name = item.name
                    if let cut = item.cut {
                        // THE CHOICE IS A MINIATURE, NOT A WORD: the picture and its subject stand
                        // side by side, and the chosen one wears the ring.
                        Button {
                            if let i = pastedImages.firstIndex(where: { $0.photo == item.photo }) {
                                pastedImages[i].asSticker.toggle()
                                MontanaTrace.mark("paste_subject", pastedImages[i].asSticker ? "sticker" : "photo")
                            }
                        } label: {
                            Group {
                                if let ui = docImage(cut) {
                                    Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit).padding(5)
                                } else {
                                    Color(white: 0.2)
                                }
                            }
                            .frame(width: 62, height: 78)
                            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(item.asSticker ? 0.9 : 0.15), lineWidth: item.asSticker ? 2 : 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    ZStack(alignment: .topTrailing) {
                        Group {
                            // ONE OWNER OF A STAGED THUMBNAIL (22.09, the sticker session's own): the
                            // plate of a letter draws a picture and a video alike.
                            if let ui = MTLetterThumb.plate(file: name, isVideo: item.video) {
                                Image(uiImage: ui).resizable().aspectRatio(contentMode: item.sticker ? .fit : .fill)
                            } else {
                                Color(white: 0.2)
                            }
                        }
                        .frame(width: 116, height: 78)
                        .overlay { if item.video { Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundColor(.white.opacity(0.9)) } }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { PhotoPresenter.present(name) }
                        // The cross is drawn small, as in his example, and taken on the platform's own
                        // least target: the circle is 22 points and the touch around it is 44 — the
                        // target grows INWARD from the corner (the critic 22.09: carried outward by an
                        // offset, half of it lay outside the tile and was cut by the row's own bounds).
                        Button { pastedImages.removeAll { $0.photo == item.photo } } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.black.opacity(0.75), in: Circle())
                                .padding(4)
                                .frame(width: montanaTouchTarget, height: montanaTouchTarget, alignment: .topTrailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
    }
    func sendPasted(caption: String) {
        let names = pastedImages
        pastedImages = []
        // The letter a paste answers (22.09): the plate stands over the first picture, and a
        // sticker carries its quote to the other side in its passport.
        let answered = replyingTo
        replyingTo = nil
        let quote = answered.map { ChatStore.listPreview($0) } ?? ""
        let quoteMid = answered?.msgId.map { MontanaStickerBook.bare($0) } ?? ""
        // Pictures pasted together are one group too (19.09) — a sticker never folds, so a paste
        // that holds one stands on its own.
        let slots: [MTMediaGroup.Slot?] = names.contains(where: \.sticker) ? Array(repeating: nil, count: names.count)
                                                                            : MTMediaGroup.slots(names.count)
        for (i, item) in names.enumerated() {
            let cap = i == 0 ? caption : ""   // the words ride with the first picture
            // A STICKER THAT LEAVES JOINS MY SET (22.09): the set fills itself from what the person
            // actually sends, so the panel holds what they use. The bytes are copied into the book,
            // never linked -- a letter's file may be swept without emptying the set.
            if item.sticker {
                let file = item.name
                let peer = convKey, chatKey = chat.name
                let first = (i == 0 && !quote.isEmpty)
                let letter = store.letterMidFor(chatKey, file: file)
                Task { @MainActor in
                    MontanaStickerBook.shared.adopt(file: file)
                    // The passport rides behind this sticker too (22.09): a pasted sticker belongs
                    // to this phone's set exactly as one picked from the panel does.
                    MontanaStickerWire.sendPassport(letter: letter, file: file,
                                                    pack: MontanaStickerBook.shared.mineId, title: "Montana",
                                                    to: peer, chat: chatKey,
                                                    quote: first ? quote : "", quoteMid: first ? quoteMid : "")
                }
            }
            let docName = item.sticker ? MontanaCardPlate.stickerName : nil   // the sticker's name in the manifest (15.42)
            let qt: String? = (i == 0 && !quote.isEmpty) ? quote : nil   // the plate rides with the first picture
            var row = item.video
                ? Message(text: cap, isFromMe: true, time: nowHHMM(), replyText: qt, videoFile: item.name,
                          deliveryStatus: .sending, senderRef: nil, replyToId: qt == nil ? nil : answered?.id)
                : Message(text: cap, isFromMe: true, time: nowHHMM(), replyText: qt, imageFile: item.name,
                          docName: docName, deliveryStatus: .sending, senderRef: nil, replyToId: qt == nil ? nil : answered?.id)
            if let slot = slots[i] {
                row.groupKey = slot.key; row.groupIndex = slot.index; row.groupCount = slot.count
            }
            store.append(chat.name, row)
            sendMediaOverE2E(fileName: item.name, kind: item.video ? "vid" : "img", docName: docName, caption: cap)
        }
    }

    /// THE CARD IS SEEN BEFORE IT RIDES (the critic 22.09, the reference own panel above the field):
    /// a link in the field grows a plate of the tier — the site and the page title, or the link itself
    /// while the page is being read — and the cross beside it sends this letter with the bare link.
    /// THE PEOPLE A «@» NAMES (stage R, the reference folder's mention list): above a group's field while a word follows «@»,
    /// five at most; the whole row is the target, and the name goes into the words with a space after it.
    @ViewBuilder private var mentionPlate: some View {
        if chat.isGroup, mentions.chat == chat.name, mentions.query != nil {
            let people = mentions.people()
            if !people.isEmpty {
                VStack(spacing: 0) {
                    ForEach(people) { p in
                        Button { mention(p.name) } label: {
                            HStack(spacing: 10) {
                                AvatarCircle(photoURL: nil, color: .gray, initial: MontanaAvatar.initial(title: p.name, name: p.name), size: 30)
                                Text(verbatim: p.name).foregroundColor(.white).lineLimit(1)   // USER-DATA: a person's name in the group
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .montanaFieldGlass(maxCut: 18)
                .padding(.horizontal, 8)
                .transition(.opacity)
            }
        }
    }
    /// The word after «@» becomes the person's name, and a space after it; the caret stands at the end.
    private func mention(_ name: String) {
        guard let q = MTMentionCompose.tail(newMessage) else { return }
        let next = String(newMessage.dropLast(q.count + 1)) + "@" + name + " "
        newMessage = next
        input.caret = (next as NSString).length
        handleDraftChange(next)
    }
    @ViewBuilder private var linkPlate: some View {
        let composer = MTLinkPreviewBuilder.Compose.shared
        if !composer.url.isEmpty {
            // The plate stands while the page is being read and while there is something to show; a page
            // that said nothing takes its plate away with it (the author's word 22.09: nothing may hang).
            // WHAT THE PLATE SAYS IS WHAT THE CARD WILL SAY (the author word 22.09, the reference own
            // panel): the page title on the first line, the page words on the second — and while the
            // page is still being read, the link itself stands there instead of any waiting word.
            barPlate(glyph: "link",
                     title: Text(verbatim: composer.card?.t ?? composer.card?.s ?? URL(string: composer.url)?.host ?? composer.url),   // USER-DATA: the page own title
                     words: composer.card?.d ?? composer.card?.s ?? composer.url,
                     thumb: nil,
                     onTap: { if let u = URL(string: composer.url) { UIApplication.shared.open(u) } }) {
                composer.drop()
            }
            .transition(.opacity)
        }
    }

    func replyPreview(_ m: Message) -> some View {
        let words = ChatStore.listPreview(m)
        // What the letter carries, in small (the author's word 16.09) — the one thumbnail every place
        // draws (MTLetterThumb); the words then carry no glyph of their own.
        return barPlate(glyph: "arrowshape.turn.up.left",
                        title: Text("Reply to \(m.isFromMe ? E2E.myDisplayName() : store.displayName(for: chat.convId ?? chat.name))"),
                        words: ChatStore.rowMediaKind(m) == nil ? words : MontanaRowWords.bare(words),
                        thumb: MTLetterThumb(message: m, side: MontanaOctagon.composeHeight - 8),
                        onTap: { MontanaTrace.mark("plate_tap", "reply"); jumpTo(m.id) }) { replyingTo = nil }
    }

    /// A recovered transcript has no pipe: the letters are readable, nobody can be answered
    /// through them. Saying so beats a composer whose every letter would sit at a clock forever.
    var recoveredNote: some View {
        Text("Recovered from the archive without its key: these messages can be read, not answered. To write again, open a new contact.")
            .font(.footnote).foregroundColor(.gray).multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }

    /// A conversation the other side closed (24.09, pipeClosedMark): its letters stay readable; nobody is left to answer.
    var closedNote: some View {
        Text("The other side closed this conversation: these messages can be read, not answered. To write again, open a new contact.")
            .font(.footnote).foregroundColor(.gray).multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }

    /// OUT OF A GROUP, THE FIELD'S PLACE IS THE WAY OUT (the reference folder: «Delete and Exit», the red line standing where the
    /// field stood): its letters stay readable until the person takes the chat off this phone, after the platform's own question.
    var groupDeleteBar: some View {
        Button(role: .destructive) { askEraseGroup = true } label: {
            Text("Delete and Exit").font(.body).foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: montanaTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .confirmationDialog(Text("Are you sure you want to leave and delete \(store.title(for: chat))?"),
                            isPresented: $askEraseGroup, titleVisibility: .visible) {
            Button("Delete and Exit", role: .destructive) {
                MTGroup.shared.erase(chat.name, store: store)
                dismiss(); ui.closeChat()
            }
        }
    }
    /// A GROUP'S EVENT ROW (MTGroupEvent, stage R): the reference folder's service row -- a capsule in the middle of the feed in the
    /// day's own dress; a voice chat's row is the way in while its room lives.
    func groupEventRow(_ m: Message) -> some View {
        let e = MTGroupEvent.of(m.text)
        return Button {
            if e?.e == "call", let gid = MTGroup.id(of: chat.name), let b = MTRoomBook.shared.rooms[gid] {
                if b.mine { MTGroupRoom.shared.show(true) } else { MTGroupRoom.shared.join(chat.name, video: false) }
            } else {
                hideKeyboard()
            }
        } label: {
            Text(verbatim: MTGroup.shared.eventWords(m.text) ?? "")   // USER-DATA: the people's names inside the catalogue's sentence
                .font(.caption2).foregroundColor(.white).multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .montanaFieldGlass(maxCut: .greatestFiniteMagnitude)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
    /// A SUBSCRIBER READS, THE OWNER ALONE POSTS (the checklist, stage 4): a field whose letters the owner refuses would lie, so
    /// in its place stands the platform's bell -- the channel's sound off or on, the same switch as the list's swipe.
    var channelMuteBar: some View {
        let muted = store.mutedChats.contains(chat.name)
        return Button { store.toggleMuteChat(chat.name) } label: {
            Image(systemName: muted ? "bell.slash.fill" : "bell.fill")
                .font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                .frame(width: montanaTouchTarget, height: montanaTouchTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(muted ? "Unmute" : "Mute"))
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    /// The previews and the bar, as one node — hosted by MTKeyboardRider; the environment rides in by hand.
    /// THE PREVIEWS STAND ON THE FEED'S SIDE OF THE FIELD (02.10): above it on the keys, under it at the top of the turned feed.
    private var bottomGroup: some View {
        MTMainStack.noteDepth("chat-bar")   // the deepest point of the 2069 and 2070 deaths: the margin, measured
        return VStack(spacing: 0) {
            if !newestFirst { composePreviews }
            composeSlot
            if newestFirst { composePreviews }
        }
        .environmentObject(store).environment(ui)
        .environment(\.mtWindowSize, mtWin)
        .environment(\.mtWallpaperConv, chat.convId ?? chat.name)   // the bar's wash draws this chat's ground (22.09)
        .environment(\.mtChatKeyboardGeometry, pageKeyboard)   // the field takes the page's accessory from here
        .mtBoxed()
    }
    /// The open bar's row of buttons under the turned feed (03.10): the same bar, its lower tier alone, on the keys.
    private var rowGroup: some View {
        inputBar(.row)
            .environmentObject(store).environment(ui)
            .environment(\.mtWindowSize, mtWin)
            .environment(\.mtWallpaperConv, chat.convId ?? chat.name)
            .environment(\.mtChatKeyboardGeometry, pageKeyboard)
            .mtBoxed()
    }
    /// Whether the field's place holds the bar itself (not the selection's bar, a closed or recovered note, or the room that speaks).
    private var barWrites: Bool {
        if selectingMsgs { return false }
        if !chat.isGroup, chat.convId != nil, store.closedChats.contains(convKey) { return false }
        if !chat.isGroup, !ChatStore.isLocalRoom(chat.name), chat.convId != nil, !MontanaConv.holds(convKey) { return false }
        if chat.isGroup, !MTGroup.shared.canWrite(chat.name) { return false }
        return !ChatStore.isMontanaRoom(chat.name)
    }
    /// THE GROUND UNDER THE FIELD ON TOP (03.10): the top strip of the page -- the chat's own ground at the wash's alpha,
    /// solid from the screen's edge to the field's line at rest and fading over the feed's first letters -- hung behind the
    /// field's node, so the words stand on it as the bar stands on its strip at the bottom. A room nobody writes into lays no
    /// field: the strip is then the navigation bar's own, as it is in normal mode.
    private var topFieldGround: some View {
        GeometryReader { g in
            let y = g.frame(in: .global).minY
            let field = barWrites ? min(topBarSize.height, MTInputField.restingBar(open: false)) : 0
            MTEdgeWash(edge: .top, fade: MTEdgeWash.topFade, solid: y + field + MTEdgeWash.topReach - MTEdgeWash.topFade)
                .offset(y: -y)
        }
    }
    /// What the next letter carries before it goes: the letter being edited, the one answered, the link's card, the pasted pictures.
    @ViewBuilder private var composePreviews: some View {
        if let e = editingMessage { editPreview(e) }
        if let r = replyingTo { replyPreview(r) }
        linkPlate
        mentionPlate
        if !pastedImages.isEmpty { pastedPreview }
    }
    /// The field's own place: the bar, or what stands instead of it.
    @ViewBuilder private var composeSlot: some View {
        if selectingMsgs { selectionBar }
        else if !chat.isGroup, chat.convId != nil, store.closedChats.contains(convKey) { closedNote }
        // A person's own room is never a recovered correspondence.  Keep this guard beside
        // the composer as well as the archive repair: an old, stale row cannot turn Saved
        // Messages read-only during the frame before its store is reconciled.
        else if !chat.isGroup, !ChatStore.isLocalRoom(chat.name), chat.convId != nil, !MontanaConv.holds(convKey) { recoveredNote }
        else if ChatStore.isMontanaRoom(chat.name) { Color.clear.frame(height: 0) }   // the room speaks; nobody writes into it (29.09)
        else if chat.isGroup, MTGroup.shared.isOut(chat.name) { groupDeleteBar }   // out of the group: read, and the way out (stage R)
        else if chat.isGroup, !MTGroup.shared.canWrite(chat.name) { channelMuteBar }   // a subscriber reads; the owner alone posts
        else {
            inputBar(newestFirst ? .field : .whole)
        }
    }
    func inputBar(_ part: ChatInputBar.Part) -> some View {
        HStack(alignment: .bottom, spacing: 10) {   // the send/microphone keeps the bottom corner as the field grows
            ChatInputBar(model: input, focused: $inputFocused,
                         showEmoji: $showEmoji, composeOpen: $composeOpen, cap: fieldCap,
                         panel: showEmoji ? emojiHolder.view(height: kb.height,
                                    onEmoji: { input.text += $0 }, onSticker: { sendSticker($0) },
                                    onStickerFile: { sendStickerFile($0) },
                                    onOpenSet: { sheet = .stickerSet("") },
                                    onGifFile: { sendGifFile($0) },
                                    onGifFound: { sendGifFound($0) },
                                    onLift: { ask in
                                        // THE PAGE TAKES THE WHOLE SCREEN, so the keys go down with
                                        // the panel they carried: one choosing on the screen, not two.
                                        // It opens on the tab the panel showed; a touch on the search
                                        // line opens it with the search awake (23.09).
                                        MontanaTrace.mark("picker_page", "open tab=\(ask.tab) search=\(ask.search ? 1 : 0)")
                                        pickerAsk = ask
                                        inputFocused = false
                                        showEmoji = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pickerPage = true }
                                    },
                                    onSettings: { sheet = .stickerSet("") }) : nil,
                         rec: rec,
                         // THE PLATE IS OPEN (the author's word 22.09): every action the «+» used to
                         // hide stands in the lower tier of the bar and is called by its own name.
                         actions: MTComposeActions(gallery: { openGallery() },
                                                   card: { modal = .card },
                                                   file: { showFileImporter = true },
                                                   location: { ui.placeAsk = MTPlaceAsk(chat: chat.name, conv: convKey) },
                                                   contact: { modal = .contact }),
                         onSend: { sendMessage() },
                         onSendLongPress: { showSchedule = true },
                         onTextChange: { handleDraftChange($0) },
                         onPasteImages: { imgs in attachPasted(imgs) },
                         hasAttachment: !pastedImages.isEmpty,
                         hint: holdHint,
                         groupRoom: chat.isGroup,
                         part: part,
                         live: ribbon)
        }
        .padding(.horizontal).padding(.vertical, MTInputField.barPad)   // the bar's room — the tier's owner's number
        .background(alignment: .top) {
            // The reference's bottom edge: from 20 above the panel's top, fading in over 60, solid on past the
            // screen's edge; lifted with the bar it hides under the keys.
            // The wash's ground is window-sized: placed so its bottom is the window's bottom (the bar at rest
            // stands above the safe strip); its opaque run reaches up to 20 above the panel, fading over 60.
            // THE GROUND IS THE BAR AT REST, NOT THE BAR AS GROWN (the author's word 22.09: «at the
            // third line some fill appears — it is not needed; the field must always look the way it
            // looks on one line»). Measured from the bar's own height, the solid run climbed with
            // every new line of words and a dark band rose behind the field. It is the resting height
            // now — one number, one owner (MTInputField.restingBar) — so the ground is the same on
            // the first line and on the thirteenth, and the letters travel under the field's glass.
            // At the top of the turned feed the field's ground is the top strip's (topFieldGround): no bottom strip hangs from
            // it. The row of buttons left on the keys keeps the bottom strip of its own height (03.10).
            if !newestFirst || part == .row {
                GeometryReader { g in
                    let safe = MTScene.safeInsets().bottom
                    let rest = part == .row ? MTInputField.buttonTier + 2 * MTInputField.barPad : MTInputField.restingBar(open: composeOpen)
                    MTEdgeWash(edge: .bottom, fade: MTEdgeWash.bottomFade,
                               solid: rest + safe + MTEdgeWash.bottomReach - MTEdgeWash.bottomFade)
                        .offset(y: g.size.height + safe - MTScene.size().height)
                }
            }
        }
        // A TAP BESIDE THE FIELD IS A TAP ON IT (the author's word 20.09): the bar's own room above and
        // below the tier and the gaps between the buttons wake the field too. The buttons and the
        // field itself stand over this ground and take their own touches first.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { if !inputFocused { inputFocused = true } })
        // The whole bar and the row on the keys are both measured; the row is named «compose-bar-row» (03.10).
        .mtOnScreen("compose-bar" + (part == .row ? "-row" : ""))
        .onAppear {
            // The roads out of the machine, and the crown's controls on the way in — the owner
            // names them once; the crown and the bar only ask. The note's road is named the same
            // way as the voice's (21.09): the owner calls it once per tape — no publisher on the bar.
            rec.voiceSent = { sendVoice() }
            rec.noteSent = { sendVideoNote($0) }
            let st = MTHoldOverlayState.shared
            st.onSend = { VoicePlayer.shared.stop(); st.previewFile = nil; rec.send(why: "crown-tap") }
            st.onPause = { rec.pauseToggle() }
            st.onCancel = { VoicePlayer.shared.stop(); st.previewFile = nil; rec.cancel(why: "bin") }
            // LISTEN BEFORE SENDING (the author's word 23.09). The first press closes the tape — an AAC
            // container is playable only when it is closed — and hands the file to the ONE player of the
            // app ([C-1]: the same player every voice message uses, with its own ear routing); the next
            // presses stop and start it. The closed tape waits in its recorder and leaves by the very same
            // road as any other (sendVoice asks stop(), and stop() hands back what was heard).
            st.onPreview = {
                if let f = st.previewFile {
                    VoicePlayer.shared.toggle(f, title: String(localized: "Voice message", bundle: MTLanguage.bundle), voice: true)
                    MontanaTrace.mark("voice_preview", VoicePlayer.shared.paused ? "paused" : "playing")
                    return
                }
                guard let f = rec.voice.finishForReview() else { tooShortTape(); rec.cancel(why: "ear-short"); return }
                st.previewFile = f
                VoicePlayer.shared.toggle(f, title: String(localized: "Voice message", bundle: MTLanguage.bundle), voice: true)
                MontanaTrace.mark("voice_preview", "closed and playing")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .montanaVoiceEndedAtEar)) { _ in beginEarReply() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)) { _ in
            if earReply, !UIDevice.current.proximityState { endEarReply() }   // the phone left the ear: the tape stands, the screen decides
        }
    }
    @State private var reportSheet: MontanaReport? = nil   // Guideline 1.2
    @State private var landed = false        // the opening landing ran (once per opening, 18.09)
    /// THE REPLY AT THE EAR (the author's word 14.09): the chat's last voice ended with the phone
    /// at the ear — a tone in the ear, then the tape rolls; taking the phone away pauses the tape
    /// and leaves the recording on screen, hands-free, to send or to bin.
    @State private var earReply = false
    @State private var holdHint = false     // a press too short for a tape: the field says «hold to record»
    @ObservedObject private var dock = MontanaVideoDock.shared

    /// The round video note leaves by the ONE media road ([C-1]), the file already in the
    /// media tmp under its vnote_ name — the name is the roundness, every build can read it.
    func sendVideoNote(_ stored: String) {
        // THE ROW IS BORN ONCE PER FILE (21.09, the critic): a second call for a file already standing in
        // the chat rows nothing and sends nothing — the first row owns the letter; a second row would get
        // a name of its own, never a letter, and turn red «resend» at the mirror law's next pass.
        if (store.messages[chat.name] ?? []).contains(where: { $0.videoFile == stored }) {
            MontanaTrace.mark("send_dup", "note \(stored.prefix(24)) already in the chat — not born twice")
            return
        }
        store.append(chat.name, Message(text: "", isFromMe: true, time: nowHHMM(),
                                        videoFile: stored, deliveryStatus: .sending, senderRef: nil))
        if chat.convId != nil { sendMediaOverE2E(fileName: stored, kind: "vid") }
        else { store.setMediaStatus(chat.name, file: stored, .sent) }
    }

    // send the selected item from the media feed (photo or video) straight to the chat
    /// THE DRAFT BECOMES THE CAPTION (the author's word 19.09): words already typed in the field
    /// stand under the pictures being picked; once they leave as the caption the field is emptied by
    /// the one road a send takes — for the peer the draft is over as well.
    func consumeDraftAsCaption(_ caption: String) {
        let d = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.isEmpty, editingMessage == nil, caption.hasPrefix(d) else { return }
        newMessage = ""
        persistDraft("")
        if chat.convId != nil { ChatStore.setCkptSent(chat.convId ?? "", "") }
    }

    /// PICTURES PICKED TOGETHER LEAVE AS ONE GROUP (19.09): every letter of the pick carries one key,
    /// its place in the group and the group's size; the caption rides with the first letter only, so
    /// a feed that folds the group shows it once, and a feed that does not shows it once as well. Ten
    /// is the ceiling of a group; the eleventh picture opens the next key. The names are minted here,
    /// in the pick's order, so both chats stand the pictures the way the finger chose them.
    func sendAssets(_ assets: [PHAsset], caption: String) {
        guard assets.count > 1 else {
            if let a = assets.first { sendAsset(a, caption: caption) }
            return
        }
        let slots = MTMediaGroup.slots(assets.count)
        for (i, a) in assets.enumerated() {
            sendAsset(a, caption: i == 0 ? caption : "", mid: "mid:" + ChatStore.mintMid().mid, group: slots[i])
        }
    }

    /// A TAP ON ONE TILE OF A GROUP (19.09): the very road a single picture or video takes — a failed
    /// own letter, the resend; no file, the download; else the platform's viewer on that very picture.
    func tileTap(_ m: Message) {
        if m.isMine, m.deliveryStatus == .failed { resendAny(m); return }
        guard let f = m.imageFile ?? m.videoFile else { return }
        if !fileOnDisk(f) {
            if m.videoFile != nil, let st = store.stream(forFile: f) { VideoPresenter.present(stream: st.source, whole: st.landed); return }
            MontanaTrace.markFolded("media_tap", "no file -- the download is asked again", window: 5)
            store.retryOneMedia(m.msgId); return
        }
        if m.videoFile != nil { VideoPresenter.present(f); return }   // a video opens in the system's player at once (28.09)
        PhotoPresenter.present(f, among: store.pictures(in: chat.name))
    }

    /// The row a letter stands in: a letter folded into a media group is found by its group's row.
    func rowLead(_ id: MID) -> MID {
        chatRows.first { $0.id == id || $0.members.contains { $0.id == id } }?.id ?? id
    }
    /// THE LETTERS A ROW STANDS FOR (the author's word 19.09: a group is selected as one bubble):
    /// the members of a media group, or the letter itself.
    func rowLetters(_ id: MID) -> [Message] {
        if let r = chatRows.first(where: { $0.id == id || $0.members.contains { $0.id == id } }), !r.members.isEmpty { return r.members }
        return msgs.first { $0.id == id }.map { [$0] } ?? []
    }

    /// UNDER LIMITED ACCESS THE GALLERY IS THE WHOLE LIBRARY AT ONCE (the author's word 24.09: «with
    /// limited access open the All photos page at once — no page before it and no ticks set on it — to
    /// pick there and send»). The row's own page would show only the few pictures the person allowed,
    /// and the platform's page for that state wears every allowed one ticked; the platform's
    /// whole-library page asks no permission and opens clean. What is picked there waits above the
    /// field (stagePicks). Every other state keeps the row's page with its camera tile.
    func openGallery() {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else { sheet = .gallery; return }
        MontanaTrace.mark("gallery_open", "limited: the whole library at once")
        showGallery = true
    }

    /// FROM A CHOSEN PICTURE TO A WAITING ATTACHMENT, ONE ROAD (the author word 22.09). The gallery
    /// of the row hands over the pictures themselves, and they take here the very shape a pasted or
    /// a picked photograph takes — the outgoing shape of a photo, a video copied as it is — and land
    /// in the SAME array every other road lands in (pastedImages), so the hold, the release, the
    /// drawing above the field and the send stay one road for all of them.
    /// The library reads each picture on a thread of its own, so they come back out of order: a
    /// place is kept for each, and the field receives them in the order the finger chose them.
    /// A PICTURE THE LIBRARY WILL NOT NAME (limited access, the author's word 24.09) comes as the
    /// whole-library page's own hand-over and is read from it (stageFromPage), into the same slots.
    func stagePicks(_ picks: [MTPick]) {
        guard !picks.isEmpty else { return }
        let order = MTStageOrder(picks.count)
        let t0 = Date()
        let landed: () -> Void = {
            order.done += 1
            guard order.done == picks.count else { return }
            let made = order.slots.compactMap { $0 }
            pastedImages.append(contentsOf: made)
            MontanaTrace.mark("gallery_stage", "n=\(made.count) of \(picks.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
        }
        for (i, pick) in picks.enumerated() {
            let asset: PHAsset
            switch pick {
            case .asset(let a): asset = a
            case .provider(let page):
                stageFromPage(page, slot: i, order: order, landed: landed)
                continue
            }
            if asset.mediaType == .video {
                let opts = PHVideoRequestOptions()
                opts.isNetworkAccessAllowed = true
                opts.deliveryMode = .highQualityFormat
                PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                    let urlAsset = avAsset as? AVURLAsset
                    let stored = urlAsset.flatMap { copyToDocs(from: $0.url, original: $0.url.lastPathComponent)?.0 }
                    // A STAGED CLIP WEARS ITS FRAME LIKE A STAGED PHOTOGRAPH (the author's word 22.09:
                    // a photograph added above the field shows its thumbnail, a video shows a grey plate).
                    // The plate above the field asks MTLetterThumb for a picture; for a picture that is
                    // the file itself, for a clip it is the POSTER, and a poster is read from disk only —
                    // by rule, so that a list never decodes a frame while scrolling. Nothing on this road
                    // wrote one, so the tile stood grey for every video and only for a video. The frame is
                    // taken here, from the library that already keeps one, on this background callback and
                    // BEFORE the attachment is handed to the screen — so the very first drawing has it.
                    if let stored { MontanaVideoPoster.fromLibrary(asset, as: stored) }
                    DispatchQueue.main.async {
                        if let stored { order.slots[i] = MTPasted(photo: stored, asSticker: false, video: true) }
                        landed()
                    }
                }
            } else {
                let opts = PHImageRequestOptions()
                opts.isNetworkAccessAllowed = true
                opts.deliveryMode = .highQualityFormat
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
                    let name = data.flatMap { MontanaMedia.photoForSend($0) }.flatMap { saveChatPhotoTmp($0) }   // the one shape of a photo on its way out
                    DispatchQueue.main.async {
                        if let name { order.slots[i] = MTPasted(photo: name, asSticker: false) }
                        landed()
                    }
                }
            }
        }
    }

    /// A picture of the whole-library page that the library will not name to this app (limited access,
    /// 24.09): the page's own hand-over is read. A clip's file lives only inside the answer, so it is
    /// copied before the answer returns and its frame is taken from the copy there, off the screen,
    /// before the plate is drawn; a photo takes the one outgoing shape every photo takes.
    private func stageFromPage(_ page: NSItemProvider, slot i: Int, order: MTStageOrder, landed: @escaping () -> Void) {
        if page.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            page.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, err in
                let stored = url.flatMap { copyToDocs(from: $0, original: $0.lastPathComponent)?.0 }
                if let stored { MontanaVideoPoster.fromFile(stored) }
                else { MontanaTrace.mark("gallery_stage", "REFUSED kind=vid by=page — \(err?.localizedDescription ?? "the page handed no file")") }
                DispatchQueue.main.async {
                    if let stored { order.slots[i] = MTPasted(photo: stored, asSticker: false, video: true) }
                    landed()
                }
            }
        } else {
            page.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, err in
                let name = data.flatMap { MontanaMedia.photoForSend($0) }.flatMap { saveChatPhotoTmp($0) }   // the one shape of a photo on its way out
                if name == nil { MontanaTrace.mark("gallery_stage", "REFUSED kind=img by=page — \(err?.localizedDescription ?? "the page handed no picture")") }
                DispatchQueue.main.async {
                    if let name { order.slots[i] = MTPasted(photo: name, asSticker: false) }
                    landed()
                }
            }
        }
    }

    func sendAsset(_ asset: PHAsset, caption: String = "", mid: String? = nil,
                   group: (key: String, index: Int, count: Int)? = nil) {
        let born = mid.flatMap(ChatStore.birthMs(fromMid:)) ?? Date().timeIntervalSince1970
        func stamp(_ row: inout Message) {
            if let group { row.groupKey = group.key; row.groupIndex = group.index; row.groupCount = group.count }
        }
        if asset.mediaType == .video {
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            // THE TWO WAITS BEFORE A ROW EXISTS ARE MEASURED (the critic 22.09): the library's
            // hand-over of the file and the copy of it onto our own disk. Neither had a single line
            // in any diary, so «why do I have to wait to put a local file in the chat» could only be
            // guessed at. Now the next incident is read, not guessed.
            let askedAt = Date()
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                let handMs = Int(Date().timeIntervalSince(askedAt) * 1000)
                guard let urlAsset = avAsset as? AVURLAsset else {
                    MontanaTrace.mark("asset_stage", "REFUSED kind=vid hand_ms=\(handMs) — the library handed no file")
                    return
                }
                let copyT0 = Date()
                guard let (stored, _) = copyToDocs(from: urlAsset.url, original: urlAsset.url.lastPathComponent) else {
                    MontanaTrace.mark("asset_stage", "REFUSED kind=vid hand_ms=\(handMs) — the file could not be copied")
                    return
                }
                let copyMs = Int(Date().timeIntervalSince(copyT0) * 1000)
                // THE ROW IS BORN WITH ITS PICTURE. The frame comes from the library — which keeps one
                // for every video of its own — here, before the row exists. Made inside the send it
                // raced the encoder for one video engine and lost for sixteen seconds, and the person
                // watched a grey plate of a file already lying on his phone (iPhone 17, 17:57:32).
                MontanaVideoPoster.fromLibrary(asset, as: stored)
                let mb = (((try? FileManager.default.attributesOfItem(atPath: attachmentURL(stored).path))?[.size] as? Int) ?? 0) / 1_048_576
                MontanaTrace.mark("asset_stage", "kind=vid hand_ms=\(handMs) copy_ms=\(copyMs) mb=\(mb)")
                DispatchQueue.main.async {
                    var row = Message(text: caption, isFromMe: true, time: nowHHMM(),
                                      videoFile: stored, deliveryStatus: .sending,
                                      msgId: mid, senderRef: nil, createdAt: born)
                    stamp(&row)
                    store.append(chat.name, row)
                    self.sendMediaOverE2E(fileName: stored, kind: "vid", caption: caption)
                }
            }
        } else {
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
                guard let data, let jpeg = MontanaMedia.photoForSend(data),   // the one shape of a photo on its way out
                      let name = saveChatPhotoTmp(jpeg) else { return }
                DispatchQueue.main.async {
                    var row = Message(text: caption, isFromMe: true, time: nowHHMM(),
                                      imageFile: name, deliveryStatus: .sending,
                                      msgId: mid, senderRef: nil, createdAt: born)
                    stamp(&row)
                    store.append(chat.name, row)
                    self.sendMediaOverE2E(fileName: name, kind: "img", caption: caption)
                }
            }
        }
    }

    // row shown while recording a voice message: cancel · red dot + timer · send
    // photo taken by the camera → image message
    /// The card is typed in the open, like a letter (15.43, the author's word): the plate on the
    /// peer's screen fills in as the words come. The same gates and pace as the field's live
    /// typing, the same word — the draft word with the card mark ahead; an old reader shows the text.
    func sendCardDraft(_ t: String) {
        let peer = convKey
        guard !peer.isEmpty else { return }
        if t.isEmpty { draft.task?.cancel(); draft.task = nil; E2E.shared.sendDraftClear(to: peer); return }
        guard ribbon && (store.peerInChat(chat.name) || store.typingChats.contains(chat.name)) else { return }
        draft.pending = MontanaCardPlate.mark + t; draft.caret = -1; draft.replyMid = ""
        if draft.task == nil {
            let wait = max(0, 0.12 - Date().timeIntervalSince(draft.lastSent))
            let box = draft
            box.task = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                box.lastSent = Date(); box.task = nil
                E2E.shared.sendDraft(to: peer, text: box.pending, caret: -1, replyMid: "")
            }
        }
    }

    /// THE CARD AS A PHOTO (the author's word 28.09: «sent as a beautiful photo of the standard size»): the kept card
    /// drawn at the card's standard proportions and sent down the picture road as any photo is; its words ride as the
    /// caption under the card's mark, so every build reads them, and a build that knows the mark draws the photo alone and
    /// offers the words to the contacts.
    @MainActor func sendCardPhoto(_ card: MontanaBusinessCard) {
        guard let jpeg = card.photo(), let name = saveChatPhotoTmp(jpeg) else { MontanaTrace.mark("card_photo", "FAIL render"); return }
        _ = store.append(chat.name, Message(text: card.wire, isFromMe: true, time: nowHHMM(), imageFile: name,
                                            deliveryStatus: .sending, senderRef: nil))
        sendMediaOverE2E(fileName: name, kind: "img", caption: card.wire)
        MontanaTrace.mark("card_photo", "bytes=\(jpeg.count) lines=\(card.lines.count)")
    }

    /// A MOVING PICTURE LEAVES AS A FILE (22.09): the picture road re-encodes to a still frame by
    /// construction (photoForSend), so a GIF rides the document road, which touches no byte of it --
    /// the receiver gets the file it was sent, frame for frame.
    @MainActor func sendGifFile(_ book: String) {
        guard let data = try? Data(contentsOf: MontanaMediaStore.url(book)) else { return }
        // THE NAME SAYS WHICH OF THE TWO IT IS (23.09): a sticker of the house rides the same
        // road as a moving picture, and only its name tells both sides to draw it bare and at a
        // sticker's size. A build that knows neither name shows the file plate it always showed.
        let mark = book.hasPrefix("stick_") ? "stick_" : "gif_"
        let name = mark + UUID().uuidString + ".gif"
        guard MontanaMediaStore.put(name, data: data) else { return }
        _ = store.append(chat.name, Message(text: "", isFromMe: true, time: nowHHMM(),
                                            docFile: name, docName: name,
                                            deliveryStatus: .sending, senderRef: nil))
        sendMediaOverE2E(fileName: name, kind: "doc", docName: name)
        MontanaTrace.mark("gif_send", "bytes=\(data.count)")
    }

    /// A MOVING PICTURE OF THE HOUSE STANDS IN THE CHAT AT THE TAP (the author's word 23.09: «first into the chat,
    /// then let it load»). The row is born now under its one name, wearing the light picture the tile already
    /// holds; the full picture is brought down behind it and takes the same name's place before a byte leaves —
    /// the name never changes, only what lies under it before the road starts. The book keeps the full one. If
    /// the full one cannot be brought, the light one leaves, so the row neither hangs nor vanishes.
    @MainActor func sendGifFound(_ f: MontanaGifSearch.Found) {
        let name = "gif_" + UUID().uuidString + ".gif"
        let light = MontanaGifArt.light(f)
        if let light { _ = MontanaMediaStore.put(name, data: light) }
        _ = store.append(chat.name, Message(text: "", isFromMe: true, time: nowHHMM(),
                                            docFile: name, docName: name,
                                            deliveryStatus: .sending, senderRef: nil))
        MontanaTrace.mark("gif_send", "row at the tap light=\(light?.count ?? 0)")
        Task {
            let t0 = Date()
            let full = await MontanaGifSearch.fetchFull(f)   // within its term, or the light one leaves
            await MainActor.run {
                if let full, MontanaMediaStore.put(name, data: full) {
                    _ = MontanaGifBook.shared.add(data: full)
                    MTGifPlay.shared.renew(name)   // the full picture plays its own three cycles
                }
                sendMediaOverE2E(fileName: name, kind: "doc", docName: name)
                MontanaTrace.mark("gif_send", "bytes=\(full?.count ?? light?.count ?? 0) full=\(full == nil ? 0 : 1) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
            }
        }
    }

    /// A STICKER OF MY OWN SET LEAVES BY THE PICTURE ROAD (22.09) -- the road the card sticker has
    /// ridden since 15.42: an ordinary picture letter whose manifest carries the card sticker's
    /// name, which every live build already draws without a bubble around it. The book's own file
    /// is never handed to a letter: the bytes are copied under a letter's name, so sweeping the
    /// conversation never empties the set.
    @MainActor func sendStickerFile(_ book: String) {
        guard let png = try? Data(contentsOf: MontanaMediaStore.url(book)) else {
            MontanaTrace.mark("sticker_send", "FAIL read")
            return
        }
        let name = "att_\(UUID().uuidString).png"
        guard MontanaMediaStore.put(name, data: png) else {
            MontanaTrace.mark("sticker_send", "FAIL store")
            return
        }
        // A STICKER ANSWERS A LETTER LIKE ANY WORD DOES (the author's word 22.09): the plate stands
        // over it here at once, and the quote reaches the other side in the sticker's passport --
        // the picture road carries no reply of its own.
        let answered = replyingTo
        replyingTo = nil
        let quote = answered.map { ChatStore.listPreview($0) } ?? ""
        let quoteMid = answered?.msgId.map { MontanaStickerBook.bare($0) } ?? ""
        _ = store.append(chat.name, Message(text: "", isFromMe: true, time: nowHHMM(),
                                            replyText: quote.isEmpty ? nil : quote,
                                            imageFile: name,
                                            docName: MontanaCardPlate.stickerName, deliveryStatus: .sending,
                                            senderRef: nil, replyToId: answered?.id))
        // A sticker used is a sticker kept, and it moves to the front of the panel's strip (22.09).
        MontanaStickerBook.shared.adopt(file: name)
        sendMediaOverE2E(fileName: name, kind: "img", docName: MontanaCardPlate.stickerName)
        MontanaTrace.mark("sticker_send", "bytes=\(png.count)")
        // THE PASSPORT RIDES BEHIND THE STICKER (22.09), named by the SAME letter the picture rides
        // under: on the other side the two meet by that name, and the menu grows its rows.
        MontanaStickerWire.sendPassport(letter: store.letterMidFor(chat.name, file: name), file: book,
                                        pack: MontanaStickerBook.shared.mineId, title: "Montana",
                                        to: convKey, chat: chat.name, quote: quote, quoteMid: quoteMid)
    }

    func sendCameraImage(_ img: UIImage) {
        if let jpeg = img.avatarResized(1200).jpegData(compressionQuality: 0.85),
           let name = saveChatPhotoTmp(jpeg) {
            store.append(chat.name, Message(text: "", isFromMe: true, time: nowHHMM(),
                                            imageFile: name, deliveryStatus: .sending,
                                            senderRef: nil))
            sendMediaOverE2E(fileName: name, kind: "img")
        }
    }

    // video taken by the camera → video message
    func sendCameraVideo(_ url: URL) {
        if let (stored, _) = copyToDocs(from: url, original: url.lastPathComponent) {
            store.append(chat.name, Message(text: "", isFromMe: true, time: nowHHMM(),
                                            videoFile: stored, deliveryStatus: .sending,
                                            senderRef: nil))
            sendMediaOverE2E(fileName: stored, kind: "vid")
        }
    }

    // pick from gallery: can be photo OR video — determined by type
    /// A press that outlived the tap but not the tape's least length: the platform's warning tap
    /// and a word in the field, instead of silence (measured 19.09 on an iOS 18 phone: eight
    /// such presses in a row, and nothing said).
    func tooShortTape() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        holdHint = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            holdHint = false
        }
    }

    // finish recording and send the voice message
    func sendVoice() {
        guard let (file, dur) = rec.voice.stop() else { tooShortTape(); return }
        guard let data = try? Data(contentsOf: voiceFileURL(file)) else { return }
        let localName = "voice_\(UUID().uuidString).m4a"
        MontanaMediaStore.put(localName, data: data)
        // THE WAVE IS BORN WITH THE ROW (18.09, the author's word: everything local is ready at
        // placement — the sending is a second process). Probed from the recording here, kept under
        // the row's name: the first frame draws the bars, and the manifest carries this same shape.
        if let w = MTWaveform.compute(voiceFileURL(file), bars: MTWaveform.bars) { MTWaveform.remember(localName, w) }
        try? FileManager.default.removeItem(at: voiceFileURL(file))         // remove the original recording
        store.append(chat.name, Message(text: "", isFromMe: true, time: nowHHMM(),
                                        audioFile: localName, audioDuration: dur,
                                        deliveryStatus: .sending, senderRef: nil))
        // UNIFIED media path: vault + chunked-blob + honest status — like photo/video/file
        if chat.convId != nil {
            sendMediaOverE2E(fileName: localName, kind: "aud")
        } else {
            store.setMediaStatus(chat.name, file: localName, .sent)
        }
    }

    // send media to the peer over E2E (photo/video/document inside, base64).
    // Heavy files (>6 MB, e.g. long videos) are not sent through the relay — a server-side upload is required.
    // Stage 12: the file is split into chunks (512 KB), each a separate content-addressed blob;
    // upload runs in parallel with the "On my way!" progress, a compact manifest goes into the E2E ratchet.
    // Resend of failed media (red "Retry" banner).
    // ONE resend entry for every bubble kind: media re-mints and re-rides; text (and any
    // letter without a file) re-knocks through the queue under the SAME letter identity —
    // the receiver dedups by mid, so a double tap cannot create a second bubble.
    func resendAny(_ m: Message) {
        if m.videoFile != nil || m.imageFile != nil || m.audioFile != nil || m.docFile != nil {
            resendMedia(m); return
        }
        if chat.isGroup { MTGroup.shared.resend(m, in: chat.name, store: store); return }   // a group's letter rides again on its own copies
        guard let sid = m.msgId else { return }
        let bare = sid.hasPrefix("mid:") ? String(sid.dropFirst(4)) : sid
        store.settleByMid(conv: chat.name, mid: bare, .sending)
        MontanaDeliveryEngine.shared.retryNow(mid: bare, to: convKey, chat: chat.name, text: m.text)
    }

    func resendMedia(_ m: Message) {
        let file: String?; let kind: String
        if let v = m.videoFile { file = v; kind = "vid" }
        else if let i = m.imageFile { file = i; kind = "img" }
        else if let a = m.audioFile { file = a; kind = "aud" }
        else if let d = m.docFile { file = d; kind = "doc" }
        else { return }
        guard let f = file else { return }
        store.setMediaStatus(chat.name, file: f, .sending)
        // THE SAME CALL AS THE FIRST SEND. Not one special parameter: the door takes the
        // letter's identity from the bubble itself. Different behaviour for «send» and
        // «retry» is two mechanisms for one task, each catching its bugs alone.
        sendMediaOverE2E(fileName: f, kind: kind, docName: m.docName, caption: m.text)
    }

    // Single media-send entry point. ONE progress bar on the bubble: video — compression 0…30% +
    // upload 30…100%; everything else — upload 0…100%. Each outgoing media file is stored
    // sealed in Montana/Chats/<label>/Media/ (vault, media_key) — same as incoming.
    // FORWARDING RIDES THE SAME ROADS AS SENDING. The old handler put a copy of the letter into the
    // target feed and stopped there: no identity, no queue, no attempt — the sender saw the letter
    // in the peer's chat, the peer never received it, and nothing in the diaries could show a loss
    // that was never a send (the author, 05.09). A file keeps its one name across conversations
    // (purgeLocalCopies counts on that); the target chat mints its own letter identity.
    /// The forward the feed asked for: this screen's executor, the same picker, the same road.
    /// The profile's selection asked to forward several letters: the same picker as the chat's own.
    private func consumePendingForwardMany() {
        guard let mids = ui.pendingForwardMany, !mids.isEmpty else { return }
        let picked = msgs.filter { mids.contains($0.id) }
        ui.pendingForwardMany = nil
        guard !picked.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sheet = .forwardMany(picked) }
    }
    private func consumePendingForward(_ mid: MID?) {
        guard let mid, let m = msgs.first(where: { $0.id == mid }) else { return }
        ui.pendingForward = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sheet = .forward(m) }
    }

    /// The correspondent's face for the reaction plates — a value the bubble carries (feed and menu).
    var reactionFaces: MTReactionFaces {
        MTReactionFaces(solo: ChatStore.isLocalRoom(chat.name),
                        peerPhoto: ChatStore.isLocalRoom(chat.name) ? nil : store.avatarFor(chat),
                        peerColor: chat.color, peerInitial: store.initial(for: chat))
    }

    func forwardMessage(_ m: Message, to target: Chat) {
        let conv = target.convId ?? ""
        let source: String?; let kind: String
        if let v = m.videoFile { source = v; kind = "vid" }
        else if let i = m.imageFile { source = i; kind = "img" }
        else if let a = m.audioFile { source = a; kind = "aud" }
        else if let d = m.docFile { source = d; kind = "doc" }
        else { source = nil; kind = "" }
        // A FORWARD IS A LETTER OF ITS OWN, WITH A FILE OF ITS OWN (20.09, the critic): the media
        // roads name a row by its file — status, progress, the letter's name (letterMidFor) all find
        // the FIRST row wearing the file. A copy that shared the original's file in the same chat was
        // sent under the original's name (the peer refused it as a copy), stood nameless for its
        // receipts, and a reaction to it landed on the original. The copy takes a hard link under a
        // fresh name — no bytes doubled, no row shared.
        let file: String? = source.flatMap { src in
            let mid = ChatStore.mintMid().mid
            let fresh = store.mediaFileName(kind: kind, ext: (src as NSString).pathExtension, seed: "mid:" + mid,
                                            round: src.hasPrefix("vnote_"), badge: MontanaVideoNoteCamera.badgeTag(src))
            guard MontanaMediaStore.clone(src, as: fresh) else {
                MontanaTrace.mark("forward", "refused — the file could not be cloned kind=\(kind)")
                return nil
            }
            if let poster = try? Data(contentsOf: posterURL(src)) { try? poster.write(to: posterURL(fresh)) }
            if MontanaVideoMark.isCompressed(src) { MontanaVideoMark.mark(fresh) }   // the same bytes: transcoded once
            return fresh
        }
        guard let f = file else {
            guard !m.text.isEmpty else { return }   // SILENT-OK: an empty row carries nothing to forward
            guard !MTRowLetter.ownRow(m.text) else { MontanaTrace.mark("forward", "refused -- a row of this phone's own"); return }
            if m.text.hasPrefix(MontanaWakePush.letterBlobMark) {
                // The row holds a reference, not words: fetch the words first; without them
                // nothing leaves (07.09 20:14, a raw reference forwarded to the store build).
                let src = chat.name
                Task {
                    guard let full = await MontanaWakePush.resolveLongLetter(m.text) else {
                        MontanaTrace.mark("forward", "refused raw-reference")
                        return
                    }
                    await MainActor.run {
                        if let i = store.messages[src]?.firstIndex(where: { $0.id == m.id }) { store.messages[src]?[i].text = full }
                        let sent = store.send(text: full, chat: target.name, convRef: conv,
                                              replyText: Message.forwardedQuote, linkCard: m.linkPreview)
                        store.noteForwardSource(chat: target.name, id: sent.id, from: chat.name)
                    }
                }
                return
            }
            let sent = store.send(text: m.text, chat: target.name, convRef: conv,
                                  replyText: Message.forwardedQuote, linkCard: m.linkPreview)
            store.noteForwardSource(chat: target.name, id: sent.id, from: chat.name)
            return
        }
        store.append(target.name, Message(text: m.text, isFromMe: true, time: nowHHMM(),
                                          imageFile: kind == "img" ? f : nil, videoFile: kind == "vid" ? f : nil,
                                          audioFile: kind == "aud" ? f : nil, audioDuration: m.audioDuration,
                                          docFile: kind == "doc" ? f : nil, docName: m.docName,
                                          deliveryStatus: target.convId == nil ? .sent : .sending,
                                          senderRef: nil, fwdFrom: chat.name, forwarded: true))
        guard target.convId != nil else { return }   // SILENT-OK: a room without an address has no wire, as in sendVoice
        MontanaTrace.mark("forward", "kind=\(kind) to=\(String(conv.prefix(10)))")
        sendMediaOverE2E(fileName: f, kind: kind, docName: m.docName, caption: m.text, peer: conv, chatKey: target.name)
    }

    // `peer`/`chatKey` name another conversation when a letter is forwarded; the open chat otherwise.
    /// THE ONE MEDIA ROAD lives in MontanaMediaSender (16.09): the chat and the share sheet's
    /// ingest send by the same function; the screen only names its own peer and chat.
    func sendMediaOverE2E(fileName: String, kind: String, docName: String? = nil, caption: String = "",
                          peer: String? = nil, chatKey: String? = nil) {
        MontanaMediaSender(store: store).sendMediaOverE2E(fileName: fileName, kind: kind, docName: docName, caption: caption,
                                                          peer: peer ?? convKey, chatKey: chatKey ?? chat.name)
    }

    /// The chat's ground — the one view the appearance preview draws too ([C-1], 11.09).
    var chatBackground: some View { MontanaChatBackdrop(conv: chat.convId ?? chat.name) }   // this chat's own wallpaper first (22.09)

    var darkGradient: LinearGradient { montanaDarkGradient }
    var logoPattern: some View { MontanaLogoPattern() }
    // our default background: the chat's own ground, drawn once at file scope ([C-1])
    var defaultBackground: some View { MontanaChatGround() }

    // whether two timestamps fall on the same day
    func sameDay(_ a: Double, _ b: Double) -> Bool {
        Calendar.current.isDate(Date(timeIntervalSince1970: a), inSameDayAs: Date(timeIntervalSince1970: b))
    }
    // day label: Today / Yesterday / "8 June" — one owner, see MTDayLabel
    func dayLabel(_ epoch: Double) -> String { MTDayLabel.of(epoch) }

    // conversation start date: Today / Yesterday / date
    var startDate: String {
        let cal = Calendar.current
        if cal.isDateInToday(Date()) { return String(localized: "Today", bundle: MTLanguage.bundle) }
        if cal.isDateInYesterday(Date()) { return String(localized: "Yesterday", bundle: MTLanguage.bundle) }
        return MTDayLabel.of(Date().timeIntervalSince1970)
    }

    // The flow and floating day share the same white text and glass capsule.
    func datePill(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.caption2).foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .montanaFieldGlass(maxCut: .greatestFiniteMagnitude)
            .padding(.vertical, 4)
    }

    // THE ONE PANEL lives in MontanaBubble (EmojiInputPanel) as the field's inputView; a second
    // SwiftUI panel with a height of its own stood here dead until 18.09 — two heights, one screen.
    func sendSticker(_ e: String) {
        let saved = newMessage
        newMessage = stickerMark + e
        sendMessage()
        newMessage = saved
        withAnimation { showEmoji = false }
    }

    // ── message actions ──
    // ONE ANSWER FROM ONE PERSON. A second tap on the same emoji takes the answer back; a tap on
    // another one REPLACES it, because a person does not feel two things about one letter at once.
    // The peer's answer is replaced the same way when it arrives, and the wire is unchanged: it
    // still says only "add this" and "drop that", so an older build speaks with us as before.
    func react(_ m: Message, _ e: String) {
        MTReactClock.tapped(m.id)
        let began = Date().timeIntervalSince1970
        guard let i = store.messages[chat.name]?.firstIndex(where: { $0.id == m.id }) else {
            MontanaTrace.mark("react_lost", "no row for the letter in \(chat.name)")
            return
        }
        // The letter is changed ONCE and published ONCE. Four separate touches of the same letter
        // copied the whole conversation four times and redrew the feed four times for a single tap
        // — that is where the wait a person felt was spent.
        guard var list = store.messages[chat.name] else { return }
        var target = list[i]
        let mine = target.myReact
        var dropped: String? = nil
        if mine == e {
            target.reactions.removeAll { $0 == e }
            target.myReact = nil
        } else {
            if let old = mine, let k = target.reactions.firstIndex(of: old) {
                target.reactions.remove(at: k)
                dropped = old
            } else if !target.reactions.isEmpty {
                // A letter answered BEFORE this build carries plates nobody is named on. The one
                // name we do know is the peer's; everything else on that letter was put there by
                // this person, so it is his old answer and it goes when he gives a new one.
                // Without this, an unnamed plate would sit beside the new one for ever — two
                // answers from one person, which is the thing that must not exist.
                let peers = target.peerReact
                for old in target.reactions where old != peers {
                    if dropped == nil { dropped = old }
                }
                target.reactions.removeAll { $0 != peers }
            }
            target.reactions.append(e)
            target.myReact = e
            MTReactions.note(e)
        }
        list[i] = target
        store.messages[chat.name] = list
        MTReactionBoard.shared.show(target)   // the face of the letter, in the same move
        let added = target.myReact == e
        store.noteReaction(chat.name, added ? e : nil, mine: true, on: target)   // the row wears the answer
        MontanaTrace.mark("react_put", "\(e) added=\(added) rows=\(list.count) ms=\(Int((Date().timeIntervalSince1970 - began) * 1000))")
        // sync to the peer over E2E (bound by serverId, fallback — by text)
        guard chat.convId != nil else { return }
        let peer = convKey
        let tell: (String, Bool) -> Void = { emoji, add in
            let obj: [String: Any] = ["sid": target.msgId ?? "", "txt": target.text,
                                      "e": emoji, "op": add ? "add" : "del"]
            guard let json = try? JSONSerialization.data(withJSONObject: obj),
                  let body = String(data: json, encoding: .utf8) else { return }
            // A group's answer rides the group's own carrier to every phone of it (MTGroup.signal), never to an address it lacks.
            if chat.isGroup { MTGroup.shared.signal(reactionMark + body, in: chat.name, store: store); return }
            MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer, mid: UUID().uuidString,
                                                 text: reactionMark + body, silent: true)
        }
        if let old = dropped { tell(old, false) }
        tell(e, added)
    }

    // ── multiple message selection ──
    // Top: left "Delete chat", right "Cancel". Bottom: [Delete · Share · Forward].
    var selectionTopBar: some View {
        HStack {
            Button(role: .destructive) { confirmDeleteWholeChat = true } label: {
                Text("Delete chat").foregroundColor(.red).font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text("Selected: \(selectedMsgs.count)").foregroundColor(.white).font(.subheadline)
            Spacer()
            Button { selectingMsgs = false; selectedMsgs.removeAll() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MontanaOctagon.barGlyph)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Cancel"))
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    var selectionBar: some View {
        HStack(spacing: 0) {
            selectionToolButton("trash", "Delete", tint: .red) { deleteSelected() }
            selectionToolButton("square.and.arrow.up", "Share", tint: Color.accentColor) { shareSelected() }
            selectionToolButton("arrowshape.turn.up.right", "Forward", tint: Color.accentColor) { forwardSelected() }
        }
        .padding(.vertical, 8)
        .opacity(selectedMsgs.isEmpty ? 0.4 : 1)
        .disabled(selectedMsgs.isEmpty)
    }
    func selectionToolButton(_ icon: String, _ title: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20))
                Text(LocalizedStringKey(title)).font(.system(size: 11))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
        }
    }
    // share the selected messages (text + local media files) via the system share sheet
    func shareSelected() {
        let picked = (store.messages[chat.name] ?? []).filter { selectedMsgs.contains($0.id) }
        var items: [Any] = []
        for m in picked {
            if !m.text.isEmpty { items.append(m.text) }
            for f in [m.imageFile, m.videoFile, m.audioFile, m.docFile].compactMap({ $0 }) {
                let u = attachmentURL(f)   // the finished-file store, then the legacy
                if FileManager.default.fileExists(atPath: u.path) { items.append(u) }
            }
        }
        guard !items.isEmpty else { return }
        MTShare.present(items)   // the one door of every modal (MTTop, 25.09)
        selectingMsgs = false; selectedMsgs.removeAll()
    }
    func deleteSelected() {
        // The one road out of the feed ([C-1], 19.09): the tombstone, the cargo and the list record
        // follow each row, as under the menu's «Delete for me».
        let picked = (store.messages[chat.name] ?? []).filter({ selectedMsgs.contains($0.id) })
        for m in picked { delete(m) }
        selectingMsgs = false; selectedMsgs.removeAll()
    }
    func forwardSelected() {
        let picked = (store.messages[chat.name] ?? []).filter { selectedMsgs.contains($0.id) }
        guard !picked.isEmpty else { return }
        sheet = .forwardMany(picked)
    }

    // time picker screen for a scheduled message (long press on send)
    var scheduleSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(chat.convId == nil ? "Remind me" : "Send later").font(.headline).foregroundColor(.white)
                DatePicker("When", selection: $scheduleDate, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                Button {
                    let txt = newMessage.trimmingCharacters(in: .whitespaces)
                    if !txt.isEmpty {
                        store.schedule(chat: chat.name,
                                       convRef: chat.convId != nil ? convKey : nil,
                                       text: txt, at: scheduleDate.timeIntervalSince1970)
                        newMessage = ""
                    }
                    showSchedule = false
                } label: {
                    Text(chat.convId == nil ? "Remind me" : "Schedule").frame(maxWidth: .infinity).padding()
                        .background(Color.accentColor).foregroundColor(.black).font(.headline)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Spacer()
            }
            .padding()
            .montanaPageGround()   // my page's ground, as every page wears it (26.09)
        }
        .preferredColorScheme(.dark)
    }
    func delete(_ m: Message) { store.deleteLocally(chat: chat.name, m) }   // ONE road with the profile ([C-1])
    // Field height budget: screen minus the keyboard minus the chrome
    // (header, bars, feed minimum), bounded by the absolute 15-line ceiling inside MTInputField.
    // Both inputs come from single owners (screen constant, MTKeyboard height) — the cap is a
    // deterministic function, not a measurement race.
    // Field cap from a STABLE input: the chat overlay height (mtWin), measured by ChatOverlay,
    // which shrinks with the keyboard but NOT with the field — so the field's own growth can
    // never move its own ceiling (the feedback loop that froze the field). Half the overlay,
    // bounded by the absolute 15-line ceiling; the feed keeps the other half. Any device/OS.
    private var fieldCap: CGFloat {
        // The overlay is the screen's height now (measured on the container, never shrunk by the
        // keyboard); the keyboard is subtracted from its one owner — still two stable inputs.
        // MEASURED 1817 (field_grow cap=65 with the keys up, 279 with them down): the overlay's size DID
        // shrink with the keyboard, and the keys were taken off twice — the room was the screen less two
        // keyboards. The window's own height never shrinks: one owner, the keys taken off once.
        let room = MTScene.size().height - (kb.isUp ? kb.height : 0)
        return MTInputField.cap(room: room)   // the one owner of the tier answers the ceiling (20.09)
    }

    // Everything a keystroke must do beyond redrawing the panel: persist, stream, signal typing.
    func handleDraftChange(_ val: String) {
        MTLinkPreviewBuilder.Compose.shared.look(at: val)   // the plate above the field follows the words (22.09)
        MTMentionCompose.shared.look(at: val, in: chat.name)   // «@» in a group raises its people (stage R)
        // THE FIELD IS THE DRAFT ON DISK TOO (the author's word 20.09: a text of 86 characters rose in
        // Saved Messages at every opening, through erasing and sending alike). The disk used to be
        // written by three hands: a throttled write here behind a gate on the peer's address — which
        // Saved Messages has not, so nothing of it ever reached the disk — the send's clear behind
        // the same gate, and a snapshot at leaving the screen, which a second instance of the same
        // screen overwrote with the old text. One hand now: every change of the field, at once,
        // before any gate; editing a letter is not a draft. The send clears by emptying the field;
        // leaving the screen writes nothing — the disk already says what the field says.
        persistDraft(editingMessage == nil ? val : "")
        guard let peer = chat.convId, !peer.isEmpty, !chat.isGroup else { return }   // SILENT-OK: Saved Messages and a group have no pipe of their own; Saved Messages has no wire — the draft is on disk, nothing to stream
        // Live chat, in the Money Flow alone (03.10): coalesced full-state snapshots (max ~8/s) while the peer's chat is OPEN —
        // their presence beacon is the gate, not reachability. Reachability lied by omission:
        // it said «a road exists», while the receiver draws the draft only on an open chat.
        store.myTyping(chat.name, active: !val.trimmingCharacters(in: .whitespaces).isEmpty)
        // THE FIELD IS THE DRAFT — and this is the ONE road from the field to the wire. Every
        // change writes the box FIRST, before any branch decides anything, so the box is a reading
        // of the field and never a memory of it. A word is then taken FROM the box at the moment it
        // is spoken, so the wire cannot say what the field no longer holds: a word waiting its turn
        // when the letter leaves becomes the ending, not the words that already became the letter.
        draft.pending = val
        draft.caret = input.caret
        draft.replyMid = replyingTo?.msgId.flatMap { $0.hasPrefix("mid:") ? String($0.dropFirst(4)) : nil } ?? ""
        // An empty field is a word too, and it is said AT ONCE and through every gate: emptiness
        // carries no letter to leak, and it is the only word whose loss leaves a ghost. It passes
        // the live-typing gate on purpose — that gate is about streaming the person's letters, and
        // an ending has none; while it stood here, erasing the field by hand left the last frame
        // hanging on the peer's screen with nothing behind it.
        if val.isEmpty {
            draft.task?.cancel(); draft.task = nil
            E2E.shared.sendDraftClear(to: peer)
            return
        }
        // THE GATE OF THE LIVE WORD, NAMED WHEN IT CLOSES (22.09). The word goes only while the peer is
        // seen in the chat or seen typing; presence flaps by its own timer, and a closed gate looked
        // exactly like a broken feature -- nothing on their screen, nothing in the record. Folded, so a
        // minute of typing leaves one line and not two hundred.
        let peerNear = store.peerInChat(chat.name) || store.typingChats.contains(chat.name)
        if !ribbon || !peerNear {
            MontanaTrace.markFolded("draft_gate",
                "flow=\(ribbon ? "on" : "off") near=\(peerNear ? 1 : 0) to=\(String(peer.prefix(10)))",
                window: 30, key: peer)
        }
        if ribbon && peerNear {
            if draft.task == nil {
                let wait = max(0, 0.12 - Date().timeIntervalSince(draft.lastSent))
                let box = draft
                box.task = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    box.lastSent = Date(); box.task = nil
                    if box.pending.isEmpty { E2E.shared.sendDraftClear(to: peer) }
                    else { E2E.shared.sendDraft(to: peer, text: box.pending, caret: box.caret, replyMid: box.replyMid) }
                }
            }
            return
        }
        guard !val.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if Date().timeIntervalSince(lastTypingSent) > 3 {
            lastTypingSent = Date()
            // The word says when it was said (24.09): the lane keeps it a minute and hands it over when the chat opens,
            // and a «typing» a minute old is not typing now.
            let word = typingMark + E2E.saidTail()
            Task { _ = await E2E.shared.signalNow(to: peer, word) }   // lives an instant — no place in the queue
            MontanaWakePush.postChatSignal(peer, text: word)          // and the road that is always there
        }
    }

    func persistDraft(_ text: String) { ChatStore.setDraft(chat.name, text) }

    // The ONE scroll-to-bottom executor: every rule targets the same anchor through it.
    // Explicit human intents only (down button, send, search jump). In the inverted list the
    // visual bottom is the scroll's own top edge — hence anchor .top.
    func stickBottom(animated: Bool = true) {
        feedControl.scrollToBottom(animated: animated)
    }

    // backgrounding with the chat open: onDisappear won't fire — freeze the peer's bubble here
    func checkpointDraftIfBackground(_ ph: ScenePhase) {
        guard ph == .background, chat.convId != nil, !chat.isGroup else { return }   // a group streams no draft: it has no pipe of its own
        let d = newMessage.trimmingCharacters(in: .whitespaces)
        let saved = (d.isEmpty || editingMessage != nil) ? "" : newMessage
        E2E.shared.sendDraftCheckpoint(to: chat.convId ?? "", text: saved, caret: input.caret)
    }

    func sendMessage() {
        let text = newMessage.trimmingCharacters(in: .whitespaces)
        if !pastedImages.isEmpty {
            // Pictures wait above the field: the arrow sends them, the words as their caption.
            newMessage = ""
            persistDraft("")
            if chat.convId != nil { ChatStore.setCkptSent(chat.convId ?? "", "") }
            stickBottom()
            sendPasted(caption: text)
            return
        }
        guard !text.isEmpty else { return }
        // THE FIELD IS EMPTIED FIRST, and emptying the field is what ends the draft — the same one
        // road a person's backspace takes (handleDraftChange). Nothing here speaks to the peer about
        // drafts: a second voice for one event is exactly how the wire came to say what the field
        // did not — the send said «the draft is over» while a word of the old text was still on its
        // way, and the peer's screen kept a frame the field no longer held.
        newMessage = ""
        persistDraft("")   // the field emptied — the disk says so at once, Saved Messages included
        if chat.convId != nil {
            ChatStore.setCkptSent(chat.convId ?? "", "")       // durable state: superseded by the real message
        }
        stickBottom()   // sending is an explicit intent to be at the bottom, wherever you were
        // edit mode: change the text of an existing message
        if let editing = editingMessage {
            store.editMessage(chat.name, id: editing.id, newText: text)
            editingMessage = nil
            return
        }
        // THE LETTER TAKES THE CARD THE PERSON SAW (the critic 22.09): the plate above the field held
        // it, the cross could drop it — the send attaches exactly that and never reads the page again.
        let composer = MTLinkPreviewBuilder.Compose.shared
        let seen = composer.attachable
        let refused = composer.url.isEmpty && !MTLinkPreviewBuilder.webURLs(in: text).isEmpty
        composer.sent()
        _ = store.send(text: text, chat: chat.name, convRef: chat.convId ?? "",
                              replyText: replyingTo.map { ChatStore.listPreview($0) }, replyToId: replyingTo?.id,
                              replyWireMid: replyingTo?.msgId.flatMap { $0.hasPrefix("mid:") ? String($0.dropFirst(4)) : nil },
                              linkCard: seen, noLinkCard: refused)
        replyingTo = nil
    }

    // fetch the chat messages from the server (history + new ones)
    @MainActor
    func refreshFromServer() async {
        guard chat.convId != nil else { return }
        // The conversation's history already lies on the device: the channel serves that same history, not something from outside.
        _ = try? await store.channel.fetchMessages(chatId: chat.convId ?? "")
    }
}

// ════════════════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════
// FORWARDPICKERVIEW — pick the chat to forward the message to
// ════════════════════════════════════════════════════════════
/// ONE FACE OF A ROW ABOUT A PERSON OR A ROOM ([C-1], the author's word 16.09): the avatar and the
/// title exactly as the chats tab draws them; every list of whom to write to — the forward
/// picker, the new call, the contacts tab — draws its rows through here and adds only its own
/// trailing glyph.
/// THE ONE FACE OF A CHAT ([C-1], the author's word 18.09: Saved Messages wears one's own face in the
/// chat too, not only in the list). Every place that draws a chat's avatar — the list row, the chat's
/// header, the rows of the calls and contacts pages, the pickers — draws it here: a correspondent's
/// face, or one's own for the room without an address.
struct MTChatAvatar: View {
    @EnvironmentObject private var store: ChatStore
    let chat: Chat
    let size: CGFloat
    var showPresence = false
    var body: some View {
        let montana = ChatStore.isMontanaRoom(chat.name)
        let saved = ChatStore.isLocalRoom(chat.name) && !montana
        MTChatFace(face: saved ? nil : (montana ? montanaRoomFace : store.avatarFor(chat)), color: chat.color, initial: store.initial(for: chat), local: saved, size: size)
            .modifier(MTPresenceBadge(active: showPresence && !saved && !chat.isGroup && (store.presenceWord(chat.convRef)?.tier ?? 0) > 0))
    }
}

struct MTPresenceDot: View {
    var body: some View { Circle().fill(Color.green).frame(width: 9, height: 9) }
}

struct MTPresenceBadge: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        // At the face's lower right, where the platform puts a presence (the author's word 30.09), not under its middle.
        content.overlay(alignment: .bottomTrailing) {
            if active {
                MTPresenceDot().padding(2)
                    .background(.regularMaterial, in: Circle())
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
/// THE ONE FACE OF A CHAT, AS VALUES ([C-1], 23.09): MTChatAvatar asks the store for them and draws this, and the chat
/// list's row — which draws values only (ChatRowModel) — hands them in. Saved Messages wears one's own face (11.09).
struct MTChatFace: View {
    let face: String?
    let color: Color
    let initial: String
    let local: Bool
    let size: CGFloat
    var body: some View {
        // The local room IS one's own face (MTSelfFace), which watches the bytes itself: handed the same values here
        // before and after a change of face, this view is never asked again, and a picture read in its body stood still.
        if local {
            MTSelfFace(size: size, initial: initial)
        } else {
            AvatarCircle(photoURL: face, color: color, initial: initial, size: size, timeMarkWhenMissing: true)
        }
    }
}
struct MontanaChatFace: View {
    @EnvironmentObject private var store: ChatStore
    let chat: Chat
    var size: CGFloat = 40
    /// The list's own dress (the calls page, the contacts page): the face in its hexagon rim, the
    /// name at the list's 17 semibold.
    var rim = false
    var body: some View {
        HStack(spacing: 12) {
            MTChatAvatar(chat: chat, size: size)
                .overlay { if rim { MontanaHexagon().stroke(Color.white.opacity(0.45), lineWidth: 1) } }
            Text(MontanaAvatar.spokenName(store.title(for: chat)))
                .font(rim ? .system(size: 17, weight: .semibold) : .body)
                .foregroundColor(.white).lineLimit(1).truncationMode(.tail)
            if ChatStore.isMontanaRoom(chat.name) { MTMontanaCrownMark(height: rim ? 18 : 16) }
        }
    }
}

/// THE CROWN BESIDE THE NAME (the author's word 29.09): his own picture -- a pure golden volume like the knight of his
/// poster, no frame and no square -- drawn from the asset «MontanaCrown» byte for byte, and nothing at all until his
/// file lands there. No drawing of our own stands in for it.
struct MTMontanaCrownMark: View {
    let height: CGFloat
    var body: some View {
        if let ui = UIImage(named: "MontanaCrown") {
            Image(uiImage: ui).resizable().scaledToFit().frame(height: height).accessibilityHidden(true)
        }
    }
}

struct ForwardPickerView: View {
    let message: Message
    var onPick: (Chat) -> Void
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    /// The chats tab's list, one to one — Saved Messages, groups and pins included, in its order.
    var chats: [Chat] { store.listChats() }

    var body: some View {
        NavigationStack {
            List {
                ForEach(chats) { c in
                    Button { onPick(c); dismiss() } label: {
                        HStack(spacing: 12) {
                            MontanaChatFace(chat: c)
                            Spacer()
                            Image(systemName: "arrowshape.turn.up.right").foregroundColor(.gray)
                        }
                        .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                    }
                    .listRowBackground(MTGlassRowPlate())
                }
            }
            .scrollContentBackground(.hidden)
            .montanaPageGround()   // my page's ground, as every page wears it (26.09)
            .navigationTitle("Forward to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MontanaCloseMark { dismiss() }
                }
            }
        }
    }
}

/// THE ONE MEDIA ROAD OUT ([C-1], the author's word 16.09: the share sheet is a way of sending, not
/// a sender): a photo, a video, a voice, a document leave by this function alone — from the chat's
/// picker, the camera, the recorder, the forward, the paste, and from the share sheet's inbox. The
/// intent before compression, the poster with the letter, the compression with its ring, the
/// upload; a second road drifted by construction and died on its own upload.
@MainActor
struct MontanaMediaSender {
    let store: ChatStore
    func sendMediaOverE2E(fileName: String, kind: String, docName: String? = nil, caption: String = "",
                          peer: String, chatKey: String) {
        // Saved Messages is this device writing to itself: no wire, no receipt — the file is in
        // the store already; the row settles at once (15.48).
        if peer.isEmpty {
            store.setMediaStatus(chatKey, file: fileName, .sent)
            MontanaTrace.mark("saved_local", "kind=\(kind)")
            return
        }
        // THE LETTER NAME AND THE INTENT COME BEFORE COMPRESSION, NOT AFTER. Measured 20.08
        // 19:03: of 79 seconds of sending, 75 are transcoding, and all that time the work was
        // protected by NOTHING — an app dying mid-compression left no trace that a send ever
        // existed. An intent that starts after compression closed the hole one step later
        // than it opened.
        let letterMid = store.letterMidFor(chatKey, file: fileName)
        // A group's media has no piece in the pipes' queue: the group's carrier takes its manifest (MTGroup.carryMedia).
        if !MTGroup.isKey(chatKey) {
            MontanaDeliveryEngine.shared.enqueue(
                to: peer, chat: chatKey, mid: letterMid,
                text: "{\"k\":\"\(kind)\",\"e\":\"\(fileName)\"}",
                silent: false, kind: .piece)
        }
        if kind == "vid" {
            guard MTEncodeRegistry.shared.begin(file: fileName, letter: letterMid) else {
                MontanaTrace.mark("send_dup", "file \(fileName.prefix(24)) already encoding — joined the living job")
                return
            }
            store.setUploadProgress(fileName, 0.01)   // ring visible immediately, from the first compression frame
            store.setUploadStatus(fileName, String(localized: "In queue"))
            // The poster is born WITH the letter, while the decoder is still free. An
            // opportunistic poster (written only when a thumbnail happened to succeed)
            // left nothing on disk when the cache purged mid-encode — the bubble turned
            // black and square after backgrounding (precedent 23.08 00:33).
            let posterPath = posterURL(fileName)
            if !FileManager.default.fileExists(atPath: posterPath.path) {
                let srcForPoster = attachmentURL(fileName)
                Task.detached(priority: .userInitiated) {
                    // The SAME recipe the manifest carries (320 px / 12 KB): one set of
                    // bytes lives through compressing, sending and receiving ([C-1]).
                    guard let img = videoPosterImage(srcForPoster),
                          let d = img.mediaThumbnail(maxDim: 320, maxBytes: 12_000) else { return }
                    try? d.write(to: posterPath)
                    if let small = UIImage(data: d) {
                        videoThumbCache.setObject(small, forKey: fileName as NSString)
                    }
                }
            }
            MontanaTelemetry.shared.event("compress START \(fileName)")
            let compressT0 = Date()
            // A file already compressed by our encoder is NOT transcoded again: on a long
            // video that is 4-5 minutes of wasted work on every resend.
            if MontanaVideoMark.isCompressed(fileName) {
                MTEncodeRegistry.shared.end(file: fileName)
                store.setUploadStatus(fileName, nil)
                store.setUploadProgress(fileName, 0.01)
                // The bytes name the extension: a transcoded file wears its birth name (.MOV) over mp4 bytes
                // and travels as mp4; a round note is born _mtc.mov and travels as .mov.
                let ext = MontanaVideoMark.marked(fileName) ? "mp4"
                    : ((fileName as NSString).pathExtension.isEmpty ? "mp4" : (fileName as NSString).pathExtension)
                store.sendMediaToPeer(peer: peer, source: .file(attachmentURL(fileName)), kind: "vid", ext: ext,
                                      progressKey: fileName, caption: caption,
                                      statusChat: chatKey, statusFile: fileName, forceMid: letterMid)
                return
            }
            let outer = Task {
                let hold = MTSendAssertion("media-compress")
                hold.onExpire = { MTCompressResume.shared.flag(letterMid) }
                defer { hold.end(); MTEncodeRegistry.shared.end(file: fileName) }
                let src = attachmentURL(fileName)
                // Compression with progress into the shared bar (0…0.3); a stuck export does not block sending — timeout.
                // The time watchdog arms only when compression has actually started —
                // waiting in the queue does not count toward it.
                let startedAt = MTBox<Date?>(nil)
                // The encoder reports progress PER FRAME — hundreds of main-actor tasks a
                // second starved the main thread, and a chat could not even open while a long
                // video was encoding (precedent 23.08). One update per whole percent is plenty.
                let lastPct = MTBox<Int>(-1)
                // The segment work dir is keyed by the FILE: the letter dies and re-mints
                // on a red retry, and keying by it threw finished segments away on every
                // retry (trace 23.08: durations 115s/295s/115s/323s, never shrinking).
                let segDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mt-seg-\(fileName)")
                let compressed = await withTaskGroup(of: URL?.self) { g -> URL? in
                    g.addTask {
                        await MontanaVideo.compressResumable(src, workDir: segDir, progress: { p in
                            let pct = Int(p * 100)
                            guard pct != lastPct.value else { return }   // SILENT-OK: progress coalescing, not a delivery path
                            lastPct.value = pct
                            Task { @MainActor in
                                store.setUploadProgress(fileName, 0.01 + p * 0.29)
                                store.setUploadStatus(fileName, "Compressing \(pct)%")
                            }
                        }, onStart: {
                            startedAt.value = Date()
                            Task { @MainActor in store.setUploadStatus(fileName, String(localized: "Compressing")) }
                        })
                    }
                    // A watchdog for a hung encoder — but not a hard 90s: a long video
                    // transcodes longer, and the old ceiling cut compression short, after
                    // which the raw file went to the network (measured: 305 MB, the send
                    // died). Counted from duration: 30s base + 4x duration, minimum 5 minutes.
                    let durSec = CMTimeGetSeconds(AVURLAsset(url: src).duration)
                    let capSec = max(300.0, 30.0 + (durSec.isFinite ? durSec : 0) * 4)
                    g.addTask {
                        // The limit counts from the moment work actually starts (queue waiting is
                        // free) and counts ACTIVE seconds only: frozen background time is a pause
                        // of the encoder, not its work — the export continues from the same frame
                        // on thaw instead of being killed and restarted from zero.
                        while startedAt.value == nil {
                            if Task.isCancelled { return nil }
                            try? await Task.sleep(nanoseconds: 300_000_000)
                        }
                        var worked = 0.0
                        while worked < capSec {
                            if Task.isCancelled { return nil }
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            if MTForeground.active { worked += 1 }
                        }
                        return nil
                    }
                    let first = await g.next() ?? nil
                    g.cancelAll()
                    return first
                }
                MontanaTelemetry.shared.event("compress END compressed=\(compressed != nil) ms=\(Int(Date().timeIntervalSince(compressT0)*1000))")
                // Stage 8.4: the window expired while encoding — the work resumes on the next
                // foreground moment under the SAME letter (the intent is on disk; the compressed
                // cache skips finished work). Neither red nor an uncompressed source.
                if compressed == nil, !Task.isCancelled, MTCompressResume.shared.isFlagged(letterMid) {
                    await MainActor.run { store.setUploadStatus(fileName, String(localized: "In queue")) }
                    // The seat is freed BEFORE the re-run is queued: runAll fires within a
                    // fraction of a second of registration, and a still-occupied seat would
                    // swallow the resume as a duplicate.
                    MTEncodeRegistry.shared.end(file: fileName)
                    MTCompressResume.shared.register(letterMid) {
                        self.sendMediaOverE2E(fileName: fileName, kind: kind, docName: docName, caption: caption,
                                              peer: peer, chatKey: chatKey)
                    }
                    return
                }
                if Task.isCancelled {
                    // Delete ONLY the transcode's temporary result. When compression is
                    // skipped (the video already fits the target), the original itself is
                    // returned — deleting it would lose the user's footage.
                    if let c = compressed, c != src { try? FileManager.default.removeItem(at: c) }
                    MontanaDeliveryEngine.shared.dropPiece(letterMid)   // manual cancel: the status is already red
                    return
                }
                // THE NAME GIVEN AT BIRTH NEVER CHANGES (the critic 22.09). The transcoded bytes become the
                // letter's file UNDER THE SAME NAME: the row, the ring, the status word, the poster, the
                // frame cache, the seat and the registry are keyed by it, and none of them moves. The old
                // road renamed (.mov becoming _mtc.mp4) and carried every mirror across in «the one rename
                // point» -- a point that had to know every mirror, and bit three times (20.08, 29.08, 22.09).
                // The file MOVES into the store -- not copied: a copy of three hundred megabytes meant three
                // instances on disk at once; the store replaces the raw source in one action or not at all.
                let storeURL = MontanaMediaStore.url(fileName)
                var sendExt = (fileName as NSString).pathExtension.isEmpty ? "mov" : (fileName as NSString).pathExtension
                if let compressed, compressed != src {
                    guard MontanaMediaStore.adopt(from: compressed, name: fileName) else {
                        NSLog("[MEDIA] vid not adopted \(fileName)")
                        await MainActor.run {
                            store.setUploadProgress(fileName, nil)
                            store.setMediaRefused(chatKey, file: fileName, because: .fileUnreadable)
                        }
                        MontanaDeliveryEngine.shared.dropPiece(letterMid)   // the failure is shown red
                        return
                    }
                    if src != storeURL { try? FileManager.default.removeItem(at: src) }   // the raw source leaves the temporary folder
                    MontanaVideoMark.mark(fileName)   // a resend never transcodes again
                    sendExt = "mp4"   // the receiver names its file by the bytes it gets
                } else {
                    // The encoder returned the source itself (it already fits) or gave up: the source is
                    // the letter's file, moved into the store if it still stands in the temporary folder.
                    if src != storeURL, !MontanaMediaStore.adopt(from: src, name: fileName) {
                        NSLog("[MEDIA] vid not adopted \(fileName)")
                        await MainActor.run {
                            store.setUploadProgress(fileName, nil)
                            store.setMediaRefused(chatKey, file: fileName, because: .fileUnreadable)
                        }
                        MontanaDeliveryEngine.shared.dropPiece(letterMid)
                        return
                    }
                    if compressed != nil { MontanaVideoMark.mark(fileName) }
                }
                await MainActor.run { store.setUploadProgress(fileName, 0.3) }   // the upload phase begins at the bar's 30%
                store.sendMediaToPeer(peer: peer, source: .file(storeURL), kind: "vid", ext: sendExt,
                                      progressKey: fileName, caption: caption, statusChat: chatKey, statusFile: fileName,
                                      progressBase: 0.3, progressSpan: 0.7, forceMid: letterMid)
            }
            // THE ENCODE HAS ONE HOLDER — THE ENCODE REGISTRY, NEVER THE UPLOAD TABLE (the critic 22.09).
            // The transcode used to sit in uploadTasks too, so the cancel button could reach it; the
            // one rename point then carried that living task under the compressed name, and the
            // refusal of a living upload (sendMediaToPeer) met ITSELF there: every gallery video on
            // 1833–1860 ended in «send_dup … is uploading» two milliseconds after «compress END»,
            // with no media START ever (iPhone 15 Pro Max 12:14 and 12:16, iPhone 14 Plus 11:45).
            // And the seat was released under the OLD name only, so the drain and the sweep read a
            // living send for the rest of the process: an eternal ring at 30 %, never red, never
            // resumed. The registry already holds the task and cancels it by the letter
            // (cancel(letter:) — dropPiece, deleteEverywhere, cancelUpload); uploadTasks holds
            // uploads alone, and the refusal above is true by construction.
            MTEncodeRegistry.shared.adopt(file: fileName, task: outer)
            return
        }
        let srcURL = attachmentURL(fileName)
        guard let data = try? Data(contentsOf: srcURL, options: .mappedIfSafe) else {
            NSLog("[MEDIA] send: file not read \(fileName)")
            store.setMediaRefused(chatKey, file: fileName, because: .fileUnreadable)
            return
        }
        if !MontanaMediaStore.exists(fileName) { MontanaMediaStore.put(fileName, data: data) }   // one finished copy
        let ext = (fileName as NSString).pathExtension
        // A picture needs its thumbnail — it is already in memory; a document of arbitrary size is
        // served as a file so it does not rise into memory whole.
        let mediaSrc: MediaSource = (kind == "img") ? .memory(data) : .file(srcURL)
        store.sendMediaToPeer(peer: peer, source: mediaSrc, kind: kind, ext: ext,
                              docName: docName, progressKey: fileName, caption: caption,
                              statusChat: chatKey, statusFile: fileName, forceMid: letterMid)
    }

}

/// THE BAR'S RIGHT MARKS' ONE ROUND (the author's word 02.10 18:27): the turn, the chess and the handset each a glyph on one
/// circle of glass, the platform's own regular glass where it has it (MTGlassCirclePlate), 44 points -- the bar's own item
/// height -- and the platform's blue ring (MTMiniFace.playingRing) drawn inside that same circle (strokeBorder), so the ring and
/// the plate are one circle by construction. Before the newest system the mark's plate with its rim (montanaOctagonFace mark:)
/// is a circle of the field's tier inside the 44-point target, and the ring stands on that circle, not on the target.
/// The chat's own top bar (chatTop beside the content, 8 from each edge): the platform's bar beside a view on the newest system,
/// with the scroll's edge effect under it; the safe area's inset before it. Nothing while the chat keeps the system's bar.
struct MTChatTopBar<Row: View>: ViewModifier {
    let shown: Bool
    @ViewBuilder let row: () -> Row
    func body(content: Content) -> some View {
        if !shown {
            content
        } else if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .top, spacing: 0) { bar }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) { bar }
        }
    }
    private var bar: some View { row().padding(.horizontal, 8).padding(.vertical, 4) }
}

struct MTBarRoundMark<Glyph: View>: View {
    let ringed: Bool
    /// The round's side: the bar's 44, less where the chat's top has no room for it (chatTop); the target stays 44 all the same.
    var side: CGFloat = 44
    @ViewBuilder let glyph: () -> Glyph
    /// The platform's shared plate of the bar item stays hidden where the mark wears its own glass.
    static var shared: Visibility { MontanaSkin.isNative ? .hidden : .automatic }
    var body: some View {
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            glyph()
                .frame(width: side, height: side)
                .background(MTGlassCirclePlate())
                .overlay { if ringed { Circle().strokeBorder(MTMiniFace.playingRing, lineWidth: 1.5) } }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        } else {
            let h = min(MontanaOctagon.composeHeight, side)
            glyph()
                .montanaOctagonFace(square: true, bar: true, height: h, mark: true)
                .frame(width: 44, height: 44)
                .overlay { if ringed { Circle().strokeBorder(MTMiniFace.playingRing, lineWidth: 1.5).frame(width: h, height: h) } }
                .contentShape(Rectangle())
        }
    }
}
