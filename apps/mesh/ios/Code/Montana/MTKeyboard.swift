import Combine
import SwiftUI
import UIKit

/// The one owner of what the keyboard is doing. A screen that listens for the system notification
/// itself becomes a second owner of one fact, and two owners of one fact drift apart: one of them
/// is always a frame behind, and the feed jumps by exactly that difference.
/// A TAP ANYWHERE ON THE FEED PUTS THE KEYBOARD AWAY (the author's word 21.09: «with them a tap
/// anywhere folds the keyboard, even on a bubble»), UNLESS A CONTROL TOOK THE TOUCH (the author's word
/// 14.09: playing a voice must not move the keyboard). A hosted control cannot be told from plain
/// bubble text by the view a touch names — the whole row is one hosted view — so the control says it
/// itself: its action claims the touch, and the feed's tap, deferred one turn of the loop, finds the
/// claim and keeps the keyboard.
enum MTTouchClaim {
    private static var at: CFTimeInterval = 0
    static func claim() { at = CACurrentMediaTime() }
    static var fresh: Bool { CACurrentMediaTime() - at < 0.3 }
}
final class MTKeyboard: ObservableObject {
    static let shared = MTKeyboard()

    /// The height of the last keyboard seen IN THIS ORIENTATION. The emoji panel takes exactly it, so switching
    /// between the two changes nothing in the geometry of the screen.
    /// PER ORIENTATION (the critic 24.09, T1 03:11:47Z): the keys stand 345 tall upright and 208 sideways on one phone;
    /// one number for both put a sideways-sized panel under an upright keyboard region -- 91 points of the keyboard's
    /// own dark between the bar and the panel after every turn. Each orientation keeps the height its keys were last
    /// seen at; the published height is the current orientation's, re-published as the page turns (MontanaSlideController).
    @Published private(set) var height: CGFloat = 336
    @Published private(set) var isUp = false
    private var heights: [Bool: CGFloat] = [:]   // sideways? : the keys' height
    private static func fallback(sideways: Bool) -> CGFloat { sideways ? 200 : 336 }
    /// The panel that stands as the field's input view, for the judge in the show handler: the keyboard's region and the
    /// panel are two births of one number, and their disagreement is a diary line, not a screenshot (24.09).
    weak var panel: UIView?
    /// Whether an announced keyboard frame is a sideways one: wider than the phone's short side. The window may still be
    /// turning when the frame is announced, so the frame says it, not the window.
    private static func sideways(_ f: CGRect) -> Bool {
        let s = MTScene.size()
        return f.width > min(s.width, s.height) + 1
    }
    /// THE PAGE TURNS (viewWillTransition): the height for the orientation it turns to is published before the platform
    /// measures the panel anew, so the panel is put on at the keys' own height there.
    func turning(to size: CGSize) {
        let side = size.width > size.height
        let h = heights[side] ?? Self.fallback(sideways: side)
        MontanaP2PTrace.mark("rotate", "to=\(Int(size.width))x\(Int(size.height)) keys=\(Int(h))")
        if height != h { height = h }
    }
    /// The chat's accessory (its bar's height in the keyboard's frame): the frame the platform
    /// announces includes it, and the keys' own height is what the emoji panel and the field's
    /// ceiling read — so it is taken off while the accessory stands in the keyboard's window.
    weak var accessory: MTKeyboardAccessorySpacer?

    private var bag: [NSObjectProtocol] = []

