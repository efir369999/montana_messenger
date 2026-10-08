import SwiftUI
import UIKit
import Combine

// ═══════════════════════════════════════════════════════════════════════════
// STAGE 11: THE OWN FEED CONTAINER (birth-point sovereignty). The feed's scroll
// view is OURS from birth: candidacy off, inversion by transform, the diffable
// snapshot keyed by row id, and the position held by OUR arithmetic — a prepend
// compensates the offset, so the visible rows never move under the reader.
// Cells host the existing SwiftUI bubbles untouched.
// ═══════════════════════════════════════════════════════════════════════════
/// The reference keeps the list's frame fixed and represents the keyboard by an inset.
/// Its pan moves the messages once; changing that inset adds no second motion while tracking.
struct MTFeedKeyboardLayout {
    let height: CGFloat
    let inset: CGFloat
    init(visibleHeight: CGFloat, coveredHeight: CGFloat, reserve: CGFloat) {
        let covered = max(0, coveredHeight)
        // THE FRAME IS FIXED, THE KEYBOARD IS AN INSET (the reference's rule; the author's word 21.09:
        // «the field now lies over the feed»). The frame used to grow by the covered height — right
        // while the page itself shrank to the keyboard's edge, wrong once the page stays whole and
        // the bar rises inside it: the grown frame put the newest letter back under the bar.
        height = visibleHeight
        inset = reserve + covered
    }
}

final class MTFeedCollectionView: UICollectionView {
    lazy var scrollSpring = MTFeedSpring(collection: self)
    var keyboardGeometry: MTChatKeyboardGeometry?
    var keyboardGestureActive = false
    /// How near an end a reader stands to be held at it when the content changes under them.
    static let holdReach: CGFloat = 60
    /// The feed turned: the newest letters at the visual top (the list sets it on every pass).
    var newestOnTop = false
    /// THE NEWEST END HOLDS ITS READER WHEN IT GROWS BY ITSELF (the author's word 03.10 20:29: «the new bubble of the live
    /// dialogue sits behind the message panel -- fix it and align everything»). Turned, the newest end is the content's far
    /// end, under the field on top. A pass of the list holds a reader standing there (pinNewestOnTop); a row that grows on
    /// its own -- the peer's live words as they come, a picture landing -- grows the far end with no pass, the offset stood
    /// still, and the growth went up under the field. A reader at the visual top when the content grows stays at the visual
    /// top; a finger's scroll stays the finger's. On the keys the newest end is the offset's zero, where growth holds still.
    override var contentSize: CGSize {
        didSet {
            guard newestOnTop, oldValue.height != contentSize.height, !isTracking, !isDecelerating, !keyboardGestureActive else { return }
            let oldTop = max(mtBottomY, oldValue.height - bounds.height + contentInset.bottom)
            guard abs(oldTop - contentOffset.y) <= Self.holdReach else { return }
            contentOffset.y = mtTopY
        }
    }

