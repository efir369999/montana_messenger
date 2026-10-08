import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════
// 13.0.2: THE CHAT LIST'S OWN CONTAINER — the law the feed already lives by
// (stage 11, frozen), carried to the second screen. The list used to be handed to
// the renderer as a freshly built array inside a lazy stack, in the hope that it
// would work out the difference by itself; what it worked out was "everything is
// new". Here the difference is not hoped for, it is computed: a snapshot keyed by
// the conversation's address, rows that did not change left untouched, and a move
// applied as a move — one row travels, the rest stand still.
// ═══════════════════════════════════════════════════════════════════════════
final class MTChatCollectionView: UICollectionView {
    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        // The frame names the bar's insets whole (the run-on, the player's room, the coin's gap): the safe area is not
        // added over them a second time, or the bar would stop short of the rows it measures (MTChatListFrame.setInsets).
        automaticallyAdjustsScrollIndicatorInsets = false
        keyboardDismissMode = .onDrag
        alwaysBounceVertical = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        MontanaMainProbe.firstTouch()   // the touch reached the list (15.25)
        return super.hitTest(point, with: event)
    }
}

/// A ROW OF THE CANVAS (MTChatListView.canvasRow; the author's words 26.09: «in this style, as the settings, only the margins
/// at the sides 8»): the list's own cell, as a row of the settings' list is, wearing the posts' glass as its background's own
/// view -- one glass for the cell's life, in the platform's list background, which the list rounds at the first and the last
/// cell of a run with the platform's own radius, as it rounds the settings' rows.
final class MTCanvasCell: UICollectionViewListCell {
    override func preferredLayoutAttributesFitting(_ a: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let began = CACurrentMediaTime()
        defer { MTFrameMeter.shared.sized(ms: (CACurrentMediaTime() - began) * 1000) }
        return super.preferredLayoutAttributesFitting(a)
    }
    private let glass: UIHostingController<AnyView> = {
        let h = MontanaHost.make(MTGlassRowPlate().ignoresSafeArea())
        h.view.backgroundColor = .clear
        return h
    }()
    func wearCanvas() {
        var bg: UIBackgroundConfiguration
        if #available(iOS 18.0, *) { bg = .listCell() } else { bg = .listGroupedCell() }
        bg.backgroundColor = .clear
        bg.customView = glass.view
        backgroundConfiguration = bg
    }
}

final class MTListCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(_ a: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let began = CACurrentMediaTime()
        defer { MTFrameMeter.shared.sized(ms: (CACurrentMediaTime() - began) * 1000) }
        return super.preferredLayoutAttributesFitting(a)
    }
}

/// THE ROWS RUN ON TO THE SCREEN'S EDGES, AS THE CHAT'S LETTERS DO (the author's word 23.09: «the chat list in the
/// same style above and below — the feed to the end of the screen, as in the chats»). The chat's construction
/// (MTFeedFrame) carried to the list: the page lays the list out exactly where it always stood — the proven column
/// under the time panel — and this view runs the collection on past that frame to the window's top and bottom, the
/// insets keeping every row where it stood. NOTHING IS HANDED BACK TO THE PAGE: the list under the bars of
/// 1436–1439 died of a layout recursion between SwiftUI and UIKit born of exactly that (measured insets fed into
/// the page's layout, the checklist 15.52.50.3); here the page's layout depends on nothing this view does.
/// Past the frame the rows sink into the ground by the chat's own wash (MTEdgeWash's numbers). The ground behind the
/// rows is the page's own, so the rows fade in their own layer rather than the ground being drawn a second time over
/// them: the same two layers, the same arithmetic, one drawing less. Touches still end at this view's bounds.
final class MTChatListFrame: UIView {
    let cv: MTChatCollectionView
    /// The rows run on past the frame: every page under the time panel (the author's word 23.09) — the panel's list
    /// (MontanaTimePanelList) says this one word for them all, and they stand on the page's one ground; a list
    /// elsewhere (an archive pushed over the page) keeps its frame.
    var runsToEdges = false {
        didSet {
            guard runsToEdges != oldValue else { return }
            cv.mtHideEdgeEffects(runsToEdges)   // the edge is the wash's, not the system's blur (as the chat's feed)
            setNeedsLayout()
        }
    }
    /// A row of the page stands between the bar and the list with no plate of its own (the archive row): the rows
    /// stop at the list's top while it stands, as they always did — they must not show through it.
    var headFloats = false { didSet { if headFloats != oldValue { fade(animated: true) } } }
    /// The search holds the list at its top: the rows stop at the list's bottom, and its results stand alone.
    var pinned = false { didSet { if pinned != oldValue { fade(animated: true) } } }
    /// Room for a bar floating over the rows' bottom (the player): part of the bottom inset.
    var reserve: CGFloat = 0 { didSet { if reserve != oldValue { setInsets(); setNeedsLayout() } } }   // the arrow to the top stands over it too
    /// The gap the coin keeps open while its round completes: part of the top inset.
    var hold: CGFloat = 0 { didSet { if hold != oldValue { setInsets() } } }
    /// THE PAGE, NAMED IN THE DIARY (the critic 23.09): «list_edges» named no page, and the run-on of the contacts
    /// could be told from the chats' only by the moment of the tab's switch.
    var page = ""
    /// THE LIST OPENS AT ITS END (the gallery, 25.09: the newest at the bottom, as the platform's photos open at their
    /// newest): asked once by the list after its first rows are applied, done in the next two layouts -- the second lands on
    /// the rows sized by the first -- and never again: a person's scroll is theirs.
    private var endPasses = 0
    func showEnd() { endPasses = 2; setNeedsLayout() }
    private func landAtEnd() {
        guard endPasses != 0, cv.numberOfSections != 0 else { return }
        let s = cv.numberOfSections - 1   // the last section: the list's own, or the canvas's last run (canvasRow)
        let n = cv.numberOfItems(inSection: s)
        guard n != 0 else { return }
        cv.layoutIfNeeded()
        cv.scrollToItem(at: IndexPath(item: n - 1, section: s), at: .bottom, animated: false)
        endPasses -= 1
        if endPasses != 0 { setNeedsLayout() }
    }
    /// The rows are numbered beside the platform's scroll bar while the list scrolls (the music page) — MTRowNumber.
    var numbered = false {
        didSet {
            guard numbered != oldValue else { return }
            cv.showsVerticalScrollIndicator = numbered
            if !numbered { number.hide(animated: false) }
        }
    }
    private let number = MTRowNumber()
    private let toTop = MTToTopButton()   // the arrow back to the list's top (the author's word 30.09), MTToTopButton
    private var laying = false       // the frame moving the list itself: no scroll of the person's, the number keeps still
    private var over: CGFloat = 0    // the run-on above the frame, as applied
    private var under: CGFloat = 0   // the run-on below the frame, as applied
    private let edgeFade = CAGradientLayer()