    private init() {
        let c = NotificationCenter.default
        bag.append(c.addObserver(forName: UIResponder.keyboardWillShowNotification,
                                 object: nil, queue: .main) { [weak self] n in
            guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
            // THE ACCESSORY AS LAID OUT, NOT AS ASKED (22.09): the announced frame and the accessory's bounds
            // are one layout of the platform's; our own `height` runs ahead of it (T1 20:13:11 read 102).
            let acc: CGFloat = (self?.accessory?.superview == nil) ? 0 : (self?.accessory?.laidHeight ?? 0)
            let h = f.cgRectValue.height - acc
            MontanaP2PTrace.mark("kb_show", "h=\(Int(h)) acc=\(Int(acc)) y=\(Int(f.cgRectValue.minY))")   // the keyboard's every move, in the diary
            MTFrameMeter.shared.moveBegan()   // the keys' rise, to the platform's did-show (25.09)
            guard h > 100 else { return }        // an accessory bar alone is not a keyboard
            // THE PANEL AND THE REGION DISAGREE (the critic 24.09, T1 03:11:48Z: region 299, panel 208 -- the gap the
            // author photographed): a line here, before anyone takes a picture.
            if let p = self?.panel, p.window != nil, abs(p.bounds.height - h) > 1 {
                MontanaP2PTrace.mark("panel_gap", "region=\(Int(h)) panel=\(Int(p.bounds.height))")
            }
            self?.heights[Self.sideways(f.cgRectValue)] = h
            // A VALUE WRITTEN AGAIN IS NOT NEWS (the critic 22.09). Both of these are published, and a
            // publisher fires on every WRITE, not on every change: the platform announces the keyboard
            // many times through one interactive drag with the same height each time, so the whole page
            // rebuilt on each announcement. Measured on T1: `fires=kb:42` inside a single drag of the
            // feed -- 42 rebuilds of the conversation, 189 renders and 840 ms spent building rows, for a
            // height that never moved off 328. The write happens when the fact changes.
            if self?.height != h { self?.height = h }
            if self?.isUp != true { self?.isUp = true }
        })
        bag.append(c.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                 object: nil, queue: .main) { [weak self] _ in
            MontanaP2PTrace.mark("kb_hide", "-")
            MTFrameMeter.shared.moveBegan()   // the keys' fall, to the platform's did-hide (25.09)
            if self?.isUp != false { self?.isUp = false }
        })
        // THE KEYS' MOVE IS MEASURED TO THE PLATFORM'S OWN END (25.09): will-show and will-hide begin the motion meter,
        // did-show and did-hide end it -- one line per rise and fall of the keyboard (motion what=keys:…).
        bag.append(c.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
            MTFrameMeter.shared.moveEnded("keys:up")
        })
        bag.append(c.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
            MTFrameMeter.shared.moveEnded("keys:down")
        })
        bag.append(c.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                 object: nil, queue: .main) { n in
            guard let b = n.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue,
                  let e = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
            let d = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? -1
            MontanaP2PTrace.mark("kb_frame", "y=\(Int(b.cgRectValue.minY))>\(Int(e.cgRectValue.minY)) h=\(Int(e.cgRectValue.height)) d=\(Int(d * 1000))")
        })
    }

    /// THE KEYBOARD'S OWN MOVE REACHES THE PAGE (the author's word 20.09: «the keyboard must lift
    /// the field»). The one owner of the keyboard's facts hands each animated frame change to the
    /// pinned page's geometry, which rides it in the keyboard's spring. The rider is registered
    /// AFTER the page has asked for its guide: the platform's observer is born with the guide, and
    /// observers answer in the order of their birth — ours after it, when the guide's constraint
    /// already holds the keyboard's new edge.
    private var riders: [NSObjectProtocol] = []
    func ride(_ view: UIView, geometry: MTChatKeyboardGeometry) {
        _ = view.keyboardLayoutGuide   // the guide, and with it the platform's observer, is born first
        accessory = geometry.accessory
        riders.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                                             object: nil, queue: .main) { [weak view, weak geometry] n in
            guard let view, view.window != nil, let geometry else { return }
            let d = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            // No transition announced: under a finger the guide's layout pass leads frame by frame;
            // otherwise (the keys folded under a pushed screen, 21.09) the page is placed at the announced end.
            guard d > 0 else { geometry.settle(announced: end); return }
            geometry.rideKeyboard(announced: end)
        })
        // THE PLATFORM'S LAST WORD ON A MOVE (22.09): when the keys have finished going (did-hide, did-change),
        // the page is placed from where the platform finally put them — the sink for every move that ended
        // without a transition to ride (a drag cut short, a hide with no frame to follow).
        for name in [UIResponder.keyboardDidHideNotification, UIResponder.keyboardDidChangeFrameNotification] {
            riders.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak view, weak geometry] _ in
                guard let view, view.window != nil, let geometry else { return }
                geometry.settle(announced: nil)
            })
        }
    }

    deinit { bag.forEach(NotificationCenter.default.removeObserver) }
}


