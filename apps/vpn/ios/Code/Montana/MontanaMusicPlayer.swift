import SwiftUI
import Combine
import AVFoundation
import AVKit
import MediaPlayer
import UIKit
import WebKit
import UniformTypeIdentifiers
import ImageIO
import CryptoKit
import Security

// ════════════════════════════════════════════════════════════
// MUSIC PLAYER — the page that opens when a music file starts playing. THE LOCK SCREEN'S (the
// author's word 29.09): over the person's page ground, the player's one glass plate at the foot of
// the screen, and, pulled up, the queue that plays as the notifications' plates.
// ════════════════════════════════════════════════════════════

struct MusicTrack: Equatable {
    let file: String      // the name on disk
    let title: String     // the document's name as it was sent
    let msgId: MID
    let chat: String      // the chat the track was sent in
    let chatTitle: String // the chat's name as the person sees it
    var at: Double = 0    // when the track appeared (the letter's birth) — the playlist's order
    /// A TRACK NOT YET WHOLE (25.09): its pieces, for the streaming player, and what to do once the file is whole (nil —
    /// the file lies here). Two tracks are the same track by everything but these.
    var stream: MTStreamSource? = nil
    var whole: (() -> Void)? = nil
    /// A TRACK OF A POST (the feed's or a wall's, MTBoardPlaylist): it lies in a post, not in a letter -- no message to go to.
    /// WHERE A TRACK LIES IS NEVER SAID (the author's word 29.09 ~23:20: «take the addresses out of the tracks everywhere, and in
    /// the tracks' feed too»): the line under a track's name is the artist its own tags name (MTTrackMeta.byline), or nothing --
    /// never its chat, its folder's path, the feed or a wall. Not a part of the track's sameness.
    var inPost = false
    /// A track as a row of the pages' list (MTChatListView), named by its file -- the music page's rows and the big player's alike.
    var listRow: Chat { Chat(name: file, lastMessage: "", time: "", unread: 0, status: "", convId: "track:" + file) }
    static func == (a: MusicTrack, b: MusicTrack) -> Bool {
        a.file == b.file && a.title == b.title && a.msgId == b.msgId && a.chat == b.chat && a.chatTitle == b.chatTitle && a.at == b.at
    }
}

/// Every music file in every chat, in feed order — the player's search space and the queue
/// a search pick plays through.
enum MontanaMusicLibrary {
    /// ONE TRACK ONCE, ONE KEY (the author's word 16.09): the name without its kind and the size on disk — the
    /// library's own sameness, for the letters' tracks and the lent folders' alike (MTMusicFolders).
    static func key(_ title: String, size: Int) -> String {
        (title as NSString).deletingPathExtension.lowercased() + "#" + String(size)
    }
    /// A STORED FILE'S SIZE IS ASKED OF THE DISK ONCE (the critic 24.09): a file never changes under its name, so its
    /// size is kept by the name; the library is built again at every change of the letters, and each build asked the
    /// disk for every track's size.
    private static var sizes: [String: Int] = [:]
    private static let sizesLock = NSLock()
    static func size(_ file: String) -> Int {
        if let lent = MTMusicFolders.size(file) { return lent }   // a lent folder's track: the walk's own word, no disk asked
        sizesLock.lock(); let kept = sizes[file]; sizesLock.unlock()
        if let kept { return kept }
        let s = ((try? FileManager.default.attributesOfItem(atPath: attachmentURL(file).path))?[.size] as? Int) ?? 0
        if 0 < s { sizesLock.lock(); sizes[file] = s; sizesLock.unlock() }
        return s
    }
    static func build(messages: [String: [Message]], lent: [MusicTrack], nameOf: (String) -> String) -> [MusicTrack] {
        let t0 = ProcessInfo.processInfo.systemUptime
        var out: [MusicTrack] = []
        for (chat, msgs) in messages.sorted(by: { $0.key < $1.key }) {
            let title = nameOf(chat)
            for m in msgs {
                guard let d = m.docFile, mtIsAudioName(m.docName ?? "") || mtIsAudioName(d), fileOnDisk(d) else { continue }
                out.append(MusicTrack(file: d, title: m.docName ?? d, msgId: m.id, chat: chat, chatTitle: title, at: m.createdAt))
            }
        }
        // In order of appearance across every chat (the author's word 10.09). THE LENT FOLDERS' TRACKS (MTMusicFolders,
        // the author's word 24.09) stand at the moment their folder was lent, in the folder's own order, and are merged
        // into the letters' order by that moment — a letter first on a tie.
        let letters = out.sorted { $0.at < $1.at }
        var merged: [MusicTrack] = []
        merged.reserveCapacity(letters.count + lent.count)
        var i = 0, j = 0
        while i < letters.count || j < lent.count {
            if j == lent.count || (i < letters.count && letters[i].at <= lent[j].at) { merged.append(letters[i]); i += 1 }
            else { merged.append(lent[j]); j += 1 }
        }
        // ONE TRACK ONCE (the author's word 16.09): the same song sent to two chats, or twice to one, or lying in a lent
        // folder as well, is one row and one place in the queue — the same name and the same bytes; the first stays.
        // ONE FILE, ONE ROW (the critic 24.09): the rows are named by the file, and a name twice would break the list's
        // snapshot — the file is asked before the sameness.
        var seen = Set<String>(), files = Set<String>()
        let list = merged.filter { t in files.insert(t.file).inserted && seen.insert(key(t.title, size: size(t.file))).inserted }
        // The build is measured (the critic 24.09): it runs at every change of the letters that a reader follows.
        MontanaP2PTrace.markFolded("music_build", "n=\(list.count) of \(out.count + lent.count) lent=\(lent.count) ms=\(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000))", window: 60)
        return list
    }
}

struct MusicOpen: Identifiable { let file: String; var id: String { file } }

enum MTMusic {
    static let orange = Color(red: 0.96, green: 0.62, blue: 0.36)
    static let orangeUI = UIColor(red: 0.96, green: 0.62, blue: 0.36, alpha: 1)
    static let panel = Color(white: 0.07)
    static let text = Color(white: 0.58)
    static let dim = Color(white: 0.45)
    static let trackUI = UIColor(white: 0.22, alpha: 1)

    static func thumb(diameter: CGFloat, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter)).image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }
    }

    // A 1×3 stretchable line: the volume view's own slider takes its track from an image.
    static func line(_ color: UIColor) -> UIImage {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        return img.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1))
    }
}

/// ONE SCRUBBER FOR THE WHOLE APP (the author's word 18.09: strictly UIKit, one working slider,
/// and everything else refers to it). The platform's own UISlider: while the finger tracks, the
/// value is the finger's; the finger's lift — touchUpInside, touchUpOutside, touchCancel, UIKit's
/// own events, never a SwiftUI editing signal that sometimes never comes — asks the player ONCE.
/// THE ASKED PLACE HOLDS FOR A QUARTER OF A SECOND, THEN THE CLOCK LEADS (the author's word 18.09:
/// the thumb jumped after a seek; then the bar's thumb froze and jumped on a note while a track was
/// fine). A seek lands within that time on every player, and a clock that reports its old second
/// once right after a seek reports it inside that time too — so the thumb and the label beside keep
/// the sought value for the quarter second and follow the clock from there, a smooth continuation.
/// No tolerance rule: a tolerance in shares of the length fits a three-minute track and misses a
/// ten-second note, whose clock is past two percent before the rule looks. The players publish
/// nothing optimistic: the truth is their clock, the hold is the scrubber's.
/// A BARE scrubber (the bubble's wave): the same control with no track and no thumb of its own —
/// the wave behind it is the picture, the touch anywhere along it takes the thumb (UIControl's own
/// tracking override), and the drag is UISlider's.
struct MontanaScrubber: UIViewRepresentable {
    var live: Double                       // the player's position, 0…1
    var bare = false
    /// THE PLATE IS GRABBED (the author's word 21.09): no track, no thumb of its own, the thumb — a 44-pt clear target —
    /// stands exactly at the fill's edge. SINCE 29.09 the finger takes the music anywhere on the plate (the author's word:
    /// «native seeking by swipes right and left on the name's plate») and drags the fill's edge along by its own travel; a
    /// lift without a swipe is a tap (onTap).
    var grab = false
    /// Names the frame meter's line for a drag (motion what=scrub:NAME); nil measures nothing.
    var meter: String? = nil
    var onSeek: (Double) -> Void
    var onHold: (Double?) -> Void = { _ in }   // the held or sought value for the labels beside; nil = free
    var onTap: () -> Void = {}
    /// A tap with its place: x in points and the control's width — the host tells the slot's room from the name's.
    var onTapAt: ((CGFloat, CGFloat) -> Void)? = nil
    /// THE HOLD COPIES THE NAME (the author's word 29.09 ~23:10: «the track's name copied in the mini player at once»): a long
    /// press ON THE CONTROL ITSELF, at the chat's own threshold (montanaLongPress, the bubble's hold) -- the platform's recogniser on
    /// the platform view (a gesture of the drawn tree hung on it is never asked on iOS 17, the touch law of 29.09): it survives every
    /// redraw of the plate by the player's clock, and the control's tracking yields to it as it yields to any long press of the
    /// system. The share is the big player's menu (MontanaPlayerBar.share).
    var onLongPress: (() -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MontanaSliderView {
        let s = MontanaSliderView()
        s.tapAnywhere = bare
        s.grab = grab
        let c = context.coordinator
        s.onTap = { c.parent.onTap() }
        s.onTapAt = { x, w in c.parent.onTapAt?(x, w) }
        if onLongPress != nil {
            let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.held(_:)))
            hold.minimumPressDuration = montanaLongPress
            s.addGestureRecognizer(hold)
        }
        s.setContentHuggingPriority(.defaultLow, for: .horizontal)
        s.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        s.addTarget(context.coordinator, action: #selector(Coordinator.began(_:)), for: .touchDown)
        s.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        for ev: UIControl.Event in [.touchUpInside, .touchUpOutside] {
            s.addTarget(context.coordinator, action: #selector(Coordinator.lifted(_:)), for: ev)
        }
        s.addTarget(context.coordinator, action: #selector(Coordinator.cancelled(_:)), for: .touchCancel)
        s.setValue(Float(max(0, min(1, live))), animated: false)
        return s
    }
    func updateUIView(_ s: MontanaSliderView, context: Context) {
        context.coordinator.parent = self
        guard !s.isTracking else { return }
        let c = context.coordinator
        let held = c.sought != nil
        guard c.release(live: live) else { return }
        if held { DispatchQueue.main.async { c.parent.onHold(nil) } }   // the labels go free with the thumb
        s.setValue(Float(max(0, min(1, live))), animated: false)
    }
    final class Coordinator: NSObject {
        var parent: MontanaScrubber
        var sought: Double? = nil
        var liftedAt = Date.distantPast
        init(_ p: MontanaScrubber) { parent = p }
        @objc func began(_ s: MontanaSliderView) { parent.onHold(Double(s.value)) }
        /// A tap is no drag: the meter starts on the first move.
        private var metering = false
        private func meterEnds() {
            guard metering, let m = parent.meter else { return }
            metering = false
            MTFrameMeter.shared.moveEnded("scrub:" + m)
        }
        @objc func changed(_ s: MontanaSliderView) {
            guard s.isTracking else { return }
            if !metering, parent.meter != nil { metering = true; MTFrameMeter.shared.moveBegan() }
            parent.onHold(Double(s.value))
        }
        @objc func lifted(_ s: MontanaSliderView) {
            meterEnds()
            // A FINGER THAT NEVER MOVED ASKS FOR NO SEEK (29.09): the plate takes every touch now, so a tap is a touch too --
            // the player is not stopped and started on the very second it plays; the labels go free with the thumb.
            if s.grab, !s.moved { sought = nil; parent.onHold(nil); return }
            let v = Double(s.value)
            sought = v; liftedAt = Date()
            parent.onHold(v)
            parent.onSeek(v)
        }
        /// THE HOLD ON THE CONTROL (onLongPress): once, the moment the platform recognises it.
        @objc func held(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            MontanaP2PTrace.mark("music", "mini hold")
            parent.onLongPress?()
        }
        /// A cancelled touch is the system's, not the finger's lift: no seek, the thumb goes back to
        /// the clock. Named in the diary — a cancel that still happens has a gesture behind it to find.
        @objc func cancelled(_ s: MontanaSliderView) {
            meterEnds()
            sought = nil
            parent.onHold(nil)
            MontanaP2PTrace.mark("scrub", "cancelled at=\(Int(s.value * 100))%")
        }
        /// The hold ends a quarter of a second after the lift; the clock leads from there.
        func release(live: Double) -> Bool {
            guard sought != nil else { return true }
            if 0.25 < Date().timeIntervalSince(liftedAt) { sought = nil; return true }
            return false
        }
    }
}

/// THE ONE SCRUBBER'S UIKIT BODY: A CONTROL THAT DRAWS NOTHING (the author's word 04.10.2026 12:30 MSK, «by constitution 0»; T1
/// 04.10 09:08:08Z: at a cold start the main thread stood 4.0 s inside the first frame of the system slider -- UISlider's frame, UIKit,
/// QuartzCore -- and the app stood frozen). Every host draws its own fill and asks this view for the finger alone: the system slider
/// it was drew no track and no thumb on any of its four hosts, so a plain control takes the touch, holds a value from 0 to 1 and
/// sends the slider's own events -- touchDown, valueChanged, the two lifts, the cancel. The track is the whole width; with
/// tapAnywhere the value comes to the finger's first touch.
/// THE SLIDER OWNS ITS HORIZONTAL (the author's word 29.09 on 2000: «the seeking on the central plate must not fight the page's
/// swipe»): the tabs' pan (MTTabPan) gives way at the touch over it, as over the call pill -- a flat stroke on the live plate is
/// the plate's alone; a still row's plate takes no touch at all (the list's selection does), so the pages turn over it as before.
final class MontanaSliderView: UIControl, MTHorizontalOwning {
    private(set) var value: Float = 0
    func setValue(_ v: Float, animated: Bool) { value = max(0, min(1, v)) }
    var tapAnywhere = false
    /// THE GRAB DRESS (the author's word 21.09): the thumb's centre IS the fill's edge -- the track spans the whole width and the
    /// edge stands at width × value; the drag keeps the finger's offset from the edge (no jump under the finger). SINCE 29.09 the
    /// finger takes the music anywhere on the plate, not at the edge alone (the author's word: «native seeking by swipes»); a lift
    /// near where it landed is still a tap, given to the host (the page opens).
    var grab = false
    var onTap: () -> Void = {}
    var onTapAt: (CGFloat, CGFloat) -> Void = { _, _ in }
    private var grabDX: CGFloat = 0
    private var landed: CGPoint? = nil
    private var landedAt: TimeInterval = 0
    /// THE PLATE IS TAKEN ANYWHERE (the author's word 29.09): a swipe moves the fill's edge by the finger's own travel -- no jump to
    /// the finger, the edge keeps its distance from it (grabDX). The first eight points are a tap's room: the fill stands still
    /// through them, and a lift inside them is the tap it always was. `moved` says the finger left that room -- the lift then
    /// seeks, otherwise it does not (Coordinator.lifted).
    private(set) var moved = false
    private static let slop: CGFloat = 8
    /// The fill's edge: where the value stands along the whole width.
    private var edge: CGFloat { bounds.width * CGFloat(value) }
    private func value(at x: CGFloat) -> Float { 1 < bounds.width ? Float(max(0, min(1, x / bounds.width))) : value }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }
    required init?(coder: NSCoder) { nil }
    /// THE PLATFORM'S ADJUSTABLE, AS THE SYSTEM SLIDER GAVE IT: VoiceOver moves the value by a twentieth and seeks there.
    override var accessibilityValue: String? {
        get { Double(value).formatted(.percent.precision(.fractionLength(0)).locale(MTLanguage.locale)) }
        set { }
    }
    override func accessibilityIncrement() { stepped(0.05) }
    override func accessibilityDecrement() { stepped(-0.05) }
    private func stepped(_ d: Float) {
        value = max(0, min(1, value + d))
        moved = true
        sendActions(for: [.valueChanged, .touchUpInside])
    }

    /// THE FINGER ON THE THUMB IS THE SLIDER'S ALONE (the author's word 18.09: the thumb jumped in the bar while a note played,
    /// and never on the music page — the same scrubber, a different host). The chat around the bar carries gestures of its own —
    /// the edge drag that closes it, the tap on the bar; a gesture that began mid-drag cancelled the touch, the cancel counted as
    /// a lift, and the thumb was set from the clock. Here every outer gesture is refused while the control tracks — as the
    /// platform's own playback and volume sliders do — on every host alike.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        // The control's own recognisers -- the hold that copies the name (29.09) -- begin over its tracking: the platform cancels the
        // touch for them, as it does under any of its own buttons; every outer recogniser still waits for the lift.
        if g.view === self { return true }
        return isTracking ? false : super.gestureRecognizerShouldBegin(g)
    }
    /// A cancel names its cause in the diary (the author's word 18.09: 1684 showed the cancels, not who sent them): every
    /// recogniser that holds the touch, with its state and its view, and whether the control still stands in a window.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let who = touches.first.map { t -> String in
            (t.gestureRecognizers ?? []).filter { $0.state != .possible && $0.state != .failed }
                .map { "\(type(of: $0)):\($0.state.rawValue)@\($0.view.map { String(describing: type(of: $0)) } ?? "-")" }
                .joined(separator: " ")
        } ?? "?"
        MontanaP2PTrace.mark("scrub", "cancel-by \(who.isEmpty ? "none" : who) window=\(window == nil ? 0 : 1) tracking=\(isTracking ? 1 : 0)")
        super.touchesCancelled(touches, with: event)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if grab, let t = touches.first { landed = t.location(in: self); landedAt = t.timestamp; moved = false }
        super.touchesBegan(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let tracked = isTracking
        super.touchesEnded(touches, with: event)
        guard grab, let t = touches.first, let l = landed else { return }
        landed = nil
        let p = t.location(in: self)
        let still = abs(p.x - l.x) <= Self.slop && abs(p.y - l.y) <= Self.slop && t.timestamp - landedAt < 0.5
        if still {
            MontanaP2PTrace.mark("music", "mini tap on=\(tracked ? "edge" : "plate") x=\(Int(p.x)) w=\(Int(bounds.width))")
            onTap()
            onTapAt(p.x, bounds.width)
        }
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let x = touch.location(in: self).x
        // Anywhere on the plate (29.09): the touch is held from its first point; the fill's edge keeps its distance from the
        // finger (taken again when the swipe leaves the tap's room, continueTracking), so nothing jumps under it.
        if grab { grabDX = x - edge } else if tapAnywhere { value = value(at: x) }
        keepTouch(touch)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard 1 < bounds.width else { return true }
        let at = touch.location(in: self)
        if grab, !moved {
            // Inside the tap's room the fill stands; leaving it, the edge starts from where it stands -- its distance from the
            // finger is taken here, so the first point of the swipe moves the fill by one point, never by eight.
            guard let l = landed, Self.slop < abs(at.x - l.x) else { return true }
            moved = true
            grabDX = at.x - edge
            MontanaP2PTrace.mark("music", "mini swipe from=\(Int(value * 100))% x=\(Int(at.x)) w=\(Int(bounds.width))")
        }
        let v = value(at: grab ? at.x - grabDX : at.x)
        if v != value { value = v; sendActions(for: .valueChanged) }
        return true
    }
    /// THE TOUCH IS NOT CANCELLED FROM ABOVE (the diary of 1685 named the sender: the window's own
    /// _UIFlexInteractionPanGestureRecognizer of iOS 26, begun mid-drag over a playing note and never
    /// over a track — a window-level recogniser that gestureRecognizerShouldBegin never reaches). For
    /// the length of its own touch the control asks every recogniser of the chain that holds the touch
    /// not to cancel it — the platform's own rule for a control inside a scroll view (touchesShouldCancel),
    /// applied by the control to its own touch — and gives them their word back at the lift.
    private var kept: [(UIGestureRecognizer, Bool)] = []
    private func keepTouch(_ touch: UITouch) {
        kept = (touch.gestureRecognizers ?? []).filter { $0.view !== self }.map { ($0, $0.cancelsTouchesInView) }
        kept.forEach { $0.0.cancelsTouchesInView = false }
    }
    private func giveBack() {
        kept.forEach { $0.0.cancelsTouchesInView = $0.1 }
        kept = []
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        giveBack()
        super.endTracking(touch, with: event)
    }
    override func cancelTracking(with event: UIEvent?) {
        giveBack()
        super.cancelTracking(with: event)
    }
}

