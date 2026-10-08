import UIKit
import SwiftUI

/// The size of OUR window, not of the display. The global screen answers with other numbers under
/// mirroring, an external display, Display Zoom or a split view, so layout would diverge per device
/// and per setting. One window, one truth — and one place that decides what to use when a view has
/// not measured itself yet.
enum MTScene {
    static func size() -> CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let w = active?.windows.first(where: { $0.isKeyWindow }) ?? active?.windows.first {
            return w.bounds.size
        }
        return active?.screen.bounds.size ?? .zero
    }

    /// The key window's safe area — the notch and the home line, as the platform reports them.
    static func safeInsets() -> UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return (active?.windows.first(where: { $0.isKeyWindow }) ?? active?.windows.first)?.safeAreaInsets ?? .zero
    }
    /// The pixel scale of OUR window: under mirroring and on an external display the shared screen
    /// answers with another number, and a picture rendered at it is the wrong size on this device.
    static func scale() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let win = active?.windows.first(where: { $0.isKeyWindow }) ?? active?.windows.first
        let s = win?.traitCollection.displayScale ?? 0
        return s > 0 ? s : 3
    }
    static func width(_ measured: CGFloat) -> CGFloat { measured > 0 ? measured : size().width }
    static func height(_ measured: CGFloat) -> CGFloat { measured > 0 ? measured : size().height }

    /// Whether the screen is being recorded right now. Asked of the app's OWN window:
    /// on an external display and in a second scene the device main screen speaks of another window.
    static var isCaptured: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.isCaptured }
            .contains(true)
    }
}

/// NOTHING STANDS PAST THE SCREEN (the author's word 20.09: the reactions row ran off the right
/// edge, the call screen's top ran under the notch on T3). Every surface that matters names itself
/// here; the frame it actually got is measured against the window and the top safe area, and a
/// frame past either edge is a diary line — the verdict fails on it. The measure runs on the
/// platform's own layout, after the fact: not a guess about sizes, the sizes.
struct MTOnScreen: ViewModifier {
    let name: String
    /// Which edges the surface must keep: a row inside a scrolling cloud may leave the top by the
    /// finger's own act, so it answers for its sides alone.
    var axes: Axis.Set = [.horizontal, .vertical]
    func body(content: Content) -> some View {
        content.background(MTOnScreenProbe(name: name, axes: axes))
    }
}
/// THE FRAME IS THE PLATFORM'S, READ WHEN IT HAS COME TO REST (20.09). A geometry reader re-runs on a
/// change of SIZE and not of place: the compose bar measured at x=428 while a chat was being pushed,
/// at x=-128 while it was popped, at x=-62 in its first instant — every one a frame of a transition,
/// never the bar's own place, and a judgement delayed on a stale reading judged the stale reading.
/// A UIKit view lays itself out on EVERY move; half a second after its last layout it converts its
/// bounds to the window and judges that — the place the surface actually holds.
struct MTOnScreenProbe: UIViewRepresentable {
    let name: String
    let axes: Axis.Set
    func makeUIView(context: Context) -> MTOnScreenProbeView {
        let v = MTOnScreenProbeView()
        v.name = name; v.axes = axes
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: MTOnScreenProbeView, context: Context) {}
}
final class MTOnScreenProbeView: UIView {
    var name = ""
    var axes: Axis.Set = [.horizontal, .vertical]
    private var said = false
    private var pending: DispatchWorkItem?
    override func layoutSubviews() {
        super.layoutSubviews()
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.judge() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)   // settled: half a second after the last layout
    }
    override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
    private func judge() {
        guard !said, let win = window else { return }
        let f = convert(bounds, to: win)
        let size = win.bounds.size
        let top = win.safeAreaInsets.top
        guard size.width > 0, size.height > 0, f.width > 0 else { return }
        let offX = axes.contains(.horizontal) && (f.minX < -0.5 || f.maxX > size.width + 0.5)
        let offY = axes.contains(.vertical) && (f.minY < top - 0.5 || f.maxY > size.height + 0.5)
        guard offX || offY else { return }
        said = true
        MontanaP2PTrace.mark("offscreen", "\(name) x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height)) win=\(Int(size.width))x\(Int(size.height)) safe_top=\(Int(top))")
    }
}
extension View {
    /// The surface names itself; a frame past the screen or under the notch is a diary line.
    func mtOnScreen(_ name: String, axes: Axis.Set = [.horizontal, .vertical]) -> some View { modifier(MTOnScreen(name: name, axes: axes)) }
}