    func beginKeyboardDrag() {
        // THE DRAG'S FIRST FRAME CHANGES NOTHING OF THE KEYBOARD'S (22.09): the accessory was re-sized here
        // and the platform re-laid the keys under the finger (measured 21.09: +61 points up at the start
        // of a downward drag; the keys' height read 102). The accessory is the field's own constant, given
        // at its birth and never written again (MTChatKeyboardGeometry.accessory); here only the drag is named.
        keyboardGestureActive = (keyboardGeometry?.coveredHeight ?? 0) > 1
    }

    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        scrollsToTop = false                       // born opted out — the one candidate stays elsewhere
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        showsVerticalScrollIndicator = false       // flipped feed: the system indicator would mirror
        alwaysBounceVertical = true                // a short chat must still deliver a native keyboard pan
        // THE KEYBOARD FOLLOWS THE FINGER (the author's word 20.09): the platform's own interactive
        // mode — the keyboard rides under the dragging touch, a release below its top edge lets it
        // go, a pull back up cancels. `.onDrag` tore it away whole at the first point of movement.
        // The reference reaches the same feel by moving the system keyboard window through a
        // private class; here the one word of UIKit does it, and nothing of ours touches that window.
        keyboardDismissMode = .interactive
        // NO EDGE EFFECT OF THE SYSTEM'S (the author's word 21.09): the newest system blurs a list's
        // edge under the bar — and this list is flipped, so its «top» stands at the visual bottom and
        // the blur fell over the letters below the bar instead of the strip beneath it. The bar has
        // no ground, the feed is clean on its whole height, as the reference draws it.
        mtHideEdgeEffects()
        transform = CGAffineTransform(scaleX: 1, y: -1)
        NotificationCenter.default.addObserver(self, selector: #selector(stopSpring), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopSpring), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func stopSpring() { scrollSpring.reset() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { scrollSpring.reset() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The collection spans the space available with the keyboard down. Its covered part is an inset.
/// That space is measured from the page's guide on every layout, including first opening with the
/// keyboard already visible. A notification's isUp flag cannot measure an intermediate frame.
final class MTFeedFrame: UIView {
    let cv: MTFeedCollectionView
    /// Room for a bar floating over the feed's bottom (the voice player); part of the one inset.
    var reserve: CGFloat = 0 { didSet { if reserve != oldValue { setNeedsLayout() } } }
    /// THE FEED RUNS ON TO THE WINDOW'S BOTTOM (the author's word 21.09: the bubbles show through the
    /// field and its buttons; the feed is not cut at the bottom, it goes to the end of the screen — on
    /// every device and every system). The run-on is MEASURED, never assumed: the distance from this
    /// view's bottom to the window's bottom edge, whatever stands between (the bar, the home indicator's
    /// strip, anything the platform adds). It is part of the one inset — the visual bottom stays above
    /// the bar, the letters scrolled past it are drawn behind the glass. Touches end at this view's bounds.
    private var underlap: CGFloat {
        guard let w = window else { return 0 }
        return max(0, w.bounds.maxY - convert(bounds, to: w).maxY)
    }
    /// AND TO THE WINDOW'S TOP (the author's word 21.09): the same measure upward — whatever stands
    /// above (the bar, the status strip). It is the visual TOP's inset (the flipped space's bottom), so
    /// the oldest letter stops under the bar's edge and nothing is buried beneath it.
    private var overlapTop: CGFloat {
        guard let w = window else { return 0 }
        return max(0, convert(bounds, to: w).minY)
    }
    /// The one inset, told outward as it is applied — with the keyboard's spring when the keys move by themselves.
    var onInset: ((CGFloat, Float?) -> Void)?
    /// THE KEYS' COVER, told beside the inset (the author's word 21.09: the player never goes under
    /// the keyboard, on any device and any system): a bar that floats over the feed's visual
    /// bottom stands on this number, in the same spring as the feed and the «down» button.
    var onCover: ((CGFloat, Float?) -> Void)?
    private var covered: CGFloat = 0
    init(cv: MTFeedCollectionView) {
        self.cv = cv
        super.init(frame: .zero)
        clipsToBounds = false   // the feed runs on under the panel and the keys; they cover it
        addSubview(cv)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// THE FIRST FRAME OF THE FEED IS THE END OF THE ROAD (21.09): a chat is «open» for the eye when
    /// its letters are laid out, not when its view has appeared — the clock started at the banner
    /// tap stops here, once per feed.
    private var firstLaid = false
    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        guard h > 1, bounds.width > 1 else { return }
        // The clock is handed over at the conversation's onAppear, which comes AFTER this view's first
        // layout (T3 21:10:18: no feed_first line at all) — so the first layout after the hand-over
        // closes it, whichever number it is.
        if let t0 = MontanaOutsideOpen.openedAt {
            MontanaOutsideOpen.openedAt = nil
            MontanaTrace.mark("feed_first", "why=banner ms=\(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)) rows=\(cv.numberOfSections > 0 ? cv.numberOfItems(inSection: 0) : 0) first=\(firstLaid ? 0 : 1)")
        }
        firstLaid = true
        let over = overlapTop
        let layout = MTFeedKeyboardLayout(visibleHeight: h + underlap + over,
                                          coveredHeight: cv.keyboardGeometry?.coveredHeight ?? 0,
                                          reserve: reserve + underlap)
        let frame = CGRect(x: 0, y: -over, width: bounds.width, height: layout.height)
        if cv.frame != frame { cv.frame = frame }
        if abs(cv.contentInset.bottom - over) > 0.5 { cv.contentInset.bottom = over; cv.verticalScrollIndicatorInsets.bottom = over }
        covered = max(0, cv.keyboardGeometry?.coveredHeight ?? 0)
        apply(inset: layout.inset)
    }
    /// THE KEYBOARD'S TRANSITION REACHES THE FEED (20.09): the offset moves to where the covered
    /// edge puts it, and when the keys move by themselves its bounds ride the keyboard's spring —
    /// the reference's list under the same transition as its input panel.
    func keyboardCovered(_ covered: CGFloat, speed: Float?) {
        let h = bounds.height
        guard h > 1 else { return }
        let over = overlapTop
        let layout = MTFeedKeyboardLayout(visibleHeight: h + underlap + over, coveredHeight: covered, reserve: reserve + underlap)
        let frame = CGRect(x: 0, y: -over, width: bounds.width, height: layout.height)
        if cv.frame != frame { cv.frame = frame }
        let now = (cv.layer.presentation() ?? cv.layer).bounds   // where the feed actually is (an interrupted move begins here)
        self.covered = max(0, covered)
        apply(inset: layout.inset, speed: speed)
        let after = cv.bounds
        if let speed, now.origin.y != after.origin.y {
            cv.layer.add(MTKeyboardSpring.animation("bounds", from: NSValue(cgRect: now), to: NSValue(cgRect: after), speed: speed), forKey: "keyboard")
        } else {
            cv.layer.removeAnimation(forKey: "keyboard")
        }
    }
    /// THE INSET IS A SCROLL INSET, NEVER A RELAYOUT (14.09: a relayout of the section inset blanked
    /// the feed and tore a hole under the last letter). It moves no cell by itself. A reader at the
    /// bottom is glued to the new bottom — unless a finger is tracking: then the finger's scroll is
    /// the motion, and gluing under it would be the second motion. A reader higher up keeps the same
    /// letters in view.
    private func apply(inset: CGFloat, speed: Float? = nil) {
        guard abs(cv.contentInset.top - inset) > 0.5 else { onCover?(covered, speed); return }
        let wasAtBottom = cv.contentOffset.y - cv.mtBottomY < 60
        cv.contentInset.top = inset
        cv.verticalScrollIndicatorInsets.top = inset
        if wasAtBottom, !cv.isTracking, !cv.keyboardGestureActive { cv.contentOffset.y = cv.mtBottomY }
        onInset?(inset - underlap, speed)   // the visual bottom above THIS view's bottom: what the «down» button stands on (1809: it flew up by the run-on)
        onCover?(covered, speed)             // the keys' share alone: what the floating player stands on
        // Under a dragging finger the inset changes on every frame: the diary keeps the drag's own line
        // (kb_drag) and not a line per frame here (measured 21.09: keyboard drags 53 ms worst frame against 20).
        if !cv.keyboardGestureActive {
            MontanaTrace.mark("feed_inset", "inset=\(Int(inset)) reserve=\(Int(reserve)) h=\(Int(bounds.height)) feed_h=\(Int(cv.frame.height)) tracking=\(cv.isTracking)")
        }
    }
}

extension UIScrollView {
    /// THE VISUAL BOTTOM OF THE INVERTED FEED. A bar floating over the feed's bottom is a top
    /// inset in the flipped space (the system's own way of putting a bar over a scroll view):
    /// the offset that glues the newest letter above the bar is minus that inset, not zero.
    var mtBottomY: CGFloat { -contentInset.top }
    /// THE VISUAL TOP OF THE INVERTED FEED: the far end of the content, never below the visual bottom.
    var mtTopY: CGFloat { max(mtBottomY, contentSize.height - bounds.height + contentInset.bottom) }
}

/// The command bridge: SwiftUI asks, the container executes with its own numbers.
final class MTFeedControl: ObservableObject {
    weak var view: MTFeedCollectionView?
    fileprivate weak var coordinator: MTFeedListView.Coordinator?
    /// The feed turned: the newest letters stand at the visual top, and «to the newest» goes up.
    var newestOnTop = false
    func scrollToBottom(animated: Bool) {
        guard let v = view else { return }
        if newestOnTop { coordinator?.askNewest(); scrollToTop(animated: animated); return }
        let far = v.contentOffset.y - v.mtBottomY > 2000
        v.setContentOffset(CGPoint(x: 0, y: v.mtBottomY), animated: animated && !far)
    }
    func scrollToTop(animated: Bool = true) {
        guard let v = view else { return }
        let maxY = v.mtTopY
        let far = abs(maxY - v.contentOffset.y) > 2000
        v.setContentOffset(CGPoint(x: 0, y: maxY), animated: animated && !far)
    }
    func scrollTo(_ id: MID, animated: Bool = true) {
        coordinator?.scrollTo(id, animated: animated)
    }
}

/// 13.3 — AN EMPTY SCREEN SAYS WHICH EMPTINESS IT IS. Four different truths used to wear one
/// face — a blank: «there is nothing here yet», «nothing matches the search», «the history is
/// still being read» and «there is nowhere to read it from». A person cannot act on a blank, and
/// worse, waits for a message that will never come while the phone knows it holds no network at
/// all. Each state now carries its own word, and the one that CAN be acted on carries an action.
struct MTFeedEmpty: View {
    enum Kind { case loading, noNetwork, noResults, freshChat }
    let kind: Kind
    let onAction: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            switch kind {
            case .loading:
                ProgressView().tint(.gray)
                Text(LocalizedStringKey("Reading the conversation…"))
                    .font(.footnote).foregroundColor(.gray)
            case .noNetwork:
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 30)).foregroundColor(.gray)
                Text(LocalizedStringKey("No connection to the network"))
                    .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                Text(LocalizedStringKey("Messages will be sent as soon as a door answers"))
                    .font(.footnote).foregroundColor(.gray).multilineTextAlignment(.center)
            case .noResults:
                Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundColor(.gray)
                Text(LocalizedStringKey("Nothing found"))
                    .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            case .freshChat:
                Text(LocalizedStringKey("No messages yet"))
                    .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                Text(LocalizedStringKey("Write the first one — it will wait for them on a node"))
                    .font(.footnote).foregroundColor(.gray).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .contentShape(Rectangle())
        .onTapGesture { onAction() }
        .allowsHitTesting(kind == .freshChat)   // only the one state with something to do takes a tap
    }
}