    init(cv: MTChatCollectionView) {
        self.cv = cv
        super.init(frame: .zero)
        clipsToBounds = false   // the rows run on under the bar and the home strip; what stands there covers them
        addSubview(cv)
        addSubview(toTop)    // over the rows at the bottom right; the platform's own button takes its own touch
        toTop.addTarget(self, action: #selector(toTheTop), for: .primaryActionTriggered)
        addSubview(number)   // over the rows; it takes no touch itself — a press on it is the list's (grip)
        grip.minimumPressDuration = 0.12
        grip.allowableMovement = 12
        grip.delegate = gripGate
        gripGate.allow = { [weak self] g in self?.mayGrip(g) ?? false }
        cv.addGestureRecognizer(grip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
    /// The run-on is a distance to the window's edges: a move of this view is a new run-on even at the same size,
    /// whichever of the two the page sets.
    override var center: CGPoint { didSet { if center != oldValue { setNeedsLayout() } } }
    override var frame: CGRect { didSet { if frame.origin != oldValue.origin { setNeedsLayout() } } }

    /// How far the window's top stands above this view's top, and its bottom below this view's bottom, in this
    /// view's own points — MEASURED, never assumed: the status strip, the bar, the home strip, the selection bar.
    private var runOn: (top: CGFloat, bottom: CGFloat) {
        guard runsToEdges, let w = window else { return (0, 0) }
        let top = convert(CGPoint(x: 0, y: w.bounds.minY), from: w).y
        let bottom = convert(CGPoint(x: 0, y: w.bounds.maxY), from: w).y
        return (max(0, -top), max(0, bottom - bounds.maxY))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1 else { return }
        laying = true; defer { laying = false }
        let run = runOn
        // THE LIST'S OWN OFFSET IS KEPT — zero with its head at the frame's top: the rows ride with the list's top
        // exactly as they did while the collection was the frame (the archive row's fold moves the top, not the rows).
        let own = cv.contentOffset.y + over
        let f = CGRect(x: 0, y: -run.top, width: bounds.width, height: bounds.height + run.top + run.bottom)
        if cv.frame != f { cv.frame = f }
        if run.top != over || run.bottom != under {
            over = run.top; under = run.bottom
            // Folded: a frame the page animates may lay this view out on every frame of the move.
            MontanaP2PTrace.markFolded("list_edges", "page=\(page) over=\(Int(over)) under=\(Int(under)) h=\(Int(bounds.height))")
        }
        setInsets()
        if abs(cv.contentOffset.y - (own - over)) > 0.5 { cv.contentOffset.y = own - over }
        fade(animated: false)
        landAtEnd()
        placeTop()
        showTop()
    }

    /// The one inset of each edge: the run-on, and what the page keeps open there (the coin's gap, the player).
    private func setInsets() {
        let want = UIEdgeInsets(top: over + hold, left: 0, bottom: under + reserve, right: 0)
        guard cv.contentInset != want else { return }
        let was = laying; laying = true; defer { laying = was }
        cv.contentInset = want
        cv.verticalScrollIndicatorInsets = want
    }

    /// THE ARROW'S PLACE, FROM ITS NEIGHBOURS' OWNERS (the author's word 30.09 ~00:45: «the arrow up at the bottom right corner»):
    /// at the right edge as the pages' own corner button, over the player's room (reserve, the player's owner) and, on a page under
    /// the bar, over the page's corner button (MTPageCorner) -- the bar itself stands below this view's bottom.
    private func placeTop() {
        let side = MTToTopButton.side
        let corner = runsToEdges ? MTPageCorner.room : 0
        let axis = runsToEdges ? MTPageCorner.axis : MTPageCorner.edge + side / 2   // on a page, over the action's own centre
        let c = CGPoint(x: bounds.width - axis, y: bounds.height - reserve - corner - MTPageCorner.edge - side / 2)
        if toTop.center != c { toTop.center = c }
    }
    /// The arrow stands while the list's first screen is out of sight and leaves when the list is back at its top; never while
    /// the search holds the list still.
    private func showTop() {
        let ins = cv.adjustedContentInset
        let screen = cv.bounds.height - ins.top - ins.bottom
        toTop.stand(cv.isScrollEnabled && 0 < screen && screen < cv.contentOffset.y + ins.top)
    }
    /// A tap on the arrow: the platform's own animated scroll to the list's top, said to the diary.
    @objc private func toTheTop() {
        MontanaP2PTrace.markFolded("list_top", "page=\(page)", key: page)
        cv.setContentOffset(CGPoint(x: cv.contentOffset.x, y: -cv.adjustedContentInset.top), animated: true)
    }

    /// The number's rail: the rows' count, the bar's track as the platform's indicator measures it, the list's range.
    private func rail() -> (n: Int, top: CGFloat, track: CGFloat, range: CGFloat)? {
        let n = max(0, (0..<cv.numberOfSections).reduce(0) { a, s in a + cv.numberOfItems(inSection: s) } - 1)   // the head stands first, in either shape
        let bar = cv.verticalScrollIndicatorInsets, ins = cv.adjustedContentInset
        let top = cv.frame.minY + bar.top, track = cv.bounds.height - bar.top - bar.bottom
        let range = cv.contentSize.height + ins.top + ins.bottom - cv.bounds.height
        guard 0 < n, 1 < range, MTRowNumber.height * 2 < track else { return nil }
        return (n, top, track, range)
    }
    /// A row's place among the rows, from 1: every item before it counted, the head (the list's first) being 0 -- one section
    /// or the canvas's sections alike (MTChatListView.canvasRow).
    private func ordinal(_ ip: IndexPath) -> Int {
        var n = ip.item
        for s in 0..<ip.section { n += cv.numberOfItems(inSection: s) }
        return n
    }
    /// The list's place along the rail, as the finger reads it: its offset's share of the range, at the rail's height.
    private func railY(_ r: (n: Int, top: CGFloat, track: CGFloat, range: CGFloat)) -> CGFloat {
        let f = min(1, max(0, (cv.contentOffset.y + cv.adjustedContentInset.top) / r.range))
        return r.top + MTRowNumber.height / 2 + f * (r.track - MTRowNumber.height)
    }
    /// THE PLATFORM'S THUMB, MEASURED, NOT RECKONED (the author's picture 30.09 00:44, the big player's playlist on its sheet: the
    /// number «15» stood some forty points above the platform's bar, where the music page's number rides beside it). On a sheet the
    /// platform lays its bar by a room of its own that no inset of ours names; so the number rides the middle of the platform's own
    /// indicator -- the scroll view's own subview -- read in this view's points, and names the row at that height. Nil while it
    /// does not stand: the number rides the rail as reckoned (railY). One owner of the number's place for every list.
    private func thumbMiddle() -> CGFloat? {
        for v in cv.subviews where v.bounds.width < v.bounds.height {
            guard String(describing: type(of: v)).hasSuffix("ScrollIndicator"), !v.isHidden, 0 < v.alpha else { continue }
            return convert(v.center, from: cv).y
        }
        return nil
    }
    /// A scroll of the list: the arrow to the top stands or leaves; the number rides beside the bar's thumb and names the row
    /// standing at its height.
    func scrolled() {
        showTop()
        guard numbered, !laying, cv.isScrollEnabled else { return }   // the search's hold on the top is no scroll either
        guard let r = rail() else { number.hide(animated: true); return }
        let half = MTRowNumber.height / 2
        let y = min(r.top + r.track - half, max(r.top + half, thumbMiddle() ?? railY(r)))
        let spot = CGPoint(x: cv.bounds.midX, y: cv.contentOffset.y + y - cv.frame.minY)
        let item = cv.indexPathForItem(at: spot).map(ordinal) ?? (y - r.top < r.track / 2 ? 1 : r.n)
        // Item 0 is the head: no row stands at the thumb yet.
        guard item != 0 else { number.hide(animated: true); return }
        let n = r.n
        if number.show(min(n, max(1, item)), right: bounds.width - MTRowNumber.gap, centerY: y) {
            // Whether the platform tells a drag of its bar from a drag of the rows is measured, not assumed: «other» is any
            // scroll neither the hand nor its coast drives — the bar's drag, or the platform's own (the status bar's tap).
            let by = cv.isTracking ? "hand" : cv.isDecelerating ? "coast" : "other"
            MontanaP2PTrace.markFolded("list_number", "page=\(page) rows=\(n) by=\(by)", key: page + by)
        }
    }
    /// THE NUMBER TAKEN BY THE FINGER (the author's word 24.09: «let me press the number: it clings, it grows, and the
    /// music's list scrolls by it»): the finger's height along the bar's track is the list's place, as the platform's
    /// own thumb reads it; the list follows at once, the platform's bar shown beside it all the while. THE NUMBER IS
    /// TAKEN BY A PRESS ON IT, A TAP BESIDE THE BAR GOES TO ITS ROW (the critic 24.09: the number's own target took every
    /// touch beside the bar for a second and a half, and a row touched there did not play): the press is the list's own,
    /// begins only on the number standing in view, on the platform's least target around it, after a short hold — a
    /// tap fails it and falls to the list's selection; a drag before the hold is the list's scroll.
    private lazy var grip = UILongPressGestureRecognizer(target: self, action: #selector(gripped(_:)))
    private let gripGate = MTGestureGate()
    private var gripOffset: CGFloat = 0   // the finger's distance from the list's place on the rail when it took it (railY)
    private func mayGrip(_ g: UIGestureRecognizer) -> Bool {
        guard numbered, cv.isScrollEnabled, number.standing else { return false }   // the search's pin holds the list still
        let p = g.location(in: self), c = number.center, w = number.bounds.width
        return CGRect(x: c.x - w / 2 - 10, y: c.y - 22, width: w + 20, height: 44).contains(p)
    }
    @objc private func gripped(_ g: UILongPressGestureRecognizer) {
        let at = g.location(in: self)
        guard numbered, let r = rail() else { number.release(); return }
        switch g.state {
        case .began:
            cv.setContentOffset(cv.contentOffset, animated: false)   // a coasting list stops under the finger
            gripOffset = at.y - railY(r)   // the rail's place, not the number's: the number rides the platform's thumb
            number.take()
            cv.flashScrollIndicators()
            MontanaP2PTrace.markFolded("list_number", "held page=\(page) rows=\(r.n)", key: page + "held")
        case .changed:
            let half = MTRowNumber.height / 2
            let y = min(r.top + r.track - half, max(r.top + half, at.y - gripOffset))
            let f = (y - r.top - half) / (r.track - MTRowNumber.height)
            cv.setContentOffset(CGPoint(x: cv.contentOffset.x, y: f * r.range - cv.adjustedContentInset.top), animated: false)
            cv.flashScrollIndicators()   // the platform's bar stands beside the number while the finger moves it
        default:
            number.release()
        }
    }

    /// THE CHAT'S WASH AS THE ROWS' OWN FADE (MTEdgeWash): the wash lays the ground over the letters at `alpha`, and a
    /// row drawn at 1 − alpha × wash over the same ground makes the same picture by the same arithmetic. Six stops in
    /// every mode, so a change of mode is one smooth animation of the same six.
    private func fade(animated: Bool) {
        guard runsToEdges, cv.frame.height > 1 else { if layer.mask != nil { layer.mask = nil }; return }
        if layer.mask !== edgeFade { layer.mask = edgeFade }
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(0.3) } else { CATransaction.setDisableActions(true) }
        edgeFade.frame = cv.frame
        let stops = Self.fadeStops(height: cv.frame.height, top: over, bottom: over + bounds.height,
                                   up: !headFloats, down: !pinned)
        edgeFade.locations = stops.map { NSNumber(value: Double($0.at)) }
        edgeFade.colors = stops.map { UIColor(white: 0, alpha: $0.alpha).cgColor }
        CATransaction.commit()
    }

    /// The rows' alpha over the collection's height `h`, the list's frame standing from `top` to `bottom` in it —
    /// straight between the stops, as the wash's own gradient is. Up: the chat's top wash over its fade, gone at the
    /// list's top: the list's first row is the search, a control, and a control stands over the wash as the chat's
    /// pinned plate does (22.09) — inside the frame nothing changes. Down: the chat's bottom wash, from its reach
    /// above the list's bottom (the panel's top in the chat), whole after its fade. Not up, not down: nothing past
    /// the edge, as before.
    static func fadeStops(height h: CGFloat, top: CGFloat, bottom: CGFloat, up: Bool, down: Bool) -> [(at: CGFloat, alpha: CGFloat)] {
        let a = CGFloat(MTEdgeWash.alpha)
        let clear = top, solid = clear - MTEdgeWash.topFade
        func above(_ y: CGFloat) -> CGFloat { 1 - a * min(1, max(0, (clear - y) / MTEdgeWash.topFade)) }
        let start = bottom - MTEdgeWash.bottomReach, whole = start + MTEdgeWash.bottomFade
        func below(_ y: CGFloat) -> CGFloat { 1 - a * min(1, max(0, (y - start) / MTEdgeWash.bottomFade)) }
        func loc(_ y: CGFloat) -> CGFloat { min(1, max(0, y / h)) }
        var s: [(at: CGFloat, alpha: CGFloat)] = up
            ? [(0, above(0)), (loc(solid), above(max(0, solid))), (loc(clear), 1)]
            : [(0, 0), (loc(top), 0), (loc(top), 1)]
        s += down
            ? [(loc(start), 1), (loc(whole), below(min(h, whole))), (1, below(h))]
            : [(loc(bottom), 1), (loc(bottom), 0), (1, 0)]
        for i in 1..<s.count where s[i].at < s[i - 1].at { s[i].at = s[i - 1].at }   // a list too short for both meets them in the middle
        return s
    }
}

/// THE TRACK'S NUMBER BESIDE THE BAR (the author's word 24.09: «on the music list, at the right, the bar while it
/// scrolls, and beside the bar, in the native manner, the track's number in the list»). The bar is the platform's own
/// scroll indicator; on a long list the platform lets the finger take it and drag. NATIVE-CHECKED: the platform draws no
/// word beside its indicator (UIScrollView names none; a list's index strip, indexTitles, is another control and stands
/// always), so the number is ours in the platform's own dress: its material in a capsule, its label colour, digits of one
/// width. It rides the bar's height and names the row standing there: the bar's place in its track is the list's place
/// in its rows, so the row at the bar's height is the one it has reached. It comes with a scroll and leaves as the bar does;
/// taken by a press on it, it clings, grows, steps aside from the finger and moves the list (MTChatListFrame.gripped).
final class MTRowNumber: UIView {
    static let height: CGFloat = 28
    /// From the list's right edge to the number's: beside the platform's thumb, clear of it.
    static let gap: CGFloat = 14
    /// Taken by the finger, the number grows and steps this far aside, so the finger that holds it does not cover it.
    static let lift: CGFloat = 60
    private let plate = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let label = UILabel()
    private var shown = 0
    private var leave: DispatchWorkItem?
    private(set) var held = false
    var standing: Bool { 0.01 < alpha }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false   // a touch here is the list's: its press takes the number, its tap the row
        alpha = 0
        plate.clipsToBounds = true
        plate.layer.cornerCurve = .continuous
        plate.layer.cornerRadius = Self.height / 2
        addSubview(plate)
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        plate.contentView.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Taken: the platform's light impact, the plate grows and steps aside from the finger, and stays while held.
    func take() {
        held = true
        leave?.cancel(); leave = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            self.alpha = 1
            self.transform = CGAffineTransform(translationX: -Self.lift, y: 0).scaledBy(x: 1.35, y: 1.35)
        }
    }
    /// Let go: the plate returns to its place and leaves a moment after.
    func release() {
        guard held else { return }
        held = false
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState]) { self.transform = .identity }
        linger()
    }

