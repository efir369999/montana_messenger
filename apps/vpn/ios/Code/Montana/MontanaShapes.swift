//
//  MontanaShapes.swift
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



/// THE FACE OF MONTANA IS A REGULAR HEXAGON, vertex up (the author's word 07.09): one figure for
/// every face in the client — the list, the search, the contacts, the chat header, one's own
/// face in the profile and on the code card. The hexagon is inscribed in the frame's shorter side,
/// so it replaces the circle in place; `inset` keeps the rim on the figure, not on its box.
struct MontanaHexagon: InsettableShape {
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 - inset
        let c = CGPoint(x: rect.midX, y: rect.midY)
        if MontanaSkin.isNative { return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
        var p = Path()
        for k in 0..<6 {
            let a = (Double(k) * 60 - 90) * Double.pi / 180   // the first vertex at the top
            let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> MontanaHexagon { var s = self; s.inset += amount; return s }
}

/// The stretched octagon (the author's word 08.09): eight sides, the four corners cut at
/// forty-five degrees — a plate that holds a word beside a face, and the corner button pair.
struct MontanaLongOctagon: InsettableShape {
    var inset: CGFloat = 0
    var maxCut: CGFloat = .greatestFiniteMagnitude   // a ceiling for tall plates: a photo bubble keeps its picture
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        if MontanaSkin.isNative {
            let radius = maxCut.isFinite ? min(maxCut + 4, r.height / 2) : min(r.width, r.height) / 2
            return Path(roundedRect: r, cornerRadius: radius)
        }
        let cut = min(r.height * 0.32, r.width * 0.25, maxCut)   // the cut corner: a third of the height, never past a quarter of the width
        var p = Path()
        p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
        p.addLine(to: CGPoint(x: r.maxX - cut, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + cut, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - cut))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> MontanaLongOctagon { var s = self; s.inset += amount; return s }
}

/// THE ONE HEIGHT of every octagon button and plate (the author's word 09.09): written here and
/// nowhere else. A square button is exactly this wide; a plate takes any width at this height.
enum MontanaOctagon {
    static let height: CGFloat = 42
    /// The top bar of the Chats tab (the author's word 10.09, after the system's own glass
    /// buttons): five plates of THIS height — four square buttons and the title — and the search.
    static let barHeight: CGFloat = 60   // the tier of the bar's buttons (the author's word 14.09)
    /// The compose row (the author's word 14.09, the platform's own message field): «+», the
    /// field and the microphone all stand at the system field's height.
    static var composeHeight: CGFloat { MTInputField.tier }   // read from the one owner of the compose tier (20.09)
    /// The glyph inside a bar button. ONE STYLE FOR EVERY BUTTON (the author's word 07.10.2026 18:4x MSK: the style of the buttons
    /// -- write on the wall, send and the rest -- one for each style chosen; with white icons, everything in that style): with the
    /// white icons chosen (MTLibraryIconStyle, the one owner of the choice) every bar glyph is that white, as the send mark already
    /// is; with another style, the platform's grey.
    static var barGlyph: Color {
        let chosen = MTLibraryIconStyle(rawValue: UserDefaults.standard.string(forKey: MTLibraryIconStyle.key) ?? "") ?? .initial
        return chosen == .white ? .white : Color(white: 0.8)
    }
    /// The search row — the first row of the conversations (the author's word 10.09): THE PLATFORM'S OWN SEARCH BAR (26.09),
    /// whose own room stands around its field -- the row adds none; one number the results overlay reads too.
    static let searchRowPad: CGFloat = 0
    static var searchHeight: CGFloat { MTSearchField.height }   // the platform's bar at its own height (26.09)
    /// THE PLATFORM'S BLUE, ONE OWNER ([C-1]): the playing track's ring (24.09) and the chosen server's edge (25.09) wear it.
    static let platformBlue = Color(uiColor: .systemBlue)
    static var searchRowHeight: CGFloat { searchHeight + 2 * searchRowPad }
    /// The bar plate's body under both skins where the system's glass is not drawn: a thin
    /// material that lets the ground behind blur through (the author's word 10.09).
    static var barMaterial: AnyShapeStyle { AnyShapeStyle(.ultraThinMaterial) }
    /// NOTHING AROUND THE FIELD AND ITS BUTTONS (the author's word 21.09, the reference's panel:
    /// NavigationBackgroundNode(color: .clear)): the compose panel has no ground of its own — the
    /// feed runs on under it (MTFeedFrame.underlap) and shows between the plates; the plates alone
    /// carry the glass. A ground was drawn here twice (solid, then a tint over material) — both gone.
    /// The bar's breathing room above and below it; the list's top inset is measured from the
    /// bar as drawn, so these numbers are read here and nowhere else.
    static let barTopPad: CGFloat = 4
    static let barBottomPad: CGFloat = 2
}

/// The layered face of an octagon button (the author's word 09.09): a body lit from the top, an
/// inner light rim, an outer rim and a drop shadow — a thing a finger wants to press. One drawing
/// for every button and plate of the tree; `pressed` sinks it under the finger.
struct MontanaOctagonFace: ViewModifier {
    var prominent = false
    var square = false
    var pressed = false
    var ghost = false   // the search hangs with no plate (the author's word 10.09)
    var bar = false     // the top bar's tier: the bar height, the glass of the system's own buttons
    var height: CGFloat? = nil   // an explicit tier (the compose row) in the bar's glass
    /// A MARK OF THE SYSTEM'S BAR (the author's word 21.09): where the platform has liquid glass it
    /// draws the mark's own circle itself — nothing is drawn here; before that, the plate with its rim,
    /// so the mark is seen on every system and device.
    var mark = false
    /// THE PLATE'S OWN COLOUR (the author's word 21.09, the call screen): End is red, Accept green, a lit
    /// state white — the same glass, tinted, on every system; `prominent` wears the accent.
    var tint: Color? = nil
    /// ON A ROW OF THE CANVAS (the author's word 26.09: «the music's pages in the style of the contacts, the chats and the calls,
    /// only thin as now»): the face keeps its size and its finger room and draws neither plate nor rim -- the row's glass is the
    /// plate (MTChatListView.canvasRow).
    var bare = false
    private var plateTint: Color? { tint ?? (prominent ? Color.accentColor : nil) }
    private var h: CGFloat { height ?? (bar ? MontanaOctagon.barHeight : MontanaOctagon.height) }
    func body(content: Content) -> some View {
        if bare {
            bareFace(content)
        } else if ghost {
            ghostFace(content)
        } else if MontanaSkin.isNative {
            nativeFace(content)
        } else {
            geometricFace(content)
        }
    }
    /// No plate, no rim, no shadow: the glyph at the face's own size, and a press sinks it a little.
    private func bareFace(_ content: Content) -> some View {
        content
            .padding(.horizontal, square ? 0 : 14)
            .frame(width: square ? h : nil, height: h)
            .scaleEffect(pressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
    /// No background, no shadow: a hairline rim around the glyph, the same shape as the skin draws.
    private func ghostFace(_ content: Content) -> some View {
        content
            .padding(.horizontal, square ? 0 : 14)
            .frame(width: square ? h : nil, height: h)
            .overlay(MontanaLongOctagon().stroke(Color.white.opacity(pressed ? 0.6 : 0.28), lineWidth: 1))
            .scaleEffect(pressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
    /// The platform's own face: liquid glass where the system has it, the thin material before.
    @ViewBuilder private func nativeFace(_ content: Content) -> some View {
        let base = content
            .padding(.horizontal, square ? 0 : 14)
            .frame(width: square ? h : nil, height: h)
        if mark {
            // A MARK IS ROUND AS THE HANDSET (the author's word 21.09): the newest system draws its own glass
            // circle around the bare glyph; before that, a round plate with the rim, on a 44-point target.
            if #available(iOS 26.0, *) {
                content
            } else {
                content
                    .frame(width: h, height: h)
                    .background(MontanaOctagon.barMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                    .frame(width: montanaTouchTarget, height: montanaTouchTarget)
                    .contentShape(Rectangle())
            }
        } else if #available(iOS 26.0, *) {
            // The bar plate is plain glass: it stands over a scrolling list, and the interactive
            // variant samples the finger every frame on top of the backdrop; its glyphs answer
            // the finger themselves (MTBarGlyphStyle).
            // PLAIN AGAIN, NOT INTERACTIVE (the author's word 25.09: «on 1916 the glass was plain — make it the same»): made
            // interactive on 24.09, the plate answered a tap with the system's own press and release in the very frames the
            // folded plate sprang out to its width, and the unfold «jumped out»; the coin's pull never touches the plate and
            // unfolded smoothly, and the diaries of 1941 show the same spring on both roads — the plate alone differed. The
            // puck (MTBarPuck) is a light inside this glass, not a second glass.
            base.glassEffect(plateTint.map { .regular.tint($0.opacity(0.85)).interactive() }
                                  ?? (bar ? .regular : .regular.interactive()),
                             in: MontanaLongOctagon())
                .scaleEffect(pressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.12), value: pressed)
        } else {
            // THE RIM IS SEEN (the author's word 21.09): on the systems without glass the plate keeps a
            // visible contour over any ground, so a button reads as a button on every device.
            base.background(plateTint.map { AnyShapeStyle($0) } ?? MontanaOctagon.barMaterial, in: MontanaLongOctagon())
                .overlay(MontanaLongOctagon().stroke(Color.white.opacity(0.28), lineWidth: 1))
                .scaleEffect(pressed ? 0.96 : 1)
                .brightness(pressed ? -0.06 : 0)
                .animation(.easeOut(duration: 0.12), value: pressed)
        }
    }
    private func geometricFace(_ content: Content) -> some View {
        content
            .padding(.horizontal, square ? 0 : 14)
            .frame(width: square ? h : nil, height: h)
            .background {
                ZStack {
                    // The bar tier is see-through under Geometric too: the ground blurs through the plate.
                    MontanaLongOctagon().fill(bar && plateTint == nil ? MontanaOctagon.barMaterial : AnyShapeStyle(LinearGradient(
                        colors: prominent ? [Color.accentColor, Color.accentColor.opacity(0.75)] : (tint.map { [$0, $0.opacity(0.75)] } ?? [Color(white: 0.26), Color(white: 0.09)]),
                        startPoint: .top, endPoint: .bottom)))
                    MontanaLongOctagon().inset(by: 1.5).stroke(LinearGradient(
                        colors: [.white.opacity(prominent ? 0.55 : 0.32), .white.opacity(0)],
                        startPoint: .top, endPoint: .center), lineWidth: 1)
                    MontanaLongOctagon().stroke(Color.white.opacity(prominent ? 0.40 : 0.24), lineWidth: 1)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(pressed ? 0.25 : 0.55), radius: pressed ? 2 : 5, y: pressed ? 1 : 3)
            .scaleEffect(pressed ? 0.95 : 1)
            .brightness(pressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

extension View {
    func montanaOctagonFace(prominent: Bool = false, square: Bool = false, pressed: Bool = false, ghost: Bool = false, bar: Bool = false, height: CGFloat? = nil, mark: Bool = false, tint: Color? = nil, bare: Bool = false) -> some View {
        modifier(MontanaOctagonFace(prominent: prominent, square: square, pressed: pressed, ghost: ghost, bar: bar, height: height, mark: mark, tint: tint, bare: bare))
    }
    func montanaFieldGlass(maxCut: CGFloat) -> some View { modifier(MontanaFieldGlass(maxCut: maxCut)) }
}

/// THE FIELD WEARS THE PLATE'S GLASS (the author's word 21.09): the message field is the same
/// transparent liquid glass as the mini player's plate — the bar tier of MontanaOctagonFace, drawn
/// here on the field's own growing shape (its cut stays at 18): the system's glass where it has it,
/// the thin material with the rim before. The style alone; nothing of the field's measure or touch.
struct MontanaFieldGlass: ViewModifier {
    var maxCut: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            content.glassEffect(.regular, in: MontanaLongOctagon(maxCut: maxCut))
        } else {
            content
                .background(MontanaOctagon.barMaterial, in: MontanaLongOctagon(maxCut: maxCut))
                .overlay(MontanaLongOctagon(maxCut: maxCut).stroke(Color.white.opacity(0.28), lineWidth: 1))
        }
    }
}

/// THE LIVE WAVE OF A RECORDING (the author's word 14.09): the meter's last readings as thin
/// bars, newest at the right, the empty tail at the quiet height.
struct MTLiveWave: View {
    let levels: [Float]
    /// THE PLATFORM'S RECORDER LINES (the author's word 22.09, its recorder beside ours): the system red,
    /// lines a point and a half wide with two between, mirrored about the middle, as many as the wave's
    /// own room holds — the newest at the right, the not-yet-recorded tail a faint dotted line. A line
    /// is the linear amplitude of its 25 ms slot at the reference's scale (VoiceRecorder.shown: a sample
    /// of 4000 is the height, a louder tape is scaled to its loudest word) — the sound itself: silence
    /// is a dot, a word is a spike, the loudest word is the height.
    static let line: CGFloat = 1
    static let gap: CGFloat = 2
    var body: some View {
        GeometryReader { g in
            let count = max(1, Int(g.size.width / (Self.line + Self.gap)))
            let h = g.size.height
            let peak = levels.suffix(count).max() ?? 0
            HStack(alignment: .center, spacing: Self.gap) {
                ForEach(0..<count, id: \.self) { i in
                    let j = i - (count - levels.count)
                    let amp: CGFloat = j >= 0 && j < levels.count ? CGFloat(VoiceRecorder.shown(levels[j], peak: peak)) : 0
                    Capsule().fill(Color.red.opacity(j >= 0 ? 1 : 0.35))
                        .frame(width: Self.line, height: max(Self.line, amp * h))
                }
            }
            .frame(width: g.size.width, height: h, alignment: .trailing)
        }
    }
}

/// The dual note's glyph (the author's picture, 22.09): the platform's own phone with its rear camera —
/// the body and the lens, one symbol, the way the system draws it.
struct MTDualCameraGlyph: View {
    let on: Bool
    var body: some View {
        Image(systemName: "iphone.rear.camera")
            .font(.system(size: 21, weight: .semibold))
            .foregroundColor(on ? Color.accentColor : MontanaOctagon.barGlyph)
    }
}

struct MontanaOctagonButtonStyle: ButtonStyle {
    var prominent = false
    var square = false
    var ghost = false
    var bar = false
    var height: CGFloat? = nil
    var tint: Color? = nil
    var bare = false   // a canvas row's glyph: no plate, the row's glass is it (MontanaOctagonFace.bare)
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .montanaOctagonFace(prominent: prominent, square: square, pressed: configuration.isPressed, ghost: ghost, bar: bar, height: height, tint: tint, bare: bare)
            .contentShape(MontanaLongOctagon())
            .modifier(MTFingerRoom(face: height ?? (bar ? MontanaOctagon.barHeight : MontanaOctagon.height), square: square))
    }
}

/// THE FINGER'S 44 AROUND EVERY PLATE OF THE STYLE (the author's word 26.09: «the cross of the search answers badly -- check
/// everywhere and make the 44-point tap area right»): the cross stood on the default plate, 42 points, and its touch was the
/// plate's capsule -- the corners took nothing. A face drawn below the platform's least target keeps its drawn size in the layout
/// and gives the finger 44 around it, as the compose bar's plates do (montanaFingerRoom): a square face the whole square, a wide
/// one its height. Every button the style draws is a target of 44 by construction.
struct MTFingerRoom: ViewModifier {
    let face: CGFloat
    let square: Bool
    @ViewBuilder func body(content: Content) -> some View {
        let room = max(0, (montanaTouchTarget - face) / 2)
        if room == 0 {
            content
        } else if square {
            content.montanaFingerRoom(layout: face)
        } else {
            content.frame(minWidth: montanaTouchTarget, minHeight: montanaTouchTarget)
                .contentShape(Rectangle())
                .padding(.vertical, -room)
        }
    }
}

/// A glyph on the bar plate (the author's word 10.09): no plate of its own — the plate is the
/// bar — an equal share of the width, and a press sinks it a little.
struct MTBarGlyphStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
/// THE PUCK of the bar (the author's word 10.09): the tab bar's own way of switching — a lighter
/// lozenge under the chosen glyph that flows to the next one when it is tapped. It lies INSIDE the
/// plate's liquid glass, so it is a light, not a second glass (24.09): glass over glass is a lens —
/// it drew darker than the plate and blurred whatever it stood over. A lit capsule before iOS 26.
/// NO LENS (the author's word 25.09, 1942: the platform's clear glass drawn over the glyph as the system's tab bar
/// selection — «take that lens away»): the light under the glyph, as on 1941.
struct MTBarPuck: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Capsule().fill(Color.white.opacity(0.16))
        } else {
            Capsule().fill(Color.white.opacity(0.14))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }
}

extension ButtonStyle where Self == MontanaOctagonButtonStyle {
    static func montanaOctagon(prominent: Bool = false, square: Bool = false, ghost: Bool = false, bar: Bool = false, height: CGFloat? = nil, tint: Color? = nil, bare: Bool = false) -> MontanaOctagonButtonStyle {
        MontanaOctagonButtonStyle(prominent: prominent, square: square, ghost: ghost, bar: bar, height: height, tint: tint, bare: bare)
    }
}

extension UIImage {
    // shrink the photo so the avatar doesn't take much space
    func avatarResized(_ dim: CGFloat = 320) -> UIImage {
        let scale = min(dim / size.width, dim / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1   // true pixels: the screen's 3x used to turn "640" into 1920px silently
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// ════════════════════════════════════════════════════════════
// ONE'S OWN FACE — the single funnel ([C-1]). Every place that sets or clears the
// profile photo goes through here: the bytes are normalized to ONE wire shape
// (side <= 640px, <= 128 KiB) and the announcement to the peers fires HERE — not in a
// view's onChange, which is silent whenever that particular view is not mounted.
// ════════════════════════════════════════════════════════════
enum MontanaSelfFace {
    static let sideMax: CGFloat = 640
    static let byteCap = 131_072   // 128 KiB: a couple of sealed blobs on the long-letter road

    /// One wire shape for any source: gallery pick, crop, an old build's stored bytes.
    static func normalize(_ raw: Data) -> Data? {
        guard let ui = UIImage(data: raw), ui.size.width > 0, ui.size.height > 0 else { return nil }
        let px = max(ui.size.width * ui.scale, ui.size.height * ui.scale)
        let sized = px > sideMax + 60 ? ui.avatarResized(sideMax) : ui
        var q: CGFloat = 0.8
        while q >= 0.4 {
            if let d = sized.jpegData(compressionQuality: q), d.count <= byteCap { return d }
            q -= 0.1
        }
        return sized.jpegData(compressionQuality: 0.35)
    }
    /// Already in the wire shape — nothing to redo (keeps stored bytes byte-stable).
    static func isNormal(_ d: Data) -> Bool {
        guard d.count <= 200_000, let ui = UIImage(data: d) else { return false }
        return max(ui.size.width * ui.scale, ui.size.height * ui.scale) <= sideMax + 60
    }
    static func set(_ raw: Data) {
        guard let face = normalize(raw) else { return }
        UserDefaults.standard.set(face, forKey: "avatarData")
        changed()
    }
    static func clear() {
        UserDefaults.standard.set(Data(), forKey: "avatarData")
        changed()
    }
    /// THE ONE EVENT OF A CHANGE OF FACE (30.09). The views that draw the face watch the bytes themselves (MTSelfFace);
    /// the peers, the cards on the node and the share sheet's mirror are told here, at once -- the mirror used to keep
    /// the old face until the chat list happened to save itself.
    private static func changed() {
        cached = nil
        E2E.shared.broadcastAvatar()
        MontanaCard.faceChanged()   // the face beside every live card follows at once (15.32)
        NotificationCenter.default.post(name: .montanaRemirror, object: nil)
    }
    /// One's own face as a picture, decoded once per change — the Saved Messages row wears it
    /// (the author's word 11.09), the same face the person set for themselves.
    /// THE PICTURE HAS ONE OWNER ([C-1], the critic 22.09): five views drew the face by decoding the
    /// stored bytes themselves, inside their own body — the drawer, the code page, the time panel, the
    /// profile and AvatarView — so a page whose body runs on every letter and every keyboard move
    /// built a NEW picture object each pass, and a new object is a new picture to the platform: it is
    /// decoded again and drawn again. The bytes are still what the views watch; the picture comes from
    /// here.
    /// THE PICTURE FOLLOWS THE BYTES BY CONSTRUCTION (30.09): the one decoded picture is kept WITH the bytes it was
    /// decoded from, and it answers only while they are the bytes that stand. A hand that writes them past `set` and
    /// `clear` -- a copy restored, a change of seed (SeedScope writes and wipes every key of the account) -- used to
    /// leave the old picture answering for the new bytes until the next launch.
    private static var cached: (bytes: Data, image: UIImage?)?
    /// How many faces this launch has decoded: the face's exact print, where a count of bytes could repeat.
    private static var turns = 0
    /// A hand that writes the bytes past `set`/`clear` may say so here; the bytes decide in any case.
    static func invalidate() { cached = nil }
    private static func current() -> (image: UIImage?, turn: Int) {
        let d = UserDefaults.standard.data(forKey: "avatarData") ?? Data()
        if let c = cached, c.bytes == d { return (c.image, turns) }
        turns += 1
        let img = d.isEmpty ? nil : UIImage(data: d)?.preparingForDisplay()
        cached = (d, img)
        return (img, turns)
    }
    static var image: UIImage? { current().image }
    /// The face's print, for a row's fingerprint and the small faces a wall keeps: it moves exactly when the picture does.
    static var tag: Int { current().turn }
}

/// ONE'S OWN FACE, DRAWN -- the one view of it ([C-1], the author's word 30.09: Saved Messages changes at once with my
/// face and is it, by the one function of the face). The view watches the bytes itself, so no host's inputs decide
/// whether it is drawn again: MTChatFace handed the platform the same values before and after a change (no file, the
/// local room, the same letter), the platform kept the old body, and Saved Messages wore the old face while the row's
/// print had moved (T1 29.09 21:15:34 UTC: chat_list apply changed=1 page=chats field=avatar,model). The letter comes
/// from the host, which watches the name.
struct MTSelfFace: View {
    @AppStorage("avatarData") private var bytes: Data = Data()
    let size: CGFloat
    var initial: String = E2E.myFaceGlyph()
    var body: some View {
        AvatarCircle(photoURL: nil, color: .black, initial: initial, size: size,
                     image: bytes.isEmpty ? nil : MontanaSelfFace.image)
    }
}

// 10-C.1 The «last seen» phrase ladder (the checklist word): just now -> N minutes ago ->
// today at HH:MM -> yesterday at HH:MM -> date. Relative words come from the system
// formatter — they speak the device's language by themselves.
enum MontanaSeen {
    /// The floor: a stamp at the floor reads «seen long ago» in both ladders — the word a
    /// person who took their face back leaves behind (the block, 15.09).
    static let longAgo: Double = 1
    /// 10-C.3 The coarse classes (coarse buckets, never the exact minute): when the exact moment is private.
    static func coarse(_ ts: Double) -> String {
        let d = MontanaWakePush.nodeNow() - ts   // the stamp is said by the node's clock (24.09)
        if d < 3 * 86400 { return String(localized: "seen recently", bundle: MTLanguage.bundle) }
        if d < 7 * 86400 { return String(localized: "seen this week", bundle: MTLanguage.bundle) }
        if d < 30 * 86400 { return String(localized: "seen this month", bundle: MTLanguage.bundle) }
        return String(localized: "seen long ago", bundle: MTLanguage.bundle)
    }
    static func phrase(_ ts: Double) -> String {
        if ts <= longAgo { return String(localized: "seen long ago", bundle: MTLanguage.bundle) }
        let date = Date(timeIntervalSince1970: ts)
        let diff = MontanaWakePush.nodeNow() - ts   // the stamp is said by the node's clock (24.09)
        if diff < 3600 {
            // The bare minutes phrase — the system component formatter speaks the app's one language
            // (its calendar's locale, MTLanguage; left on the system's it spoke the minutes in Russian on a phone
            // switched to English, 24.09) with honest plurals and no trailing "ago". Under a minute reads as one
            // minute (the author's word 11.09): no «less than» sign in a presence line.
            let f = DateComponentsFormatter()
            var cal = Calendar.current; cal.locale = MTLanguage.locale; f.calendar = cal
            // The short unit (the author's word 05.10.2026 14:04 MSK: «minutes» to «min»), so the line fits beside the face.
            f.allowedUnits = [.minute]; f.unitsStyle = .short
            return f.string(from: max(60, diff)) ?? MTClock.time(date)
        }
        if Calendar.current.isDateInToday(date) {
            return String(localized: "today at \(MTClock.time(date))", bundle: MTLanguage.bundle)
        }
        if Calendar.current.isDateInYesterday(date) {
            return String(localized: "yesterday at \(MTClock.time(date))", bundle: MTLanguage.bundle)
        }
        return MTClock.day(date)
    }
}

/// THE NATIVE LETTER'S WORDS (the author's words 11.09, 26.09, 29.09): the sender's letter wears the platform's blue and a
/// correspondent's the platform's grey (MTLetterPlate, drawn by MTBubbleStyle.fill), both with THE default's (BT) white words. One
/// place for the colours: the bubble draws them, the appearance preview draws the bubble.
enum MontanaNativeBubble {
    static var mineText: Color { Color(montanaHexString: BT.mTx) }
    static var peerText: Color { Color(montanaHexString: BT.pTx) }
    static var peerLink: Color { peerText }
    /// A link's word in a letter, underlined: white on mine, the default's white on theirs. One answer for the three places that draw it.
    static func link(mine: Bool) -> Color { mine ? .white : peerLink }
}

/// The Time mark used when a person has not chosen a picture.  It is deliberately not a fallback
/// to somebody else's face: absence is a complete, stable visual answer of its own.
struct MTTimeMarkAvatar: View {
    let side: CGFloat
    var body: some View {
        MontanaHexagon().fill(Color.black)
            .overlay(Image("Logo").resizable().scaledToFit().padding(side * 0.36))   // the sign at 28% of the side (the author's word 30.09: half of 56%)
            .overlay(MontanaHexagon().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .frame(width: side, height: side)
    }
}

// Peer's avatar: a photo by link, otherwise a colored circle with a letter or the Time mark.
struct AvatarCircle: View {
    let photoURL: String?
    let color: Color
    let initial: String
    let size: CGFloat
    var image: UIImage? = nil   // a picture already in hand (one's own face) wins over any file
    var timeMarkWhenMissing = false

    var fallback: some View {
        // A face without a photo is a black circle: the tree has one colour, and a random
        // palette colour here was the only place it broke. The letter on it is gold; a glyph
        // draws itself and is assigned no colour.
        MontanaHexagon().fill(Color.black)
            .overlay(Text(initial)
                .font(.system(size: size * MontanaAvatar.glyphScale(initial), weight: .bold))
                .foregroundColor(Color.accentColor))
    }

    // THE FACE IS DECODED OFF THE MAIN THREAD (15.16). A list of forty photographed correspondents
    // decoded forty JPEGs on the main thread in its first pass — and looked up forty names in the
    // asset catalogue on every pass. The catalogue answer is remembered; the file is decoded once,
    // in the background, and the circle shows the initial until the picture is ready.
    private static var assetHit: [String: Bool] = [:]
    private static let assetLock = NSLock()
    private static func isAsset(_ s: String) -> Bool {
        assetLock.lock(); let known = assetHit[s]; assetLock.unlock()
        if let known { return known }
        let hit = UIImage(named: s) != nil
        assetLock.lock(); assetHit[s] = hit; assetLock.unlock()
        return hit
    }
    // SwiftUI may reuse a circle while its row changes.  The image therefore carries the file
    // it was decoded from: a photo of one person is never drawable for another row in that gap.
    @State private var decoded: (file: String, image: UIImage)? = nil

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()   // the picture in hand
            } else if let s = photoURL, Self.isAsset(s) {
                Image(s).resizable().scaledToFill()           // built-in photo
            } else if let s = photoURL, size <= 64, let ui = MontanaSmallPicture.image(s) {
                Image(uiImage: ui).resizable().scaledToFill()  // a row's face: the small copy, on the first frame (16.09)
            } else if let s = photoURL, let ui = (decoded?.file == s ? decoded?.image : nil) ?? docImageCached(s) {
                Image(uiImage: ui).resizable().scaledToFill()  // photo file (faces, created groups)
            } else if let s = photoURL, s.hasPrefix("http"), let url = URL(string: s) {
                AsyncImage(url: url) { phase in                // photo from the internet (fallback)
                    if let img = phase.image { img.resizable().scaledToFill() }
                    else if timeMarkWhenMissing { MTTimeMarkAvatar(side: size) }
                    else { fallback }
                }
            } else {
                if timeMarkWhenMissing { MTTimeMarkAvatar(side: size) } else { fallback }
            }
        }
        .frame(width: size, height: size)
        .clipShape(MontanaHexagon())
        .task(id: photoURL) {
            decoded = nil
            guard size > 64, let s = photoURL, !Self.isAsset(s), !s.hasPrefix("http"), docImageCached(s) == nil else { return }
            let img = await Task.detached(priority: .userInitiated) { docImage(s) }.value
            if !Task.isCancelled, photoURL == s, let img { decoded = (s, img) }
        }
    }
}


/// THE SWOLLEN HOLD BUTTON ABOVE THE KEYBOARD (the author's word 14.09). The keyboard lives in a
/// window of its own that stands above the app's, so a shape drawn inside the chat is cut by
/// it. The shape is drawn in a window of ours that stands above the keyboard's. The window
/// takes no touches at all: the finger's gesture began on the button slot beneath and stays
/// there by the platform's own rule, so nothing here can steal or break it.
final class MTHoldOverlayState: ObservableObject {
    static let shared = MTHoldOverlayState()
    @Published var anchor: CGPoint = .zero   // the slot's centre, in screen coordinates — written by follow() alone
    /// THE SLOT NAMES ITS OWN PLACE (the author's word 21.09, the reference's updateOverlay): the crown's
    /// anchor is read from the control standing in the slot, through the platform's own conversion
    /// to the window — at the finger's arrival and at every move of the bar's node. A snapshot taken by
    /// the layout of the bar's tree went stale the moment the keys lifted the node by its layer
    /// (1796: the node is never laid out again for the move), and the arrow, the pause and the lock
    /// stood a keyboard's height away from the slot.
    weak var slot: UIView?
    /// The voice's tape: the crown draws the voice's circle and its seconds from it, as the note's from `cam`.
    weak var voiceTape: VoiceRecorder?
    func follow(speed: Float? = nil) {
        guard let slot, slot.window != nil else { return }
        let c = slot.convert(CGPoint(x: slot.bounds.midX, y: slot.bounds.midY), to: nil)
        guard abs(c.x - anchor.x) > 0.5 || abs(c.y - anchor.y) > 0.5 else { return }
        MontanaP2PTrace.mark("crown_anchor", "x=\(Int(c.x)) y=\(Int(c.y)) was=\(Int(anchor.y)) anim=\(speed == nil ? 0 : 1)")
        let move = { [self] in
            if anchor != .zero, !strip.isEmpty { strip.origin.y += c.y - anchor.y }   // the strip rides in the same node: the bin keeps its head
            anchor = c
        }
        if let speed { withAnimation(MTKeyboardSpring.swiftUI(speed: speed), move) }   // the keys' own spring, the crown in it
        else { move() }
    }
    @Published var big = false               // the shape is up (held or locked)
    @Published var locked = false            // the arrow instead of the microphone
    @Published var video = false
    @Published var away = false              // the finger slid left: red
    @Published var lift: CGFloat = 0         // 0…1 of the way up to the lock
    @Published var voice: CGFloat = 0        // the last reading of the microphone
    @Published var paused = false            // the tape stands
    var side: CGFloat = 108                  // the resting side of the swollen shape
    var lockWay: CGFloat = 72
    var maxScale: CGFloat = 1.28
    var holdClear: CGFloat = 81              // the swell's ceiling over the slot's centre
    // THE VIDEO NOTE'S CHROME (the author's word 15.09, the reference): while a note records the
    // whole screen is dimmed from this window, and everything of the recording — the note, its
    // buttons, the strip with the seconds, the pause, the lock, the swollen button — is drawn here
    // ABOVE the dim. The note's own controls (the window, the flash, the flip, the dual, the bin,
    // the pause) are taken HERE, inside the rectangles they report; the held button's gesture
    // stays with the chat's slot beneath, where it began (16.09).
    var cam: MontanaVideoNoteCamera?
    var feed: CGRect = .zero                 // the visible feed on the screen: the note centres in it
    var strip: CGRect = .zero                // the recording strip's place in the bar
    var touchable: [String: CGRect] = [:]    // where this window takes a touch: the recording's own controls
    /// THE LOCKED TAPE'S CONTROLS ASK THE RECORDING'S OWNER (the reference's model): the crown
    /// draws the arrow, the pause and the bin and catches their taps in its own window; the
    /// owner (the chat's MontanaRecording) decides. Set by the screen that owns the tape.
    var onSend: (() -> Void)?
    var onPause: (() -> Void)?
    var onCancel: (() -> Void)?
    /// LISTEN BEFORE SENDING (the author's word 23.09): the third control of a standing voice tape, on
    /// the same line as the bin and the wave. The owner closes the tape and hands it to the one player;
    /// this holds only the name of what is being heard, so the glyph can say play or pause.
    var onPreview: (() -> Void)?
    @Published var previewFile: String? = nil
    /// THE TAPE'S CIRCLE STANDS IN THE MIDDLE OF THE VISIBLE PART (the author's word 21.09) — the voice's
    /// and the note's alike, its seconds under it — with the keys up or down. THE VISIBLE PART: its top is
    /// the feed's top; its bottom is the swell's ceiling (stack) — the top of the button under the finger,
    /// wherever the keyboard and the field put the slot. The crown's controls stand in the slot's own
    /// column at the right edge; the circle in the middle never meets them (1840 measured the feed
    /// running under the bar and the keys: its own middle was the screen's).
    var visible: CGRect {
        let f = feed.isEmpty ? UIScreen.main.bounds.insetBy(dx: 0, dy: 120) : feed   // GEOMETRY-CHECKED: a fallback only until the feed is measured
        let bottom = anchor == .zero ? f.maxY : min(f.maxY, stack)
        return CGRect(x: f.minX, y: f.minY, width: f.width, height: max(1, bottom - f.minY))
    }
    var orb: CGPoint { CGPoint(x: visible.midX, y: visible.midY) }
    /// THE FIRST FREE POINT ABOVE THE BUTTON UNDER THE FINGER (the author's word 14.09): the swollen
    /// button stands at the slot; the pause stands on this line, the lock plate a lock's way above it.
    var stack: CGFloat { anchor.y - holdClear }
}

private final class MTPassthroughWindow: UIWindow {
    /// Never a touch — but on the note's own controls, which report where they stand.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard MTHoldOverlayState.shared.touchable.values.contains(where: { $0.contains(point) }) else { return nil }
        return super.hitTest(point, with: event)
    }
}
/// The same rule for the host mounted into the keyboard's window (its points are the screen's).
private final class MTPassthroughHost: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let p = convert(point, to: nil)
        guard MTHoldOverlayState.shared.touchable.values.contains(where: { $0.contains(p) }) else { return nil }
        return super.hitTest(point, with: event)
    }
}

enum MTHoldOverlayWindow {
    private static var window: UIWindow?
    private static var host: UIViewController?
    private static var mounted: UIView?
    /// Where the crown stands now — «kbd» inside the keyboard's window, «own» in ours, «none»:
    /// the diary's hold_end line names it, so a verdict can be read against the keyboard's state.
    private(set) static var mountKind = "none"
    private static var keyboardWatch: [NSObjectProtocol] = []
    /// THE KEYBOARD COMES AND GOES UNDER A ROLLING TAPE (the reference re-seats its chrome the
    /// moment the keyboard's window is gone). The platform says so itself: the keyboard's own
    /// notifications, not a patrol — when the seat no longer matches the keyboard, the crown moves.
    private static func watchKeyboard() {
        guard keyboardWatch.isEmpty else { return }
        let nc = NotificationCenter.default
        for name in [UIResponder.keyboardDidHideNotification, UIResponder.keyboardDidShowNotification] {
            keyboardWatch.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                guard MTHoldOverlayState.shared.big else { return }
                let kbUp = keyboardWindow().map { !$0.isHidden && $0.bounds.height > 1 } ?? false
                let seatedInKeyboard = mounted != nil
                guard kbUp != seatedInKeyboard else { return }
                MontanaP2PTrace.mark("hold_mount", "re-seat keyboard=\(kbUp ? 1 : 0)")
                hide(); show()
                MTHoldOverlayState.shared.follow()   // the slot moved with the bar: the crown asks it where
            })
        }
    }
    /// Measured 14.09 (hold_windows): the process sees only its own window and the text-effects
    /// window; the keyboard's window is not in the list and stands above ANY level of ours — a
    /// thousand million was still under it. The reference messenger draws over the keyboard
    /// the only way there is: INTO the keyboard's own window, reached by its class name.
    private static func keyboardWindow() -> UIWindow? {
        guard let cls = NSClassFromString("UIRemoteKeyboardWindow") else { return nil }
        let sel = NSSelectorFromString("remoteKeyboardWindowForScreen:create:")
        guard let meta = object_getClass(cls), class_respondsToSelector(meta, sel),
              let imp = class_getMethodImplementation(meta, sel) else { return nil }
        typealias Call = @convention(c) (AnyObject, Selector, UIScreen?, Bool) -> UIWindow?
        let call = unsafeBitCast(imp, to: Call.self)
        return call(cls, sel, UIScreen.main, false)   // GEOMETRY-CHECKED: the keyboard's own window is looked up by the screen it is on; no size is read from it
    }
    private static let floor = UIWindow.Level(rawValue: 1_000_000_000)
    /// THE CROWN IS BORN ONCE (21.09, measured on T1: rec_state→hold_mount stood 500–1280 ms, a
    /// host, a window and a whole tree made anew on every hold). The host and the window live for
    /// the process; a show seats the host — into the keyboard's window or its own — and a hide
    /// unseats it. Nothing is allocated under the finger.
    private static func theHost() -> UIViewController {
        if let host { return host }
        let h = MontanaHost.make(MTHoldOverlayView())
        h.view.backgroundColor = .clear
        // The window takes a touch ONLY inside the rectangles its controls report (touchable) —
        // one gate for the voice and the note alike; an empty map is a window that takes nothing.
        h.view.isUserInteractionEnabled = true
        host = h
        return h
    }
    /// Made at the first chat, kept hidden: showing is a flag, not a birth.
    static func prepare() { _ = theHost(); _ = ownWindow() }
    private static func ownWindow() -> UIWindow? {
        if let window { return window }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return nil }
        let w = MTPassthroughWindow(windowScene: scene)
        w.windowLevel = floor
        w.backgroundColor = .clear
        w.isHidden = true
        window = w
        return w
    }
    static func show() {
        guard mountKind == "none" else { return }
        let h = theHost()
        MTHoldOverlayState.shared.touchable = [:]
        if let kw = keyboardWindow(), !kw.isHidden, kw.bounds.height > 1 {
            let c = MTPassthroughHost(frame: kw.bounds)
            c.backgroundColor = .clear
            c.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            h.view.removeFromSuperview()
            h.view.frame = c.bounds
            h.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            c.addSubview(h.view)
            kw.addSubview(c)
            mounted = c
            mountKind = "kbd"
            watchKeyboard()
            MontanaP2PTrace.mark("hold_mount", "keyboard-window h=\(Int(kw.bounds.height))")
            return
        }
        guard let w = ownWindow() else { return }
        if w.rootViewController !== h || h.view.superview !== w { w.rootViewController = nil; w.rootViewController = h }
        w.isHidden = false
        mountKind = "own"
        watchKeyboard()
        MontanaP2PTrace.mark("hold_mount", "own-window")
    }
    static func hide() {
        mounted?.removeFromSuperview(); mounted = nil
        window?.isHidden = true
        mountKind = "none"
    }
}

