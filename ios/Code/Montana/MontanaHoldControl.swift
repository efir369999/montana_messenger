//
//  MontanaHoldControl.swift
//  Montana — a Montana messenger
//
//  THE HOLD BUTTON IS THE PLATFORM'S OWN CONTROL (the author's word 19.09, the reference's model).
//  Measured 16-19.09 on two phones under iOS 18: with the keyboard up, six recordings of six
//  ended as «cancel» — the release of the finger was read as a slide away, the tape was thrown
//  out, and the person tapped the button eight times more into silence. The old button was a
//  SwiftUI drag with a verdict recomputed on every move from the framework's own velocity
//  estimate. The control tracks its own touch in its own coordinates through the platform's
//  press recogniser (08.11.2026: UIControl's beginTracking never ran on T2, iOS 27.0.1), takes the
//  velocity from the platform's pan recogniser, decides ONCE when the finger leaves, on the
//  dominant axis only, and never throws a tape away because the system took the touch: that
//  tape locks and rolls on.
//

import UIKit
import SwiftUI

/// What the control decided when the finger left it — one word for the owner, one line for the diary.
enum MontanaHoldVerdict: String {
    case send, cancel, lock
    case tap      // shorter than the mode timeout: the owner switches the mode
}

final class MontanaHoldControl: UIControl, UIGestureRecognizerDelegate {
    /// The reference's numbers. A press shorter than this is a tap; a longer one records.
    static let modeTimeout: TimeInterval = 0.19
    /// Cancel: a hundred points left at the release, a hundred and fifty on the way, or a flick
    /// left faster than four hundred points a second.
    static let cancelWay: CGFloat = 100
    static let cancelWayLive: CGFloat = 150
    static let flick: CGFloat = 400
    /// Lock: sixty points up at the release (or a flick up), a hundred and ten on the way.
    static let lockWayEnd: CGFloat = 60
    static let lockWayLive: CGFloat = 110
    /// The visual way to the lock plate: the owner's swell rides up by `lift = -dy / lockWay`.
    var lockWay: CGFloat = 72

    var onPressed: (Bool) -> Void = { _ in }              // the finger is down / up: the small glyph sinks
    var onBegan: () -> Void = {}                          // the press outlived the mode timeout: record
    var onMove: (_ lift: CGFloat, _ away: Bool) -> Void = { _, _ in }
    var onVerdict: (MontanaHoldVerdict) -> Void = { _ in }