    /// The number `n`, its right edge at `right`, its middle at `centerY`; true when it was not standing. Its place is
    /// set by its middle and its size, never by its frame: the frame of a view carrying a transform is not its own.
    @discardableResult func show(_ n: Int, right: CGFloat, centerY: CGFloat) -> Bool {
        // USER-DATA: the row's place in the list, digits.
        if n != shown { shown = n; label.text = String(n) }
        let w = max(Self.height, ceil(label.intrinsicContentSize.width) + 20)
        let size = CGSize(width: w, height: Self.height)
        if bounds.size != size { bounds = CGRect(origin: .zero, size: size); plate.frame = bounds; label.frame = bounds }
        let c = CGPoint(x: right - w / 2, y: centerY)
        if center != c { center = c }
        if !held { linger() }
        guard alpha < 1 else { return false }
        if !held, alpha == 0 { transform = CGAffineTransform(translationX: Self.gap + w / 2, y: 0) }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
            self.alpha = 1
            if !self.held { self.transform = .identity }
        }
        return true
    }
    /// The number leaves a moment after the last move — long enough for the finger to reach it after a fling — and
    /// never while the finger holds it.
    private func linger() {
        leave?.cancel()
        let l = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        leave = l
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: l)
    }
    func hide(animated: Bool) {
        guard !held else { return }
        leave?.cancel(); leave = nil
        guard 0 < alpha else { return }
        if animated { UIView.animate(withDuration: 0.3) { self.alpha = 0 } } else { alpha = 0 }
    }
}

/// THE PAGES' CORNER, ONE MEASURE (the author's words 30.09 ~00:45 and 01.10 00:42: «the action button of the contacts, the calls,
/// the chats and the VPN aligned by the chats' reference, everywhere by one function; the arrow up centred on the action
/// button»): every page's own button at the bottom right (mtPageAction) stands its centre one row over the list's bottom, as the
/// chats' write has stood since 17.09 -- the bar's tier tall, its centre this far from the right edge; the list's arrow to the
/// top stands over it on the same vertical line (MTChatListFrame.placeTop).
enum MTPageCorner {
    static var lift: CGFloat { MTLibraryRow.height - MontanaOctagon.barHeight / 2 }
    static let edge: CGFloat = 16   // from the right edge, and the arrow's gap over its neighbour
    static var room: CGFloat { lift + MontanaOctagon.barHeight }
    /// The action's centre from the right edge: the arrow's vertical line.
    static var axis: CGFloat { edge + MontanaOctagon.barHeight / 2 }
}

extension View {
    /// THE PAGE'S ACTION, ONE FUNCTION (MTPageCorner): the button at the bottom right of every page under the time panel, over the
    /// player's room when the bar stands (reserve), and away while the page says it must not stand.
    func mtPageAction<A: View>(reserve: CGFloat = 0, shown: Bool = true, @ViewBuilder _ action: () -> A) -> some View {
        let a = action()
        return overlay(alignment: .bottomTrailing) {
            if shown { a.padding(.trailing, MTPageCorner.edge).padding(.bottom, MTPageCorner.lift + reserve) }
        }
    }
}

/// BACK TO THE TOP (the author's word 30.09 ~00:45: «when you scroll down any feed -- the walls, the VPN, the music, the playlist --
/// the button at the right, the arrow up, at the bottom right corner»): the platform's own round button in the system's glass --
/// the thin material before it -- with the platform's arrow glyph and no word, one for every list of this container
/// (MTChatListFrame owns it, never a page). A target of the platform's 44 points; it takes its own touch.
final class MTToTopButton: UIButton {
    static let side: CGFloat = 44
    private(set) var standing = false
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        var c: UIButton.Configuration
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            c = .glass()
        } else {
            c = .plain()
            c.background.customView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }
        c.cornerStyle = .capsule
        c.image = UIImage(systemName: "arrow.up")
        c.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        c.baseForegroundColor = .label
        configuration = c
        accessibilityLabel = String(localized: "Back to top", bundle: MTLanguage.bundle)
        alpha = 0
        isUserInteractionEnabled = false
        transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// Comes and leaves as the platform's own controls do: a short fade with a small scale; out of sight it takes no touch.
    func stand(_ on: Bool) {
        guard on != standing else { return }
        standing = on
        isUserInteractionEnabled = on
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = on ? 1 : 0
            self.transform = on ? .identity : CGAffineTransform(scaleX: 0.6, y: 0.6)
        }
    }
}