/// The shape itself: gold and see-through, living rings breathing out around it, the glyph in
/// the middle; it rides up with the finger and greys towards the lock, reddens towards the bin.
struct MTComposeMark: View {
    enum Kind: Equatable { case send, voice, video }
    let kind: Kind
    var side: CGFloat = MontanaOctagon.composeHeight
    private var asset: String {
        switch kind {
        case .send: return "SendButton"
        case .voice: return "VoiceRecordButton"
        case .video: return "VideoRecordButton"
        }
    }
    var body: some View {
        Group {
            if kind == .send { face }
            else { face.scaleEffect(1.33).clipShape(Circle()) }
        }.accessibilityHidden(true)
    }
    private var face: some View {
        Image(asset).renderingMode(.original).resizable().scaledToFit().frame(width: side, height: side)
    }
}

/// THE SYMBOL OF SENDING TIME (the author's words 05.10.2026 18:3x-18:5x MSK: «save it in Media and use it always as the symbol of
/// sending time»; «use only our send symbol, a touch larger and in proportion to the text»): the author's own file, byte for byte
/// (Media/IMG_3066.png, the asset TimeSend), drawn at the height it is given -- the one owner of the mark wherever time is sent.
struct MTTimeSendMark: View {
    var height: CGFloat = 22
    var body: some View {
        Image("TimeSend").renderingMode(.original).resizable().scaledToFit().frame(height: height).accessibilityHidden(true)
    }
}