struct WebQuery: Identifiable { let q: String; var id: String { q } }

/// WHERE A TRACK CAME FROM, THE PLAYLIST'S ONE CHOICE (the author's word 30.09 ~00:55: «to the right of the search in the big music
/// player put the native filter, so that one can choose where one listens from -- a chat, a wall, a folder and so on»): the places the
/// line under a track's name no longer says (29.09 ~23:20) live here -- a letter's chat, a post of the feed or a wall, a folder lent
/// from the phone. One owner of the choice: which tracks the playlist shows, and which it plays through.
enum MTTrackSource: Hashable {
    case all, chats, walls, folders
    case chat(String)   // one chat, by its conversation's name
    static func of(_ t: MusicTrack) -> MTTrackSource {
        if MTMusicFolders.isLent(t.file) { return .folders }
        return t.inPost ? .walls : .chat(t.chat)
    }
    func holds(_ t: MusicTrack) -> Bool {
        let from = Self.of(t)
        switch self {
        case .all: return true
        case .chats: if case .chat = from { return true } else { return false }
        default: return from == self
        }
    }
}
extension MTTrackSource {
    /// A SOURCE CHOSEN, WHAT PLAYS IS THAT SOURCE (the author's word 30.09 ~00:55: «choose where one listens from»): its tracks
    /// become the queue -- a chat's letters, the lent folders, the feed's and my wall's posts (MTBoardPlaylist) -- and the track
    /// that plays keeps playing when the source holds it, else the source's first plays.
    @MainActor static func listen(_ s: MTTrackSource) {
        let list: [MusicTrack]
        if s == .walls {
            let board = MTBoard.shared
            let posts: [(post: MTBoardSeen, wall: String?)] = board.feed().map { it in (post: it.post, wall: it.owner) }
                + board.posts(on: nil).map { p in (post: p, wall: String?.none) }
            list = MTBoardPlaylist.tracks(posts)
        } else {
            let lib = ChatStore.one().musicLibrary()
            list = s == .all ? lib : lib.filter { t in s.holds(t) }
        }
        guard !list.isEmpty else { return }
        let p = VoicePlayer.shared
        let playing = p.currentTrack?.file
        p.queue = list
        if let playing, let i = list.firstIndex(where: { q in q.file == playing }) { p.queueIndex = i } else { p.play(index: 0) }
        MontanaP2PTrace.mark("music_source", "listen n=\(list.count)")
    }
    /// The chats the library's letters came from, each once, in the library's order: the filter's one-chat choice.
    @MainActor static func chats() -> [MTTrackChat] {
        var once = Set([String]())
        return ChatStore.one().musicLibrary().compactMap { t in
            guard Self.of(t) == .chat(t.chat), once.insert(t.chat).inserted else { return nil }
            return MTTrackChat(id: t.chat, title: t.chatTitle)
        }
    }
}

/// THE TRACK'S PLACE, ASKED OF THE MUSIC PAGE (the author's word 01.10 00:44: «the track's number opens the page where it plays and
/// centres the visible area on that track, on any page, so that it stands at the middle of the screen between the player and the
/// screen's top»): the host turns to the page and asks here; the page's list stands the row there (MTChatListView.focus).
@MainActor final class MTMusicFocus: ObservableObject {
    static let shared = MTMusicFocus()
    @Published private(set) var ask: MTListFocus? = nil
    func show(_ t: MusicTrack) {
        ask = MTListFocus(id: t.listRow.id, ticket: (ask?.ticket ?? 0) + 1)
        MontanaP2PTrace.mark("music", "place asked")
    }
}

/// WHETHER THE MINI STANDS UNFOLDED (the author's word 01.10 00:13): one fact for the bar of every page, so the bar on the next
/// page stands as the person left it.
@MainActor final class MTPlayerUnfold: ObservableObject {
    static let shared = MTPlayerUnfold()
    @Published var open = false
    /// The unfold and the fold, one motion measured as every other (motion what=player:unfold / player:fold).
    func set(_ on: Bool) {
        guard on != open else { return }
        MontanaP2PTrace.mark("music", on ? "mini unfolds" : "mini folds")
        MTFrameMeter.shared.moveBegan()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88), completionCriteria: .logicallyComplete) {
            open = on
        } completion: {
            MTFrameMeter.shared.moveEnded(on ? "player:unfold" : "player:fold")
        }
    }
}

/// A chat of the filter's one-chat choice: its conversation's name and its name as the person sees it.
struct MTTrackChat: Hashable, Identifiable { let id: String; let title: String }

/// THE MINI UNFOLDED (the author's word 01.10 00:13, with the big player's plate on his screenshot: «a tap on the mini player
/// unfolds it as on the screenshot, the same buttons one to one, on any page where the mini player stands; a second tap on the
/// name folds it back»): the lock screen's plate and the playlist's head with its round glass buttons, standing in the bar's own
/// place over the rows (MontanaPlayerBar); the separate page of the big player is gone. It watches the player's face itself;
/// the clock is the time line's alone (MTPlayerClockLine). The cover rises over the plate in the room above it (coverRoom).
struct MTPlayerHead: View {
    /// The plates' side room and the gap between two plates, read off the author's screenshots (a 428-point screen).
    static let edge: CGFloat = 15
    static let gap: CGFloat = 8
    @Binding var source: MTTrackSource   // the filter's choice (MTTrackSource): what plays is that source
    let chats: () -> [MTTrackChat]      // the chats the one-chat choice offers, read when the filter opens
    let place: Int?                      // nil: the playlist shown does not hold the playing track
    let onPlace: () -> Void
    let onSearch: () -> Void
    let onGoToMessage: (MusicTrack) -> Void
    let leave: () -> Void
    let coverRoom: CGFloat               // the room the cover rises in, over the plate
    let onTitle: () -> Void              // a tap on the name folds the plate back into the mini
    /// The face, not the player: the clock ticks four times a second, and only MTPlayerClockLine needs it.
    @ObservedObject private var face = VoicePlayer.shared.face
    @ObservedObject private var meta = MTTrackMeta.shared   // the artist's line, drawn when its reading lands
    private var player: VoicePlayer { VoicePlayer.shared }

    private var track: MusicTrack? { player.currentTrack }
    // The file's name as it was sent, nothing else (the author's word 07.09).
    private var title: String { ((track?.title ?? "") as NSString).deletingPathExtension }
    /// A lent folder's track (MTMusicFolders) lies in no chat: it has no message to go to; nor has a track of the feed or a wall
    /// (MusicTrack.inPost): it lies in a post, not in a letter.
    private var lentTrack: Bool { track.map { MTMusicFolders.isLent($0.file) || $0.inPost } ?? false }
    /// THE NAME ALONE, AND A HOLD COPIES IT (the author's words 29.09: «a long press copies the track's name»; ~23:10: «at the speed
    /// our menu opens in the chat»): MTNameCopy, the one act of both players.
    @State private var copied = 0
    private func copyTitle() { MTNameCopy.copy(title, from: "player", mark: $copied) }
    /// The cover's rise and fold, one motion of the page measured as every other (motion what=cover:rise / cover:fold).
    private func toggleCover() {
        let opens = !coverOpen
        MTFrameMeter.shared.tap("player:cover")
        MontanaP2PTrace.mark("cover_look", opens ? "rises own=\(MTTrackMeta.shared.cover(track?.file ?? "") == nil ? 0 : 1)" : "folds")
        MTFrameMeter.shared.moveBegan()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86), completionCriteria: .logicallyComplete) {
            coverOpen = opens
        } completion: {
            MTFrameMeter.shared.moveEnded(opens ? "cover:rise" : "cover:fold")
        }
    }
    private var sounding: Bool { face.playingFile != nil && !face.isVoice }
    /// The cover opened over the plate (MTCoverStage), in the room above it.
    @State private var coverOpen = false

    var body: some View {
        let _ = MTFrameMeter.shared.body("player-head")
        VStack(spacing: Self.gap) {
            VStack(spacing: Self.gap * 2) {
                if coverOpen, 80 < coverRoom {
                    MTCoverStage(file: track?.file ?? "", onClose: toggleCover)
                        .frame(height: coverRoom)
                        .transition(.scale(scale: 0.15, anchor: .bottomLeading).combined(with: .opacity))
                }
                nowPlaying
            }
            head
        }
    }

    /// THE PLAYER'S ONE PLATE, THE LOCK SCREEN'S (the author's screenshot 29.09): the cover, the name running over the artist its
    /// tags name, the sound's wave while it plays; the line of the time with the elapsed and the remaining at its ends; the track
    /// before, the play and the track after at the middle, the sound's way at the end.
    private var nowPlaying: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // THE COVER OPENS OVER THE PLATE (the author's word 30.09 22:58: «at a tap on the album's icon it appears above the
                // music panel, not as a separate window»): the platform's button over the picture; the cover rises in this page's
                // own room above the plate and folds back at a tap (MTCoverStage).
                Button(action: toggleCover) {
                    MTMusicCover(file: track?.file ?? "", side: 57, corner: 10)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Group {
                        if copied != 0 { MTCopiedWord(font: .body.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading) }
                        else { MTMarquee(text: title, style: .body) }
                    }
                    .frame(height: 22)
                    if let s = said {
                        // THE STATE SAID UNDER THE NAME (the author's word 01.10 00:42): a moment, then the artist again.
                        Label(s.text, systemImage: s.glyph).font(.subheadline.weight(.semibold))
                            .foregroundColor(MontanaOctagon.platformBlue).lineLimit(1)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if let by = track.flatMap({ meta.byline($0.file) }) {
                        // USER-DATA: the artist the file's own tags name (MTTrackMeta.byline) -- never where the track lies.
                        Text(verbatim: by).font(.body).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTitle() }   // the name folds the plate back into the mini (the author's word 01.10 00:13)
                .onLongPressGesture(minimumDuration: montanaLongPress) { copyTitle() }   // the chat bubble's own threshold
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .medium)).foregroundColor(.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: sounding && !face.paused)
            }
            MTPlayerClockLine().padding(.top, 12)
            controls.padding(.top, 4)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(MTGlassCardPlate(cornerRadius: 26))
    }

    /// The lock screen's three at the plate's middle -- the track before, the play, the track after -- and the sound's way at
    /// its end: the platform's glyphs, no plate of their own.
    private var controls: some View {
        ZStack {
            HStack(spacing: 30) {
                control("backward.fill", size: 28) { player.prev() }
                control(sounding && !face.paused ? "pause.fill" : "play.fill", size: 36) {
                    // A track standing ready (nothing of the music playing yet) starts from its place.
                    if !sounding { player.play(index: player.queueIndex) }
                    else if player.paused { player.resume() } else { player.pause() }
                }
                control("forward.fill", size: 28) { player.next() }
            }
            HStack {
                placeMark
                Spacer()
                MTSoundWayMark()
            }
        }
        .frame(height: 60)
    }
    @ViewBuilder private var placeMark: some View {
        if let n = place {
            Button(action: { onPlace(); MTFrameMeter.shared.tap("player:place") }) {
                HStack(spacing: 3) {
                    Image(systemName: "list.number").font(.system(size: 15, weight: .medium))
                    // USER-DATA: the track's place in the playlist, digits.
                    Text(verbatim: String(n)).font(.footnote.weight(.semibold)).monospacedDigit().lineLimit(1)
                }
                .foregroundColor(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Show in playlist"))
        }
    }
    private func control(_ glyph: String, size: CGFloat, _ act: @escaping () -> Void) -> some View {
        Button(action: { act(); MTFrameMeter.shared.tap("player:" + glyph) }) {
            Image(systemName: glyph).font(.system(size: size)).foregroundColor(.primary)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
    }

    /// THE FIVE ROUND BUTTONS UNDER THE PLATE (the author's words 01.10 00:42 and ~00:48: «instead of the three dots only the native
    /// share»; «take the word Playlist away under the unfolded player, and the buttons under it aligned and centred evenly on the
    /// line, all five at their present size»): the repeat and the shuffle lit in the platform's blue while on, the search, the
    /// filter, the platform's share -- the same space between every two and at both ends.
    private var head: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            // THE REPEAT'S ROUND (the author's word 01.10 00:42): the track, the playlist, off -- each said under the name.
            circleButton(face.repeatOn ? "repeat.1" : "repeat", on: face.repeatOn || face.repeatAll) {
                player.turnRepeat()
                if player.repeatOn { say("Repeat track", glyph: "repeat.1") }
                else if player.repeatAll { say("Repeat playlist", glyph: "repeat") }
                else { say("Repeat off", glyph: "repeat") }
            }
            Spacer(minLength: 0)
            circleButton("shuffle", on: face.shuffleOn) {
                player.shuffleOn.toggle()
                say(player.shuffleOn ? "Shuffle on" : "Shuffle off", glyph: "shuffle")
            }
            Spacer(minLength: 0)
            circleButton("magnifyingglass", on: false) { onSearch() }   // the music page's own search
            Spacer(minLength: 0)
            filter
            Spacer(minLength: 0)
            circleButton("square.and.arrow.up", on: false) { if let t = track { MontanaPlayerBar.share(t.file, as: title, from: nil) } }
                .accessibilityLabel(Text("Share"))
            Spacer(minLength: 0)
        }
    }
    /// THE STATE SAID UNDER THE NAME (the author's word 01.10 00:42: «the statuses shown natively, as the system's notice under the
    /// track's name, flashing for a couple of seconds»): the platform's glyph and the catalogue's word, gone after two seconds.
    struct Said: Equatable { let text: LocalizedStringKey; let glyph: String; let n: Int }
    @State private var said: Said? = nil
    private func say(_ text: LocalizedStringKey, glyph: String) {
        let s = Said(text: text, glyph: glyph, n: (said?.n ?? 0) + 1)
        withAnimation(.easeOut(duration: 0.2)) { said = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if said?.n == s.n { withAnimation(.easeOut(duration: 0.25)) { said = nil } } }
    }
    private func circleButton(_ glyph: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: { act(); MTFrameMeter.shared.tap("player:" + glyph) }) {
            Image(systemName: glyph).font(.system(size: 16, weight: .semibold))
                .foregroundColor(on ? MontanaOctagon.platformBlue : .primary)
                .frame(width: 44, height: 44)
                .background(MTGlassCirclePlate())
                .contentShape(Circle())
        }
    }
    /// THE SOURCE'S FILTER, TO THE RIGHT OF THE SEARCH (the author's word 30.09 ~00:55): the platform's own menu with its pickers --
    /// every track, the chats', the walls', the folders', or one chat's -- on the round glass with the platform's filter glyph and no
    /// word, lit in the platform's blue while a source is chosen.
    private var filter: some View {
        Menu {
            Picker(selection: $source) {
                Label("All", systemImage: "music.note.list").tag(MTTrackSource.all)
                Label("Chats", systemImage: "bubble.left.and.bubble.right").tag(MTTrackSource.chats)
                Label("Walls", systemImage: "text.below.photo").tag(MTTrackSource.walls)
                Label("Folders", systemImage: "folder").tag(MTTrackSource.folders)
            } label: { EmptyView() }
            .pickerStyle(.inline)
            let each = chats()
            if 1 < each.count {
                Picker(selection: $source) {
                    ForEach(each) { c in
                        // USER-DATA: the chat's name as the person sees it.
                        Text(verbatim: c.title).tag(MTTrackSource.chat(c.id))
                    }
                } label: { Label("Chat", systemImage: "bubble.left") }
                .pickerStyle(.menu)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 16, weight: .semibold))
                .foregroundColor(source == .all ? .primary : MontanaOctagon.platformBlue)
                .frame(width: 44, height: 44)
                .background(MTGlassCirclePlate())
                .contentShape(Circle())
        }
        .accessibilityLabel(Text("Source"))
    }

}

/// The one view of the big player that watches the clock, and the only one a drag redraws.
struct MTPlayerClockLine: View {
    @ObservedObject private var player = VoicePlayer.shared
    @State private var scrub: Double? = nil
    var body: some View {
        let total = player.duration
        let live = total > 0 ? min(1, player.elapsed / total) : 0
        let p = scrub ?? live
        HStack(spacing: 10) {
            // USER-DATA: the elapsed time, digits.
            Text(verbatim: fmtDuration(total * p)).font(.footnote.weight(.medium)).monospacedDigit().foregroundColor(.secondary)
            ZStack {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(Color.white.opacity(0.72))
                            .frame(width: g.size.width * p)
                            .animation(scrub == nil ? .linear(duration: 0.25) : nil, value: p)
                    }
                    .frame(height: 7)
                    .frame(maxHeight: .infinity)
                }
                .allowsHitTesting(false)
                MontanaScrubber(live: live, grab: true, meter: "player", onSeek: { player.seek(to: $0) }, onHold: { scrub = $0 })
            }
            .frame(height: montanaTouchTarget)
            // USER-DATA: the remaining time, digits.
            Text(verbatim: "-" + fmtDuration(max(0, total - total * p))).font(.footnote.weight(.medium)).monospacedDigit().foregroundColor(.secondary)
        }
    }
}

/// AVRoutePickerView draws only its AirPlay glyph, so the device's glyph lies beneath a clear picker that takes the tap.
struct MTSoundWayMark: View {
    @ObservedObject private var way = MontanaAudioRoute.Way.shared
    var body: some View {
        ZStack {
            Image(systemName: way.glyph).font(.system(size: 19, weight: .medium))
                .foregroundColor(MontanaOctagon.platformBlue)   // the source said in the system's blue (the author's word 01.10 ~00:50)
                .allowsHitTesting(false)
            MontanaRoutePicker()
        }
        .frame(width: 44, height: 44)
        .onAppear { MontanaAudioRoute.read("music") }
    }
}