/// 13.2 — THE HONEST FRAME METER. «The feed lags» is a feeling; a frame that took 180ms is a
/// fact, and only a fact can decide whether an asynchronous layout is worth building. The meter
/// counts what the person actually feels — how long the screen stood still between two frames
/// WHILE THE FINGER WAS MOVING — and says it once per gesture, in numbers: how many frames, the
/// worst one, how many were late, and the size of the feed it happened on.
///
/// It is deliberately cheap: one display link that exists only during a scroll, no allocation per
/// frame, and not a single measurement while the screen is still. A meter that costs frames of
/// its own measures itself.
final class MTFrameMeter {
    static let shared = MTFrameMeter()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var late = 0        // frames that took longer than two display intervals
    /// Display intervals a frame overran: dropped frames that no hang detector sees.
    private var missed = 0
    private var worstMs = 0
    private var began: CFTimeInterval = 0
    private var rows = 0
    /// WHO ATE THE FRAME (the critic 22.09): the cells configured since the previous tick, by kind,
    /// and the snapshots applied during the gesture with their cost — so a late frame is named by
    /// what it was building, not only counted.
    private var cellsSinceTick: [String] = []
    private var lateNotes: [String] = []
    private var applies = 0
    private var applyMs = 0
    private var renders = 0
    private var rowsMs = 0
    /// WHO WOKE THE SCREEN (the critic 22.09, T1 on 1857: 31 rebuilds in one fling with the player's
    /// clock already silenced): every object the conversation observes is counted by name while the
    /// finger moves, so a rebuild is named by its publisher, not guessed.
    private var fires: [String: Int] = [:]
    private var watched: String? = nil
    private var bag: [AnyCancellable] = []
    /// THE GESTURE'S OWN END, ASKED OF THE PLATFORM (the critic 22.09). The meter used to end only
    /// on the two delegate words `didEndDragging` and `didEndDecelerating` -- and a scroll that
    /// leaves by any OTHER road (the page dismissed mid-fling, the deceleration stopped by the
    /// system, the app suspended under the finger) never spoke them: the display link stayed on the
    /// main run loop and woke the whole main thread sixty times a second for as long as the app
    /// lived. Measured on the fleet in thirty hours: one "fling" of 28 311 frames (eight minutes at
    /// 58 fps) and one "drag" of 54 520 frames whose worst gap was 485 788 ms -- the app had been
    /// suspended and resumed with the link still ticking. The scroll view itself knows when the
    /// gesture is over, so the meter asks it on every frame instead of waiting to be told.
    private weak var scroller: UIScrollView?
    private var backgroundWatch: NSObjectProtocol?
    /// THE LATE FRAME NAMED BY ITS CODE (the author's word 30.09 on T1: «every metric of the player; where nothing measures the
    /// response and the page's behaviour, install it»): the playlist's 500-750 ms frames stood with «none» -- no cell built, the
    /// main thread busy with what no line named. While a motion is measured, a watcher reads the main thread's stack once per
    /// stall past 48 ms, and the motion's line is followed by the stacks it caught.
    private let stalls = MTStallWatch()
    /// The bodies of the pages and rows that ran while the finger moved, by name: a rebuild is a count, not a guess.
    private var bodies: [String: Int] = [:]
    func body(_ name: String) { if link != nil { bodies[name, default: 0] += 1 } }
    func configured(_ kind: String) { if link != nil { cellsSinceTick.append(kind) } }
    /// Time the list's cells spent sizing their hosted views since the last tick: tells row building from other work in a late frame.
    private var sizedMsSinceTick: Double = 0
    func sized(ms: Double) { if link != nil { sizedMsSinceTick += ms } }
    func applied(ms: Double) { if link != nil { applies += 1; applyMs += Int(ms) } }
    func rendered() { if link != nil { renders += 1 } }
    func rowsBuilt(ms: Double) { if link != nil { rowsMs += Int(ms) } }
    func watch(_ key: String, _ subs: () -> [(String, AnyPublisher<Void, Never>)]) {
        guard watched != key else { return }
        watched = key
        bag = subs().map { name, pub in
            pub.sink { [weak self] _ in
                guard let self, self.link != nil else { return }
                self.fires[name, default: 0] += 1
            }
        }
    }
    static func kind(of row: ChatConversationView.ChatRowVM) -> String {
        let m = row.message
        if !row.members.isEmpty { return "group" }
        if m.imageFile != nil { return "photo" }
        if m.videoFile != nil { return "video" }
        if m.audioFile != nil { return "voice" }
        if m.docFile != nil { return "doc" }
        return "text"
    }

    /// EVERY MOTION OF THE SCREEN IS MEASURED BY THIS ONE METER (the author's word 25.09: «make the metrics show every
    /// scenario»): a page pushed or popped, a sheet risen or lowered, a page slid over the chats and slid off, the drawer, the
    /// pane turned by the finger, the time panel folded, the keyboard raised or lowered, a chat opened or closed -- each owner
    /// of a motion says when it begins and, by the platform's own completion, when it ends; one line per motion
    /// (motion what=… frames= fps= worst_ms= late=). Two motions at once are one line, named by the first to end.
    func moveBegan() { begin(rows: 0) }
    func moveEnded(_ what: String) { end(what, mark: "motion") }

    /// From a control's action to the first frame after it: the wait the finger feels.
    func tap(_ what: String) {
        let since = CACurrentMediaTime()
        DispatchQueue.main.async { MTTapProbe(what: what, since: since).start() }
    }

    /// The gesture began. Idempotent: a second call while running only refreshes the size.
    func begin(rows: Int, on scrollView: UIScrollView? = nil) {
        self.rows = rows
        self.scroller = scrollView
        if backgroundWatch == nil {
            backgroundWatch = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.end("background") }
        }
        guard link == nil else { return }
        frames = 0; late = 0; worstMs = 0; missed = 0
        cellsSinceTick = []; lateNotes = []; applies = 0; applyMs = 0; renders = 0; rowsMs = 0; fires = [:]; bodies = [:]
        last = CACurrentMediaTime(); began = last
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
        stalls.start()
    }

    /// The gesture ended: one line, then silence. A meter that speaks every frame is noise.
    func end(_ what: String, mark: String = "feed_fps") {
        guard link != nil else { return }
        link?.invalidate(); link = nil
        scroller = nil
        let caught = stalls.stop()
        guard frames > 5 else { return }   // a flick too short to judge says nothing
        let secs = max(0.001, CACurrentMediaTime() - began)
        let fps = Int(Double(frames) / secs)
        let line = "what=\(what) rows=\(rows) frames=\(frames) fps=\(fps) worst_ms=\(worstMs) late=\(late) missed=\(missed) renders=\(renders) rows_ms=\(rowsMs) fires=\(fires.keys.sorted().map { "\($0):\(fires[$0]!)" }.joined(separator: ",")) applies=\(applies) apply_ms=\(applyMs) bodies=\(bodies.keys.sorted().map { "\($0):\(bodies[$0]!)" }.joined(separator: ",")) stalls=\(caught.count) late_cells=\(lateNotes.joined(separator: ","))"
        MontanaTrace.mark(mark, line)
        // The trace rotates within an hour under load; telemetry.log keeps the player's and the pages' lines for a day.
        let kept = what.hasPrefix("player") || what.hasPrefix("scrub") || what.hasPrefix("page:rise:music") || what.hasPrefix("pane")
        if kept { MontanaLog.event("FRAMES " + mark + " " + line) }
        for (i, s) in caught.enumerated() {
            let stack = "what=\(what) n=\(i + 1) ms=\(s.ms) frames: " + MTStallWatch.told(s.frames)
            MontanaTrace.mark("frame_stack", stack)
            if kept { MontanaLog.event("FRAMES stack " + stack) }
        }
    }

    func end(on scrollView: UIScrollView) {
        guard scroller === scrollView else { return }
        end("closed")
    }

    @objc private func tick(_ l: CADisplayLink) {
        // THE SCROLL VIEW IS ASKED, NOT AWAITED: the moment it is neither held nor coasting the
        // gesture is over, whatever delegate word did or did not arrive.
        if let sv = scroller, !sv.isTracking, !sv.isDragging, !sv.isDecelerating {
            end("settled"); return
        }
        stalls.beat()
        let now = l.timestamp
        let dt = now - last
        last = now
        frames += 1
        let ms = Int(dt * 1000)
        if ms > worstMs { worstMs = ms }
        if 0 < l.duration { missed += max(0, Int((dt / l.duration).rounded()) - 1) }
        // «Late» is measured against the display's OWN rhythm, not against sixty: on a 120Hz
        // screen a 16ms frame is already a stutter, and a fixed number would call it healthy.
        if dt > l.duration * 2 {
            late += 1
            if lateNotes.count < 8 {
                var byKind: [String: Int] = [:]
                for k in cellsSinceTick { byKind[k, default: 0] += 1 }
                let cells = byKind.keys.sorted().map { "\($0)\(byKind[$0]!)" }.joined(separator: "+")
                let sizing = sizedMsSinceTick < 1 ? "" : ":sized\(Int(sizedMsSinceTick))ms"
                lateNotes.append("\(ms)ms/" + (cells.isEmpty ? "none" : cells) + sizing)
            }
        }
        cellsSinceTick.removeAll(keepingCapacity: true)
        sizedMsSinceTick = 0
    }
}

