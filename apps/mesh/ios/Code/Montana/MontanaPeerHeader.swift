import SwiftUI
import PhotosUI

// ════════════════════════════════════════════════════════════
// PEER INFO — the header. One header for the person on the other side and for ourselves: the same
// avatar, the same camera badge, the same title block, and a flag for whose profile it
// is. Two headers is how the same avatar came to answer a tap differently on two screens.
// ════════════════════════════════════════════════════════════

// Where the picture comes from. A peer's avatar is a file on disk; our own is the bytes we keep for
// ourselves, and both reach the same puck.
enum MTAvatarSource {
    case file(String?)
    case data(Data)

    var isEmpty: Bool {
        switch self {
        case .file(let f): return f == nil
        case .data(let d): return d.isEmpty
        }
    }
}

struct MTPeerHeader: View {
    let source: MTAvatarSource
    let color: Color
    let initial: String
    var size: CGFloat = 100
    var title: String? = nil
    var subtitle: LocalizedStringKey? = nil
    var subtitleIsActive: Bool = false
    var note: String = ""
    var blocked: Bool = false       // the red «Blocked» pill under the name (the author's word 15.09)
    var showsCamera: Bool = false
    @Binding var pickerItem: PhotosPickerItem?
    var onAvatarTap: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                // The face wears the skin (the author's word 18.09): the platform's circle under
                // Native, Montana's hexagon under Geometric — as every face in the app does.
                Group {
                    if MontanaSkin.isNative {
                        puck.frame(width: size, height: size).clipShape(Circle())
                            .contentShape(Circle())
                    } else {
                        puck.frame(width: size, height: size).clipShape(MontanaHexagon())
                            .contentShape(MontanaHexagon())
                    }
                }
                .onTapGesture { onAvatarTap() }
            }
            // THE PHOTO IS EDITED THE PLATFORM'S WAY (the author's word 18.09): the system's link under
            // the face, in the system's tint — not a gold camera of ours on the face.
            if showsCamera {
                PhotosPicker(selection: $pickerItem, matching: .images) { Text("Edit") }
                    .frame(minWidth: 44, minHeight: 44)   // the platform's minimum touch target
            }

            if let title {
                Text(title)
                    .font(.title2).bold().foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            if blocked { MTBlockedPill() }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(subtitleIsActive ? .green : .gray)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.subheadline).foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30).padding(.top, 2)
            }
        }
    }

    @ViewBuilder private var puck: some View {
        switch source {
        case .file(let f):
            AvatarCircle(photoURL: f, color: color, initial: initial, size: size)
        case .data(let d):
            if let ui = UIImage(data: d) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Circle().fill(Color.black)
                    .overlay(Text(initial)
                        .font(.system(size: (size * 0.42) / 0.40 * MontanaAvatar.glyphScale(initial), weight: .bold))
                        .foregroundColor(Color.accentColor))
            }
        }
    }
}

/// The red «Blocked» pill under a person's name (the author's word 15.09) — one drawing for both headers.
struct MTBlockedPill: View {
    var body: some View {
        Label("Blocked", systemImage: "nosign")
            .font(.subheadline.weight(.semibold)).foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color(red: 0.55, green: 0.15, blue: 0.25), in: Capsule())
    }
}

// ════════════════════════════════════════════════════════════
// THE FACE AND HOW IT OPENS — ONE OWNER (the author's word 24.09: «nothing is to be invented: Settings
// already shows it right, a tap or a pull down and it opens as it should; make it on the profile already
// opened, SSOT, one owner of the avatar and its display, so it closes into the circle as there»).
// Settings' header, cut out whole and not redrawn: the circle that opens to the screen's width on a tap, to the
// whole screen on a second tap, and closes back into the circle when the list below is scrolled up. THE CIRCLE
// OPENS ONLY BY A PRESS, AND EVERY PAGE STARTS AT THE CIRCLE (the author's word 24.09, the later one: «by default
// the avatar is folded into the circle and opens only by a press, not by a swipe; one owner of the avatar and its
// behaviour»): no pull opens it, and no page chooses a start of its own -- Settings, a correspondent's page and
// «My profile» wear the same face the same way. The comments below are Settings' own, moved with the code they
// explain.
// ════════════════════════════════════════════════════════════

final class MTFaceDock: ObservableObject {
    // The ONE definition of the avatar-morph spring: circle ↔ half screen. It drives both
    // the tap's opening and the scroll's closing. The same value used to stand as two separate
    // lines — editing one changed only half the transitions while the other stayed silent.
    /// SLOW AND SMOOTH (the author's word 25.09: «the face folding from big into the small circle must be smooth and slow»):
    /// the platform's smooth spring, no bounce, most of a second.
    static let morph = Animation.smooth(duration: 0.8)
    @Published private(set) var dock: Int = 0      // 0 circle, 1 half, 2 full screen -- every page starts at the circle
    @Published private(set) var image: UIImage?    // decoded face (cache, to avoid decoding JPEG every frame)
    private var isMorphing = false
    private weak var listScroll: UIScrollView?
    private var asked = 0   // the last face asked for: a slower decode of an older one never lands over it

    /// The list below the face: its scroll up closes the open face; only a tap opens it.
    var probe: ScrollProbe {
        ScrollProbe(onPull: { [weak self] raw in self?.scrolled(raw) },
                    onAttach: { [weak self] sv in self?.listScroll = sv })
    }

    // The ONE place that changes the avatar state. Both tap and scroll come here. The tap
    // used to set the state directly, then a scroll event with a negative offset arrived and
    // collapsed the avatar right back — with a scrolled list the tap looked unresponsive.
    func set(_ new: Int) {
        guard new != dock else { return }
        // While the header morphs, its height change itself moves contentOffset — ScrollProbe
        // fires, the scroll reader takes it for a «pull» and flips dock back: menu rows twitch.
        // ScrollProbe is muted for the animation's whole span (taps do not go through
        // the scroll reader — they keep working).
        isMorphing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.isMorphing = false }
        // Expansion returns the list into place — by the same move as the avatar itself, so
        // the header and menu items settle straight instead of staying shifted. This scroll
        // can no longer cancel the expansion: collapsing fires only when the finger drags
        // the list.
        // A finger that holds the list is let go at the change: the return to the circle is a stop point, and
        // however long the finger holds, the list rides no further (a held finger used to carry the list on and the
        // circle overshot its place). The face opens only by a tap (the author's word 24.09), so no finger holds the
        // list as it opens.
        if let sv = listScroll, sv.isDragging {
            sv.panGestureRecognizer.isEnabled = false
            sv.panGestureRecognizer.isEnabled = true
        }
        // The list's return is needed in BOTH directions. On collapse the header shrinks by
        // almost 400 points while the scroll offset stays — the content rides away and
        // the screen does not return to its initial state. The reset used to happen only on
        // expansion — hence the asymmetry.
        // The list position is set INSTANTLY and in the same transaction as the state change.
        // A separate scroll animation ran alongside the header re-layout, the system trimmed
        // the offset on the fly — the circle landed off target and had to be pulled back. The
        // instant set is invisible (a shift of about 25 points), and all visible motion is
        // done by the header's own spring.
        if let sv = listScroll {
            let top = -sv.adjustedContentInset.top
            if abs(sv.contentOffset.y - top) > 0.5 {
                sv.setContentOffset(CGPoint(x: 0, y: top), animated: false)
            }
        }
        // Without withAnimation: the implicit animation used to spread to every menu row and
        // each sprang on its own (a 0.50 damping bounce) — «jumping rows». The animation is
        // attached precisely to the header container (.animation(value: dock)).
        dock = new
    }

    // The list's scroll up closes the open face; nothing of the scroll opens it (the author's word 24.09: «the avatar
    // opens only by a press, not by a swipe»). The offset is read RELIABLY via KVO on the list's UIScrollView
    // (ScrollProbe), not via List-preference.
    func scrolled(_ raw: CGFloat) {
        if isMorphing { return }   // events from our own header re-layout — ignore, or dock flips and the menu jumps
        // Collapse only when the FINGER drags the list. Expansion changes the header height,
        // the list recomputes layout and shifts the offset itself — an event with a negative
        // value arrived and collapsed the avatar that same instant. From outside it looked
        // like «the tap does not work», though expansion fired and was immediately undone by
        // its own re-layout.
        // An event of unknown origin — do NOT collapse. The old default was the opposite:
        // when the list reference failed to capture, collapsing fired on the re-layout and
        // the tap again «did not work».
        let byFinger = listScroll.map { $0.isDragging || $0.isDecelerating } ?? false
        // Scroll up → circle. The circle opens only by a tap, the whole screen only by a tap on the open face.
        if dock == 1, raw < -25, byFinger { set(0) }
        // dock == 2: fullscreen photo, dismiss only by swipe (the viewer)
    }

    // Decode the avatar ONCE off-main + preparingForDisplay → render without per-frame JPEG decode.
    func load(_ data: Data) {
        asked += 1; let ask = asked
        if data.isEmpty { image = nil; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = UIImage(data: data)
            let prepared = img?.preparingForDisplay() ?? img
            DispatchQueue.main.async { [weak self] in
                guard let self, self.asked == ask else { return }
                self.image = prepared
            }
        }
    }
    /// A correspondent's face: a file on disk or a built-in picture, decoded the same way.
    func load(file: String?) {
        asked += 1; let ask = asked
        guard let s = file else { image = nil; return }
        if let hit = UIImage(named: s) ?? docImageCached(s) { image = hit; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = docImage(s)
            let prepared = img?.preparingForDisplay() ?? img
            DispatchQueue.main.async { [weak self] in
                guard let self, self.asked == ask else { return }
                self.image = prepared
            }
        }
    }
}

// Profile header: morphs circle ↔ half-screen; a tap on the half-screen photo
// opens the SSOT fullscreen viewer (MontanaPhotoViewer, dock==2). It lives ABOVE the scroll,
// never inside it — a resizing element inside a ScrollView makes SwiftUI snap the content reflow,
// which jerked the name and the menu. Outside the scroll the height animates cleanly and the list
// below simply follows. A tap opens it and the list's scroll up closes it (MTFaceDock); no pull opens it.
// Under the name stand the person's own words and their link, with no caption over either (the
// author's word 24.09), following the name's side.
struct MTFaceHeader: View {
    @ObservedObject var face: MTFaceDock
    let glyph: String
    let name: String
    let pageWidth: CGFloat
    var blocked = false
    var bio = ""
    var link: URL? = nil
    var note = ""
    /// THE HEAD'S OWN WIDTH, MEASURED (the author's word 25.09: «in the landscape layout the page and the wall must stand
    /// straight, now they are crooked»): the head drew itself at the window's width, and in landscape the window is wider
    /// than the page's rows by the safe area on both sides — the face ran past the rows. The width it stands in rules.
    @State private var measured: CGFloat = 0

    @ViewBuilder private var picture: some View {
        if let ui = face.image {
            // The saved face is the square the person framed; the open header is that square
            // exactly, so fill and fit are the same picture and nothing is added at the edges.
            Image(uiImage: ui).resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // No photo — the field is black, not coloured: the expanded header used to fill
            // half the screen with solid palette colour, the one screen where the tree's
            // colour rule broke. The glyph grows with the header: it IS the face, and drawing
            // it at forty-four points across half a screen means showing a dot instead of a face.
            GeometryReader { g in
                Color.black.overlay(
                    Text(glyph)   // USER-DATA: the person's own glyph or letter, not interface text
                        .font(.system(size: min(g.size.width, g.size.height)
                                      * MontanaAvatar.glyphScale(glyph), weight: .bold))
                        .foregroundColor(Color.accentColor))
            }
        }
    }