/// A TRACK'S PICTURE IN A PLATE'S CORNER (the lock screen's player and the notifications' plates, 29.09): the track's own cover
/// when it carries one (MTTrackMeta), filled into the square and cut by the plate's rounding, as the platform draws an album's
/// art; else the app's own icon in its own shape, as the home screen shows it (MTMusicArt) -- no ground under it, no frame round
/// it. The play or the pause over it for the track that plays.
struct MTMusicCover: View {
    let file: String
    let side: CGFloat
    let corner: CGFloat
    var glyph: String? = nil
    @ObservedObject private var meta = MTTrackMeta.shared
    var body: some View {
        let own = meta.cover(file)
        let shape = RoundedRectangle(cornerRadius: own == nil ? side * MTMusicArt.corner : corner, style: .continuous)
        ZStack {
            if let own {
                Image(uiImage: own).resizable().scaledToFill()
            } else if let icon = MTMusicArt.thumb {   // the icon drawn down once to a row's pixels (MTMusicArt.thumb)
                Image(uiImage: icon).resizable().scaledToFill()
            } else {
                shape.fill(Color(white: 0.24))
            }
            if let glyph {
                Color.black.opacity(0.35)
                Image(systemName: glyph).font(.system(size: side * 0.42, weight: .semibold)).foregroundColor(MontanaOctagon.platformBlue)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .onAppear { meta.load(file) }
        // A reused cell keeps its view and never appears again.
        .onChange(of: file) { _, f in meta.load(f) }
    }
}

/// THE APP'S OWN ICON WHERE A TRACK HAS NO COVER (the author's words: 29.09 ~23:10 «Media/Montana_AppIcon_iOS_1024.png on the music's
/// cover -- integrate the app's icon natively, if the music has no real cover»; 30.09 ~00:45 «the icon's bubble has no black
/// insets, and on the app's icon it stands without the black contour -- do so on the cover»). The file of Media/ carries its glass
/// inside a black field (x 107..916, y 110..876 of 1024), and drawn whole it stood in the plates as a glass square in a black
/// frame (the author's picture 30.09 00:44). The home screen shows his pixels fitted to the icon's whole canvas (5dd2afeb: along
/// every ray the rim lands on the icon's shape, nothing redrawn) -- that very picture, AppIcon.icon/Assets/logo.png byte for byte
/// (sha256 b123ed40...), is the one the cover wears (AppIconPicture.imageset), cut by the icon's own shape. One owner of a track's
/// picture for the plate, the playlist's rows and the lock screen; a track's own cover is always first.
enum MTMusicArt {
    static let asset = "AppIconPicture"
    static let icon: UIImage? = UIImage(named: asset)
    /// THE ICON'S OWN SHAPE: a rounded square whose corner is 22.37 % of its side -- the home screen's mask, the shape the picture
    /// was fitted to (5dd2afeb). Inside it no black of the author's field shows; a flatter rounding would show it at the corners.
    static let corner: CGFloat = 0.2237
    /// The icon for the lock screen, cut by its own shape with its corners clear: the lock screen rounds a picture less than the
    /// home screen does, and the picture's corners past the glass would stand there as a dark frame.
    static let lockIcon: UIImage? = icon.map { picture in
        let format = UIGraphicsImageRendererFormat()
        format.scale = picture.scale
        format.opaque = false
        let rect = CGRect(origin: .zero, size: picture.size)
        return UIGraphicsImageRenderer(size: picture.size, format: format).image { _ in
            UIBezierPath(roundedRect: rect, cornerRadius: rect.width * corner).addClip()
            picture.draw(in: rect)
        }
    }
    /// The lock screen's picture (MPNowPlayingInfoCenter): the track's own cover at the lock screen's measure when it has one
    /// (MTTrackMeta.wholeCover), else the icon -- both square and whole, so the platform shows them at their full place.
    static func artwork(_ own: UIImage?) -> MPMediaItemArtwork? {
        guard let picture = own ?? lockIcon else { return nil }
        return MPMediaItemArtwork(boundsSize: picture.size) { _ in picture }
    }
}

/// THE COVER OPENED OVER THE PLATE (the author's words: 30.09 ~01:45 «a tap on the album shows our icon when there is no album,
/// and our icon sends out waves to the music's rhythm, smoothly -- glass waves, colourless, like living glass»; 30.09 22:58 «at a
/// tap on the album's icon it appears above the music panel, not as a separate window, and smoother»). It rises in the big
/// player's own head, in the room the plate leaves above it (MTPlayerHead.stage), and a tap folds it back. The track that plays:
/// its own cover whole (MTTrackMeta.wholeCover), else the app's icon sending out its waves (MTCoverWaves) inside the stage.
/// The separate full-screen page it replaces took 3065 ms to rise on T1 and, while it stood, drove the app from 1.6 to 2.6 GB
/// with 551 memory warnings in 80 s (2047, 30.09 22:56-22:58 MSK).
struct MTCoverStage: View {
    let file: String
    let onClose: () -> Void
    @ObservedObject private var meta = MTTrackMeta.shared
    @State private var whole: UIImage? = nil
    @State private var wholeOf = ""
    var body: some View {
        let own = (wholeOf == file ? whole : nil) ?? meta.cover(file)
        Button(action: onClose) {
            GeometryReader { g in
                let side = min(g.size.width, g.size.height)
                Group {
                    if let own {
                        Image(uiImage: own).resizable().scaledToFit()
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        MTCoverWaves(side: side * 0.45, stage: g.size)   // a quarter smaller (the author's word 01.10 00:46)
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { meta.load(file) }
        .task(id: file) {
            guard !file.isEmpty else { return }
            let img = await MTTrackMeta.wholeCover(file)
            whole = img
            wholeOf = file
        }
    }
}

/// THE ICON'S WAVES (the author's word 30.09 ~01:45): out of the app's icon, in its own shape, rings part and spread to the
/// stage's edges, rounding into circles as they go -- colourless, a light rim as glass has. They follow the music that plays:
/// its level, read once a frame from the player's own meter (VoicePlayer.level), smoothed -- quick to rise, slow to fall
/// (MTCoverPulse) -- sets how often a wave parts, how strong it stands and the icon's breath; a beat over the running average
/// sends one at once. At rest no wave parts, the ones already out run their course and the frames stop. Reduce Motion: the icon
/// stands still, nothing spreads, nothing is measured. ONE LAYER FOR ALL THE RINGS (drawingGroup), the stage's size: each ring
/// of the system's glass was a backdrop of its own growing past the screen, redrawn sixty times a second.
struct MTCoverWaves: View {
    let side: CGFloat
    let stage: CGSize
    @ObservedObject private var face = VoicePlayer.shared.face
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var pulse = MTCoverPulse()
    /// A wave's life after the music rests: then the frames stop.
    @State private var quiet = false
    private var playing: Bool { face.playingFile != nil && !face.paused && !VoicePlayer.shared.isVoice }
    var body: some View {
        let run = !still && (playing || !quiet)
        // TO THE SCREEN'S EDGES IN EVERY WAY (the author's word 01.10 00:46: «the pulse goes past the square's bounds beautifully and
        // does not draw it; to the screen's end in all directions, slowly and beautifully, in rhythm»): a wave runs until it has
        // passed the screen's farthest corner, drawn over whatever stands there and taking no touch.
        let screen = MTScene.size()
        let reach = (screen.width * screen.width + screen.height * screen.height).squareRoot()
        Group {
            if still {
                icon
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !run)) { ctx in
                    let now = ctx.date.timeIntervalSinceReferenceDate
                    let breath = pulse.step(now, level: VoicePlayer.shared.level())
                    ZStack {
                        ForEach(0..<MTCoverPulse.slots, id: \.self) { i in ring(pulse.waves[i], now: now, reach: reach) }
                        icon.scaleEffect(breath)
                    }
                }
            }
        }
        .frame(width: stage.width, height: stage.height)
        .allowsHitTesting(false)
        .onAppear { VoicePlayer.shared.metering = !still }
        .onDisappear { VoicePlayer.shared.metering = false }
        .onChange(of: still) { _, s in VoicePlayer.shared.metering = !s }
        .task(id: playing) {
            guard !playing else { quiet = false; return }
            try? await Task.sleep(nanoseconds: UInt64(MTCoverPulse.life * 1.2 * 1_000_000_000))
            if !Task.isCancelled { quiet = true }
        }
    }
    private var icon: some View {
        Group {
            if let picture = MTMusicArt.icon { Image(uiImage: picture).resizable().scaledToFill() }
            else { Color(white: 0.24) }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * MTMusicArt.corner, style: .continuous))
    }
    /// A wave at its age: parting from under the icon at the icon's size, quick at first and settling as it reaches the edges,
    /// thinning and fading as it goes.
    @ViewBuilder private func ring(_ w: MTCoverPulse.Wave, now: Double, reach: CGFloat) -> some View {
        let t = (now - w.born) / MTCoverPulse.life
        if 0 <= t, t < 1 {
            let e = CGFloat(1 - pow(1 - t, 1.6))   // an even, slow spread
            let size = side + (reach * 2 - side) * e
            let round = MTMusicArt.corner + (0.5 - MTMusicArt.corner) * min(1, e * 6)   // a circle almost at once: the square is never drawn
            RoundedRectangle(cornerRadius: size * round, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0.18)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: CGFloat(2.5 + 9 * w.strength) * (1 - 0.55 * e))
                .frame(width: size, height: size)
                .opacity((0.35 + 0.65 * w.strength) * pow(1 - t, 1.6) * 0.5)
        }
    }
}

/// THE WAVES' CLOCK (MTCoverWaves): the level smoothed -- quick to rise, slow to fall -- and a running average under it. A WAVE
/// PARTS ON A BEAT ONLY (the author's word 01.10 00:46: «the pulse exactly in rhythm with the music»): the moment the heard level
/// crosses over its running average by a beat's margin, on the rising edge, never twice within a quarter of a second; no clock
/// of its own sends waves between the beats -- only a long quiet of beats (two seconds) lets one go, so a soft track still
/// breathes. Sixteen places held for the page's life: a frame writes into them and allocates nothing.
final class MTCoverPulse {
    struct Wave { var born: Double = -100; var strength: Double = 0 }
    static let slots = 16
    static let life: Double = 4.0   // slow, to the screen's edges
    private(set) var waves = [Wave](repeating: Wave(), count: slots)
    private var next = 0
    private var level: Double = 0
    private var floor: Double = 0
    private var last: Double = 0
    private var lastWave: Double = -100
    private var over = false   // the heard level stands over the beat's margin: its rising edge is the beat
    /// One frame: the level taken in, a wave parted on a beat; the icon's breath returned.
    func step(_ now: Double, level heard: Float) -> CGFloat {
        let dt = min(0.1, max(0, now - last))
        last = now
        let x = Double(heard)
        let rising = level < x
        level += (x - level) * (1 - exp(-dt / (rising ? 0.03 : 0.25)))
        floor += (x - floor) * (1 - exp(-dt / 1.2))
        let margin = max(0.05, floor * 0.3)
        let above = margin < x - floor
        let beat = above && !over && 0.25 < now - lastWave
        over = above
        if 0.04 < level, beat || 2 < now - lastWave {
            lastWave = now
            waves[next] = Wave(born: now, strength: max(0.25, min(1, level * 1.3)))
            next = (next + 1) % Self.slots
        }
        return CGFloat(1 + 0.02 * level + 0.1 * max(0, level - floor))
    }
}

// ════════════════════════════════════════════════════════════
// THE PLAYER BAR — ONE bar for every file the player plays, music and voice alike (the
// author's word 14.09): one gate (something is playing), one chrome, two hosts — the chat
// floats it over the feed's bottom above the message field, the chat list keeps it in the
// rows' bottom inset; both let the rows show through the same material. Native throughout:
// the system slider along the top, SF glyphs, the bordered small buttons, the system close.
// ONE MINI FOR ALL THREE (the author's word 22.09): the play button, the plate-scrubber with the
// name inside, the timer (a track) or the speed (a voice, a note), the close — see mini(kind:);
// since 29.09, for a track, the track before at the play's side and the track after at the plate's end.
// ════════════════════════════════════════════════════════════
struct MontanaPlayerBar: View {
    @ObservedObject private var player = VoicePlayer.shared
    @ObservedObject private var dock = MontanaVideoDock.shared
    @ObservedObject private var unfold = MTPlayerUnfold.shared   // the mini unfolded where it stands (MTPlayerHead)
    @State private var source: MTTrackSource = .all              // the unfolded plate's filter: what plays
    /// The unfolded plate's number and search ask the host for the music page: the track's place in its list, its own search.
    var onPlace: (MusicTrack) -> Void = { _ in }
    var onSearch: () -> Void = {}
    /// A tap on the bar's voice or note goes to its bubble (the author's word 15.09): the chat and
    /// the file — the host opens the chat at the letter, or scrolls to it when it is already open.
    var onGoTo: (String, String) -> Void = { _, _ in }
    /// THE PLAYING TRACK'S ROW WEARS THE MINI ITSELF (the author's word 24.09: «the chosen track that plays — in the same
    /// style as the mini player: the circle turns into the play, and a bubble as wide as the row that fills, with the
    /// time at its end; all the same as the mini player, only without the cross»): the music list's standing row is this
    /// very view, the close left out and no room of the bar around it — one owner of the mini, two places.
    var row = false

    /// THE TIMER'S TWO FACES (the author's word 21.09): the position, or — after a tap on it — the
    /// remaining time with a minus; the choice is kept across launches.
    @AppStorage("miniTimeRemaining") private var timeRemaining = false

    /// The one gate: the bar stands while the player plays anything — a track, a voice, a note.
    static var standing: Bool {
        let p = VoicePlayer.shared
        return (p.playingFile != nil && (p.currentTrack != nil || p.isVoice)) || MontanaVideoDock.shared.file != nil
    }
    /// THE ONE BIT THE HOSTS OBSERVE (the critic 22.09, T1 on 1855): the conversation and the chat list
    /// observed the whole player, and its clock — progress and elapsed, several times a second — re-rendered
    /// the entire screen and rebuilt every row of the feed while a voice played under a fling (81 rebuilds
    /// in one 24-second fling, frames of 70–135 ms with no cell to blame). The hosts need one fact —
    /// whether the bar stands — so one fact is published, and only when it changes.
    final class Gate: ObservableObject {
        static let shared = Gate()
        @Published private(set) var standing = MontanaPlayerBar.standing
        private var bag = Set<AnyCancellable>()
        private init() {
            VoicePlayer.shared.objectWillChange
                .merge(with: MontanaVideoDock.shared.objectWillChange)
                .receive(on: DispatchQueue.main)   // one turn later, when the change has landed
                .sink { [weak self] _ in
                    guard let self else { return }
                    let now = MontanaPlayerBar.standing
                    if now != self.standing { self.standing = now }
                }
                .store(in: &bag)
        }
    }
    /// A TAPE HOLDS WHAT PLAYS, AND THE BAR STAYS (the author's word 26.09: «the mini player must remember where it stopped and not
    /// be reset by recording»; before, 16.09, a tape stopped whatever played and took the bar down): what plays pauses where it
    /// stands (VoicePlayer.holdForTape) and its play goes on from there after the tape; the open note still closes -- its stage
    /// stands where the tape is recorded. One road for both tapes ([C-1]). A NOTE LETS THE MUSIC PLAY ON (the author's word
    /// 24.09): a track keeps playing under a note.
    static func standDown(keepingMusic: Bool = false) {
        let v = VoicePlayer.shared
        if !(keepingMusic && !v.isVoice && v.playingFile != nil) { v.holdForTape() }
        MontanaVideoDock.shared.close()
    }

    var body: some View {
        if row { mini(kind: .track) }   // the list's standing row: the track, whatever else plays over it
        else if Self.standing {   // the one gate, read here and by the hosts alike
            if unfold.open, dock.file == nil, let t = player.currentTrack { unfolded(t) }
            else { mini(kind: dock.file != nil ? .note : (player.currentTrack != nil ? .track : .voice)) }
        }
    }
    /// THE MINI UNFOLDS WHERE IT STANDS (the author's word 01.10 00:13, MTPlayerHead): the same bar, the same place over the rows,
    /// the plate of the screenshot with its buttons one to one; the name folds it back. The cover rises over it in a third of the
    /// screen.
    private func unfolded(_ t: MusicTrack) -> some View {
        let place = player.queue.firstIndex { q in q.file == t.file }.map { i in i + 1 }
        return MTPlayerHead(source: $source, chats: { MTTrackSource.chats() }, place: place,
                            onPlace: { onPlace(t) }, onSearch: onSearch,
                            onGoToMessage: { m in onGoTo(m.chat, m.file) }, leave: { MTPlayerUnfold.shared.set(false) },
                            coverRoom: MTScene.size().height / 3, onTitle: { MTPlayerUnfold.shared.set(false) })
            .padding(.horizontal, MTPlayerHead.edge).padding(.vertical, MTPlayerHead.gap)
            .onChange(of: source) { _, s in MTTrackSource.listen(s) }
            .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
    }

    private enum Kind { case track, voice, note }

    /// THE ONE MINI PLAYER (the author's word 22.09): ONE owner for the track, the voice and the video
    /// note alike, as tall as its play button, in the bar's own dress — no ground of its own, the plates
    /// alone carry the glass, exactly as the message field and its buttons. The play button; the plate
    /// that is the scrubber (grabbed at its fill's edge; tapped — the track opens its page, a voice or a
    /// note goes to its bubble) with the name running inside it; at the plate's right the track's timer
    /// (its two faces) or, for a voice and a note, the speed; and the close. No sender line, no <next>,
    /// no picture: the note plays on its stage over the feed.
    private func mini(kind: Kind) -> some View {
        let note = kind == .note
        let paused = note ? !dock.playing : player.paused
        let duration = note ? dock.duration : player.duration
        let live = duration > 0 ? max(0, min(1, note ? dock.progress : player.progress)) : 0
        // USER-DATA: the track's own name, or the speaker's name as the person sees it.
        let title: String
        switch kind {
        // The track's name as the list names it: its tag's, else its file's (the row and the bar say one name).
        case .track: title = player.currentTrack.map { MTTrackMeta.shared.of($0.file)?.title ?? ($0.title as NSString).deletingPathExtension } ?? ""
        case .voice: title = player.nowSender
        case .note: title = dock.caption
        }
        return MTMiniFace(paused: paused, title: title, live: live,
                          side: { p in
                              kind == .track
                                  ? MTPlayerPlate.trackTime(p, duration: duration, remaining: timeRemaining)
                                  // The speed: one tap around 1 → 1.5 → 2 — the voice's and the note's alike.
                                  : (player.voiceRate == 1 ? "1×" : (player.voiceRate == 2 ? "2×" : "1.5×"))
                          },
                          onPlay: {
                              // A rest and a resume are said, and whose play it was: the bar's, or the list's row (the critic 24.09).
                              MontanaP2PTrace.mark("music", "mini play by=\(row ? "row" : "bar") to=\((note ? !dock.playing : player.paused) ? "on" : "rest")")
                              if note { dock.toggle() } else if player.paused { player.resume() } else { player.pause() }
                          },
                          onSeek: { v in if note { dock.seek(to: v) } else { player.seek(to: v) } },
                          onSide: {
                              // A tap in the slot's room is the slot's: the timer's face, or the speed.
                              if kind == .track { timeRemaining.toggle() }
                              else { player.voiceRate = player.voiceRate >= 2 ? 1 : (player.voiceRate >= 1.5 ? 2 : 1.5); dock.applyRate() }
                          },
                          onOpen: { open(kind) },
                          // The list's row has no cross: the track stands down from the bar, not from its row.
                          onClose: row ? nil : { if note { dock.close() } else { player.stop() } },
                          // THE THIN BLUE RING ON EVERY PAGE (the author's word 29.09: «the system's blue outline on all the
                          // pages»): the bar wears the playing row's ring wherever it floats.
                          ring: MTMiniFace.playingRing,
                          // A HOLD ON THE MINI COPIES ITS NAME AT ONCE (the author's word 29.09 ~23:10, MTNameCopy).
                          copies: true,
                          // THE TRACK BEFORE AND THE TRACK AFTER (the author's word 29.09 on 2000: «the buttons switch the track,
                          // the seeking is the central plate's»): the queue's own turn (VoicePlayer.prev/next -- the lock screen's
                          // buttons, the same road); the bar's alone, as the close is, and a track's alone.
                          onPrev: row || kind != .track ? nil : { MontanaP2PTrace.mark("music", "mini prev"); player.prev() },
                          onNext: row || kind != .track ? nil : { MontanaP2PTrace.mark("music", "mini next"); player.next() })
            // THE MIRROR IS MEASURED, NOT EYEBALLED (23.09): the row writes its own place, so the «+»
            // and the microphone below can be held against the play and the close to the point — the bar's, not the list's.
            .background(row ? nil : MTFrameMark("player-row"))
    }
    /// «SHARE» HANDS THE FILE UNDER THE NAME THE PAGE SHOWS (the author's word 29.09: «share the file with the same name as
    /// the track»): a letter's track lies on disk under the letter's own name, so the sheet is given the file under the title
    /// (MTDocLink, the documents' own road, [C-1]) -- made off the main thread (a lent folder's track may have to be copied), the
    /// sheet raised once it stands. A voice and a note go under their own names. A lent track whose bytes its keeper still holds is
    /// not handed: there is nothing to hand yet.
    /// The mini's hold menu said it until the hold became the copy (29.09 ~23:10); the big player's menu says it now.
    static func share(_ file: String?, as title: String?, from anchor: UIView?) {
        guard let file, !MTMusicFolders.needsFetch(file) else { return }
        let src = attachmentURL(file)
        MontanaP2PTrace.mark("music", "player share named=\(title == nil ? 0 : 1)")
        Task.detached(priority: .userInitiated) {
            let url = title.map { MTDocLink.named(src, as: $0) } ?? src
            await MainActor.run { MTShare.present([url], from: anchor) }
        }
    }
    /// A tap on the name's room: the track unfolds the mini where it stands; a voice or a note goes to its bubble
    /// (the author's word 15.09) — the host opens the chat at the letter, or scrolls to it.
    private func open(_ kind: Kind) {
        switch kind {
        case .track: if player.currentTrack != nil { MTPlayerUnfold.shared.set(true) }
        case .voice: if let f = player.playingFile { onGoTo(player.nowChat, f) }
        case .note: if let f = dock.file { onGoTo(dock.chat, f) }
        }
    }
}

/// THE HOLD COPIES THE NAME (the author's word 29.09 ~23:10: «at a long press, at the speed our menu opens in the chat, the
/// track's name is copied -- in the mini player at once, and in the big one»): one act for both players -- the name to the
/// pasteboard at the chat's own threshold (montanaLongPress, the bubble's hold), the platform's success tap, and for a moment the
/// name's room says the client's copy word with the platform's check (as CopyLinkButton says it, for as long). A voice's or a
/// note's plate copies the name it shows, as its menu did before.
enum MTNameCopy {
    static let shown: TimeInterval = 2
    static func copy(_ name: String, from place: String, mark: Binding<Int>) {
        guard !name.isEmpty else { return }
        UIPasteboard.general.string = name
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        MontanaP2PTrace.mark("music", "\(place) title copied")
        withAnimation(.easeOut(duration: 0.18)) { mark.wrappedValue += 1 }
        let now = mark.wrappedValue
        DispatchQueue.main.asyncAfter(deadline: .now() + shown) {
            if mark.wrappedValue == now { withAnimation(.easeOut(duration: 0.18)) { mark.wrappedValue = 0 } }
        }
    }
}

/// The word that stands in the name's room for a moment after a hold copied it (MTNameCopy): the platform's check and the
/// catalogue's «Copied».
struct MTCopiedWord: View {
    let font: Font
    var body: some View {
        Label("Copied", systemImage: "checkmark").font(font).foregroundColor(.primary).lineLimit(1)
    }
}

/// THE MINI PLAYER'S ONE FACE (the author's words 22.09 and 24.09): the play; the plate that is the scrubber, the name
/// inside it and the side word at its end; the close, in the bar only. The bar wears it for what plays (MontanaPlayerBar);
/// the music list wears it for every track (the author's word 24.09: «all the music's rows in the mini player's form») —
/// a track standing still with its play, its name and its length. MIRROR OF THE MESSAGE ROW, TO THE PIXEL (22.09): the
/// spacing is the message row's (10). THE SAME ROOM AS THE INPUT BAR (21.09: the play exactly above «+», the same size):
/// the bar's side padding and the tier owner's vertical pad — so two faces one above the other stand as far apart as
/// the bar and the message field under it (the author's word 24.09, the list's rows). busy: the keeper brings the
/// track, the platform's spinner in the play; cloud: its bytes are the keeper's, the platform's cloud in the play.
struct MTMiniFace: View {
    let paused: Bool
    let title: String
    var runs = true
    let live: Double
    let side: (Double) -> String
    let onPlay: () -> Void
    let onSeek: (Double) -> Void
    let onSide: () -> Void
    let onOpen: () -> Void
    var onClose: (() -> Void)? = nil
    var busy = false
    var cloud = false
    /// THE PLAYING TRACK'S THIN RING (the author's word 24.09: «I liked the blue of the progress bar while the backup
    /// uploads to iCloud; a thin outline for the play bubble and its name bubble on the track that plays»): the copy's bar
    /// is the platform's own ProgressView left untinted, the app's accent colour an empty asset — so its blue is the
    /// platform's own, systemBlue; drawn on the two plates' own figure, a point wide.
    var ring: Color? = nil
    static let playingRing = MontanaOctagon.platformBlue   // one owner of the platform's blue (MontanaShapes)
    /// THE HOLD COPIES THE NAME (the author's word 29.09 ~23:10, MTNameCopy): carried to the control that owns the plate's touch
    /// (MontanaScrubber.onLongPress), where it neither flickers under the clock's redraws nor is refused over the fill's edge; a
    /// still row of the list carries none.
    var copies = false
    /// THE TRACK BUTTONS (the author's word 29.09, corrected on 2000: «the buttons should switch to the next track, not seek;
    /// the seeking is the central plate's»): the track before at the play's side, the track after at the plate's end — the
    /// platform's own glyphs on the bar's own square plates; the bar's alone, for a track alone (nil on the music list's
    /// rows, as the close is, and for a voice and a note, which have no queue of tracks). EVERY BUTTON WEARS THE RING (the
    /// author's word 29.09 on 2000: «all the buttons in the system's outline, as the play and the central one»).
    var onPrev: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil
    /// ON THE MUSIC'S CANVAS (the author's word 26.09: «the music's pages in the style of the contacts, the chats and the calls, only
    /// thin as now»): the row's glass is the plate -- the play and the name's plate keep their size, the finger's room and the
    /// ring, and draw no glass of their own; the row keeps the canvas rows' inset.
    @Environment(\.mtRowOnCanvas) private var onCanvas
    var body: some View { face }
    /// A track button's square plate (29.09): the bar's own, the platform's glyph for the track before or after, the ring on it.
    private func trackButton(_ glyph: String, height h: CGFloat, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: glyph).font(.system(size: 18, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
        }
        .buttonStyle(.montanaOctagon(square: true, bar: true, height: h, bare: onCanvas))
        .overlay { if let ring { MontanaLongOctagon().stroke(ring, lineWidth: 1).allowsHitTesting(false) } }
    }
    private var face: some View {
        let h = MontanaOctagon.composeHeight
        return HStack(spacing: 10) {
            Button(action: onPlay) {
                if busy {
                    ProgressView().tint(MontanaOctagon.barGlyph)
                } else {
                    Image(systemName: cloud ? "icloud.and.arrow.down" : (paused ? "play.fill" : "pause.fill"))
                        .font(.system(size: cloud ? 17 : 20, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
                }
            }
            .buttonStyle(.montanaOctagon(square: true, bar: true, height: h, bare: onCanvas))
            .overlay { if let ring { MontanaLongOctagon().stroke(ring, lineWidth: 1).allowsHitTesting(false) } }
            if let onPrev { trackButton("backward.fill", height: h, onPrev) }
            // THE PLATE IS THE SCRUBBER (the author's word 21.09) — the one plate of the app (MTPlayerPlate); the hold's menu is its.
            MTPlayerPlate(title: title, live: live, height: h, runs: runs, side: side, onSeek: onSeek, onSide: onSide, onOpen: onOpen, copies: copies)
                .overlay { if let ring { MontanaLongOctagon().stroke(ring, lineWidth: 1).allowsHitTesting(false) } }
            if let onNext { trackButton("forward.fill", height: h, onNext) }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
                }
                .buttonStyle(.montanaOctagon(square: true, bar: true, height: h))
                .overlay { if let ring { MontanaLongOctagon().stroke(ring, lineWidth: 1).allowsHitTesting(false) } }   // the ring on every button (29.09)
            }
        }
        .padding(.horizontal, onCanvas ? 12 : nil).padding(.vertical, MTInputField.barPad)   // on the canvas the rows' own inset (MTRowBubble)
    }
}

/// THE PLATE THAT IS THE SCRUBBER — the mini player's (the author's words 21.09 and 22.09), a view of its own. The glass
/// plate fills with a transparent grey as the file
/// plays; the music is taken BY A SWIPE anywhere on the plate (the author's word 29.09; before, at the fill's edge alone) —
/// the one scrubber of the app in its grab dress — a tap in the side room at its right is the side's (the timer's face, the
/// speed) and a tap anywhere else is the host's (the page, the bubble); a hold copies the name (copies). The name
/// runs inside it. The fill is drawn from the held value while it is held, from the plate's left edge to its end.
struct MTPlayerPlate: View {
    let title: String
    let live: Double                           // the player's position, 0…1
    let height: CGFloat
    var runs = true                            // the name runs past its room; a still row of the music list keeps it still
    var side: (Double) -> String               // the side room's word for a held or a live place
    var onSeek: (Double) -> Void
    var onSide: () -> Void
    var onOpen: () -> Void
    var copies = false                         // the hold copies the name (MTNameCopy), on the control that owns the plate's touch
    @State private var copied = 0              // the hold's mark: the name's room says the copy word while it stands
    private func copyName() { MTNameCopy.copy(title, from: "mini", mark: $copied) }
    /// THE THUMB UNDER THE FINGER IS THE FINGER'S (the author's word 16.09: the scrub hung and
    /// the bar went dead). Every move used to seek the player at once — a voice's player restarts
    /// its decoding on every set of its position, dozens of times a second under a drag, on the
    /// main thread — and the tick wrote the player's own position back under the finger. Now the
    /// slider holds its value while the system says it is being edited (the platform's own
    /// editing signal — a lifted finger and a cancelled touch both end it), the tick does not
    /// touch it, and the player is asked ONCE, at the release.
    @State private var scrub: Double? = nil    // the held value, for the fill and the side's word
    @Environment(\.mtRowOnCanvas) private var onCanvas   // on the music's canvas the row's glass is the plate (MTMiniFace)
    static let sideW: CGFloat = 64             // the room of «-mm:ss» or «1.5×» with its side padding
    /// THE TIMER'S TWO FACES (the author's word 21.09): the position, or the remaining time with a minus.
    static func trackTime(_ p: Double, duration: Double, remaining: Bool) -> String {
        remaining ? "-" + fmtDuration(max(0, duration - p * duration)) : fmtDuration(p * duration)
    }
    var body: some View {
        let p = scrub ?? live
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .montanaOctagonFace(bar: true, height: height, bare: onCanvas)
            // THE FILL RUNS TO THE PLATE'S END (the author's word 22.09): the whole plate is the
            // scrubber's length — the grey reaches the right edge at the end of the file, and the
            // thumb (the fill's edge) can be taken anywhere along it; the slot's word stands over it.
            .overlay {
                GeometryReader { g in
                    Rectangle().fill(Color.white.opacity(0.16))
                        .frame(width: g.size.width * p)
                        .animation(scrub == nil ? .linear(duration: 0.25) : nil, value: p)
                }
                .clipShape(MontanaLongOctagon())
                .allowsHitTesting(false)
            }
            .overlay {
                MontanaScrubber(live: live,
                                grab: true,
                                meter: "mini",
                                onSeek: onSeek,
                                onHold: { scrub = $0 },
                                onTapAt: { x, w in if x >= w - Self.sideW { onSide() } else { onOpen() } },
                                onLongPress: copies ? copyName : nil)
            }
            .overlay {
                HStack(spacing: 0) {
                    if copied != 0 {
                        // The hold copied the name (MTNameCopy): the copy word stands in its room for a moment.
                        MTCopiedWord(font: .subheadline.weight(.semibold))
                            .padding(.leading, 12).padding(.trailing, 2)
                            .frame(maxWidth: .infinity)
                    } else if runs {
                        MTMarquee(text: title, style: .subheadline, centred: true)
                            .padding(.leading, 12).padding(.trailing, 2)
                            .frame(maxWidth: .infinity)
                    } else {
                        // USER-DATA: the track's own name, still — a list of running names would give the eye no rest.
                        Text(verbatim: title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            .padding(.leading, 12).padding(.trailing, 2)
                            .frame(maxWidth: .infinity)
                    }
                    // USER-DATA: the position, the remaining time or the speed — digits.
                    Text(verbatim: side(p))
                        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundColor(MontanaOctagon.barGlyph)
                        .frame(width: Self.sideW, height: height, alignment: .center)
                }
                .allowsHitTesting(false)   // the words are the scrubber's dress; the touch is the scrubber's
            }
    }
}

/// A RUNNING LINE (the author's word 21.09): a title longer than its room scrolls past it ONCE —
/// one pass at a reading pace — then stands at its start and rests a minute before the next pass;
/// a title that fits never moves. Its own width measured, clipped to its room, nothing around it
/// touched.
/// Core Animation plays the pass in the render server, so a busy main thread never stops the name.
struct MTMarquee: UIViewRepresentable {
    let text: String
    let style: UIFont.TextStyle
    var centred = false   // a title that fits stands in the middle of its room; a long one runs from the left
    func makeUIView(context: Context) -> MTMarqueeView {
        let v = MTMarqueeView()
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: MTMarqueeView, context: Context) {
        v.show(text, font: MTMarqueeView.font(style, context.environment), centred: centred)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView v: MTMarqueeView, context: Context) -> CGSize? {
        let w = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? v.textWidth
        return CGSize(width: w, height: ceil(MTMarqueeView.font(style, context.environment).lineHeight))
    }
}

final class MTMarqueeView: UIView {
    private static let gap: CGFloat = 48
    private static let pace: CGFloat = 30      // points per second
    private static let wait: Double = 1.2
    private static let rest: Double = 60
    private let strip = UIView()
    private let first = UILabel()
    private let second = UILabel()
    private var centred = false
    private var laid = ""
    private(set) var textWidth: CGFloat = 0

    /// At the tree's locked type size (MontanaTextSize.lock), not the system's.
    static func font(_ style: UIFont.TextStyle, _ env: EnvironmentValues) -> UIFont {
        let size = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(env.dynamicTypeSize))
        return UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style, compatibleWith: size).pointSize, weight: .semibold)
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(strip)
        for l in [first, second] {
            l.textColor = .label
            l.numberOfLines = 1
            strip.addSubview(l)
        }
        // The system strips layer animations in the background.
        NotificationCenter.default.addObserver(self, selector: #selector(back), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(_ text: String, font: UIFont, centred: Bool) {
        if first.text == text, first.font == font, self.centred == centred { return }
        for l in [first, second] { l.text = text; l.font = font }   // USER-DATA: the track's or the speaker's name
        self.centred = centred
        textWidth = ceil(first.intrinsicContentSize.width)
        setNeedsLayout()
    }
    override func layoutSubviews() { super.layoutSubviews(); lay() }
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { lay() } }
    @objc private func back() { lay() }
    private func lay() {
        let room = bounds.width, h = bounds.height, w = textWidth
        guard 1 < room, 1 < h else { return }
        let runs = room + 1 < w
        let key = [first.text ?? "", String(Int(w)), String(Int(room)), String(Int(h)), String(centred)].joined(separator: "/")
        let standing = !runs ? true : strip.layer.animation(forKey: "run") != nil
        if key == laid, standing { return }
        laid = key
        strip.layer.removeAnimation(forKey: "run")
        let lh = ceil(first.font.lineHeight), y = ((h - lh) / 2).rounded()
        second.isHidden = !runs
        guard runs else {
            let x = centred ? ((room - w) / 2).rounded() : 0
            first.frame = CGRect(x: max(0, x), y: y, width: min(w, room), height: lh)
            strip.frame = bounds
            return
        }
        let travel = w + Self.gap
        first.frame = CGRect(x: 0, y: y, width: w, height: lh)
        second.frame = CGRect(x: travel, y: y, width: w, height: lh)
        strip.frame = CGRect(x: 0, y: 0, width: travel + w, height: h)
        let pass = Double(travel / Self.pace)
        let whole = Self.wait + pass + Self.rest
        let end = (Self.wait + pass) / whole
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, 0, -travel, 0, 0] as [CGFloat]
        a.keyTimes = [0, Self.wait / whole, end, end, 1].map { NSNumber(value: $0) }
        a.duration = whole
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        strip.layer.add(a, forKey: "run")
        MontanaP2PTrace.markFolded("marquee", "laid w=\(Int(w)) room=\(Int(room)) pass_ms=\(Int(pass * 1000)) by=render-server", window: 60)
    }
}

// ════════════════════════════════════════════════════════════
// THE WEB SEARCH FOR A MUSIC FILE, INSIDE THE APP (15.44). The system web view shows the
// results for «<name> mp3»; a file the person opens is never handed to a browser — the same
// view downloads it into Saved Messages, and the player plays it at once.
// ════════════════════════════════════════════════════════════
struct MontanaWebSearchSheet: View {
    let query: String
    var save: (Data, String) -> String?
    var onSaved: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    static func searchURL(_ q: String) -> URL? {
        let e = (q + " mp3").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://duckduckgo.com/?q=" + e)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let u = Self.searchURL(query) {
                    MontanaWebView(url: u, save: save, onSaved: onSaved, onDownloading: { saving = $0 })
                        .ignoresSafeArea(edges: .bottom)
                }
                if saving {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Saving to Saved Messages…").foregroundColor(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(white: 0.15), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { MontanaDoneMark { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MontanaWebView: UIViewRepresentable {
    let url: URL
    var save: (Data, String) -> String?
    var onSaved: (String) -> Void
    var onDownloading: (Bool) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.navigationDelegate = context.coordinator
        w.isOpaque = false
        w.backgroundColor = .black
        w.load(URLRequest(url: url))   // SERVER-DEBT-ACK: the page the PERSON opened with their own hands in the music page's browser — no road of ours, no word of Montana on it
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) { context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        var parent: MontanaWebView
        private var pending: [ObjectIdentifier: (URL, String)] = [:]
        init(_ p: MontanaWebView) { parent = p }

        // An audio body, or a file the view cannot show that carries a music name, becomes a
        // download of ours; anything else the page shows as a page.
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let mime = navigationResponse.response.mimeType ?? ""
            let name = navigationResponse.response.suggestedFilename ?? navigationResponse.response.url?.lastPathComponent ?? ""
            if mime.hasPrefix("audio/") || (!navigationResponse.canShowMIMEType && mtIsAudioName(name)) {
                decisionHandler(.download); return
            }
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("wdl_\(UUID().uuidString)_" + suggestedFilename)
            pending[ObjectIdentifier(download)] = (dst, suggestedFilename)
            parent.onDownloading(true)
            MontanaP2PTrace.mark("music_web", "download start")
            completionHandler(dst)
        }
        func downloadDidFinish(_ download: WKDownload) {
            parent.onDownloading(false)
            guard let (dst, name) = pending.removeValue(forKey: ObjectIdentifier(download)),
                  let data = try? Data(contentsOf: dst) else { return }
            try? FileManager.default.removeItem(at: dst)
            if let stored = parent.save(data, name) {
                MontanaP2PTrace.mark("music_web", "saved bytes=\(data.count)")
                parent.onSaved(stored)
            }
        }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            parent.onDownloading(false)
            pending.removeValue(forKey: ObjectIdentifier(download))
            MontanaP2PTrace.mark("music_web", "download FAIL")
        }
    }
}

/// A web page inside the app (15.49): a shared link opens here, never in another app.
struct MontanaWebPageSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            MontanaWebView(url: url, save: { _, _ in nil }, onSaved: { _ in }, onDownloading: { _ in })
                .ignoresSafeArea(edges: .bottom)
                // USER-DATA: the page's host as the title.
                .navigationTitle(Text(verbatim: url.host ?? "")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { MontanaDoneMark { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

/// ONE ROW OF A TRACK, ONE OWNER (the author's word 01.10 00:06: «under the big player the same list as on the music page, by one
/// function with one owner»; T1 on 2049: one fling of the big player's playlist ran its row 953 times -- each row watched the
/// whole store of readings and the player's face and drew itself again at every reading, and the music page scrolls the same
/// 672 tracks at 72-76 frames a second). The music page and the big player's playlist draw a track by this one face -- the
/// mini's form standing still -- and tell their list that it changed by this one print. The row is a value and watches nothing:
/// the page that holds the list watches the readings and the face once, and the list reconfigures only the rows whose print moved.
enum MTTrackRow {
    /// The print's fields in its order, for the diary.
    static let printNames = ["id", "title", "length", "standing", "playing", "bringing", "local"]
    @MainActor static func print(_ id: String, _ t: MusicTrack?) -> [Int] {
        func p<T: Hashable>(_ v: T) -> Int { var h = Hasher(); h.combine(v); return h.finalize() }
        guard let t else { return [p(id)] }
        let m = MTTrackMeta.shared.of(t.file), now = MTNowPlaying.shared
        return [p(id), p(m?.title ?? t.title), p(Int(m?.length ?? -1)), p(now.file == t.file),
                p(now.file == t.file && now.playing), p(MTMusicFolders.shared.fetching == t.file), p(MTMusicFolders.local(t.file))]
    }
    /// THE ROW IS THE MINI'S FACE (the author's word 24.09: «all the music's rows in the mini player's form»): its play, its name
    /// in the plate, its length at the plate's end; the track that plays wears the thin blue ring (29.09). The list's selection
    /// takes the touch, so nothing inside answers.
    @MainActor static func face(_ t: MusicTrack) -> some View {
        let m = MTTrackMeta.shared.of(t.file), now = MTNowPlaying.shared
        let length = m?.length ?? 0
        let playing = now.file == t.file
        // USER-DATA: the track's own name (its tag's, or its file's) and its length, digits.
        return MTMiniFace(paused: !(playing && now.playing), title: m?.title ?? (t.title as NSString).deletingPathExtension, runs: false, live: 0,
                          side: { _ in 0 < length ? fmtDuration(length) : "" },
                          onPlay: {}, onSeek: { _ in }, onSide: {}, onOpen: {},
                          busy: MTMusicFolders.shared.fetching == t.file, cloud: !MTMusicFolders.local(t.file),
                          ring: playing ? MTMiniFace.playingRing : nil)
            .allowsHitTesting(false)
            .onAppear { MTTrackMeta.shared.load(t.file) }
    }
}

/// The last plate while words are typed (15.44): the words handed to the system's own web search, in the plates' own measure.
struct MTWebPlate: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.24))
                Image(systemName: "globe").font(.system(size: 16, weight: .medium)).foregroundColor(.secondary)
            }
            .frame(width: 38, height: 38)
            Text("Search the web").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(MTGlassCardPlate(cornerRadius: 24))
    }
}