/// THE WATCHER OF THE MAIN THREAD'S STALLS (MTFrameMeter): alive only while a motion is measured; every 8 ms it asks when the
/// display last ticked on the main thread, and once per stall past 48 ms it reads the main thread's stack (MTMainStack, the
/// hang watchdog's own reader). The stall's whole length is written at the tick that ends it. Nothing is taken under the lock
/// while the main thread is held.
final class MTStallWatch {
    private static let threshold: CFTimeInterval = 0.048
    private static let cap = 4
    private let lock = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private var running = false
    private var lastBeat: CFTimeInterval = 0
    private var caughtBeat: CFTimeInterval = -1
    private var caught: [(ms: Int, frames: [String])] = []
    private var thread: Thread?

    func start() {
        lock.lock(); running = true; lastBeat = CACurrentMediaTime(); caughtBeat = -1; caught = []; lock.unlock()
        if thread == nil {
            let t = Thread { [weak self] in self?.watch() }
            t.name = "montana.stall-watch"; t.stackSize = 256 * 1024; t.qualityOfService = .userInteractive
            thread = t
            t.start()
        }
        wake.signal()
    }
    func beat() {
        let now = CACurrentMediaTime()
        lock.lock()
        if caughtBeat == lastBeat, !caught.isEmpty { caught[caught.count - 1].ms = Int((now - lastBeat) * 1000) }
        lastBeat = now
        lock.unlock()
    }
    func stop() -> [(ms: Int, frames: [String])] {
        lock.lock(); running = false; let out = caught; caught = []; lock.unlock()
        return out
    }
    private func watch() {
        while true {
            lock.lock(); let on = running; lock.unlock()
            guard on else { wake.wait(); continue }
            usleep(8_000)
            lock.lock()
            let beat = lastBeat, fresh = caughtBeat != beat, room = caught.count < Self.cap, still = running
            lock.unlock()
            guard still, fresh, room, Self.threshold < CACurrentMediaTime() - beat else { continue }
            let frames = MTMainStack.capture(limit: 64)
            let ms = Int((CACurrentMediaTime() - beat) * 1000)
            lock.lock()
            if running, caughtBeat != beat, caught.count < Self.cap { caughtBeat = beat; caught.append((ms, frames)) }
            lock.unlock()
        }
    }
    /// A stack as the diary keeps it: the three innermost frames, whatever their image, then the app's own frames outward.
    static func told(_ frames: [String]) -> String {
        var out: [String] = []
        for (i, f) in frames.enumerated() where out.count < 14 {
            let ours = f.hasPrefix("Montana")
            if i < 3 || ours { out.append(ours ? f : String(f.prefix(90))) }
        }
        return out.joined(separator: " < ")
    }
}

private final class MTTapProbe: NSObject {
    let what: String
    let since: CFTimeInterval
    init(what: String, since: CFTimeInterval) { self.what = what; self.since = since }
    func start() { CADisplayLink(target: self, selector: #selector(frame(_:))).add(to: .main, forMode: .common) }
    @objc private func frame(_ l: CADisplayLink) {
        l.invalidate()
        let ms = Int((l.targetTimestamp - since) * 1000)
        MontanaTrace.mark("motion", "what=tap:\(what) ms=\(ms)")
        if what.hasPrefix("player") { MontanaLog.event("FRAMES tap " + what + " ms=\(ms)") }
    }
}

/// THE CLOCK AND THE CALENDAR BELONG TO THE DEVICE, NOT TO US. Both were written by hand here:
/// the time as "HH:mm" for everybody, so a person whose region writes half past two as 2:30 PM read
/// 14:30; the date as "dd-MM-yy", with dashes nobody's region uses, and the month of a conversation's
/// first day pinned to Russian outright. A format is a fact about the READER, and the reader is
/// named by the phone. One owner asks it, everything else asks the owner ([C-1]).
enum MTClock {
    /// THE FORMATTERS ARE BUILT ONCE (the critic 22.09): a DateFormatter is among the dearest
    /// objects of Foundation, and one was born for every bubble's time on every configuration of a
    /// reused cell — several per frame on a fling, against a frame of eight milliseconds. They live
    /// here, and are thrown away when the person changes the region (the system's own notice).
    private static var timeF: DateFormatter?
    private static var dayF: DateFormatter?
    private static var agoF: RelativeDateTimeFormatter?
    private static var watching = false
    private static func made(_ build: (DateFormatter) -> Void) -> DateFormatter {
        let f = DateFormatter()
        f.locale = MTLanguage.locale   // the app's one language, the system's region (24.09)
        build(f)
        watchLocale()
        return f
    }
    static func watchLocale() {
        guard !watching else { return }
        watching = true
        // The region changed in the system, or the language in the app: the formatters are made again.
        for name in [NSLocale.currentLocaleDidChangeNotification, .appLanguageChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                timeF = nil; dayF = nil; weekdayF = nil; dayMonthF = nil; agoF = nil; MTDayLabel.reset()
            }
        }
    }
    /// The time of day, in the shape the region writes it.
    static func time(_ date: Date) -> String {
        let f = timeF ?? made { $0.dateStyle = .none; $0.timeStyle = .short }
        timeF = f
        return f.string(from: date)
    }
    static func ago(_ date: Date) -> String {
        let f: RelativeDateTimeFormatter
        if let have = agoF { f = have } else {
            f = RelativeDateTimeFormatter()
            f.locale = MTLanguage.locale
            f.dateTimeStyle = .named
            f.unitsStyle = .full
            agoF = f
            watchLocale()
        }
        return f.localizedString(for: date, relativeTo: Date())
    }
    /// A past day, in the shape the region writes it — dots where the region uses dots.
    static func day(_ date: Date) -> String {
        let f = dayF ?? made { $0.dateStyle = .short; $0.timeStyle = .none }
        dayF = f
        return f.string(from: date)
    }
    /// THE LIST'S STAMP (the author's word 22.09): today — the time; within a week — the weekday in its
    /// short form («Tue», the Russian two-letter one), the region's own word with a capital; further — the day and the month in the
    /// region's own order and separators. Every letter of it is the app's one language (MTLanguage, 24.09): a
    /// language the phone has and we do not writes English, as every other word of the app does.
    private static var weekdayF: DateFormatter?
    private static var dayMonthF: DateFormatter?
    static func listStamp(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return time(date) }
        if let week = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())), date >= week {
            let f = weekdayF ?? made { $0.setLocalizedDateFormatFromTemplate("EEE") }
            weekdayF = f
            let w = f.string(from: date)
            return w.prefix(1).uppercased() + w.dropFirst()
        }
        let f = dayMonthF ?? made { $0.setLocalizedDateFormatFromTemplate("ddMM") }
        dayMonthF = f
        return f.string(from: date)
    }
}

/// THE DAY HAS ONE WORD. The separator inside the flow and the pill floating above it name the
/// same day, so they are the same function ([C-1]) — two spellings of one date read as two days.
/// The month follows the app's one language (MTLanguage, 24.09): it was nailed to Russian once, then to the
/// system's language, and a phone switched to English in the app still read the system's month ([C-15]).
enum MTDayLabel {
    private static var dayF: DateFormatter?   // built once (the critic 22.09), reset with MTClock's on a region change
    static func reset() { dayF = nil }
    static func of(_ epoch: Double) -> String {
        let d = Date(timeIntervalSince1970: epoch)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "Today", bundle: MTLanguage.bundle) }
        if cal.isDateInYesterday(d) { return String(localized: "Yesterday", bundle: MTLanguage.bundle) }
        let f: DateFormatter
        if let have = dayF { f = have } else {
            f = DateFormatter()
            f.locale = MTLanguage.locale   // the month in the app's one language (24.09)
            f.setLocalizedDateFormatFromTemplate("d MMMM")
            dayF = f
            MTClock.watchLocale()
        }
        return f.string(from: d)
    }
}

