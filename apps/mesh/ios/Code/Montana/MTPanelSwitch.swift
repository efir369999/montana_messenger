import SwiftUI
import UIKit

/// THE PANEL'S OWN SWITCH, ON THE PLATFORM'S OWN GLASS (the author's word 22.09: the same little
/// panel -- GIF, stickers, emoji -- in liquid glass, with the settings beside it).
///
/// The reference draws its own glass by hand: a UIVisualEffectView whose private CAFilter colour
/// matrix is rewritten through NSClassFromString («LiquidLensView»). We take none of that -- the
/// platform carries the material itself since iOS 26 (UIGlassEffect, UIKit), and below that the
/// system's own thin material. A private filter is not a mechanism, it is a way around one.
///
/// The shape is the example's: one pill, three words inside it, the chosen one on a lens of its
/// own, and the settings as a separate round glass to the right.
struct MTGlassPill: UIViewRepresentable {
    let corner: CGFloat

    func makeUIView(context: Context) -> UIVisualEffectView { MTGlassKit.plate(corner: corner, interactive: true) }

    func updateUIView(_ v: UIVisualEffectView, context: Context) {
        v.layer.cornerRadius = corner
        v.layer.cornerCurve = .continuous
    }
}

extension View {
    /// The glass under a panel's own control, at its own corner.
    func mtGlassPill(corner: CGFloat) -> some View {
        background(MTGlassPill(corner: corner))
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// THE KEYBOARD'S BOTTOM SWITCH, one to one with the example: a glass pill with the three words,
/// the chosen one carrying its own lighter lens, and the settings glass beside it. The words stand
/// in the platform's own control shape, so the eye reads them as the system's -- and the touch of
/// each is the platform's least target.
struct MTPanelSwitch: View {
    /// The tabs the panel speaks: their order is the example's -- GIF, stickers, emoji.
    enum Tab: Int, CaseIterable { case gif = 2, stickers = 1, emoji = 0 }

    @Binding var tab: Int
    var onSettings: () -> Void

    private static let names: [Int: LocalizedStringKey] = [2: "GIF", 1: "Stickers", 0: "Emoji"]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.rawValue) { t in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { tab = t.rawValue }
                    } label: {
                        Text(Self.names[t.rawValue] ?? "")
                            .font(.system(size: 15, weight: tab == t.rawValue ? .semibold : .regular))
                            .foregroundColor(.white.opacity(tab == t.rawValue ? 1 : 0.65))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background {
                                if tab == t.rawValue {
                                    Capsule().fill(Color.white.opacity(0.16))
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .mtGlassPill(corner: 22)

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .mtGlassPill(corner: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