// ════════════════════════════════════════════════════════════
// THE MUSIC PAGE UNDER THE BAR (the author's word 23.09): the music is a page as the calls are — the
// app's tracks in rows of the calls' size and manner, running on to the screen's edges; the mini player
// at the bottom as on the chats and the logo untouched (the author's word 24.09); a plus at the bottom
// right that pours a folder's music in.
// ════════════════════════════════════════════════════════════

/// WHAT PLAYS, AND ONLY THAT (23.09): the music page and its rows watch which track stands in the
/// player and whether it plays — never the player's clock, which ticks four times a second (the critic 22.09, the law
/// of MontanaPlayerBar.Gate). Three of the player's own published words, and nothing else.
final class MTNowPlaying: ObservableObject {
    static let shared = MTNowPlaying()
    @Published private(set) var file: String?   // the track in the player — a voice or a note is not a track
    @Published private(set) var playing = false
    private var bag = Set<AnyCancellable>()
    private init() {
        let p = VoicePlayer.shared
        p.$playingFile.combineLatest(p.$isVoice, p.$paused)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] f, voice, paused in
                guard let self else { return }
                let now = voice ? nil : f
                let on = now != nil && !paused
                if now != self.file { self.file = now }
                if on != self.playing { self.playing = on }
            }
            .store(in: &bag)
    }
}

/// WHAT A TRACK CARRIES ITSELF (the author's word 23.09: «the music file's cover, when it has one»): its cover, its
/// name, its artist and its length — read from the file's own tags by the platform (AVURLAsset), off the main thread,
/// once per file and kept for the session; the covers in the platform's own cache, which lets them go when memory is
/// short (a cover let go is read again when a row asks). The pages are drawn again when a reading lands (rev).
@MainActor final class MTTrackMeta: ObservableObject {
    static let shared = MTTrackMeta()
    /// sawArt: the track's folder picture was known at the reading (MTMusicFolders.art) — a picture found since reads it again.
    struct Meta { var title: String?; var artist: String?; var length: Double; var hasCover: Bool; var sawArt = false }
    @Published private(set) var rev = 0
    /// THE PAGE TURNS ONCE FOR A VOLLEY OF READINGS (25.09, T1's diary of 1938: every reading turned the music page, its 674
    /// rows read anew for their prints each time — dozens of turns a minute, thirty-five to sixty-five milliseconds each,
    /// forty-five frames a second under the finger). The readings land as they come; the page turns once, a third of a
    /// second after the first of them. One pending turn, never a timer.
    private var turnDue = false
    private func turnSoon() {
        guard !turnDue else { return }
        turnDue = true
        Task { @MainActor [self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.turnDue = false
            self.rev &+= 1
        }
    }
    private var kept: [String: Meta] = [:]
    private var asking = Set<String>()
    private let covers: NSCache<NSString, UIImage> = MontanaCaches.kept("music-covers", count: 240)
    private init() {}
    func of(_ file: String) -> Meta? { kept[file] }
    /// THE LINE UNDER A TRACK'S NAME, ONE OWNER (the author's word 29.09 ~23:20): the artist the file's own tags name, once read;
    /// nil -- nothing is said. Where the track lies is never said (MusicTrack.inPost).
    func byline(_ file: String) -> String? { kept[file]?.artist }
    func cover(_ file: String) -> UIImage? { covers.object(forKey: file as NSString) }
    func load(_ file: String) {
        guard !file.isEmpty, !asking.contains(file) else { return }
        // A lent track the shelf does not know yet (its folder not opened this launch) is not read: its path would be the
        // app's own empty folder, and that empty answer would be kept for the session (the critic 24.09).
        guard !MTMusicFolders.isLent(file) || MTMusicFolders.url(file) != nil else { return }
        let art = MTMusicFolders.art(file)
        // Read once — again only when its cover was let go from memory, or when its folder's picture was found since.
        if let m = kept[file], m.hasCover ? covers.object(forKey: file as NSString) != nil : (m.sawArt || art == nil) { return }
        asking.insert(file)
        let url = attachmentURL(file)
        Task.detached(priority: .utility) {
            // A lent track whose bytes its keeper holds is not read for its tags: the read would fetch it whole — and the
            // file is asked here, off the main thread (the critic 24.09: every row's appearance asked the disk there).
            if MTMusicFolders.needsFetch(file) {
                await MainActor.run { _ = MTTrackMeta.shared.asking.remove(file) }
                return
            }
            let (m, img, folder) = await MTTrackMeta.read(url, art: art)
            await MainActor.run {
                let s = MTTrackMeta.shared
                s.asking.remove(file)
                s.kept[file] = m
                if let img { s.covers.setObject(img, forKey: file as NSString) }
                s.turnSoon()
                VoicePlayer.shared.readingLanded(file)   // the track that plays takes its cover on the lock screen at once
                // What the readings found, counted by the file's kind and never named (the covers of 24.09: a row with its
                // length alone could not tell a FLAC read past its tags from a file that carries none).
                let kind = (file as NSString).pathExtension.lowercased()
                let from = folder ? "folder" : (img != nil ? "file" : "none")
                let found = "tags=\(m.title != nil || m.artist != nil ? 1 : 0) cover=\(img != nil ? 1 : 0) from=\(from) length=\(m.length > 0 ? 1 : 0)"
                MontanaP2PTrace.markFolded("music_meta", "kind=\(kind) " + found, key: kind + found)
            }
        }
    }
    /// A COVER IS A PEER'S FILE LIKE ANY OTHER (the critic 24.09): the library holds the tracks of every correspondent, so a
    /// cover past this size is not drawn, and a cover is never decoded whole — the platform's image source draws it down.
    nonisolated private static let coverCap = 32 * 1_048_576
    nonisolated private static func thumb(_ d: Data, side: Int = rowSide) -> UIImage? {
        CGImageSourceCreateWithData(d as CFData, nil).flatMap { drawn($0, side: side) }
    }
    /// A picture file drawn as a cover: its bytes on the phone (a keeper's placeholder is not fetched for a row), never
    /// past the cap, never decoded whole.
    nonisolated private static func picture(at url: URL, side: Int = rowSide) -> UIImage? {
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey]),
              let size = v.fileSize, size <= coverCap, 0 < (v.fileAllocatedSize ?? 0) else { return nil }
        return CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { drawn($0, side: side) }
    }
    /// A row's cover: 58 points at three pixels a point. The lock screen's: its own measure (wholeCover).
    nonisolated static let rowSide = 174
    nonisolated static let lockSide = 1024
    /// THE LOCK SCREEN'S COVER, WHOLE (the author's picture 30.09 00:41: the album's cover stood small and soft in a wide card, the
    /// colour of its edge in bars at its sides): the lock screen was handed the row's reading, drawn down to 174 pixels, and the
    /// platform shows a picture that small as a small one in a card. The cover of the one track that plays is read again at the
    /// lock screen's measure, off the main thread -- the file's own picture, else its folder's -- and never kept in the rows' cache.
    nonisolated static func wholeCover(_ file: String) async -> UIImage? {
        let a = AVURLAsset(url: attachmentURL(file))
        for it in (try? await a.load(.metadata)) ?? [] where it.commonKey == .commonKeyArtwork {
            if let d = try? await it.load(.dataValue), d.count <= coverCap, let img = thumb(d, side: lockSide) { return img }
        }
        return MTMusicFolders.art(file).flatMap { picture(at: $0, side: lockSide) }
    }
    nonisolated private static func drawn(_ src: CGImageSource, side: Int) -> UIImage? {
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: side,
                                     kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
    /// The tags, by the platform; the cover drawn down to the size a row shows (58 points at three pixels a point).
    /// THE FILE'S WHOLE LIST, NOT THE COMMON ONE (the author's word 24.09: «the covers are in the files, and another
    /// music app shows them»): the platform names a FLAC's own comments — its TITLE, its ARTIST, its PICTURE block — by
    /// the common keys, yet leaves them out of its common list (measured 24.09 on a FLAC carrying all three: the common
    /// list empty, the whole list six items, those three under the title, artist and artwork keys); ID3, iTunes and
    /// the rest name the same items in both lists. A FLAC's picture marked other than the front cover is not handed.
    /// THE FOLDER'S PICTURE WHEN THE FILE CARRIES NONE (the author's word 24.09: «the covers are there, and another music
    /// app shows them locally»). T1 under 1919: 545 of the lent mp3 read with no tag and no cover — and the six of them
    /// that also lie in T1's chats carry, byte for byte, one small tag with the converter's name and nothing else. The
    /// cover of such a collection stands beside its tracks, a picture in the album's folder, where music players have long
    /// looked for it (MTMusicFolders.cover): drawn when the file has none. true in the third place: the cover is the folder's.
    nonisolated private static func read(_ url: URL, art: URL?) async -> (Meta, UIImage?, Bool) {
        let a = AVURLAsset(url: url)
        let len = (try? await a.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        let items = (try? await a.load(.metadata)) ?? []
        var title: String? = nil, artist: String? = nil, img: UIImage? = nil
        for it in items {
            if it.commonKey == .commonKeyArtwork, img == nil, let d = try? await it.load(.dataValue), d.count <= coverCap {
                img = thumb(d)
            } else if it.commonKey == .commonKeyTitle, title == nil {
                title = (try? await it.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if it.commonKey == .commonKeyArtist, artist == nil {
                artist = (try? await it.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        var folder = false
        if img == nil, let art { img = picture(at: art); folder = img != nil }
        return (Meta(title: title?.isEmpty == false ? title : nil, artist: artist?.isEmpty == false ? artist : nil,
                     length: len.isFinite && len > 0 ? len : 0, hasCover: img != nil, sawArt: art != nil), img, folder)
    }
}

/// THE APP'S ICON AT A COVER'S SIZE, MADE ONCE (the author's word 30.09 ~00:55: «check that our placeholders weigh nothing»). T1's
/// diary under 2017: the big player's playlist of 687 tracks scrolled at 32 to 60 frames a second with frames of 300 to 730 ms
/// (feed_fps what=player), where the music page, drawing no picture, stood at 66 to 75 -- and every row without a cover of its own
/// drew the icon's whole picture, 1024 pixels a side, into its 38 points. The icon drawn down once to a row's pixels
/// (MTTrackMeta.rowSide, the covers' own) and kept decoded is what a row and the plate draw; the lock screen keeps its whole icon
/// (lockIcon).
extension MTMusicArt {
    static let thumb: UIImage? = icon?.preparingThumbnail(of: CGSize(width: MTTrackMeta.rowSide, height: MTTrackMeta.rowSide))
}

/// A TRACK'S FACE (23.09): its cover in the rim the calls' faces wear; a track without one wears the note.
struct MTTrackCover: View {
    let image: UIImage?
    let side: CGFloat
    var body: some View {
        MontanaHexagon().fill(Color(white: 0.15))
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: "music.note").font(.system(size: side * 0.38)).foregroundColor(.gray) }
            }
            .clipShape(MontanaHexagon())
            .overlay(MontanaHexagon().stroke(Color.white.opacity(0.45), lineWidth: 1))
            .frame(width: side, height: side)
    }
}

/// THE MUSIC PAGE: every track a row in the mini's form; the track that plays wears the thin blue ring, and the one floating
/// player of the pages stands at the bottom over the rows, as on the chats and the feed (the author's word 29.09: «the mini
/// player there must come up, our native one, and everything pinned at the bottom as on every page»).
struct MusicTabView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(UIState.self) private var ui
    @ObservedObject private var now = MTNowPlaying.shared
    @ObservedObject private var meta = MTTrackMeta.shared
    @ObservedObject private var folders = MTMusicFolders.shared
    @Environment(\.mtPaneLive) private var paneLive
    @ObservedObject private var placeAsk = MTMusicFocus.shared   // the unfolded mini's number: this page's row to the middle
    let panel: MontanaTimePanel
    /// THE PAGE'S OWN SEARCH (the author's word 24.09: «the search on the music page searches only the music of this
    /// page, beautifully and natively»): the word at the head narrows the list itself — by the track's name, its tag's
    /// name and artist, and where it lies — in the platform's own comparison (localizedStandardContains: letter case
    /// and marks aside, as the system's search compares). No results stand over the rows, and nothing leaves the phone.
    var query = ""
    var reserve: CGFloat = 0   // the floating player's room at the rows' bottom (MontanaChatsList.playerReserve)
    @State private var pickFolder = false
    /// NEWEST FIRST, AS THE CALLS (the critic 24.09): a folder lent last stands at the top where the person looks, in its
    /// own order, and the queue a tap starts is this very order — the next track is the row below.
    private var tracks: [MusicTrack] {
        let all = Array(store.musicLibrary().reversed())
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter { t in
            let m = meta.of(t.file)
            return [t.title, m?.title ?? "", m?.artist ?? "", place(t)].contains { $0.localizedStandardContains(q) }
        }
    }
    private func rows(_ list: [MusicTrack]) -> [Chat] {
        list.map(\.listRow)
    }
    private func track(_ c: Chat) -> MusicTrack? { store.musicTrack(c.name) }
    /// Where the track lies, said when its tags name no artist: its chat as it is named now, or its lent folder's path.
    private func place(_ t: MusicTrack) -> String { MTMusicFolders.isLent(t.file) ? t.chatTitle : store.displayName(for: t.chat) }
    /// The track row's one print (MTTrackRow): the player's clock never invalidates the list.
    private func rowPrint(_ c: Chat) -> [Int] { MTTrackRow.print(c.id, track(c)) }
    /// THE ROW IS THE MINI'S FACE (the author's word 24.09: «all the music's rows in the mini player's form»; «the same
    /// space between the tracks' rows as between the mini player and the message field»; «no dividing lines between the
    /// tracks»). Every track wears the face standing still — its play, its name in the plate, its length at the plate's
    /// end — and the whole row is ONE target, the list's own selection: a touch anywhere on it plays it, a touch on the
    /// playing one rests it or plays it on, and nothing inside answers a second time (a bring started twice lets itself
    /// go). The track that plays wears the thin blue ring (29.09); the one player with its controls is the bar below. No
    /// cover and no second line: the mini has neither.
    @ViewBuilder private func cell(_ c: Chat) -> some View {
        if let t = track(c) { MTTrackRow.face(t) }   // the list's selection takes the touch: play(c)
    }
    /// A tap on a row: the track plays with the list as the queue; a second tap on a track its keeper is bringing lets the
    /// bring go; on the standing row, outside its play and its plate, it rests the track or plays it on.
    private func play(_ c: Chat) {
        guard let t = track(c) else { return }
        let p = VoicePlayer.shared
        if folders.fetching == t.file { folders.letGo(); return }
        if now.file == t.file {
            // THE WHOLE ROW IS THE BUTTON (the critic 24.09, the role's rule): a touch on the playing row outside its play
            // and its plate — those answer it themselves — rests the track or plays it on, as the row did before it wore
            // the mini.
            if p.paused { p.resume() } else { p.pause() }
            MontanaP2PTrace.mark("music_tab", "tap \(p.paused ? "rest" : "on")")
            return
        }
        let lib = tracks
        guard let i = lib.firstIndex(where: { $0.file == t.file }) else { return }
        p.queue = lib
        p.play(index: i)
    }
    var body: some View {
        let _ = MTFrameMeter.shared.body("music")   // the page's passes while a motion is measured
        let shown = tracks   // one pass of the search per pass of the page
        ZStack(alignment: .top) {
            MontanaTimePanelList(panel: panel, rows: rows(shown), fingerprint: rowPrint,
                                 swipeLeading: { _ in [] }, swipeTrailing: { _ in [] },
                                 swipesEnabled: false,
                                 onOpen: play,   // the whole row is the button: a still track plays, the playing one rests or plays on
                                 rowContent: { AnyView(cell($0).environmentObject(store).environment(ui)) },
                                 bottomReserve: reserve,   // the floating player's room, as the chats page reserves it
                                 page: "music", fieldNames: MTTrackRow.printNames,
                                 numbered: true,   // the bar at the right while it scrolls, the track's number beside it (the author's word 24.09)
                                 focus: placeAsk.ask)
                .environment(\.mtPaneLive, paneLive)
            if shown.isEmpty {
                Group {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("Your music will appear here") }
                    else { Text("Nothing found") }
                }
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // THE PLUS, bottom right (the author's word 23.09: «a plus at the bottom right to choose a folder on the phone to
        // load the music from»; 24.09: «the chosen folders are not added to Saved Messages — access is only given, so that
        // it reads from there locally»): the chats page's compose button one to one — the plate, the size, the line
        // between the last two rows; while a folder just picked is walked it turns, the platform's own spinner.
        .mtPageAction(reserve: reserve) {
            Button { pickFolder = true } label: {
                if folders.walking { ProgressView().tint(MontanaOctagon.barGlyph) }
                else { Image(systemName: "plus").font(.system(size: 27, weight: .medium)).foregroundColor(MontanaOctagon.barGlyph) }
            }
            .buttonStyle(.montanaOctagon(square: true, bar: true))
        }
        // The folder is the platform's own pick (the document picker); the permission it hands over is kept (MTMusicFolders).
        .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): folders.lend(url)
            case .failure(let e): MontanaP2PTrace.mark("music_lent", "pick refused code=\((e as NSError).code)")
            }
        }
        // The keeper's word on a track it did not bring — the platform's own alert.
        .alert("Could not open the track",
               isPresented: Binding(get: { folders.refusal != nil }, set: { if !$0 { folders.refusal = nil } }),
               presenting: folders.refusal) { _ in
            Button("OK", role: .cancel) {}
        } message: { r in
            Text(r.words)
        }
        // AT EVERY OPENING OF THE PAGE (the walk's law), by the pane's choice: the page stands built in the row before it is
        // looked at (25.09), so its appearance is not its opening.
        .onChange(of: ui.pane, initial: true) { _, p in
            guard p == .music else { return }
            folders.walk()   // what was put into the lent folders since comes in
            MontanaP2PTrace.mark("music_tab", "rows=\(tracks.count) playing=\(now.playing ? 1 : 0)")
        }
    }
}