    private let pan = UIPanGestureRecognizer()
    /// THE PRESS IS THE CONTROL'S OWN RECOGNISER (08.11.2026, the author's word 17811 «on T2 the button does not press»):
    /// T2 (iOS 27.0.1, both apps, every build since 01.11) wrote not one hold_down -- the touch never reached
    /// UIControl's beginTracking, while the send arrow in the same slot, a platform control, answered. A recogniser on the
    /// view takes the touch where the view is hit, before and apart from the view's own touch methods; it delays nothing
    /// and cancels nothing. ONE OWNER of the press: the recogniser; UIControl's tracking is refused (beginTracking).
    private let press = UILongPressGestureRecognizer()
    private var touchLocation = CGPoint.zero
    private var lastVelocity = CGPoint.zero
    private var processing = false
    private var began = false
    private var lastTouchTime: CFAbsoluteTime = 0
    private var modeTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isExclusiveTouch = true
        isMultipleTouchEnabled = false
        pan.cancelsTouchesInView = false
        pan.delegate = self
        addGestureRecognizer(pan)   // reads the velocity only; the press below tracks the finger
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delaysTouchesEnded = false
        press.delegate = self
        press.addTarget(self, action: #selector(pressed(_:)))
        addGestureRecognizer(press)
    }
    required init?(coder: NSCoder) { nil }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    /// THE HIT IS WRITTEN (08.11.2026): a finger the platform hands to this control leaves a line before any
    /// recogniser runs -- a press that never arrives is then told apart from one that arrives and is lost.
    /// THE HIT ARMS THE CONTROL (09.11.2026, the author's word 17930): the touch's first moment is here, not in the recogniser.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        if v === self, event?.type == .touches {
            MontanaTrace.markFolded("hold_hit", "x=\(Int(point.x)) y=\(Int(point.y)) enabled=\(isEnabled ? 1 : 0)", window: 2, key: "hit")
            arm(at: point, by: "hit")
        }
        return v
    }
    /// THE SLOT LEFT THE SCREEN UNDER THE FINGER (11.11.2026): a control taken out of its window gets no more of its touch,
    /// and the press would end unsaid -- the tape rolling with no finger and no lock. It is the system taking the touch:
    /// the tape locks and rolls on, and the crown's controls stand by.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { systemTook() }
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { onPressed(isHighlighted) } }
    }

    /// THE TARGET IS WIDER THAN THE PLATFORM'S LEAST (the author's word 22.09: «I do not always hit it»):
    /// the control's own frame is 56 points on the 36-point slot, and its reach runs on to the screen's
    /// edge at the right and ten points past its frame elsewhere — a thumb at the edge lands on it.
    static let target: CGFloat = 56
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        CGRect(x: -10, y: -8, width: bounds.width + 10 + 40, height: bounds.height + 16).contains(point)
    }

    /// UIControl's own tracking stays off: the press recogniser is the one owner of the finger.
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { false }

    @objc private func pressed(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began: arm(at: p, by: "press")
        case .changed: moved(to: p)
        case .ended: up(at: p)
        case .cancelled, .failed: systemTook()
        default: break
        }
    }

    /// THE PRESS IS COUNTED FROM THE FINGER'S ARRIVAL (T1 09.11.2026, the author's word 17930: «the voice button does not press,
    /// everything went crooked»). The press recogniser's .began reached this control 156-164 ms after the hit (T1 01:22:04.722 to
    /// .878 and 12:30:03.516 to .680 UTC), and the 190 ms mode timeout ran from .began: a tape rolled only from the 350th
    /// millisecond of a press, and a press of 200-340 ms -- a hold by any hand's reckoning -- was read as a tap and swapped the
    /// glyph for the camera. The reference counts from beginTracking, the touch's first moment (TGModernConversationInputMicButton.m:712-743);
    /// here that moment is the hit (hitTest), so the hit arms the control and the timeout runs from it. The recogniser's .began
    /// only confirms the finger and writes how late it came; when no hit was seen it arms as before.
    private var hitAt: CFAbsoluteTime = 0
    private func arm(at: CGPoint, by: String) {
        if processing {
            if by == "press" { MontanaTrace.mark("hold_press", "late=\(Int((CFAbsoluteTimeGetCurrent() - hitAt) * 1000))ms began=\(began ? 1 : 0)") }
            return   // the hit armed this press already (or a second hit-test of the same touch)
        }
        // The touch's arrival is written before any verdict: a tap that never reaches the control
        // is then a missing line, not a guess (measured 19.09: six locked taps, no line at all).
        MTHoldOverlayState.shared.follow()   // where the slot IS, before anything is drawn over it
        MontanaTrace.mark("hold_down", "x=\(Int(at.x)) y=\(Int(at.y)) w=\(Int(bounds.width)) h=\(Int(bounds.height)) mount=\(MTHoldOverlayWindow.mountKind) ay=\(Int(MTHoldOverlayState.shared.anchor.y)) by=\(by) enabled=\(isEnabled ? 1 : 0)")
        lastVelocity = .zero
        processing = false
        guard isEnabled else { return }   // a locked tape: the crown's own controls take the finger
        if abs(CFAbsoluteTimeGetCurrent() - lastTouchTime) < 0.4 { return }   // a second press right after the first is a bounce, not a hold
        processing = true
        began = false
        isHighlighted = true
        lastTouchTime = CFAbsoluteTimeGetCurrent()
        hitAt = lastTouchTime
        touchLocation = at
        modeTimer?.invalidate()
        modeTimer = Timer.scheduledTimer(withTimeInterval: Self.modeTimeout, repeats: false) { [weak self] _ in
            guard let self, self.processing else { return }
            self.began = true
            self.onBegan()
        }
    }

    private func moved(to p: CGPoint) {
        lastVelocity = pan.velocity(in: self)
        guard processing, began else { return }   // before the mode timeout nothing rides yet
        let dx = min(0, p.x - touchLocation.x), dy = min(0, p.y - touchLocation.y)
        if dx < -Self.cancelWayLive { settle(.cancel, dx: dx, dy: dy, why: "live"); return }
        if dy < -Self.lockWayLive { settle(.lock, dx: dx, dy: dy, why: "live"); return }
        onMove(min(1, max(0, -dy / lockWay)), dx < -Self.cancelWay)
    }

    private func up(at p: CGPoint) {
        modeTimer?.invalidate(); modeTimer = nil
        isHighlighted = false
        guard processing else { return }
        guard began else { processing = false; onVerdict(.tap); return }
        var dx = min(0, p.x - touchLocation.x), dy = min(0, p.y - touchLocation.y)
        // ONE AXIS DECIDES (the reference): a thumb rolling off the button diagonally is judged
        // by its dominant way, never as «left» and «up» at once.
        if abs(dy) < abs(dx) { dy = 0 } else { dx = 0 }
        let v = lastVelocity
        let verdict: MontanaHoldVerdict
        if v.x < -Self.flick || dx < -Self.cancelWay { verdict = .cancel }
        else if v.y < -Self.flick || dy < -Self.lockWayEnd { verdict = .lock }
        else { verdict = .send }
        settle(verdict, dx: dx, dy: dy, why: "end")
    }

    private func systemTook() {
        modeTimer?.invalidate(); modeTimer = nil
        isHighlighted = false
        guard processing else { return }
        processing = false
        guard began else { return }   // a tap the system took back: nothing recorded, nothing to say
        // THE SYSTEM TOOK THE TOUCH, NOT THE PERSON (the reference): the tape is not thrown away —
        // a second later it locks and rolls on, and the arrow sends it.
        MontanaTrace.mark("hold_end", "verdict=lock why=system-cancel mount=\(MTHoldOverlayWindow.mountKind)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.onVerdict(.lock) }
    }

    private func settle(_ v: MontanaHoldVerdict, dx: CGFloat, dy: CGFloat, why: String) {
        processing = false
        isHighlighted = false
        MontanaTrace.mark("hold_end", "verdict=\(v.rawValue) why=\(why) dx=\(Int(dx)) dy=\(Int(dy)) vx=\(Int(lastVelocity.x)) vy=\(Int(lastVelocity.y)) mount=\(MTHoldOverlayWindow.mountKind)")
        onVerdict(v)
    }
}