struct MTFeedListView: UIViewRepresentable {
    @Environment(\.mtChatKeyboardGeometry) private var keyboardGeometry
    let rows: [ChatConversationView.ChatRowVM]   // newest first — index 0 is the visual bottom
    /// THE STAMP OF WHAT THE FEED DRAWS FROM (the critic 22.09): the rows' version and the view state the
    /// fingerprints read; an unchanged stamp means an unchanged feed, and the pass over every row is skipped.
    let stamp: Int
    let control: MTFeedControl
    let pin: ChatConversationView.FeedPin
    let hasMoreAbove: Bool
    let onReachTop: () -> Void
    let onBackgroundTap: () -> Void
    /// THE HOLD ON A LETTER IS THE FEED'S (19.09): a UILongPressGestureRecognizer on the feed sees
    /// every touch of its cells — over a photo, a text, a control alike — and when it begins,
    /// the platform cancels that touch, so no tap of ours can fire on the same finger. A catcher
    /// BEHIND the drawing never saw the finger (measured 19.09: a hundred and twenty feed_tap lines
    /// naming the hosting view, one naming the catcher) — SwiftUI's drawing is opaque to a UIKit
    /// view under it. The menu is asked by the row's letter name.
    let onHold: (MID) -> Void
    let fingerprint: (ChatConversationView.ChatRowVM) -> Int
    let rowContent: (ChatConversationView.ChatRowVM) -> AnyView
    let draftContent: () -> AnyView
    /// Room kept at the VISUAL bottom for a bar that floats over the feed (the voice player):
    /// inside the flip, the section's top inset is the visual bottom, so the newest letter
    /// scrolls above the bar and the bar's material shows the letters behind it.
    var bottomReserve: CGFloat = 0
    /// THE READING END (the author words 02.10 17:56 and 17:58): with the feed turned the newest letters stand at the
    /// visual top, and every rule that follows the newest end -- the hold, the down mark, the window going home, the
    /// loading of older letters at the far end -- reads it from here.
    var newestOnTop = false
    static let draftID: MID = "draft:" + UUID().uuidString   // the one row that is not a letter

    let onAtBottom: () -> Void
    let onReplySwipe: (MID) -> Void
    let isSelecting: () -> Bool
    let onPanBegan: (MID) -> Void
    let onPanChanged: (MID) -> Void
    let onPanEnded: () -> Void