/// A new ticket is a new ask to scroll the row to the middle.
struct MTListFocus: Equatable {
    let id: String
    let ticket: Int
}

/// A gesture's one question — may it begin — answered by its owner.
final class MTGestureGate: NSObject, UIGestureRecognizerDelegate {
    var allow: (UIGestureRecognizer) -> Bool = { _ in true }
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { allow(g) }
}

/// THE SEARCH FIELD OF THE PAGES IS THE PLATFORM'S OWN (the author's word 26.09, the picture of the system's Files page: «the search
/// field as in the picture, fully the system's in every parameter, on every page -- and check that the old mistake where the search
/// field hung the app does not come back»): the system's search bar in its minimal style -- its capsule and its fill, its magnifier,
/// its placeholder, its clear key, its return key named «search», its microphone where the system shows one -- at the height the
/// platform lays it out. Nothing of ours is drawn around it or inside it. It reports focus through its delegate, so a page knows the
/// field is active from inside a hosted cell; the page drops focus by the binding (the cross), and the field resigns.
struct MTChatListView: UIViewRepresentable {
    static let headID = "mt-chat-list-head"

    let rows: [Chat]
    let headPrint: Int
    /// One print per field, in the order of `fieldNames` — so a row that «changed» can say which
    /// of its fields did (15.14: 26 applies of eleven rows all «changed» on T1 without a name).
    let fingerprint: (Chat) -> [Int]
    static let fieldNames = ["name", "order", "title", "avatar", "preview", "reaction", "picture", "time", "status", "unread", "forced", "muted", "pinned", "selecting", "selected", "blocked", "draft", "model"]
    /// THE SWIPE IS THE CONTAINER'S OWN (15.26). A SwiftUI drag gesture inside a hosted cell took
    /// the touch before the collection's pan could start: measured 07.09 09:35:06 — the touch
    /// reached the list in 287 ms, the main thread was free (worst 7 ms), and no drag began for
    /// twelve seconds. The platform's swipe actions are arbitrated with scrolling by the system,
    /// and an open row is closed by the system the moment the list scrolls.
    let swipeLeading: (Chat) -> [SwipeTile]
    let swipeTrailing: (Chat) -> [SwipeTile]
    let swipesEnabled: Bool
    let onOpen: (Chat) -> Void
    let rowContent: (Chat) -> AnyView
    let headContent: () -> AnyView
    let onPull: (CGFloat) -> Void
    /// THE HOLD IS THE CONTAINER'S OWN (16.09, the same law as the swipe): a SwiftUI long press
    /// inside a hosted cell took the touch from the collection, and a tap stopped selecting the
    /// row — the chat did not open (1617). The platform's recognizer on the collection arbitrates
    /// with the scroll and with the selection itself, as the platform's own lists do.
    /// A page with nothing to do on a hold passes none: the press then gives no haptic of a deed that does not come
    /// (the critic 24.09: the music's rows buzzed and did nothing).
    var onHold: ((Chat) -> Void)? = nil
    /// WHICH ROWS A HOLD MAY BEGIN ON (the critic 25.09, the network page): a row that holds buttons of its own keeps its
    /// touches -- a hold that begins there cancels the button's press (the platform's cancelsTouchesInView), and a finger
    /// that rested on the power button a quarter second pressed nothing -- and a row without a deed gives no haptic. Nil:
    /// every row, as on a page whose every row has a deed.
    var holdsRow: ((Chat) -> Bool)? = nil
    /// The pull on the whole feed: fetch what the network holds for us. The coin spins meanwhile.
    var onRefresh: () async -> Void = {}
    /// The coin has turned its full round and the feed is fetched: the same press as the logo
    /// (the author's word 11.09) — the bar unfolds or folds.
    var onSettled: () -> Void = {}
    /// The search holds focus: the list stands at its top, the field in view, and does not scroll.
    var pinTop: Bool = false
    /// Room kept at the bottom for the bar that floats over the rows (the player): the rows
    /// scroll under it and show through — the same construction as the chat's feed.
    var bottomReserve: CGFloat = 0
    /// The rows run on to the screen's edges (the author's word 23.09) — see MTChatListFrame.
    var runsToEdges = false
    /// A row of the page floats between the bar and the list (the archive row): the rows stop at the list's top.
    var headFloats = false
    /// The page's name for the diary (MTChatListFrame.page).
    var page = ""
    /// The names of the page's own print, in its order (the chats': `fieldNames`), so a changed row says which of its
    /// fields moved; a page that gives none is told by the fields' places (the critic 24.09: the chats' names read over
    /// the music's, the calls' and the contacts' prints named the wrong fields).
    var fieldNames: [String]? = nil
    /// The platform's scroll bar at the right while the list scrolls, the row's number beside it (MTRowNumber).
    var numbered = false
    /// Whether the page this list stands on is looked at (mtPaneLive, 25.09): off the screen, nothing is applied past the
    /// first snapshot — the rows it was born with stand ready for the moment it slides in.
    var live = true
    /// The list opens at its end once its first rows are applied (the gallery, 25.09) -- MTChatListFrame.showEnd.
    var endFirst = false
    /// THE ROWS AS ONE CANVAS, AS THE SETTINGS' SECTIONS (the author's words 26.09: «round the first and the last so that it
    /// looks as the canvas in the settings», «you draw nothing yourself: natively, systemically, as the settings page does»):
    /// the rows this names stand in the platform's own inset grouped sections -- the first and the last of each run rounded
    /// by the platform with its own radius, laid anew whenever a row comes or goes, the run the least margin off the sides
    /// (MTPageEdge.canvas); a row it does not name stands alone between two runs, in a plain section. Nil: the plain list.
    var canvasRow: ((Chat) -> Bool)? = nil
    /// THE PLATFORM'S SEPARATOR UNDER THE ROWS THIS NAMES (the author's words 28.09, the App Library's list): the plain list's own
    /// separator, from the words' edge to the margin on the right (MTLibraryRow); never over the first row, never under the head.
    /// Nil -- no separator, as every other page stands.
    var separatorRow: ((Chat) -> Bool)? = nil
    /// THE TRAILING TILE TAKES THE ROW OUT (the big player's playlist, the author's word 29.09 ~23:22: «the tracks' bubbles in the
    /// playlist with the swipe of deletion, short and long»): the platform's own destructive tile -- its red, the tile's glyph, no
    /// word -- and the long swipe performs it, as the platform's own lists delete. Every other page keeps its glass tiles and no
    /// long swipe to the left (17.09).
    var trailingDestroys = false
    var focus: MTListFocus? = nil