/// The control in the bar's slot: a bare, transparent UIControl the size of its touch target;
/// what is drawn under it (the small glyph) and above it (the swell, in the top window) is the
/// owner's. It holds ONLY the finger that never left the button: a locked tape's arrow, pause
/// and bin are the crown's own controls, in the crown's window — this one sleeps until the
/// recording is over. NATIVE-CHECKED: the platform has no hold-to-record control of its own;
/// the reference builds on UIControl's touch tracking; here the press recogniser carries the finger (08.11.2026).
struct MontanaHoldButton: UIViewRepresentable {
    var enabled: Bool
    var lockWay: CGFloat
    var onPressed: (Bool) -> Void
    var onBegan: () -> Void
    var onMove: (CGFloat, Bool) -> Void
    var onVerdict: (MontanaHoldVerdict) -> Void

    func makeUIView(context: Context) -> MontanaHoldControl {
        let c = MontanaHoldControl()
        c.backgroundColor = .clear
        MTHoldOverlayState.shared.slot = c   // the one view the crown measures from
        return c
    }
    func updateUIView(_ c: MontanaHoldControl, context: Context) {
        c.isEnabled = enabled
        c.lockWay = lockWay
        c.onPressed = onPressed
        c.onBegan = onBegan
        c.onMove = onMove
        c.onVerdict = onVerdict
    }
}