    func makeUIView(context: Context) -> MTFeedFrame {
        let cfg = UICollectionViewCompositionalLayoutConfiguration()
        cfg.scrollDirection = .vertical
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { _, env in
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                                                heightDimension: .estimated(44)))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                                                           heightDimension: .estimated(44)),
                                                         subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 7
            section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            return section
        }, configuration: cfg)
        let cv = MTFeedCollectionView(frame: .zero, collectionViewLayout: layout)
        cv.keyboardGeometry = keyboardGeometry
        cv.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.backgroundTap))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        cv.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = montanaLongPress
        hold.delegate = context.coordinator   // the feed's pan may go on; a hold that has begun holds the letter
        cv.addGestureRecognizer(hold)
        cv.panGestureRecognizer.maximumNumberOfTouches = 1   // 1 finger scrolls, 2 fingers select
        cv.panGestureRecognizer.addTarget(context.coordinator, action: #selector(Coordinator.kbDragPan(_:)))   // the drag under the keyboard, in numbers
        cv.addGestureRecognizer(MTSelectionPan(target: context.coordinator,
                                               action: #selector(Coordinator.selectPan(_:))))
        context.coordinator.attach(cv, view: self)
        control.view = cv
        control.coordinator = context.coordinator
        let frame = MTFeedFrame(cv: cv)
        frame.reserve = bottomReserve
        let pin = self.pin
        frame.onInset = { inset, speed in
            let set = { if abs(pin.bottomInset - inset) > 0.5 { pin.bottomInset = inset } }
            if let speed {
                withAnimation(MTKeyboardSpring.swiftUI(speed: speed), set)   // the keys' own spring, the button in it
            } else {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t, set)   // the finger's frame: placed at once
            }
        }
        frame.onCover = { cover, speed in
            let set = { if abs(pin.keyboardCover - cover) > 0.5 { pin.keyboardCover = cover } }
            if let speed {
                withAnimation(MTKeyboardSpring.swiftUI(speed: speed), set)   // the keys' own spring, the player in it
            } else {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t, set)
            }
        }
        keyboardGeometry?.feed = frame   // the feed under the keyboard's one transition
        return frame
    }

    func updateUIView(_ frame: MTFeedFrame, context: Context) {
        context.coordinator.view = self
        frame.cv.keyboardGeometry = keyboardGeometry
        keyboardGeometry?.feed = frame
        control.view = frame.cv
        control.coordinator = context.coordinator
        control.newestOnTop = newestOnTop
        frame.cv.newestOnTop = newestOnTop
        frame.reserve = bottomReserve   // the one inset (with the keyboard's share) is applied in the frame's layout
        context.coordinator.apply(rows: rows)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleUIView(_ view: MTFeedFrame, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // A hold that has begun holds the letter: the feed's pan and the taps do not run beside it.
            !(g is UILongPressGestureRecognizer)
        }
        /// A BACKGROUND tap is a tap on the background (the author's word 14.09: playing a voice
        /// must not move the keyboard). Measured: the play glyph of a voice bubble hid the
        /// keyboard — the tap recogniser took every touch of the feed, a bubble's own control
        /// included. A touch that a hosted control claims (the hit view lies inside the cell's
        /// hosted content) is that control's, not the background's; the feed itself, a cell
        /// and its plain content view are the background.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard g is UITapGestureRecognizer, let v = touch.view else { return true }
            // Measured 14.09 (1552): the rows are hosted content (UIHostingConfiguration) — the
            // cell's CONTENT VIEW is the hosting view, and it is what the play glyph's touch
            // names; its empty parts name nothing, so the touch falls to the cell itself. The
            // background is the feed and the cell — never the hosted content view.
            // A TAP ANYWHERE (the author's word 21.09, the reference's list): the background, a cell,
            // a bubble's own content alike. A control inside claims its touch (MTTouchClaim), and the
            // tap's action, one turn later, leaves the keyboard to it.
            let bg = v === cv || v is UICollectionViewCell
            MontanaTrace.mark("feed_tap", "\(bg ? "background" : "content") view=\(String(describing: type(of: v)).prefix(28))")
            return true
        }
        var view: MTFeedListView
        private weak var cv: MTFeedCollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Int, MID>?
        private var prints: [MID: Int] = [:]
        private var firstRowId: MID?
        /// The newest row of the turned feed (its last item, the visual top): a letter that lands there is a birth.
        private var lastRowId: MID?
        private var order: [MID] = []
        private var pendingScroll: MID?
        /// A SENT LETTER BRINGS THE TURNED FEED TO ITS NEWEST (the author's word 05.10.2026 20:3x MSK: «I sent in the money flow
        /// and the feed did not turn to the last message as a chat must; the money flow is a full chat, the new on top»). The
        /// send asks for the newest end before its row is born; the row lands a pass later, while the scroll still flies, and
        /// the reader judged off the top was not held -- the flight ended at the old end, the new letter above it under the
        /// field. The ask is kept until the newest end grows, and that pass pins the reader there.
        private var newestAskedAt: CFTimeInterval = -1
        static let askReach: CFTimeInterval = 2
        func askNewest() { newestAskedAt = CACurrentMediaTime() }
        private var appliedOnce = false
        private var rowsNow: [ChatConversationView.ChatRowVM] = []   // 13.1: the day is read from the model the container already holds
        private var dayHide: Timer?
        private var dayHideAt: CFTimeInterval = 0
        private var dayTop = -1                                        // the top row the day was last read from
        private var rowsById: [MID: ChatConversationView.ChatRowVM] = [:]   // the cell finds its row in one step (the critic 22.09)
        private var stampNow = Int.min
        private var deferredKeyboardRows = false

        init(_ v: MTFeedListView) { self.view = v }

        func stop() {
            cv?.scrollSpring.reset()
            if let cv { MTFrameMeter.shared.end(on: cv) }
            stopEdgeScroll()
            dayHide?.invalidate(); dayHide = nil
            cv?.delegate = nil
            cv?.dataSource = nil
            dataSource = nil
        }

        func attach(_ cv: MTFeedCollectionView, view v: MTFeedListView) {
            self.cv = cv
            self.view = v
            let reg = UICollectionView.CellRegistration<UICollectionViewCell, MID> { [weak self, weak cv] cell, _, id in
                guard let self else { return }
                cv?.scrollSpring.remove(cell)
                cell.transform = .identity; cell.alpha = 1   // a reused cell carries no trace of a birth in flight
                if !(cell.gestureRecognizers?.contains(where: { $0 is MTReplySwipe }) ?? false) {
                    let sw = MTReplySwipe(target: self, action: #selector(Coordinator.replySwipe(_:)))
                    sw.admit = { [weak self, weak cell] p in
                        guard let self, let cell else { return false }
                        return self.swipeAdmitted(cell: cell, point: p)
                    }
                    cell.addGestureRecognizer(sw)
                }
                if id == MTFeedListView.draftID {
                    cell.contentConfiguration = UIHostingConfiguration { self.view.draftContent() }
                        .margins(.all, 0)
                } else if let row = self.rowsById[id] {
                    cell.contentConfiguration = UIHostingConfiguration { self.view.rowContent(row) }
                        .margins(.all, 0)
                    MTFrameMeter.shared.configured(MTFrameMeter.kind(of: row))   // the meter names what a late frame was building
                }
            }
            dataSource = UICollectionViewDiffableDataSource<Int, MID>(collectionView: cv) { cv, ip, id in
                cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: id)
            }
        }

        func apply(rows: [ChatConversationView.ChatRowVM]) {
            guard let cv, let ds = dataSource else { return }
            // A snapshot must not pin the feed under the dragging finger. Apply the latest model
            // once the native gesture ends, including arrivals and media height changes.
            if cv.keyboardGestureActive { deferredKeyboardRows = true; return }
            if appliedOnce, view.stamp == stampNow { finishScrollIfPending(); return }   // nothing the feed draws from has moved
            stampNow = view.stamp
            let applyBegan = CACurrentMediaTime()
            defer { MTFrameMeter.shared.applied(ms: (CACurrentMediaTime() - applyBegan) * 1000) }
            rowsNow = rows
            rowsById = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            dayTop = -1
            var newPrints: [MID: Int] = [:]
            newPrints.reserveCapacity(rows.count)
            for r in rows { newPrints[r.id] = view.fingerprint(r) }
            let changed = rows.compactMap { r -> MID? in
                guard let old = prints[r.id], old != newPrints[r.id] else { return nil }
                return r.id
            }
            let prepended = firstRowId != nil && rows.first?.id != firstRowId
                && rows.contains(where: { $0.id == firstRowId })
            // THE TURNED FEED IS BORN AT ITS TOP (the author's word 03.10 13:35: «the same birth of a bubble, only from the top
            // down»): its rows stand oldest first, so a new letter lands at the END of the list -- the visual top, under the
            // field -- and the front only grows when older letters are read in. The birth follows the newest end in both shapes:
            // the front on the keys, the end under the field. Older letters read in are no birth in either.
            let grewNewest = view.newestOnTop
                ? (lastRowId != nil && rows.last?.id != lastRowId && rows.contains(where: { $0.id == lastRowId }))
                : prepended
            let ids = rows.map(\.id)
            let sameOrder = appliedOnce && ids == order
            let turned = appliedOnce && ids.count > 1 && ids == Array(order.reversed())
            order = ids
            let born = Set(rows.map(\.id)).subtracting(prints.keys)   // the rows this pass gives birth to
            let firstFill = !appliedOnce
            prints = newPrints
            firstRowId = rows.first?.id
            lastRowId = rows.last?.id
            if sameOrder && changed.isEmpty { MTReactClock.seen("feed saw nothing"); finishScrollIfPending(); return }
            cv.scrollSpring.reset()
            // The reacted row's cell height before the change — the plate's growth is a number.
            let reactedId = MTReactClock.tapId
            let cellBefore: CGFloat = reactedId.flatMap { id in ds.indexPath(for: id).flatMap { cv.cellForItem(at: $0)?.bounds.height } } ?? -1
            appliedOnce = true

            let wasAtBottom = cv.contentOffset.y - cv.mtBottomY <= MTFeedCollectionView.holdReach
            let wasAtTop = cv.mtTopY - cv.contentOffset.y <= MTFeedCollectionView.holdReach
            let oldHeight = cv.contentSize.height
            // Where every visible row stands in the viewport BEFORE the change: the birth animation
            // rides each row from here to where the settled layout puts it.
            var before: [MID: CGFloat] = [:]
            for cell in cv.visibleCells {
                if let ip = cv.indexPath(for: cell), let id = ds.itemIdentifier(for: ip) {
                    before[id] = cell.frame.minY - cv.contentOffset.y
                }
            }
            var snap = NSDiffableDataSourceSnapshot<Int, MID>()
            snap.appendSections([0])
            // THE PEER'S LIVE WORDS STAND AT THE NEWEST END (02.10): beside the newest letter -- the visual bottom on the keys,
            // the visual top under the field when the feed is turned (its first item is the visual bottom).
            snap.appendItems(view.newestOnTop ? rows.map(\.id) + [MTFeedListView.draftID] : [MTFeedListView.draftID] + rows.map(\.id))
            if !changed.isEmpty { snap.reconfigureItems(changed) }
            ds.apply(snap, animatingDifferences: false)
            cv.layoutIfNeeded()
            if let id = reactedId, changed.contains(id) {
                let after = ds.indexPath(for: id).flatMap { cv.cellForItem(at: $0)?.bounds.height } ?? -1
                MontanaTrace.mark("react_cell", "before=\(Int(cellBefore)) after=\(Int(after))")
            }
            MTReactClock.seen("rows=\(changed.count)")
            // POSITION IS OUR NUMBER: a prepend at the coordinate top (visual bottom) grows the
            // content above the reader — compensate exactly, or stick to the bottom if they were there.
            // A reader standing at the bottom stays at the bottom, whatever changed the height —
            // not only a new row. A media row is SHORT while its file is still coming and grows
            // when the picture arrives: the rule that watched only prepends left the person half a
            // frame up, scrolling down after the very letter the banner had just announced.
            // With the newest on top the turn, the first fill and a reader standing at the top are held at the newest
            // letter; the turn back lands at the visual bottom, where the newest letter then stands.
            let asked = CACurrentMediaTime() - newestAskedAt <= Self.askReach
            if asked, grewNewest { newestAskedAt = -1 }
            if view.newestOnTop, turned || firstFill || wasAtTop || asked {
                pinNewestOnTop()
            } else if turned {
                cv.setContentOffset(CGPoint(x: 0, y: cv.mtBottomY), animated: false)
                view.pin.atBottom = true
            } else if wasAtBottom {
                cv.setContentOffset(CGPoint(x: 0, y: cv.mtBottomY), animated: false)
                view.pin.atBottom = !view.newestOnTop
            } else if prepended {
                let delta = cv.contentSize.height - oldHeight
                if delta > 0 { cv.contentOffset.y += delta }
            }
            if grewNewest, !firstFill, !born.isEmpty { animateBirth(born: born, before: before, fromTop: view.newestOnTop) }
            finishScrollIfPending()
        }

        /// The cells under the visual top are measured as they come in, so the far end moves while it is reached: the
        /// offset is set, the layout settles, and the end is read again until it stands.
        private func pinNewestOnTop() {
            guard let cv else { return }
            for _ in 0..<4 {
                let y = cv.mtTopY
                cv.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                cv.layoutIfNeeded()
                if abs(cv.mtTopY - y) < 0.5 { break }
            }
            view.pin.atBottom = true
        }

        /// THE BIRTH OF A ROW IS THE CONTAINER'S (the author's word 18.09, stage 7: smooth, no jump,
        /// in its final shape at once, standing under the last bubble — not over it). The snapshot is
        /// applied without animation and the layout settles first, so every cell — the newborn
        /// included — already stands at its final frame in its final size; only then is the motion
        /// drawn, by UIKit, on the cells themselves: the newborn fades in while it rises from below
        /// the feed's edge into its place, and every row that the settled layout moved rides from
        /// where it stood to where it is on the same spring. Nothing is aimed at a guessed rect,
        /// nothing is measured mid-flight; the numbers live in MTLetterMotion ([C-1]).
        private func animateBirth(born: Set<MID>, before: [MID: CGFloat], fromTop: Bool = false) {
            guard !UIAccessibility.isReduceMotionEnabled, let cv, let ds = dataSource else { return }
            var moves: [(UICollectionViewCell, CGFloat)] = []
            var births: [UICollectionViewCell] = []
            for cell in cv.visibleCells {
                guard let ip = cv.indexPath(for: cell), let id = ds.itemIdentifier(for: ip) else { continue }
                if born.contains(id) { births.append(cell) }
                else if let y0 = before[id] {
                    let d = (cell.frame.minY - cv.contentOffset.y) - y0
                    if abs(d) > 0.5 { moves.append((cell, d)) }
                }
            }
            guard !births.isEmpty else { return }
            // In the flipped feed the visual «below» is the smaller content y: the newborn starts a
            // few of its heights under its place, the moved rows start where they stood. With the newest on
            // top the newborn comes from the field above it -- the same way, mirrored: from the larger content y.
            let from: CGFloat = fromTop ? 1 : -1
            for (cell, d) in moves { cell.transform = CGAffineTransform(translationX: 0, y: -d) }
            for cell in births {
                cell.transform = CGAffineTransform(translationX: 0, y: from * cell.bounds.height * MTLetterMotion.rise)
                cell.alpha = 0
            }
            UIView.animate(withDuration: MTLetterMotion.fade, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                births.forEach { $0.alpha = 1 }
            }
            MTLetterMotion.animate {
                for (cell, _) in moves { cell.transform = .identity }
                for cell in births { cell.transform = .identity }
            }
            MontanaTrace.mark("row_birth", "born=\(births.count) moved=\(moves.count) top=\(fromTop ? 1 : 0)")
        }

        func scrollTo(_ id: MID, animated: Bool) {
            guard let cv, let ds = dataSource, let ip = ds.indexPath(for: id) else {
                pendingScroll = id; return
            }
            cv.scrollToItem(at: ip, at: .centeredVertically, animated: animated)
        }
        private func finishScrollIfPending() {
            guard let id = pendingScroll else { return }
            pendingScroll = nil
            scrollTo(id, animated: true)
        }

        @objc func backgroundTap() {
            // One turn later: a control's action has run by then and its claim is on record.
            DispatchQueue.main.async { [weak self] in
                if MTTouchClaim.fresh { MontanaTrace.mark("feed_tap", "claimed - the keyboard stays"); return }
                self?.view.onBackgroundTap()
            }
        }
        @objc func hold(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let cv else { return }   // SILENT-OK: a gesture reports every phase; the menu opens once, at the beginning
            cv.scrollSpring.reset()
            guard let id = rowId(at: g.location(in: cv)) else { return }   // SILENT-OK: a hold on the empty feed asks nothing
            MontanaTrace.markFolded("bubble_hold", "menu", window: 10)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            view.onHold(id)
        }

        private var replyRow: MID?
        private var replyArmed = false
        private var replyThreshold: CGFloat = 45
        // The rubber band, verbatim numbers: linear to the threshold, decaying past it.
        private func band(_ off: CGFloat, start: CGFloat) -> CGFloat {
            if off < start { return off }
            let range: CGFloat = 100, k: CGFloat = 0.4
            return start + (1 - 1 / ((off - start) * k / range + 1)) * range
        }
        private func settleReplyPull() {
            withAnimation(MTLetterMotion.reply) {
                MTSwipePull.shared.v = .init(id: nil)
            }
        }
        // THE LETTER'S LINE, NOT THE BUBBLE'S FACE (the author's word 22.09: a pull beside the bubble
        // answers too). The face gate (1123) was the badge's need — it stood in the window beside the
        // bubble and had to know which one; the row draws the badge itself now (SwipeReplyRow), and the
        // gate never arbitrated against the scroll: the two-point validation does that, wherever the
        // touch began. What stays outside: the day pill and the unread line above the bubble, the draft
        // row, and every row while letters are being selected. Both points in WINDOW space (measured 27.08).
        func swipeAdmitted(cell: UICollectionViewCell, point p: CGPoint) -> Bool {
            guard let cv, let ds = dataSource, !view.isSelecting(),
                  let ip = cv.indexPath(for: cell),
                  let id = ds.itemIdentifier(for: ip), id != MTFeedListView.draftID else { return false }
            guard let rect = MTBubbleFrames.shared.rect(id) else { return true }   // SILENT-OK: no face measured yet — the row's whole cell answers
            return p.y >= rect.minY - 6
        }
        @objc func replySwipe(_ g: UIPanGestureRecognizer) {
            guard let cell = g.view as? UICollectionViewCell, let cv, let ds = dataSource else { return }
            switch g.state {
            case .began:
                replyRow = nil
                guard let ip = cv.indexPath(for: cell),
                      let id = ds.itemIdentifier(for: ip), id != MTFeedListView.draftID else { return }
                replyRow = id
                replyThreshold = (rowsById[id]?.message.isFromMe == true) ? 60 : 45
                replyArmed = false
            case .changed:
                guard let id = replyRow else { return }
                // Birth-point sovereignty: UIKit only reports the pull; the slide and the
                // badge are drawn by our own SwiftUI row (SwipeReplyRow) — no foreign views.
                let pull = max(0, -g.translation(in: cell).x)
                MTSwipePull.shared.v = .init(id: id, tx: band(pull, start: replyThreshold),
                                             progress: min(1, pull / replyThreshold))
                if pull >= replyThreshold, !replyArmed {
                    replyArmed = true
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            case .ended:
                if replyArmed, let id = replyRow { view.onReplySwipe(id) }
                settleReplyPull()
                replyRow = nil
            case .cancelled, .failed:
                settleReplyPull()
                replyRow = nil
            default: break
            }
        }
        private func rowId(at p: CGPoint) -> MID? {
            guard let cv, let ds = dataSource else { return nil }
            if let ip = cv.indexPathForItem(at: p), let id = ds.itemIdentifier(for: ip),
               id != MTFeedListView.draftID { return id }
            // Between the rows: the nearest visible cell by vertical distance answers.
            var best: (MID, CGFloat)?
            for ip in cv.indexPathsForVisibleItems {
                guard let id = ds.itemIdentifier(for: ip), id != MTFeedListView.draftID,
                      let attr = cv.layoutAttributesForItem(at: ip) else { continue }
                let d = abs(attr.frame.midY - p.y)
                if best == nil || d < best!.1 { best = (id, d) }
            }
            return best?.0
        }


        // The drag keeps selecting AT THE EDGES: fingers near the viewport border spin the
        // feed (speed grows with proximity) while the selection follows the finger's row.
        private var edgeLink: CADisplayLink?
        private var panPoint: CGPoint = .zero   // finger position in the VIEWPORT (bounds-local)
        private func manageEdgeScroll() {
            guard let cv else { return }
            let zone: CGFloat = 90
            let h = cv.bounds.height
            let inZone = panPoint.y < zone || panPoint.y > h - zone
            if inZone, edgeLink == nil {
                let l = CADisplayLink(target: self, selector: #selector(edgeTick(_:)))
                l.add(to: .main, forMode: .common)
                edgeLink = l
            } else if !inZone, edgeLink != nil {
                edgeLink?.invalidate(); edgeLink = nil
            }
        }
        private func stopEdgeScroll() { edgeLink?.invalidate(); edgeLink = nil }
        @objc private func edgeTick(_ link: CADisplayLink) {
            guard let cv, cv.window != nil, view.isSelecting(), UIApplication.shared.applicationState == .active
            else { stopEdgeScroll(); return }
            let zone: CGFloat = 90
            let h = cv.bounds.height
            var speed: CGFloat = 0
            // The list is inverted: the viewport's coordinate top is the VISUAL bottom.
            if panPoint.y > h - zone { speed = (panPoint.y - (h - zone)) / zone * 14 }        // visual top -> older
            else if panPoint.y < zone { speed = -((zone - panPoint.y) / zone * 14) }          // visual bottom -> newer
            guard speed != 0 else { return }
            let maxY = max(cv.mtBottomY, cv.contentSize.height - cv.bounds.height + cv.contentInset.bottom)
            let newY = min(maxY, max(cv.mtBottomY, cv.contentOffset.y + speed * CGFloat(min(1.0 / 30, max(0, link.targetTimestamp - link.timestamp))) * 60))
            guard newY != cv.contentOffset.y else { return }
            cv.contentOffset.y = newY
            let content = CGPoint(x: panPoint.x, y: panPoint.y + newY)
            if let id = rowId(at: content) { view.onPanChanged(id) }
        }
        @objc func selectPan(_ g: UIPanGestureRecognizer) {
            guard let cv else { return }
            let p = g.location(in: cv)
            panPoint = CGPoint(x: p.x, y: p.y - cv.contentOffset.y)
            switch g.state {
            case .began:
                guard view.isSelecting() else { return }   // the menu's "Select" opens the mode first
                if let id = rowId(at: p) { view.onPanBegan(id) }
                manageEdgeScroll()
            case .changed:
                guard view.isSelecting() else { return }
                if let id = rowId(at: p) { view.onPanChanged(id) }
                manageEdgeScroll()
            case .ended, .cancelled, .failed:
                stopEdgeScroll()
                view.onPanEnded()
            default: break
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            cv?.beginKeyboardDrag()
            cv?.scrollSpring.begin()
            MTFrameMeter.shared.begin(rows: rowsNow.count, on: scrollView)   // 13.2: measure only while the finger moves
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            finishKeyboardDrag()
            if !decelerate { MTFrameMeter.shared.end("drag") }
        }
        private func finishKeyboardDrag() {
            guard let cv, cv.keyboardGestureActive else { return }
            MontanaTrace.mark("kb_drag_end", "off=\(Int(cv.contentOffset.y))")
            cv.keyboardGestureActive = false
            kbDragCell = nil
            if deferredKeyboardRows {
                deferredKeyboardRows = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.apply(rows: self.view.rows)
                }
            }
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            MTFrameMeter.shared.end("fling")
        }
        /// Window coordinates of the same cell, panel and keyboard throughout one gesture.
        /// Once the keyboard follows the finger, row_bottom and guide must travel together;
        /// feed_bottom stays fixed. No message identifier or text enters the measurement.
        private var kbDragLastFinger: CGFloat = -1
        private weak var kbDragCell: UICollectionViewCell?
        @objc func kbDragPan(_ g: UIPanGestureRecognizer) {
            guard let sv = g.view as? UIScrollView, let w = sv.window else { return }
            switch g.state {
            case .began:
                kbDragLastFinger = -1
                if let cv, let first = cv.indexPathsForVisibleItems.sorted().first(where: { $0.item > 0 }) {
                    kbDragCell = cv.cellForItem(at: first)
                }
            case .changed:
                guard cv?.keyboardGestureActive == true else { return }
                let finger = g.location(in: w).y
                guard abs(finger - kbDragLastFinger) >= 8 else { return }
                kbDragLastFinger = finger
                let guideTop = cv?.keyboardGeometry?.keyboardTop(in: w) ?? -1
                let feedBottom = sv.convert(sv.bounds, to: w).maxY
                let panelTop = sv.superview.map { $0.convert($0.bounds, to: w).maxY } ?? -1
                let rowBottom = kbDragCell.map { $0.convert($0.bounds, to: w).maxY } ?? -1
                let accView = cv?.keyboardGeometry?.accessory
                let acc = accView?.window == nil ? -1 : (accView?.bounds.height ?? -1)
                let accTop = (accView?.window == nil) ? -1 : (accView.map { $0.convert($0.bounds, to: w).minY } ?? -1)
                MontanaTrace.mark("kb_drag", "finger=\(Int(finger)) guide=\(Int(guideTop)) acc=\(Int(acc)) acc_top=\(Int(accTop)) feed_bottom=\(Int(feedBottom)) panel_top=\(Int(panelTop)) row_bottom=\(Int(rowBottom)) inset=\(Int(sv.contentInset.top)) off=\(Int(sv.contentOffset.y))")
            case .cancelled, .failed: finishKeyboardDrag()
            default: break
            }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            cv?.scrollSpring.scroll(enabled: cv?.keyboardGestureActive != true && !view.isSelecting())
            let y = view.newestOnTop ? scrollView.mtTopY - scrollView.contentOffset.y
                : scrollView.contentOffset.y - scrollView.mtBottomY   // from the reading end
            let atBottom = y < 60
            if view.pin.atBottom != atBottom {
                view.pin.atBottom = atBottom
                if atBottom { DispatchQueue.main.async { self.view.onAtBottom() } }
            }
            if y > 260, !view.pin.showDownButton { view.pin.showDownButton = true }
            else if y < 60, view.pin.showDownButton { view.pin.showDownButton = false }
            reportTopDay()
        }

        /// 13.1 — THE DAY AT THE TOP OF THE GLASS. The feed is inverted, so the row a person
        /// reads at the top is the LAST visible one, not the first. The day is read from the row
        /// model the container already holds; the flow's own separators are never touched, moved
        /// or measured — the pill is a layer of ours (the birth-point invariant).
        /// COSTS NOTHING PER FRAME (the critic 22.09): this runs on every tick of the scroll, and it
        /// built a day label — a DateFormatter for a day older than yesterday — and a fresh Timer on
        /// each of them. Now the label is read only when the TOP ROW changes, and one timer sleeps
        /// until a deadline that every tick merely pushes forward.
        private func reportTopDay() {
            guard let cv else { return }
            guard let ds = dataSource,
                  let top = cv.indexPathsForVisibleItems.filter({ ds.itemIdentifier(for: $0) != MTFeedListView.draftID })
                    .max(by: { $0.item < $1.item }),
                  let id = ds.itemIdentifier(for: top), let row = rowsById[id] else { return }
            if top.item != dayTop {
                dayTop = top.item
                let label = MTDayLabel.of(row.message.createdAt)
                if view.pin.topDay != label { view.pin.topDay = label }
            }
            if !view.pin.showDayHeader { view.pin.showDayHeader = true }
            // The pill leaves on its own: every tick pushes the departure further, so it fades a
            // second after the LAST movement rather than in the middle of the travel.
            dayHideAt = CACurrentMediaTime() + 1
            if dayHide == nil { armDayHide(1) }
        }
        private func armDayHide(_ after: TimeInterval) {
            dayHide = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.dayHide = nil
                let left = self.dayHideAt - CACurrentMediaTime()
                if left > 0.02 { self.armDayHide(left) } else { self.view.pin.showDayHeader = false }
            }
        }
        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            // THE COUNT IS THE COLLECTION'S OWN NUMBER (28.09, T1 on the long chat: 461 and then 856 rows under one fling): a
            // snapshot() copied the whole list of the feed's ids at every cell a scroll brought in.
            guard view.hasMoreAbove, dataSource != nil,
                  view.newestOnTop ? indexPath.item <= 1 : indexPath.item >= collectionView.numberOfItems(inSection: 0) - 1
            else { return }
            DispatchQueue.main.async { self.view.onReachTop() }   // the top of the window loads more
        }
        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            cv?.scrollSpring.remove(cell)
        }
        func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool { false }
    }
}