    func makeUIView(context: Context) -> MTChatListFrame {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.backgroundColor = .clear
        config.showsSeparators = separatorRow != nil
        if separatorRow != nil {
            config.itemSeparatorHandler = { [weak coordinator = context.coordinator] ip, given in
                var line = given
                line.topSeparatorVisibility = .hidden
                line.bottomSeparatorVisibility = coordinator?.separates(ip) == true ? .visible : .hidden
                line.bottomSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: MTLibraryRow.textLead, bottom: 0, trailing: MTLibraryRow.side)
                return line
            }
        }
        config.leadingSwipeActionsConfigurationProvider = { [weak coordinator = context.coordinator] ip in coordinator?.swipes(at: ip, leading: true) }
        config.trailingSwipeActionsConfigurationProvider = { [weak coordinator = context.coordinator] ip in coordinator?.swipes(at: ip, leading: false) }
        let layout = canvasRow == nil ? UICollectionViewCompositionalLayout.list(using: config) : Self.canvasLayout(plain: config, coordinator: context.coordinator)
        let cv = MTChatCollectionView(frame: .zero, collectionViewLayout: layout)
        cv.delegate = context.coordinator
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = montanaLongPress
        hold.allowableMovement = 12
        cv.addGestureRecognizer(hold)
        context.coordinator.rowHold = hold
        hold.delegate = context.coordinator   // the hold asks the page which rows it may begin on (holdsRow)
        // Our own pull-to-refresh: the coin sits in the gap above the first row, the list measures the pull.
        let coin = MontanaHost.make(MontanaCoinSpinner(pull: 0, released: nil))
        coin.view.backgroundColor = .clear
        coin.view.frame = CGRect(x: 0, y: 0, width: MontanaCoinSpinner.side, height: MontanaCoinSpinner.side)
        coin.view.layer.zPosition = 1
        cv.addSubview(coin.view)
        context.coordinator.coin = coin
        context.coordinator.attach(cv, view: self)
        let host = MTChatListFrame(cv: cv)
        context.coordinator.host = host
        return host
    }

    func updateUIView(_ host: MTChatListFrame, context: Context) {
        let cv = host.cv
        context.coordinator.view = self
        // A LIST NOT LOOKED AT APPLIES NOTHING PAST ITS FIRST SNAPSHOT (25.09, mtPaneLive): its page stands off the screen with
        // the rows it last showed; the first pass after it is looked at applies what changed meanwhile.
        if live || !context.coordinator.appliedOnce { context.coordinator.apply(rows: rows, head: headPrint) }
        // THE INSETS HAVE ONE OWNER, THE FRAME: the run-on, the player's room and the coin's gap together.
        host.page = page
        host.runsToEdges = runsToEdges
        host.headFloats = headFloats
        host.pinned = pinTop
        host.reserve = bottomReserve
        host.numbered = numbered
        // A page with nothing to do on a hold takes no hold at all: the press would cancel the list's own touches for
        // nothing — a finger held on a track a quarter second played nothing (the critic 24.09).
        context.coordinator.rowHold?.isEnabled = onHold != nil
        cv.isScrollEnabled = !pinTop
        let top = -cv.adjustedContentInset.top   // the head at the list's top, wherever the frame runs on
        if pinTop, cv.contentOffset.y > top { cv.setContentOffset(CGPoint(x: 0, y: top), animated: false) }
        if !pinTop, let f = focus { context.coordinator.focus(f) }
    }

    /// The canvas's layout (canvasRow): the head's section and a row between two runs plain, as the list always was; a run of
    /// canvas rows a section of the platform's inset grouped list -- the settings' own appearance -- stood the least margin off
    /// the sides, with nothing above or below it: the platform rounds its first and last cell, the rows keep their rhythm.
    static func canvasLayout(plain: UICollectionLayoutListConfiguration, coordinator: Coordinator) -> UICollectionViewCompositionalLayout {
        var g = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        g.backgroundColor = .clear
        g.showsSeparators = false
        g.leadingSwipeActionsConfigurationProvider = plain.leadingSwipeActionsConfigurationProvider
        g.trailingSwipeActionsConfigurationProvider = plain.trailingSwipeActionsConfigurationProvider
        let grouped = g
        return UICollectionViewCompositionalLayout { [weak coordinator] index, env in
            guard coordinator?.onCanvas(index) == true else { return NSCollectionLayoutSection.list(using: plain, layoutEnvironment: env) }
            let s = NSCollectionLayoutSection.list(using: grouped, layoutEnvironment: env)
            s.contentInsetsReference = UIContentInsetsReference.none
            s.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: MTPageEdge.canvas, bottom: 0, trailing: MTPageEdge.canvas)
            return s
        }
    }

    static func dismantleUIView(_ view: MTChatListFrame, coordinator: Coordinator) {
        MTFrameMeter.shared.end(on: view.cv)
        view.cv.delegate = nil
        view.cv.dataSource = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        var view: MTChatListView
        private weak var cv: MTChatCollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        private var prints: [String: Int] = [:]
        private var fields: [String: [Int]] = [:]
        private var order: [String] = []
        private var rowsByID: [String: Chat] = [:]
        private var coinPull: CGFloat = 0
        private var coinRelease: Date?
        private(set) var appliedOnce = false
        /// Which sections are runs of the canvas (canvasRow), in the order applied: the head's is not, nor a row between two runs.
        private var canvasSections: [Bool] = []
        func onCanvas(_ section: Int) -> Bool { canvasSections.indices.contains(section) && canvasSections[section] }
        private var dragFrom: CGFloat = 0
        var coin: UIHostingController<AnyView>?
        weak var host: MTChatListFrame?   // the one owner of the insets: the coin's gap goes through it
        weak var rowHold: UILongPressGestureRecognizer?   // the rows' hold, on only where the page has a deed for it
        private var released: (at: Date, angle: Double)?
        private var held = false    // the feed's top inset carries `hold` while the round completes
        private var armed = false   // the pull has crossed the trigger: one tap of the haptic

        init(_ v: MTChatListView) { self.view = v }

        private var focusTicket = 0
        func focus(_ f: MTListFocus) {
            guard f.ticket != focusTicket, let cv, let ip = dataSource?.indexPath(for: f.id) else { return }
            focusTicket = f.ticket
            // THE ROW AT THE MIDDLE BETWEEN THE PLAYER AND THE SCREEN'S TOP (the author's word 01.10 00:44): the platform's
            // «centred» centres in the whole list, under the time panel and the floating player alike; the row stands here at the
            // middle of what the person sees above the player -- the list's own bottom room (its inset) left out.
            cv.layoutIfNeeded()
            guard let a = cv.layoutAttributesForItem(at: ip) else { return }
            let ins = cv.adjustedContentInset
            let middle = (cv.bounds.height - ins.bottom) / 2
            let lowest = max(-ins.top, cv.contentSize.height - cv.bounds.height + ins.bottom)
            let y = min(lowest, max(-ins.top, a.frame.midY - middle))
            cv.setContentOffset(CGPoint(x: cv.contentOffset.x, y: y), animated: true)
            MontanaP2PTrace.mark("list_focus", "page=\(view.page) item=\(ip.item)")
        }

        /// Resolve every action through the applied snapshot, including during animated reorders.
        private func row(at ip: IndexPath) -> Chat? {
            guard let id = dataSource?.itemIdentifier(for: ip) else { return nil }
            return rowsByID[id]
        }
        /// Whether the row at `ip` wears the platform's separator (MTChatListView.separatorRow): the head never, a row the page
        /// names always.
        func separates(_ ip: IndexPath) -> Bool {
            guard let rule = view.separatorRow, let r = row(at: ip) else { return false }
            return rule(r)
        }
        func swipes(at ip: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
            guard view.swipesEnabled, let r = row(at: ip) else { return nil }
            let tiles = leading ? view.swipeLeading(r) : view.swipeTrailing(r)
            guard !tiles.isEmpty else { return nil }
            let destroys = !leading && view.trailingDestroys
            let actions = tiles.map { t -> UIContextualAction in
                let a = UIContextualAction(style: destroys ? .destructive : .normal, title: nil) { _, _, done in t.action(); done(true) }
                a.image = UIImage(systemName: t.icon)
                if !destroys { a.backgroundColor = UIColor(t.color) }   // one style for every tile: the glass; a destroying one the platform's red
                return a
            }
            let c = UISwipeActionsConfiguration(actions: leading ? actions : actions.reversed())
            // A full swipe left to right performs the first tile — the audio call (the author's word 17.09);
            // right to left it never does: the first tile there is delete -- unless the page's trailing tile takes the row out
            // (trailingDestroys: the playlist, 29.09), which the long swipe performs as the platform's lists do.
            c.performsFirstActionWithFullSwipe = leading || destroys
            return c
        }
        func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
            cv.deselectItem(at: ip, animated: false)
            if let r = row(at: ip) { view.onOpen(r) }
        }
        /// A hold on a row: the haptic and the row, once, the moment the press is recognized.
        @objc func hold(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let act = view.onHold, let cv, let ip = cv.indexPathForItem(at: g.location(in: cv)), let r = row(at: ip) else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            act(r)
        }
        /// The hold begins only on a row the page names (holdsRow); elsewhere it fails and cancels nothing.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g === rowHold, let can = view.holdsRow, let cv else { return true }
            guard let ip = cv.indexPathForItem(at: g.location(in: cv)), let r = row(at: ip) else { return false }
            return can(r)
        }
        /// The pull, in points past the feed's own top; the held gap does not count as a pull.
        private func pull(_ sv: UIScrollView) -> CGFloat {
            -(sv.contentOffset.y + sv.adjustedContentInset.top - (held ? MontanaCoinSpinner.hold : 0))
        }
        /// A TAP ON THE STATUS BAR WITH THE CALL FOLDED IS THE WAY BACK TO THE CALL (the author's word 24.09: «on the
        /// iPhone 13 a tap on the clock's green bubble does nothing -- it must return to the call»). The platform hands a
        /// tap on the status bar to an app as the scroll-to-top gesture, and only when ONE scroll view onscreen takes it
        /// (UIScrollView.scrollsToTop); on the pages under the time panel this list is the page's own scroller. With a
        /// call folded the tap returns to the call and the list stays where it stands. Whether the platform handed the
        /// tap over is measured, not assumed: «call_clock tap by=list» in the diary, or its absence after a tap.
        func scrollViewShouldScrollToTop(_ sv: UIScrollView) -> Bool {
            !MTCallClockBubble.returnToCall(by: "list")
        }
        func scrollViewDidScroll(_ sv: UIScrollView) {
            host?.scrolled()
            guard let coin else { return }
            let pull = max(0, self.pull(sv))
            // Finishing, the coin keeps the middle of the held gap; in the hand, the middle of the pull.
            let y = released != nil ? -MontanaCoinSpinner.hold / 2 : -pull / 2
            coin.view.center = CGPoint(x: sv.bounds.width / 2, y: y)
            // Ordinary scrolling keeps pull at zero; no hosted-root update is needed.
            if pull != coinPull || released?.at != coinRelease {
                coinPull = pull; coinRelease = released?.at
                MontanaHost.reroot(coin, MontanaCoinSpinner(pull: pull, released: released), why: "coin")
            }
            if released == nil, sv.isDragging {
                let over = pull >= MontanaCoinSpinner.pullTrigger
                if over != armed {
                    armed = over
                    if over { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                }
            }
        }
        private func beginRefresh(_ sv: UIScrollView) {
            released = (Date(), MontanaCoinSpinner.angle(forPull: pull(sv)))
            held = true
            UIView.animate(withDuration: 0.25) { self.host?.hold = MontanaCoinSpinner.hold }
            // The bar answers the hand, not the network (the author's word 11.09): the toggle is
            // immediate; the fetch runs on its own and shows itself as letters arriving.
            view.onSettled()
            Task { @MainActor [weak self] in await self?.view.onRefresh() }
            DispatchQueue.main.asyncAfter(deadline: .now() + MontanaCoinSpinner.finish + 0.15) { [weak self, weak sv] in
                guard let self, let sv else { return }
                self.released = nil
                self.held = false
                UIView.animate(withDuration: 0.3) { self.host?.hold = 0 }
                self.scrollViewDidScroll(sv)
            }
        }

        func attach(_ cv: MTChatCollectionView, view v: MTChatListView) {
            self.cv = cv
            self.view = v
            // The head has its own reuse identifier: a shared one handed the head's cell to a row, and the head was rebuilt
            // from nothing each time it scrolled back.
            let headReg = UICollectionView.CellRegistration<MTListCell, String> { [weak self] cell, _, _ in
                guard let self else { return }
                var bg = UIBackgroundConfiguration.listPlainCell()
                bg.backgroundColor = .clear
                cell.backgroundConfiguration = bg
                MTFrameMeter.shared.configured("head")
                cell.contentConfiguration = UIHostingConfiguration { self.view.headContent() }
                    .margins(.all, 0)
            }
            let reg = UICollectionView.CellRegistration<MTListCell, String> { [weak self] cell, _, id in
                guard let self, let row = self.rowsByID[id] else { return }
                var bg = UIBackgroundConfiguration.listPlainCell()
                bg.backgroundColor = .clear
                cell.backgroundConfiguration = bg
                MTFrameMeter.shared.configured("row")
                cell.contentConfiguration = UIHostingConfiguration { self.view.rowContent(row) }
                    .margins(.all, 0)
            }
            // A ROW OF THE CANVAS IS THE LIST'S OWN CELL WEARING THE GLASS IN ITS OWN BACKGROUND (MTCanvasCell), as a settings row
            // wears its own: the list rounds that background at the first and the last cell of a run. 1954 handed the glass to the
            // hosting configuration's background beside the cell's own background configuration, and on the phone the rows stood
            // with no glass at all (the author's picture, 26.09 02:01). The row's bubble, told it stands on the canvas, draws no plate.
            let canvasReg = UICollectionView.CellRegistration<MTCanvasCell, String> { [weak self] cell, _, id in
                guard let self, let row = self.rowsByID[id] else { return }
                MTFrameMeter.shared.configured("row")
                cell.wearCanvas()
                cell.contentConfiguration = UIHostingConfiguration { self.view.rowContent(row).environment(\.mtRowOnCanvas, true) }
                    .margins(.all, 0)
            }
            dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: cv) { [weak self] cv, ip, id in
                if id == MTChatListView.headID { return cv.dequeueConfiguredReusableCell(using: headReg, for: ip, item: id) }
                if self?.onCanvas(ip.section) == true { return cv.dequeueConfiguredReusableCell(using: canvasReg, for: ip, item: id) }
                return cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: id)
            }
        }

        /// THE WHOLE LAW OF THE LIST, in one place: what moved, what changed, and nothing else.
        /// When the order is the same and no row's number differs, this returns without touching
        /// the screen at all - and that silence is the point of the whole item.
        func apply(rows: [Chat], head: Int) {
            guard let ds = dataSource else { return }
            MontanaMainProbe.crumb = "list-apply rows=\(rows.count)"; defer { MontanaMainProbe.crumb = "" }
            let began = ProcessInfo.processInfo.systemUptime
            var touched = false, reconfigured = 0
            defer { MTListWork.note(ms: (ProcessInfo.processInfo.systemUptime - began) * 1000, rows: rows.count, changed: reconfigured, idle: !touched) }
            let ids = [MTChatListView.headID] + rows.map(\.id)
            var newPrints: [String: Int] = [MTChatListView.headID: head]
            var newFields: [String: [Int]] = [:]
            newPrints.reserveCapacity(rows.count + 1)
            for r in rows {
                let f = view.fingerprint(r); newFields[r.id] = f
                var h = Hasher(); h.combine(f); newPrints[r.id] = h.finalize()
            }
            let changed = ids.filter { id in
                guard let old = prints[id], let now = newPrints[id] else { return false }
                return old != now
            }
            let sameOrder = appliedOnce && ids == order
            // WHICH FIELD CHANGED, by name, for the first changed row: the diary used to say
            // «changed=11» and nothing else, and a number nobody can argue with is not a measure.
            var why = ""
            if let first = changed.first(where: { $0 != MTChatListView.headID }), let a = fields[first], let b = newFields[first], a.count == b.count {
                let names = view.fieldNames ?? []
                why = " field=" + zip(a, b).enumerated().filter { $0.element.0 != $0.element.1 }
                    .map { $0.offset < names.count ? names[$0.offset] : "f\($0.offset)" }.joined(separator: ",")
            }
            rowsByID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            prints = newPrints
            fields = newFields
            order = ids
            if sameOrder && changed.isEmpty { return }
            touched = true; reconfigured = changed.count
            // The measure of this whole item, in one line and only when work is actually done:
            // how many rows moved and how many were reconfigured. "The list redraws" is a
            // feeling; "moved=1 changed=1 of 40" is a fact, and only a fact can be argued with.
            MontanaP2PTrace.mark("chat_list",
                "apply rows=\(rows.count) moved=\(sameOrder ? 0 : 1) changed=\(changed.count) page=\(view.page.isEmpty ? "list" : view.page)" + why)
            var snap = NSDiffableDataSourceSnapshot<Int, String>()
            if let canvasRow = view.canvasRow {
                // THE CANVAS'S SECTIONS (canvasRow): the head alone; each run of canvas rows one section; a row between two runs
                // one plain section of its own. The layout reads which is which (onCanvas), so it is said before the apply.
                var kinds = [false]
                var runs = [[MTChatListView.headID]]
                for r in rows {
                    let on = canvasRow(r)
                    if !on || kinds.last != true { kinds.append(on); runs.append([]) }
                    runs[runs.count - 1].append(r.id)
                }
                canvasSections = kinds
                snap.appendSections(Array(kinds.indices))
                for (i, run) in runs.enumerated() { snap.appendItems(run, toSection: i) }
            } else {
                snap.appendSections([0])
                snap.appendItems(ids)
            }
            if !changed.isEmpty { snap.reconfigureItems(changed) }
            ds.apply(snap, animatingDifferences: appliedOnce && !sameOrder && !UIAccessibility.isReduceMotionEnabled)
            if !appliedOnce, view.endFirst { host?.showEnd() }   // the first rows are in: the list opens at its end (the gallery)
            appliedOnce = true
        }

        // The two directions the page already understood, reported by the view that owns the
        // scroll instead of a gesture riding on top of it.
        func scrollViewWillBeginDragging(_ sv: UIScrollView) {
            dragFrom = sv.contentOffset.y
            MontanaMainProbe.firstDrag()
            MTFrameMeter.shared.begin(rows: view.rows.count, on: sv)
        }
        func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate: Bool) {
            if released == nil, pull(sv) >= MontanaCoinSpinner.pullTrigger { beginRefresh(sv) }
            armed = false
            view.onPull(dragFrom - sv.contentOffset.y)
            if !willDecelerate { MTFrameMeter.shared.end(view.page.isEmpty ? "list" : view.page) }   // the page's own name (the critic 24.09)
        }
        func scrollViewDidEndDecelerating(_ sv: UIScrollView) { MTFrameMeter.shared.end(view.page.isEmpty ? "list" : view.page) }
    }
}