/// THE FOLDERS LENT TO THE MUSIC (the author's word 24.09: «the folders chosen by the plus are not added to Saved
/// Messages — access is only given, so that it reads from there locally»). The plus LENDS a folder: the platform's own
/// permission for it is kept — the security-scoped URL the document picker hands over, saved as a minimal bookmark in
/// this device's keychain, where it joins no second phone and no copy. Apple, «Providing access to directories»: the URL
/// «lets your app recursively access the directory and all of its contents, which includes accessing any new items you
/// add to the directory in the future». Every music file under the folder, at any depth, stands on the page read from
/// where it lies: nothing is copied, nothing enters a chat, and a file put into the folder later comes in with the next
/// walk (every opening of the page). A lent track is named by its folder and its path — lent-<folder>-<the path's
/// digest>.<kind> — and attachmentURL, the one ladder of where a file lives, answers it with the file in its folder.
/// A FILE WHOSE BYTES ARE NOT ON THE PHONE IS NOT OPENED UNASKED: its keeper (iCloud, or another) holds them, and any
/// read — a cover, a length, a play — would fetch the file whole, on whatever network the phone is on. It stands with
/// the platform's cloud; a play of it asks the keeper for it — iCloud's own download, then a coordinated read that waits
/// for the file — the row turning meanwhile; a refusal is told in the keeper's words as their one reader reads them
/// (MontanaBackup.verdict). The diary counts; it never names a folder or a track.
@MainActor final class MTMusicFolders: ObservableObject {
    static let shared = MTMusicFolders()
    @Published private(set) var rev = 0               // a walk found something new, or a track arrived: the page draws again
    @Published private(set) var walking = false       // the plus turns while a folder just picked is walked — never at a page's own walk
    @Published private(set) var fetching: String?     // the track its keeper is bringing for a play
    /// The keeper's word on a track it did not bring, as the person is told it.
    struct Refusal: Identifiable { let id = UUID(); let words: LocalizedStringKey }
    @Published var refusal: Refusal?
    private var walks = 0                             // walks asked and not landed
    private var lends = 0                             // of them, the walks of a folder just picked
    private var waiting = false                       // a walk the person waits on: nothing of the lent folders stands yet
    private var lastWalked: TimeInterval = -1_000     // when the last walk landed, by the system's uptime
    private var holding: UIBackgroundTaskIdentifier = .invalid   // the system's leave to finish a walk the person left

    /// A lent folder as this device keeps it: its name here, the platform's permission for it, the moment it was lent.
    private struct Lent: Codable { let id: String; var bookmark: Data; let at: Double }
    /// A track as the last walk found it: where it lies, whether its bytes are on the phone, its size, whether iCloud keeps it.
    private struct Found { let url: URL; var local: Bool; let size: Int; let icloud: Bool; let art: URL? }
    /// A music file met by a walk, before it is named; art — its folder's picture, by its path under the lent folder.
    private struct Walked { let url: URL; let title: String; let rel: String; let place: String; let local: Bool; let size: Int; let icloud: Bool; let art: String? }
    nonisolated static let mark = "lent-"
    nonisolated private static let keychainKey = "musicFolders"
    nonisolated private static let probe: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .fileAllocatedSizeKey,
                                                                  .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
    // What the last walk found, asked from every thread (attachmentURL is asked everywhere): one lock, nothing else under it.
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var found: [String: Found] = [:]
    nonisolated(unsafe) private static var shelf: (rev: Int, list: [MusicTrack]) = (0, [])
    nonisolated(unsafe) private static var woke = false
    nonisolated(unsafe) private static var inFlight: NSFileCoordinator?
    // The folders and the access this launch holds, touched on the walk's queue only; a bring runs on a queue of its own.
    nonisolated private static let queue = DispatchQueue(label: "quest.montana.music-folders", qos: .utility)
    nonisolated private static let bringQueue = DispatchQueue(label: "quest.montana.music-bring", qos: .userInitiated)
    nonisolated(unsafe) private static var lent: [Lent]?
    nonisolated(unsafe) private static var opened: [String: URL] = [:]
    nonisolated(unsafe) private static var laid = false   // a list stands this launch, laid from the kept one or walked
    nonisolated(unsafe) private static var lastKept: [Kept] = []          // the kept list as the queue last knew it
    nonisolated(unsafe) private static var enumSpent: TimeInterval = 0    // the walk's time inside the enumerator itself
    nonisolated(unsafe) private static var entries = 0                    // the entries the enumerator gave, of every kind
    // Under the lock: the folders picked and not yet kept, the tracks a bring put on the phone while a walk read.
    nonisolated(unsafe) private static var picks: [URL] = []
    nonisolated(unsafe) private static var broughtDuring = Set<String>()
    /// A track of the last walk as the phone keeps it between launches: its folder, its path there, what the walk read.
    private struct Kept: Codable {
        let folder: String; let rel: String; let title: String; let place: String; let at: Double
        let local: Bool; let size: Int; let icloud: Bool
        let art: String?   // absent in a list kept before the folders' pictures were read: none, until the walk
    }
    /// Where the last walk's list waits for the next launch: this device's own, as the permission it was read under.
    nonisolated private static let keptURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MontanaMusic", isDirectory: true)
        .appendingPathComponent("shelf.json")

