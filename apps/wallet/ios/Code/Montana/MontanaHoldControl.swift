//
//  MontanaHoldControl.swift
//  Montana — a Montana messenger
//
//  THE HOLD BUTTON IS THE PLATFORM'S OWN CONTROL (the author's word 19.09, the reference's model).
//  Measured 16-19.09 on two phones under iOS 18: with the keyboard up, six recordings of six
//  ended as «cancel» — the release of the finger was read as a slide away, the tape was thrown
//  out, and the person tapped the button eight times more into silence. The old button was a
//  SwiftUI drag with a verdict recomputed on every move from the framework's own velocity
//  estimate. A UIControl tracks its own touch in its own coordinates (beginTracking /
//  continueTracking / endTracking / cancelTracking), takes the velocity from the platform's pan
//  recogniser, decides ONCE when the finger leaves, on the dominant axis only, and never throws
//  a tape away because the system took the touch: that tape locks and rolls on.
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
        addGestureRecognizer(pan)   // reads the velocity only; the control tracks the touch itself
    }
    required init?(coder: NSCoder) { nil }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

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

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard super.beginTracking(touch, with: event) else { return false }
        // The touch's arrival is written before any verdict: a tap that never reaches the control
        // is then a missing line, not a guess (measured 19.09: six locked taps, no line at all).
        let at = touch.location(in: self)
        MTHoldOverlayState.shared.follow()   // where the slot IS, before anything is drawn over it
        MontanaP2PTrace.mark("hold_down", "x=\(Int(at.x)) y=\(Int(at.y)) w=\(Int(bounds.width)) h=\(Int(bounds.height)) mount=\(MTHoldOverlayWindow.mountKind) ay=\(Int(MTHoldOverlayState.shared.anchor.y))")
        lastVelocity = .zero
        if abs(CFAbsoluteTimeGetCurrent() - lastTouchTime) < 0.4 {
            processing = false   // a second press right after the first is a bounce, not a hold
            return false
        }
        processing = true
        began = false
        lastTouchTime = CFAbsoluteTimeGetCurrent()
        touchLocation = touch.location(in: self)
        modeTimer?.invalidate()
        modeTimer = Timer.scheduledTimer(withTimeInterval: Self.modeTimeout, repeats: false) { [weak self] _ in
            guard let self, self.processing else { return }
            self.began = true
            self.onBegan()
        }
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard super.continueTracking(touch, with: event) else { return false }
        lastVelocity = pan.velocity(in: self)
        guard processing, began else { return true }   // before the mode timeout nothing rides yet
        let p = touch.location(in: self)
        let dx = min(0, p.x - touchLocation.x), dy = min(0, p.y - touchLocation.y)
        if dx < -Self.cancelWayLive { settle(.cancel, dx: dx, dy: dy, why: "live"); return false }
        if dy < -Self.lockWayLive { settle(.lock, dx: dx, dy: dy, why: "live"); return false }
        onMove(min(1, max(0, -dy / lockWay)), dx < -Self.cancelWay)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        modeTimer?.invalidate(); modeTimer = nil
        guard processing else { return }
        guard began else { processing = false; onVerdict(.tap); return }
        let p = touch?.location(in: self) ?? touchLocation
        var dx = min(0, p.x - touchLocation.x), dy = min(0, p.y - touchLocation.y)
        // ONE AXIS DECIDES (the reference): a thumb rolling off the button diagonally is judged
        // by its dominant way, never as «left» and «up» at once.
        if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 }
        let v = lastVelocity
        let verdict: MontanaHoldVerdict
        if v.x < -Self.flick || dx < -Self.cancelWay { verdict = .cancel }
        else if v.y < -Self.flick || dy < -Self.lockWayEnd { verdict = .lock }
        else { verdict = .send }
        settle(verdict, dx: dx, dy: dy, why: "end")
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        modeTimer?.invalidate(); modeTimer = nil
        guard processing else { return }
        processing = false
        guard began else { return }   // a tap the system took back: nothing recorded, nothing to say
        // THE SYSTEM TOOK THE TOUCH, NOT THE PERSON (the reference): the tape is not thrown away —
        // a second later it locks and rolls on, and the arrow sends it.
        MontanaP2PTrace.mark("hold_end", "verdict=lock why=system-cancel mount=\(MTHoldOverlayWindow.mountKind)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.onVerdict(.lock) }
    }

    private func settle(_ v: MontanaHoldVerdict, dx: CGFloat, dy: CGFloat, why: String) {
        processing = false
        MontanaP2PTrace.mark("hold_end", "verdict=\(v.rawValue) why=\(why) dx=\(Int(dx)) dy=\(Int(dy)) vx=\(Int(lastVelocity.x)) vy=\(Int(lastVelocity.y)) mount=\(MTHoldOverlayWindow.mountKind)")
        onVerdict(v)
    }
}

/// The control in the bar's slot: a bare, transparent UIControl the size of its touch target;
/// what is drawn under it (the small glyph) and above it (the swell, in the top window) is the
/// owner's. It holds ONLY the finger that never left the button: a locked tape's arrow, pause
/// and bin are the crown's own controls, in the crown's window — this one sleeps until the
/// recording is over. NATIVE-CHECKED: the platform has no hold-to-record control of its own;
/// UIControl's touch tracking is the mechanism the reference builds on.
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