    var body: some View {
        let w = measured > 0 ? measured : pageWidth
        // Open, the face is the square the crop framed — the whole of it and nothing else
        // (the author's word 11.09): a taller half-screen frame fitted the square with bands
        // above and below, and a shifted crop once showed its uncovered edge as white there.
        // In landscape the square is the height the screen gives it, never wider than the rows (25.09).
        let openH = max(105, min(w, MTScene.size().height * 0.8))
        let targetH: CGFloat = face.dock >= 1 ? openH : 104
        let frac = min(max((targetH - 104) / (openH - 104), 0), 1)   // 0 circle → 1 open
        let width = 104 + (openH - 104) * frac
        let side: Alignment = face.dock >= 1 ? .leading : .center
        let lines: TextAlignment = face.dock >= 1 ? .leading : .center
        return VStack(spacing: 8) {
            picture
                .frame(width: width, height: targetH)
                // NOTHING AROUND ANY FACE (the author's word 24.09 for a correspondent's page: «remove every contour and
                // rounding around the avatar», and 25.09 for my own: no gold rim, the platform's own look and nothing else):
                // collapsed, it is the tree's face shape with no rim; opening, the plain square frame the crop made. One
                // rule for every page -- no page keeps a rim of its own.
                .clipShape(frac < 0.01 ? AnyShape(MontanaHexagon()) : AnyShape(Rectangle()))
                .frame(maxWidth: .infinity, alignment: side)
                .contentShape(Rectangle())
                .onTapGesture {
                    if face.dock == 0 { face.set(1) } else if face.dock == 1 { face.set(2) }
                }
            // The name and the @nick are one line. The system wraps when the line does not
            // fit: there is no width check of our own here, nor should there be.
            // The name and nick size is ONE in any avatar position — the collapsed circle's.
            // Shrinking is removed: letters must not change size with the header's state;
            // when they do not fit, the system wraps to a second line.
            // THE NAME, THE BIO AND THE LINK IN BUBBLES OF ONE-TONE GLASS (the author's word 25.09): each its own plate of the
            // system's regular glass hugging its words, standing where the head's lines stand -- on my page and on a
            // correspondent's alike, this one head drawing both.
            bubble(Text(MontanaAvatar.spokenName(name)).font(.title3.bold()).foregroundColor(.white).lineLimit(2))
                .frame(maxWidth: .infinity, alignment: side)
                .padding(.horizontal, 18)
            if blocked {
                MTBlockedPill()
                    .frame(maxWidth: .infinity, alignment: side)
                    .padding(.horizontal, 18)
            }
            if !bio.isEmpty {
                // USER-DATA: the person's own words about themselves, their links live (MTLinks, 02.10)
                bubble(Text(MTLinks.linked(bio, color: Color(uiColor: .link)))
                    .font(.body).foregroundColor(.white)
                    .multilineTextAlignment(lines)
                    .textSelection(.enabled))
                    .frame(maxWidth: .infinity, alignment: side)
                    .padding(.horizontal, 18)
            }
            if let link {
                // The web alone ever opens from here (MTPeerAbout.url keeps nothing else), in the
                // platform's own link colour and through its own control.
                bubble(Link(destination: link) {
                    Text(verbatim: MTPeerAbout.shown(link))   // USER-DATA: the link the person gave
                        .foregroundColor(Color(uiColor: .link))
                        .lineLimit(1).truncationMode(.middle)
                }
                .font(.body).tint(Color(uiColor: .link))
                .contextMenu {
                    Button { UIPasteboard.general.string = link.absoluteString } label: { Label("Copy", systemImage: "doc.on.doc") }
                })
                .frame(maxWidth: .infinity, alignment: side)
                .padding(.horizontal, 18)
            }
            if !note.isEmpty {
                Text(verbatim: note)   // USER-DATA: the note the viewer keeps on this person
                    .font(.subheadline).foregroundColor(.gray)
                    .multilineTextAlignment(lines)
                    .frame(maxWidth: .infinity, alignment: side)
                    .padding(.horizontal, 18)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured = $0 }
        .padding(.top, face.dock == 0 ? 8 : 0)
    }
    /// A line of the head on its own bubble, ROUNDED AS THE WALL'S WRITE BUTTON (the author's word 26.09: «the name and bio bubbles on
    /// the profile page rounded like the "write on the wall" bubble»): the button's own figure and glass -- a capsule of the system's
    /// regular glass at one line; when the words wrap, the message field's round ends (MontanaFieldGlass, the field's growing
    /// figure), so a bio of several lines keeps its corners clear of the words.
    private func bubble<V: View>(_ v: V) -> some View {
        v.padding(.horizontal, 16).padding(.vertical, 9)
            .montanaFieldGlass(maxCut: 18)
    }
}

/// A page under a face (the author's word 25.09: «the whole page whole, scrolling as a full page, as the chats page»): the
/// face is the page's own first row -- handed to the page's list as `head`, which stands it first and scrolls it away with
/// everything below it -- and nothing of the page stands fixed over the rows but the bars. The whole screen for the face
/// on the second tap. `shown` false keeps the list where it stands and takes the face away (the edit page); the ground stays, seen through the
/// editor's rows of glass (25.09).
struct MTFacePage<Content: View>: View {
    @ObservedObject var face: MTFaceDock
    let shown: Bool
    let glyph: String
    let name: String
    let blocked: Bool
    let bio: String
    let link: URL?
    let note: String
    /// Whose page this is — mine (the settings, My page from the settings or from the drawer) or a correspondent's.
    let of: MTWallpaper.PageOf?
    /// THE PAGE'S GROUND HAS ONE OWNER (the author's words 25.09: «on the settings page the ground stands, and opening my
    /// page from the side panel I do not see it — there must be one owner»; «from T3 I opened T1's page and see no
    /// background»): the face's page decides it here from whose page it is — my ground on every page of mine, the
    /// ground a correspondent sent (MTPageGround) on theirs.
    private var ground: String? { of.map { MTWallpaper.pageKey($0) } }
    let content: Content

    init(face: MTFaceDock, shown: Bool = true, glyph: String, name: String, blocked: Bool = false,
         bio: String = "", link: URL? = nil, note: String = "", of: MTWallpaper.PageOf? = nil,
         @ViewBuilder content: (MTFacePageHead) -> Content) {
        self.face = face; self.shown = shown; self.glyph = glyph; self.name = name
        self.blocked = blocked; self.bio = bio; self.link = link; self.note = note; self.of = of
        self.content = content(MTFacePageHead(face: face, shown: shown, glyph: glyph, name: name,
                                              blocked: blocked, bio: bio, link: link, note: note))
    }

    var body: some View {
        // THE PAGE RUNS TO THE WINDOW'S EDGES, AS THE CHATS PAGE DOES (the author's words 25.09: «the scroll as the chat's,
        // from end to end, with no borders»; «the whole page whole, scrolling as a full page, as the chats page»): the list
        // runs under the bars to the window's top and bottom, and past them its rows sink into the page's ground by the
        // chats page's own numbers (MTPageEdges); the platform's edge blur and the bar's own plate stand aside, as the
        // chats page has them.
        content
            .modifier(MTNoEdgeBlur())
            .mask { if shown { MTPageEdges() } else { Color.black } }
            // THE PAGE'S GROUND ON THE WHOLE PAGE, AS THE CHAT'S (the author's words 24.09: «by the same algorithm, by SSOT,
            // as the chat's background», and 25.09: «the background choice on the whole page, the page's ground as the
            // chat's»): the chat's own ground view draws it, whole-window as its preview placed it, behind the whole page;
            // the posts and the rows stand on it as the chat's bubbles stand on its ground.
            .background { if let ground { MontanaChatBackdrop(conv: ground) } }   // the ground stays while the page is edited (25.09)
            .toolbarBackground(shown ? .hidden : .automatic, for: .navigationBar)
            .animation(MTFaceDock.morph, value: face.dock)   // the face and the rows below it morph in ONE transaction
            // Full-screen avatar photo — through the ONE viewer (SSOT MontanaPhotoViewer). Only the header
            // state's entry and exit live here, not a single gesture of its own. Full view without a photo
            // used to show a black field and nothing else: nobody told it whose face it shows. The glyph is
            // passed as the same value as in the header.
            .overlay {
                if shown, face.dock == 2 {
                    MontanaPhotoViewer(image: face.image, fallbackInitial: glyph) { face.set(1) }
                        .zIndex(30)
                }
            }
    }
}

/// THE FACE AS THE PAGE'S FIRST ROW (the author's word 25.09): the face's page hands its head to the page's own list, which
/// stands it first and scrolls it away with the rows below it. Nothing when the face is not shown.
struct MTFacePageHead: View {
    @ObservedObject var face: MTFaceDock
    let shown: Bool
    let glyph: String
    let name: String
    let blocked: Bool
    let bio: String
    let link: URL?
    let note: String
    var body: some View {
        if shown {
            MTFaceHeader(face: face, glyph: glyph, name: name, pageWidth: MTScene.size().width,
                         blocked: blocked, bio: bio, link: link, note: note)
        }
    }
}

/// THE PAGE'S EDGES, THE CHATS PAGE'S (MTChatListFrame.fadeStops -- the author's word 25.09): past the bars at the window's
/// top and bottom the rows sink into the page's ground -- one mask on the rows' own layer, the ground not drawn twice. The
/// bars' height is the safe area the page's list stands in.
struct MTPageEdges: View {
    var body: some View {
        GeometryReader { g in
            let h = max(1, g.size.height)
            let stops = MTChatListFrame.fadeStops(height: h, top: g.safeAreaInsets.top,
                                                  bottom: h - g.safeAreaInsets.bottom, up: true, down: true)
            LinearGradient(stops: stops.map { Gradient.Stop(color: Color.black.opacity(Double($0.alpha)), location: $0.at) },
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// THE PAGE'S GROUND SEEN THROUGH A ROW (the author's word 25.09: «while editing, the page must show its ground as it already
/// is»): the editor's face stands in a row of a list, not over the page's fixed head, so the ground is drawn exactly as the
/// page draws it -- the chat's own ground view, whole-window at the window's origin -- and the row shows the part of it that
/// stands behind the row, a window onto the page. None chosen -- the page's black, as the row always stood.
struct MTPageGroundWindow: View {
    var body: some View {
        GeometryReader { g in
            let at = g.frame(in: .global).origin
            let win = MTScene.size()
            MontanaChatBackdrop(conv: MTWallpaper.pageKey(.me))
                .frame(width: win.width, height: win.height)
                .offset(x: -at.x, y: -at.y)
        }
        .clipped()
        .allowsHitTesting(false)   // a ground answers no finger: clipping bounds its drawing, not its touch (the critic 26.09)
    }
}

/// A PAGE ON MY PAGE'S GROUND (the author's word 25.09: «the settings page takes the same ground as the side panel and my
/// page, and every page inside it too -- our style, transparent native bubbles, liquid glass»): the very ground my page
/// wears, black when none is chosen -- one dress for the drawer, the settings and every page pushed inside them; the rows
/// and cards stand on the system's glass over it (MTGlassRowPlate, MTGlassCardPlate).
/// THE GROUND RIDES WITH ITS PAGE (25.09, T1: «the settings lag and flicker, most of all on the way back by the arrow»): a
/// page pushed or popped by the platform's navigation is moved by Core Animation, and a ground laid by the page's global
/// frame (MTPageGroundWindow) learned the page's place only at the end of the move -- it stood misaligned for the whole
/// slide and snapped into place at the last frame. A page's ground is the page's own now, laid in the page's frame and
/// carried with it. The drawer alone keeps the window-aligned ground (still): the finger moves it frame by frame, and the
/// picture stays where the page's picture stands. Every transition is measured (MTPageMeter).
struct MTPageGroundBack: ViewModifier {
    var still = false
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Color.black
                if still { MTPageGroundWindow() } else { MontanaChatBackdrop(conv: MTWallpaper.pageKey(.me)) }
                MTPageMeter()
            }
            .ignoresSafeArea()
        }
    }
}
extension View {
    func montanaPageGround(still: Bool = false) -> some View { modifier(MTPageGroundBack(still: still)) }
}

/// THE PAGE'S TRANSITION, MEASURED BY THE PLATFORM'S OWN COORDINATOR (25.09): a view of the page's ground asks the controller
/// it lands in for the transition it is entering -- a push or a pop of the navigation stack -- and runs the honest frame meter
/// (MTFrameMeter) from that frame to the coordinator's completion: one line per transition in the diary, named by the page
/// (motion what=page:…), with the frames, the worst one and the late ones. A page entering no transition (the drawer, a
/// page under the slide host) measures nothing; a meter that costs frames of its own measures itself.
struct MTPageMeter: UIViewRepresentable {
    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var r: UIResponder? = next
            while let x = r, !(x is UIViewController) { r = x.next }
            guard let vc = r as? UIViewController, let co = vc.transitionCoordinator else { return }
            let name = vc.navigationItem.title ?? "root"
            MTFrameMeter.shared.moveBegan()
            co.animate(alongsideTransition: nil) { ctx in
                MTFrameMeter.shared.moveEnded("page:" + (ctx.isCancelled ? "cancelled:" : "") + name)
            }
        }
    }
    func makeUIView(context: Context) -> Probe {
        let v = Probe()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: Probe, context: Context) {}
}
extension View {
    /// A page or a sheet that measures its own rise and fall (MTPageMeter): the wall's pages and sheets, the editor, the
    /// scanner, the seed -- every page pushed or presented by the platform that wears no page ground of its own.
    func montanaMotionMeter() -> some View { background { MTPageMeter() } }
}