struct MTHoldOverlayView: View {
    @ObservedObject private var st = MTHoldOverlayState.shared
    @ObservedObject private var player = VoicePlayer.shared   // the one player: the ear's glyph follows what it is doing
    /// ONE CROWN FOR THE VOICE AND THE NOTE (the author's word 21.09, SSOT): the circle of the tape
    /// stands in the middle of the visible feed — the note's circle from its camera, the voice's
    /// breathing shape — and the controls stand at the slot for both kinds, drawn once here: the
    /// arrow in the slot, the pause on the slot's top, the lock plate above, the voice's bin at the
    /// strip's head (the note's bin lives in its strip). Every control is a 44-point target.
    var body: some View {
        ZStack {
            if st.big, st.video, let cam = st.cam { MTNoteChrome(cam: cam) }   // the dim, the note's circle with its seconds, its strip
            if st.big, !st.locked, !st.strip.isEmpty {
                Text(st.away ? "Release to cancel" : "Release to send")
                    .font(.subheadline).foregroundColor(st.away ? .red : .white)
                    .frame(maxWidth: max(44, st.strip.width))
                    .position(x: (st.strip.minX + st.anchor.x) / 2, y: st.strip.minY - 28)
                    .allowsHitTesting(false)
            }
            if st.big { swollen }                                              // THE BUTTON UNDER THE FINGER: at the slot, above every layer and row
            if st.big { barRow }                                               // every other control of the tape, on the bar's line
            if st.big, !st.locked { lockPlate }
        }
        .ignoresSafeArea()
    }
    private var lockPlate: some View {
        VStack(spacing: 8) {
            Image(systemName: st.lift >= 1 ? "lock.fill" : "lock.open")
                .font(.system(size: 24, weight: .semibold)).foregroundColor(.white)
                .contentTransition(.symbolEffect(.replace))
            Image(systemName: "chevron.up")
                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                .opacity(1 - st.lift)
                .frame(height: 18 * (1 - st.lift))
        }
        .padding(.vertical, 14)
        .frame(width: 52)
        .background(MontanaOctagon.barMaterial, in: MontanaLongOctagon(maxCut: 18))
        .overlay(MontanaLongOctagon(maxCut: 18).stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        .position(x: st.anchor.x, y: st.stack - 40 - st.lockWay - 9 * st.lift)   // above the slot, a lock's way up, the chevron folding
        .animation(.easeOut(duration: 0.12), value: st.lift)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
    /// WHAT IS PRESSED AFTER THE LOCK LIVES HERE (the author's word 19.09, the reference's model):
    /// controls of THIS window, caught where they are drawn. A tap no longer has to fall through
    /// the keyboard's window to the bar (measured 19.09 on iOS 18: it never did — six locked
    /// taps, not one arrived).
    /// THE ROW ON THE BAR'S LINE (the author's word 22.09): every control of a rolling tape but the one
    /// under the finger stands on ONE line — the bar's — in seats spaced equally from the bin's column
    /// at the strip's head to the pause's column right before the send: the bin, the note's flash,
    /// flip and dual, the pause. A seat is kept whether its button is shown or not, so nothing jumps
    /// at the lock; every button is the platform's glass plate of the bar's tier on a 44-point target,
    /// a control of this window (MTNoteTouchable). The arrow is the swollen button itself.
    private var barRow: some View {
        let seats: [String] = st.video
            ? (MontanaVideoNoteCamera.dualCapable ? ["bin", "flash", "flip", "dual", "pause"] : ["bin", "flash", "flip", "pause"])
            : ["bin", "play", "pause"]
        let first = st.strip.minX + montanaTouchTarget / 2
        let last = st.anchor.x - st.maxScale * st.side / 2 - 8 - montanaTouchTarget / 2   // right before the swell at its loudest
        let step = seats.count > 1 ? (last - first) / CGFloat(seats.count - 1) : 0
        // THE VOICE'S HEAD COLUMNS STAND TOGETHER (the author's word 23.09: the listen button on the same
        // line as the bin and the wave). The note's controls are spread evenly across the strip; the voice
        // has three, and an even spread would drop the middle one onto the wave itself. So the bin and the
        // ear stand side by side at the strip's head — where the bar keeps their room — and the pause
        // keeps its own column before the swell.
        let column: (Int) -> CGFloat = { i in
            guard !st.video else { return first + step * CGFloat(i) }
            switch i {
            case 0: return first
            case 1: return first + montanaTouchTarget
            default: return last
            }
        }
        return ZStack {
            if !st.strip.isEmpty {
                ForEach(Array(seats.enumerated()), id: \.element) { i, seat in
                    seatButton(seat).position(x: column(i), y: st.strip.midY)
                }
            }
        }
    }
    @ViewBuilder private func seatButton(_ seat: String) -> some View {
        switch seat {
        case "bin":
                Button { st.onCancel?() } label: {   // the one road every cancel walks: the recording's owner
                    Image(systemName: "xmark").font(.system(size: 19, weight: .semibold)).foregroundColor(st.away ? .red : .white)
                }
                .buttonStyle(.montanaOctagon(square: true, ghost: true, bar: true, height: montanaTouchTarget))
                .modifier(MTNoteTouchable(id: "bin"))
                .accessibilityLabel(Text("Cancel"))
        case "play":
            // LISTEN TO WHAT WAS RECORDED (the author's word 23.09), on the line of the bin and the wave.
            // The first press closes the tape and plays it through the ONE player of the app; the next
            // presses stop and start that playing. A closed tape has nothing left to pause, so the pause's
            // seat empties — the seat itself stays, and nothing on the line moves.
            if st.locked, !st.video {
                let heard = st.previewFile != nil
                let running = heard && VoicePlayer.shared.playingFile == st.previewFile && !VoicePlayer.shared.paused
                Button { st.onPreview?() } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .semibold)).foregroundColor(heard ? Color.accentColor : .white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.montanaOctagon(square: true, bar: true, height: montanaTouchTarget))
                .modifier(MTNoteTouchable(id: "play"))
                .accessibilityLabel(Text("Play"))
            }
        case "pause":
            if st.locked {
                // A closed tape has nothing to pause: the seat stands empty while the person listens.
                if st.previewFile == nil {
                    Button { st.onPause?() } label: {
                        Image(systemName: st.paused ? "record.circle" : "pause.fill")
                            .font(.system(size: 22, weight: .semibold)).foregroundColor(st.paused ? .red : .white)
                    }
                    .buttonStyle(.montanaOctagon(square: true, bar: true, height: montanaTouchTarget))
                    .modifier(MTNoteTouchable(id: "pause"))
                }
            }
        case "flash":
            if let cam = st.cam {
                // The fill light (the author's word 15.09), the flash's glyph: the feed behind turns
                // bright white for the front camera, the torch lights for the back one.
                Button { cam.toggleFlash() } label: {
                    Image(systemName: cam.flash ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 20, weight: .semibold)).foregroundColor(cam.flash ? Color.accentColor : MontanaOctagon.barGlyph)
                }
                .buttonStyle(.montanaOctagon(square: true, bar: true, height: montanaTouchTarget))
                .modifier(MTNoteTouchable(id: "flash"))
            }
        case "flip":
            if let cam = st.cam {
                Button { cam.flip() } label: {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 20, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
                }
                .buttonStyle(.montanaOctagon(square: true, bar: true, height: montanaTouchTarget))
                .modifier(MTNoteTouchable(id: "flip"))
            }
        case "dual":
            if let cam = st.cam {
                // Both cameras at once (the author's word 15.09): the back around, the front as a badge
                // in its corner — TWO CAMERAS on the glyph (the author's word 22.09), not two frames.
                Button { cam.toggleDual() } label: {
                    MTDualCameraGlyph(on: cam.dual)
                }
                .buttonStyle(.montanaOctagon(square: true, bar: true, height: montanaTouchTarget))
                .modifier(MTNoteTouchable(id: "dual"))
            }
        default:
            EmptyView()
        }
    }
    /// THE BUTTON UNDER THE FINGER (the author's word 21.09: above every layer and row, pressable on any
    /// system and any device): the swollen shape stands AT THE SLOT — gold and see-through, living rings
    /// breathing out around it, the glyph in the middle; it breathes with the voice, rides up with the
    /// finger, greys towards the lock and reddens towards the bin. Held, the finger's touch is the bar's
    /// control's (it began there and stays there by the platform's rule); LOCKED, the shape stays at its
    /// size and IS the send button — a control of this window, caught where it is drawn (measured 19.09 on
    /// iOS 18: a tap through the keyboard's window never reached the bar).
    private var swollen: some View {
        let rise = -st.lift * st.lockWay
        return ZStack {
            if st.locked {
                Button { st.onSend?() } label: {
                    swell.frame(width: 56, height: 56).contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Send"))
                    .modifier(MTNoteTouchable(id: "send"))
            } else {
                swell.allowsHitTesting(false)
            }
        }
        .offset(y: rise)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: st.lift)
        .animation(.easeOut(duration: 0.15), value: st.away)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: st.big)
        .position(st.anchor)
    }
    private var swell: some View {
        MTComposeMark(kind: .send, side: st.side)
            .scaleEffect(min(st.maxScale, st.away ? 0.9 : 1))
            .opacity(st.away ? 0.45 : 1)
    }
}

/// The video note's chrome over the dim (the author's word 15.09, the reference's screen): the dim
/// over the whole screen — white when the fill light is on — the note in the visible feed, the
/// strip with the red dot and the seconds where the bar's strip stands; all bright above the dim.
/// The bin is a control of this window; the pause, the lock plate and the arrow are the crown's,
/// drawn once for the voice and the note alike (MTHoldOverlayView).
struct MTNoteChrome: View {
    @ObservedObject var cam: MontanaVideoNoteCamera
    @ObservedObject private var st = MTHoldOverlayState.shared
    @State private var shown = false
    var body: some View {
        let f = st.visible   // the visible feed — the same middle the voice's circle stands in (SSOT, 21.09)
        ZStack {
            (cam.flash && (cam.front || cam.dual) ? Color.white : Color.clear)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            MontanaVideoNoteHold(cam: cam)
                .frame(width: f.width, height: f.height)
                .position(x: f.midX, y: f.midY)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
            // The strip holds nothing of its own: the bin, the flash, the flip, the dual, the pause and the
            // red arrow out are the crown's row on the bar's line (MTHoldOverlayView.barRow).
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shown)
        .onAppear { shown = true }
    }
}


/// THE BAR'S MARKS, EACH MADE ONCE ([C-1], the author's word 18.09: one of every kind of button,
/// applied by reference, never redrawn on a screen). A mark is the plain system glyph in a plain
/// button: on the platform's own bar the platform draws the circle, the size, the weight and the
/// colour — exactly as it draws its back arrow. Nothing of ours is added, so nothing of ours can differ.
struct MontanaBarGlyph: View {
    let glyph: String
    var body: some View { Image(systemName: glyph) }
}
/// THE MARK ANSWERS AS THE CHAT'S DOWN ARROW DOES (the author's word 18.09, the one law for every
/// button: the arrow fires at the first touch, the bar's marks did not). The arrow is no button —
/// it is a glyph with a touch shape and the platform's tap recogniser on it: nothing tracks a press,
/// nothing highlights, nothing waits for a style; the tap fires at the lift. The mark is built the
/// same way: the glyph, a 44-point touch target (the platform's minimum), the tap on that shape.
struct MontanaBarMark: View {
    let glyph: String
    let label: LocalizedStringKey
    var action: () -> Void
    var body: some View {
        // THE MARK IS THE PLATFORM'S OWN BUTTON (the author's word 21.09: the back mark under liquid
        // glass, native, as the handset): a Button in the bar is what the newest system dresses in its
        // glass circle; before that, the mark's plate with its rim (MontanaOctagonFace mark:). The tap
        // fires at the lift as before — only the pans of the screen wait for the edge swipe.
        // The label is the ONE label of every mark of the bar (the call menu's too): the glyph on the mark's
        // face inside the platform's least target — so the system's glass circle is the same round on each.
        Button(action: action) {
            MontanaBarGlyph(glyph: glyph)
                .montanaOctagonFace(square: true, bar: true, height: MontanaOctagon.composeHeight, mark: true)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label))
    }
}
/// THE CALL SCREEN'S MARK (the author's word 22.09): the chat's mark — the same glyph size, a 44-point
/// target, the platform's glass circle — standing on its own over the call's picture, where no bar
/// draws the circle for it: the newest system's interactive glass in a circle, before that the round
/// plate with its rim (the same face MontanaBarMark wears before the glass).
struct MontanaCallMark: View {
    let glyph: String
    let label: LocalizedStringKey
    var action: () -> Void
    static let sidePad: CGFloat = 8
    static let topPad: CGFloat = 8
    var body: some View {
        Button(action: action) {
            let face = MontanaBarGlyph(glyph: glyph)
                .font(.system(size: 20, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
                .frame(width: montanaTouchTarget, height: montanaTouchTarget)
                .contentShape(Circle())
            if #available(iOS 26.0, *) {
                face.glassEffect(.regular.interactive(), in: Circle())
            } else {
                face.background(MontanaOctagon.barMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
/// THE ONE SHARE BUTTON OF THE APP (the author's word 25.09: «make this button the system's native share, one owner in the
/// whole app»): the platform's share glyph on the platform's glass -- the bar marks' own face (MontanaCallMark) -- and the
/// sheet born by its one owner (MTShare). The items are read at the tap, never before.
struct MTShareButton: View {
    let items: () -> [Any]
    var body: some View {
        MontanaCallMark(glyph: "square.and.arrow.up", label: "Share") {
            let it = items()
            guard !it.isEmpty else { return }
            MTShare.present(it)
        }
    }
}
/// «Done»: the platform's own checkmark (the author's word 16.09), one glyph for every sheet and
/// screen that closes or confirms — drawn by the one bar mark.
struct MontanaDoneMark: View {
    var action: () -> Void
    var body: some View { MontanaBarMark(glyph: "checkmark", label: "Done", action: action) }
}
/// «Cancel» / «Close»: the platform's own cross (the author's word 19.09: every text «Cancel» of a
/// bar is this mark, every text «Save» is the checkmark) — one glyph for every sheet that is left.
struct MontanaCloseMark: View {
    var action: () -> Void
    var body: some View { MontanaBarMark(glyph: "xmark", label: "Cancel", action: action) }
}
/// «Edit» behind the platform's own three dots (the author's word 18.09: horizontal, native): the
/// profile's mark, top right, opens the edit at once — no menu between the finger and the page.
struct MontanaEditMark: View {
    var action: () -> Void
    var body: some View { MontanaBarMark(glyph: "ellipsis", label: "Edit", action: action) }
}
/// «Back»: the platform's own back chevron, for a screen that closes by its own road (the chat
/// over the tabs) and so gets no back button from the system — the one mark, the same circle.
struct MontanaBackMark: View {
    var action: () -> Void
    var body: some View { MontanaBarMark(glyph: "chevron.backward", label: "Back", action: action) }
}