    nonisolated static func isLent(_ file: String) -> Bool { file.hasPrefix(mark) }
    /// Where a lent track lies: attachmentURL's answer for it.
    nonisolated static func url(_ file: String) -> URL? {
        guard isLent(file) else { return nil }
        lock.lock(); let u = found[file]?.url; lock.unlock()
        return u
    }
    /// A lent track's size as the walk read it: the library's sameness asks no disk for it.
    nonisolated static func size(_ file: String) -> Int? {
        guard isLent(file) else { return nil }
        lock.lock(); let s = found[file]?.size; lock.unlock()
        return s
    }
    /// The picture of a lent track's folder, when the folder holds one: the cover of a file that carries none (MTTrackMeta).
    nonisolated static func art(_ file: String) -> URL? {
        guard isLent(file) else { return nil }
        lock.lock(); let a = found[file]?.art; lock.unlock()
        return a
    }
    /// The walk's word on whether the track's bytes are on the phone — the row's cloud; a play asks the file (needsFetch).
    nonisolated static func local(_ file: String) -> Bool {
        guard isLent(file) else { return true }
        lock.lock(); let l = found[file]?.local ?? true; lock.unlock()
        return l
    }
    /// The lent tracks in the library's order, with their revision; the first ask of a launch walks the folders.
    nonisolated static func tracks() -> (rev: Int, list: [MusicTrack]) {
        lock.lock()
        let s = shelf, first = !woke
        woke = true
        lock.unlock()
        if first {
            let asked = ProcessInfo.processInfo.systemUptime
            queue.async { layKept(asked: asked) }   // the last list first, when the launch has not laid it yet
            DispatchQueue.main.async { MainActor.assumeIsolated { MTMusicFolders.shared.walk() } }
        }
        return s
    }
    /// THE LAST LIST STANDS AT THE LAUNCH (the author's word 24.09: «after the update the tracks I had already given
    /// access to through the plus were gone — a gross violation; they came only a while after I opened the page»). A walk
    /// of a large folder takes half a minute (T1 under 1917: 677 files in 32 to 34 seconds), and until it landed the page
    /// stood without the lent folders. The list the last walk found is kept on the phone and laid at the launch, before
    /// any page asks, under the folders opened for this launch; the walk that follows refreshes it.
    nonisolated static func lay() { let asked = ProcessInfo.processInfo.systemUptime; queue.async { layKept(asked: asked) } }
    nonisolated private static func bare() -> Bool { lock.lock(); let b = shelf.list.isEmpty; lock.unlock(); return b }
    /// Whether opening the track now would fetch it — asked of the file itself at the moment of the play: its keeper may
    /// have taken the bytes back since the walk, or the person may have brought them in the Files app.
    nonisolated static func needsFetch(_ file: String) -> Bool {
        guard let u = url(file) else { return false }
        guard let v = try? u.resourceValues(forKeys: probe) else { return true }   // the older iCloud's placeholder: not here yet
        return !onPhone(v)
    }
    /// The player's ask (VoicePlayer runs on the main thread, not on the main actor): the bring, on the main actor.
    nonisolated static func bring(_ file: String, then: @escaping () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { MTMusicFolders.shared.fetch(file, then: then) } }
    }
    /// The bytes are on the phone: a local file, or the keeper's copy brought — not a placeholder of one the keeper holds
    /// (iCloud names it «not downloaded»; any keeper's placeholder has a size and nothing allocated for it).
    nonisolated private static func onPhone(_ v: URLResourceValues) -> Bool {
        if v.isUbiquitousItem == true, v.ubiquitousItemDownloadingStatus == .notDownloaded { return false }
        return !(0 < (v.fileSize ?? 0) && v.fileAllocatedSize == 0)
    }

    /// The lent folders walked again — every opening of the page and the first ask of a launch: what was put into them
    /// since comes in, what left goes; the page draws again only when the walk found something different.
    func walk(waited: Bool = false) {
        // A walk the person waits on turns the plus until it lands — the one sign that the lent folders are being read.
        if waited, Self.bare() { waiting = true; walking = true }
        guard walks == 0 else { return }
        // A PAGE OPENED AGAIN SOON DOES NOT WALK AGAIN (the critic 24.09: every opening of the tab read the folders whole,
        // 18 to 34 seconds of reading): the kept list stands, and within two minutes of the last walk nothing is asked.
        guard waited || Self.bare() || 120 < ProcessInfo.processInfo.systemUptime - lastWalked else { return }
        walks += 1
        hold()
        // With the lent folders standing the walk refreshes them quietly; with nothing standing the person waits on it.
        Self.queue.async(qos: Self.bare() ? .userInitiated : .utility, flags: .enforceQoS) { Self.walkAll(lend: false) }
    }
    /// The plus's pick: the folder is lent — its permission kept for the launches to come — and walked with the others.
    /// Only this walk turns the plus: a page's own walk at every opening is quiet, or the plus would blink each time.
    func lend(_ picked: URL) {
        walks += 1; lends += 1; walking = true
        hold()
        // THE PICK IS KEPT AT ONCE (the critic 24.09: a pick waited behind a page's walk of half a minute, and a launch
        // ended meanwhile lost it): a walk under way keeps it between its entries; the lend's own walk follows.
        Self.lock.lock(); Self.picks.append(picked); Self.lock.unlock()
        Self.queue.async(qos: .userInitiated, flags: .enforceQoS) {   // the person waits on the plus
            Self.keepPicks()
            Self.walkAll(lend: true)
        }
    }
    private func walked(changed: Bool, lend: Bool) {
        walks = max(0, walks - 1)
        if lend { lends = max(0, lends - 1) }
        if walks == 0 { waiting = false; lastWalked = ProcessInfo.processInfo.systemUptime; unhold() }
        walking = 0 < lends || waiting
        if changed { rev &+= 1 }
    }
    /// THE SYSTEM'S LEAVE TO FINISH A WALK (the critic 24.09: a walk the person left was cut when the app slept, and nothing
    /// was kept): the platform's own background task, ended when the walks land or when the system asks for it back.
    private func hold() {
        guard holding == .invalid else { return }
        holding = UIApplication.shared.beginBackgroundTask(withName: "music-walk") { [weak self] in
            MainActor.assumeIsolated { self?.unhold() }
        }
    }
    private func unhold() {
        guard holding != .invalid else { return }
        UIApplication.shared.endBackgroundTask(holding)
        holding = .invalid
    }
    /// The person's play of a track whose bytes its keeper holds: the keeper is asked for it — iCloud's own download (the
    /// SDK: «Use startDownloadingUbiquitousItemAtURL:error: to download it»), then a coordinated read that waits for the
    /// file to be here — and the play follows when it is. One bring at a time: a play of another lets the one in flight go.
    func fetch(_ file: String, then: @escaping () -> Void) {
        guard let url = Self.url(file), fetching != file else { return }
        letGo()
        fetching = file
        Self.lock.lock(); let icloud = Self.found[file]?.icloud ?? false; Self.lock.unlock()
        MontanaP2PTrace.mark("music_bring", "begin icloud=\(icloud ? 1 : 0)")
        let t0 = Date()
        Self.bringQueue.async {
            if icloud { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
            let c = NSFileCoordinator(filePresenter: nil)
            Self.lock.lock(); Self.inFlight = c; Self.lock.unlock()
            var error: NSError?
            var here = false
            c.coordinate(readingItemAt: url, options: [.withoutChanges], error: &error) { u in
                here = (try? u.resourceValues(forKeys: Self.probe)).map(Self.onPhone) ?? false
            }
            Self.lock.lock(); if Self.inFlight === c { Self.inFlight = nil }; Self.lock.unlock()
            let secs = Int(Date().timeIntervalSince(t0))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { MTMusicFolders.shared.fetched(file, here: here, icloud: icloud, error: error, secs: secs, then: then) }
            }
        }
    }
    /// A second tap on the turning row, or a play of another track: the bring in flight is let go.
    func letGo() {
        Self.lock.lock(); let c = Self.inFlight; Self.lock.unlock()
        c?.cancel()
        fetching = nil
    }
    private func fetched(_ file: String, here: Bool, icloud: Bool, error: NSError?, secs: Int, then: () -> Void) {
        if fetching == file { fetching = nil }
        if here, error == nil {
            Self.lock.lock(); Self.found[file]?.local = true; Self.broughtDuring.insert(file); Self.lock.unlock()
            rev &+= 1
            MTTrackMeta.shared.load(file)
            MontanaP2PTrace.mark("music_bring", "here secs=\(secs)")
            then()
            return
        }
        if let e = error, e.domain == NSCocoaErrorDomain, e.code == NSUserCancelledError {
            MontanaP2PTrace.mark("music_bring", "let go secs=\(secs)")
            return
        }
        let v = error.map(MontanaBackup.verdict) ?? .refused
        MontanaP2PTrace.mark("music_bring", "refused \(error?.domain ?? "none") \(error?.code ?? 0) verdict=\(v) icloud=\(icloud ? 1 : 0) secs=\(secs)")
        refusal = Refusal(words: Self.words(v, icloud: icloud))
    }
    /// The keeper's word, told as it is: a wait is a wait, not a refusal; iCloud is named only when iCloud keeps the file.
    private static func words(_ v: MontanaBackup.CloudVerdict, icloud: Bool) -> LocalizedStringKey {
        guard icloud else { return "The track could not be read." }
        switch v {
        case .waiting: return "iCloud could not reach its servers; the track is still in iCloud. Try again on Wi-Fi."
        case .signIn: return "iCloud asks you to sign in to your Apple Account again."
        case .driveOff: return "iCloud Drive is off on this device."
        case .noRoom, .refused: return "The track could not be read."
        }
    }

    // ── on the walk's queue ──────────────────────────────────────────────────────────────
    /// The lent folders, read from this device's keychain once a launch; nil while the keychain does not answer (before
    /// the first unlock) — a list read as empty then would be written over the kept one by the next lend.
    nonisolated private static func folders() -> [Lent]? {
        if let l = lent { return l }
        let got = E2EKeychain.getDeviceOnlyStatus(keychainKey)
        if got.status == errSecItemNotFound { lent = []; return [] }
        guard got.status == errSecSuccess, let d = got.data else { return nil }
        let l = (try? JSONDecoder().decode([Lent].self, from: d)) ?? []
        lent = l
        return l
    }
    nonisolated private static func save(_ all: [Lent]) {
        lent = all
        if let d = try? JSONEncoder().encode(all) { E2EKeychain.setDeviceOnly(keychainKey, d) }
    }
    /// Bookmarks a pass renewed, written onto the folders as they stand now: a pick kept meanwhile is not written away.
    nonisolated private static func saveRenewed(_ all: [Lent]) {
        var now = lent ?? all
        for l in all { if let j = now.firstIndex(where: { $0.id == l.id }) { now[j].bookmark = l.bookmark } }
        save(now)
    }
    /// The picks waiting to be kept, kept — by the lend's own block, or by a walk under way between its entries.
    nonisolated private static func keepPicks() {
        lock.lock(); let p = picks; picks = []; lock.unlock()
        for u in p { keep(u) }
    }
    /// The picked folder kept: its access held for the launch (the walk and every play read under it), its bookmark in the
    /// keychain; the same folder lent again renews its permission instead of standing twice.
    nonisolated private static func keep(_ picked: URL) {
        guard var all = folders() else { MontanaP2PTrace.mark("music_lent", "refused: the keychain did not answer"); return }
        guard picked.startAccessingSecurityScopedResource() else { MontanaP2PTrace.mark("music_lent", "refused: no access"); return }
        guard let bookmark = try? picked.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            picked.stopAccessingSecurityScopedResource()
            MontanaP2PTrace.mark("music_lent", "refused: no bookmark")
            return
        }
        for i in all.indices { _ = open(&all[i]) }
        let path = picked.standardizedFileURL.path
        if let i = all.firstIndex(where: { opened[$0.id]?.standardizedFileURL.path == path }) {
            all[i].bookmark = bookmark
            picked.stopAccessingSecurityScopedResource()   // the access this launch already holds for it stays
        } else {
            let id = String(UUID().uuidString.prefix(8)).lowercased()
            all.append(Lent(id: id, bookmark: bookmark, at: Date().timeIntervalSince1970))
            opened[id] = picked
        }
        save(all)
        MontanaP2PTrace.mark("music_lent", "kept folders=\(all.count)")
    }
    /// A lent folder opened for this launch: its bookmark resolved and its access started once, held for the launch; a
    /// stale bookmark is written again from the folder it resolved to (Apple: «Handle stale data here»). nil when the
    /// folder is gone or its access was taken back (Settings, Privacy & Security, Files and Folders).
    nonisolated private static func open(_ l: inout Lent) -> URL? {
        if let u = opened[l.id] { return u }
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: l.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              u.startAccessingSecurityScopedResource() else { return nil }
        opened[l.id] = u
        if stale, let b = try? u.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) { l.bookmark = b }
        return u
    }
    /// The last walk's list laid under the folders opened for this launch; a folder whose permission is gone lays none of
    /// its tracks. A walk that landed first stands: its word is the newer.
    nonisolated private static func layKept(asked: TimeInterval) {
        guard !laid else { return }
        let t0 = ProcessInfo.processInfo.systemUptime
        guard var all = folders() else { return }   // the keychain silent before the first unlock: the next ask lays it
        laid = true
        let wait = Int((t0 - asked) * 1000)   // the ask's wait on the queue
        // Three causes, told apart: no list yet, a list the phone does not give, a list this build does not read.
        var cause = "", kept: [Kept] = []
        if !FileManager.default.fileExists(atPath: keptURL.path) { cause = "none" }
        else if let d = try? Data(contentsOf: keptURL) {
            if let k = try? JSONDecoder().decode([Kept].self, from: d) { kept = k } else { cause = "undecodable" }
        } else { cause = "unreadable" }
        if !cause.isEmpty {
            MontanaP2PTrace.mark("music_kept", "\(cause) folders=\(all.count) wait_ms=\(wait)")
            // NOTHING KEPT, THE FOLDERS WALKED AT ONCE (the critic 24.09): the first launch of a build, or a list lost — the
            // half minute begins at the launch, not at the page's opening, and the plus turns while it lasts.
            if !all.isEmpty { DispatchQueue.main.async { MainActor.assumeIsolated { MTMusicFolders.shared.walk(waited: true) } } }
            return
        }
        lastKept = kept
        let before = all.map(\.bookmark)
        var roots: [String: URL] = [:]
        for i in all.indices { if let u = open(&all[i]) { roots[all[i].id] = u } }
        if all.map(\.bookmark) != before { saveRenewed(all) }
        var list: [MusicTrack] = [], map: [String: Found] = [:]
        for k in kept {
            guard let root = roots[k.folder] else { continue }
            let key = keyOf(k.folder, k.rel)
            // THE CLOUD IS DRAWN BY TODAY'S WORD (the critic 24.09, «who said so?»): the kept «not on the phone» is the
            // keeper's answer of another day — no cloud until the walk reads the file; a play asks the file itself.
            map[key] = Found(url: root.appendingPathComponent(k.rel), local: true, size: k.size, icloud: k.icloud,
                             art: k.art.map { root.appendingPathComponent($0) })
            list.append(MusicTrack(file: key, title: k.title, msgId: "", chat: "", chatTitle: k.place, at: k.at))
        }
        lock.lock()
        let stood = shelf.list.isEmpty && found.isEmpty
        if stood { found = map; shelf = (shelf.rev &+ 1, list) }
        lock.unlock()
        MontanaP2PTrace.mark("music_kept", "laid=\(stood ? list.count : 0) of \(kept.count) folders=\(roots.count) wait_ms=\(wait) ms=\(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000))")
        if stood, !list.isEmpty { DispatchQueue.main.async { MainActor.assumeIsolated { MTMusicFolders.shared.rev &+= 1 } } }
    }
    /// The list kept for the next launch — no copy and no backup take it: it is read under this device's permission alone.
    nonisolated private static func keepList(_ kept: [Kept]) {
        let fm = FileManager.default, dir = keptURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var folder = dir, rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try? folder.setResourceValues(rv)
        }
        guard let data = try? JSONEncoder().encode(kept) else { return }
        do { try data.write(to: keptURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { MontanaP2PTrace.mark("music_kept", "unwritten \((error as NSError).domain) \((error as NSError).code)") }
    }
    /// Every lent folder walked, the oldest lent first; a file lying under two lent folders stands once, in the first.
    nonisolated private static func walkAll(lend: Bool) {
        let t0 = ProcessInfo.processInfo.systemUptime
        enumSpent = 0; entries = 0
        lock.lock(); broughtDuring = []; let old = found; lock.unlock()
        guard var all = folders() else { land(nil, note: "keychain silent", t0: t0, lend: lend); return }
        let before = all.map(\.bookmark)
        var list: [MusicTrack] = [], map: [String: Found] = [:], paths = Set<String>()
        var kept: [Kept] = []
        var closed = 0, carried = 0, cloud = 0, pictures = 0, covered = 0
        for i in all.indices.sorted(by: { all[$0].at < all[$1].at }) {
            guard let root = open(&all[i]) else {
                closed += 1
                // A FOLDER THAT DID NOT OPEN KEEPS ITS TRACKS (the critic 24.09): a drive away, a keeper not answering — one
                // walk without it writes its tracks neither out of the kept list nor off the page.
                for k in lastKept where k.folder == all[i].id {
                    let key = keyOf(k.folder, k.rel)
                    list.append(MusicTrack(file: key, title: k.title, msgId: "", chat: "", chatTitle: k.place, at: k.at))
                    kept.append(k)
                    if let f = old[key] { map[key] = f }
                    carried += 1
                }
                continue
            }
            let met = walk(root)
            pictures += met.pictures
            // The page shows the newest first: the library holds a folder from its last path, so the page reads it in order.
            for f in met.tracks.reversed() where paths.insert(f.url.standardizedFileURL.path).inserted {
                let key = keyOf(all[i].id, f.rel)
                map[key] = Found(url: f.url, local: f.local, size: f.size, icloud: f.icloud, art: f.art.map { root.appendingPathComponent($0) })
                list.append(MusicTrack(file: key, title: f.title, msgId: "", chat: "", chatTitle: f.place, at: all[i].at))
                kept.append(Kept(folder: all[i].id, rel: f.rel, title: f.title, place: f.place, at: all[i].at,
                                 local: f.local, size: f.size, icloud: f.icloud, art: f.art))
                if !f.local { cloud += 1 }
                if f.art != nil { covered += 1 }
            }
        }
        if all.map(\.bookmark) != before { saveRenewed(all) }
        land((list, map, kept), note: "folders=\(all.count) closed=\(closed) carried=\(carried) files=\(list.count) cloud=\(cloud) pictures=\(pictures) covered=\(covered) entries=\(entries) enum_ms=\(Int(enumSpent * 1000))",
             t0: t0, lend: lend)
    }
    /// Every regular music file under the folder, at any depth, in the order of its path. The older iCloud stands a file
    /// not on the phone as «.name.icloud»: its real name inside, its size in the placeholder; any other hidden entry is
    /// the system's own and is not entered; a folder named like a track, or a link, is not a file.
    nonisolated private static func walk(_ root: URL) -> (tracks: [Walked], pictures: Int) {
        // The enumerator fetches these properties for EVERY entry it gives — directories and pictures too — and the reading
        // after it is its cache: so the enumerator's own time is what is measured (enum_ms, entries; the critic 24.09).
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(probe),
                                                      options: [.skipsPackageDescendants]) else { return ([], 0) }
        let base = root.standardizedFileURL.path
        var out: [Walked] = []
        var pictures: [String: [String]] = [:]   // each directory's pictures by name, the directory by its path under the root
        while true {
            let n0 = ProcessInfo.processInfo.systemUptime
            let next = en.nextObject()
            enumSpent += ProcessInfo.processInfo.systemUptime - n0
            guard let u = next as? URL else { break }
            entries += 1
            if entries % 64 == 0 { keepPicks() }   // a pick waits a few entries, never the whole walk
            var name = u.lastPathComponent, file = u
            let local: Bool, size: Int, icloud: Bool
            if name.hasPrefix(".") {
                guard name.hasSuffix(".icloud") else { en.skipDescendants(); continue }
                name = String(name.dropFirst().dropLast(".icloud".count))
                guard mtIsAudioName(name) else { continue }
                file = u.deletingLastPathComponent().appendingPathComponent(name)
                local = false; size = stubSize(u) ?? 0; icloud = true
            } else if isPicture(name) {
                let path = u.standardizedFileURL.path
                let rel = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : name
                pictures[(rel as NSString).deletingLastPathComponent, default: []].append(name)
                continue
            } else {
                guard mtIsAudioName(name), let v = try? u.resourceValues(forKeys: probe), v.isRegularFile == true else { continue }
                local = onPhone(v); size = v.fileSize ?? 0; icloud = v.isUbiquitousItem == true
            }
            let path = file.standardizedFileURL.path
            let rel = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : name
            let dir = (rel as NSString).deletingLastPathComponent
            out.append(Walked(url: file, title: name, rel: rel, place: dir.isEmpty ? root.lastPathComponent : root.lastPathComponent + "/" + dir,
                              local: local, size: size, icloud: icloud, art: nil))
        }
        // Each track takes its own directory's cover, when the directory holds a picture.
        let covers = pictures.mapValues(cover(among:))
        let tracks = out.map { w -> Walked in
            let dir = (w.rel as NSString).deletingLastPathComponent
            let art = covers[dir].flatMap { $0 }.map { dir.isEmpty ? $0 : dir + "/" + $0 }
            return Walked(url: w.url, title: w.title, rel: w.rel, place: w.place, local: w.local, size: w.size, icloud: w.icloud, art: art)
        }
        return (tracks.sorted { $0.rel.localizedStandardCompare($1.rel) == .orderedAscending }, pictures.values.reduce(0) { $0 + $1.count })
    }
    nonisolated private static func isPicture(_ name: String) -> Bool {
        ["jpg", "jpeg", "png", "heic", "webp"].contains((name as NSString).pathExtension.lowercased())
    }
    /// A directory's cover among its pictures, as music players have long chosen it: the one named for the cover (cover,
    /// folder, front, album, albumart, artwork), else the first by name.
    nonisolated private static func cover(among names: [String]) -> String? {
        let byName = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { (stem: ($0 as NSString).deletingPathExtension.lowercased(), name: $0) }
        for want in ["cover", "folder", "front", "album", "albumart", "albumartsmall", "artwork"] {
            if let hit = byName.first(where: { $0.stem == want }) { return hit.name }
        }
        return byName.first(where: { $0.stem.hasPrefix("albumart") })?.name ?? byName.first?.name
    }
    /// The size an older iCloud placeholder names for its file (its own small property list), if it names one.
    nonisolated private static func stubSize(_ stub: URL) -> Int? {
        guard let d = try? Data(contentsOf: stub),
              let p = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any] else { return nil }
        return (p["NSURLFileSizeKey"] as? NSNumber)?.intValue
    }
    /// A lent track's name: its folder and its path's digest, flat — every shelf keyed by a file's name takes it as it is.
    nonisolated private static func keyOf(_ id: String, _ rel: String) -> String {
        let h = SHA256.hash(data: Data(rel.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let ext = (rel as NSString).pathExtension.lowercased()
        return mark + id + "-" + h + (ext.isEmpty ? "" : "." + ext)
    }
    /// The walk's result published: the map and the list under the lock, then the page — drawn again only when the walk
    /// found something different. nil: the keychain did not answer, and what stands stays.
    nonisolated private static func land(_ got: (list: [MusicTrack], map: [String: Found], kept: [Kept])?, note: String, t0: TimeInterval, lend: Bool) {
        var changed = false
        if let got {
            var map = got.map
            lock.lock()
            let old = found, oldList = shelf.list
            // A TRACK BROUGHT WHILE THE WALK READ STAYS BROUGHT (the critic 24.09): the walk read it before the bring put it on
            // the phone; the bring's word is the newer.
            for k in broughtDuring where map[k] != nil { map[k]?.local = true }
            broughtDuring = []
            lock.unlock()
            // By the path, not by the URL's spelling: the list laid at the launch names a track under its folder as it was
            // opened, the walk as its enumerator spells it — one file.
            changed = oldList != got.list || old.count != map.count
                || map.contains { k, f in old[k].map { $0.url.standardizedFileURL.path != f.url.standardizedFileURL.path || $0.local != f.local
                    || $0.art?.standardizedFileURL.path != f.art?.standardizedFileURL.path } ?? true }
            if changed {
                lock.lock(); found = map; shelf = (shelf.rev &+ 1, got.list); lock.unlock()
                keepList(got.kept)
            }
            lastKept = got.kept
            laid = true
        }
        MontanaP2PTrace.mark("music_walk", note + " lend=\(lend ? 1 : 0) changed=\(changed ? 1 : 0) ms=\(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000))")
        DispatchQueue.main.async { MainActor.assumeIsolated { MTMusicFolders.shared.walked(changed: changed, lend: lend) } }
    }
}