#if DEBUG   // THE TOUCH DIARY LIVES IN DEBUG BUILDS ALONE (App Review 2.5.14, 08.10.2026): a Release build carries none of it
/// EVERY TOUCH IS WRITTEN (24.09, the author's word: «everything must be logged, every pixel»). A field that did not
/// answer the first touch could not be told from a touch that never came: the diary knew the keyboard's moves and not
/// the finger's. A passive recogniser on every window of the app writes where each finger came down and lifted, the
/// view it landed on, how long it stayed and how far it moved; it recognises nothing, delays nothing and cancels
/// nothing, so no control of the app answers differently for it. Every text input's begin and end of editing is
/// written with the field's class and place. Never a word of what is typed: classes and places only.
enum MTTouchDiary {
    private static var started = false
    static func start() {
        guard !started else { return }
        started = true
        let c = NotificationCenter.default
        c.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main) { n in
            if let w = n.object as? UIWindow { watch(w) }
        }
        let edits: [(Notification.Name, String)] = [(UITextField.textDidBeginEditingNotification, "begin field"),
                                                   (UITextField.textDidEndEditingNotification, "end field"),
                                                   (UITextView.textDidBeginEditingNotification, "begin text"),
                                                   (UITextView.textDidEndEditingNotification, "end text")]
        for (note, what) in edits {
            c.addObserver(forName: note, object: nil, queue: .main) { n in
                guard let v = n.object as? UIView else { return }
                let r = v.window.map { v.convert(v.bounds, to: $0) } ?? .zero
                // A VOLLEY IS A NUMBER (25.09): three search fields fighting for the keyboard wrote 1426 of these lines in
                // sixteen seconds on the 15 Pro Max and rotated the hour away. The first of a field's begin or end is
                // written at once; the repeats within two seconds arrive folded, with their count.
                MontanaP2PTrace.markFolded("edit", "\(what) view=\(name(of: v)) x=\(Int(r.minX)) y=\(Int(r.minY)) w=\(Int(r.width)) h=\(Int(r.height))",
                                           window: 2, key: what + name(of: v) + String(Int(r.minX)))
            }
        }
    }
    /// The keyboard's own windows are the system's: the keys are not ours to watch.
    private static func watch(_ w: UIWindow) {
        let kind = String(describing: type(of: w))
        guard !kind.contains("Keyboard"), !kind.contains("TextEffects"),
              !(w.gestureRecognizers ?? []).contains(where: { $0 is MTTouchWitness }) else { return }
        w.addGestureRecognizer(MTTouchWitness())
    }
    static func name(of v: UIView?) -> String {
        guard let v else { return "-" }
        let own = String(String(describing: type(of: v)).prefix(48))
        let up = v.superview.map { String(String(describing: type(of: $0)).prefix(32)) } ?? "-"
        return own + "<" + up
    }
}

/// The witness of every touch (MTTouchDiary): a recogniser that never recognises and never stands in another's way.
final class MTTouchWitness: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var began: [ObjectIdentifier: (at: TimeInterval, p: CGPoint)] = [:]
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
        delegate = self
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches {
            let p = t.location(in: nil)
            began[ObjectIdentifier(t)] = (t.timestamp, p)
            // A VOLLEY OF TOUCHES IS A COUNT (29.09): the first of a two-second window is written whole, the rest as n=.
            MontanaP2PTrace.markFolded("touch", "down x=\(Int(p.x)) y=\(Int(p.y)) view=\(MTTouchDiary.name(of: t.view)) n=\(event.allTouches?.count ?? 1)", window: 2, key: "down")
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, "up") }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, "cancel") }
    private func finish(_ touches: Set<UITouch>, _ how: String) {
        for t in touches {
            let p = t.location(in: nil)
            let b = began.removeValue(forKey: ObjectIdentifier(t))
            let ms = b.map { Int((t.timestamp - $0.at) * 1000) } ?? -1
            let moved = b.map { Int(hypot(p.x - $0.p.x, p.y - $0.p.y)) } ?? -1
            MontanaP2PTrace.markFolded("touch", "\(how) x=\(Int(p.x)) y=\(Int(p.y)) ms=\(ms) moved=\(moved) view=\(MTTouchDiary.name(of: t.view))", window: 2, key: how)
        }
        if began.isEmpty { state = .failed }   // the sequence is over: nothing was ever to be recognised
    }
    override func reset() { super.reset(); began.removeAll() }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif
