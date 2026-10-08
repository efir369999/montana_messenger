import SwiftUI

// The catalogue and shell destinations live in ContentView, the existing shell boundary.
extension MTApplication {
    var artworkIndex: Int {
        switch self {
        case .contacts: return 0
        case .calls: return 1
        case .chats, .groups, .channels: return 2   // the chats' tile, until the author gives the groups and the channels their own
        case .feed: return 4
        case .card: return 6
        case .music: return 7
        case .gallery: return 8
        case .chess: return 9
        case .settings: return 11
        }
    }
    var glyph: String {
        switch self {
        case .contacts: return UIState.Glyph.contacts
        case .calls: return UIState.Glyph.calls
        case .feed: return "rectangle.stack.fill"
        case .chess: return ""
        case .chats: return UIState.Glyph.chats
        case .groups: return "person.3.fill"
        case .channels: return "megaphone.fill"
        case .music: return UIState.Glyph.music
        case .gallery: return UIState.Glyph.gallery
        case .card: return "person.text.rectangle"
        case .settings: return "gearshape.fill"
        }
    }
}

enum MTLibraryIconStyle: String, CaseIterable, Identifiable {
    case white, native, gold   // native's stored word stays as born: it lives in every backup (SeedScope.settingKeys); the screen says «Montana OS»
    static let key = "appLibraryIconStyle"
    static let initial = MTLibraryIconStyle.white   // the author's word 29.09: the white glyphs of the 1990 drawer are the default
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .white: return "White icons"
        case .native: return "Montana OS"
        case .gold: return "Gold style"
        }
    }
}

/// THE FEED'S WHITE MARK (the author's word 25.09: «the time symbol in the side panel in the style of the others — a white
/// circle, empty inside, and the time symbol: exactly the same logo, only white — not another drawing»): the logo itself drawn
/// white by its own shape, inside the thin white ring the outlined glyphs wear.
struct MTFeedMark: View {
    var side: CGFloat = 26
    var body: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 1.6)
            Image("Logo").renderingMode(.template).resizable().scaledToFit()
                .foregroundColor(.white).padding(side * 0.22)
        }
        .frame(width: side, height: side)
    }
}

/// The author's original artwork is bundled unchanged. Each window shows one tile, without its poster caption.
private struct MTLibraryGoldTile: View {
    let app: MTApplication
    let side: CGFloat
    private var origin: CGPoint {
        let x: [CGFloat] = [48, 312, 576, 840]
        let y: [CGFloat] = [250, 547, 839]
        return CGPoint(x: x[app.artworkIndex % 4], y: y[app.artworkIndex / 4])
    }
    var body: some View {
        let scale = side / 234
        Image("LibraryGoldAtlas").resizable()
            .frame(width: 1122 * scale, height: 1402 * scale)
            .offset(x: -origin.x * scale, y: -origin.y * scale)
            .frame(width: side, height: side, alignment: .topLeading)
            .clipped()
    }
}

struct MTApplicationIcon: View {
    let app: MTApplication
    var side: CGFloat = 62
    var style: MTLibraryIconStyle? = nil
    @AppStorage(MTLibraryIconStyle.key) private var savedStyle = MTLibraryIconStyle.initial.rawValue
    private var effectiveStyle: MTLibraryIconStyle { style ?? MTLibraryIconStyle(rawValue: savedStyle) ?? .initial }
    /// THE WHITE ICONS (the author's word 29.09, the drawer of 1990 as the pattern): the bar's own glyphs one to one, white and
    /// outlined; the feed's is the logo in its ring, the chess's its icon. ONE STYLE FOR EVERY ROW (the author's word 29.09
    /// evening: «white icons by default, the network included, in one style»): the network's globe is the platform's outlined
    /// glyph in the same white, no longer the coloured globe of the bar. Drawn for the 30-point row mark and scaled by it, so
    /// every window shows the same set.
    @ViewBuilder private var whiteMark: some View {
        let unit = side / 30
        switch app {
        case .feed: MTFeedMark(side: 26 * unit)
        case .chess: MTChessIcon().frame(width: 26 * unit, height: 26 * unit)
        default: Image(systemName: app.glyph).font(.system(size: 22 * unit, weight: .regular)).foregroundColor(.white)
        }
    }
    @ViewBuilder private var nativeSymbol: some View {
        let index = app.artworkIndex
        let x: [CGFloat] = [29, 330, 626, 931]
        let y: [CGFloat] = [130, 482, 795]
        let inner = side
        let scale = inner / 300
        Image("LibraryNativeSymbols").resizable()
            .frame(width: 1254 * scale, height: 1254 * scale)
            .offset(x: -x[index % 4] * scale, y: -y[index / 4] * scale)
            .frame(width: inner, height: inner, alignment: .topLeading)
            .clipped()
    }
    var body: some View {
        ZStack {
            switch effectiveStyle {
            case .gold:
                MTLibraryGoldTile(app: app, side: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.21, style: .continuous))
            case .white: whiteMark
            case .native: nativeSymbol
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .bottomTrailing) {
            // The logo badge only where it can be read: on a tile of 48 and more, not on the drawer's 30-point row mark.
            if effectiveStyle == .gold && side >= 48 {
                Image("Logo").resizable().scaledToFit()
                    .padding(side * 0.025)
                    .frame(width: side * 0.30, height: side * 0.30)
                    .background(.black, in: Circle())
                    .clipShape(Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

/// The settings preview uses the library's actual renderer and preference, with no second icon system.
struct MTLibraryIconStyleView: View {
    @AppStorage(MTLibraryIconStyle.key) private var savedStyle = MTLibraryIconStyle.initial.rawValue
    @AppStorage("appLibraryIcons") private var icons = false   // the drawer's view: the 1949 list by default, the icons' grid by choice
    private let preview: [MTApplication] = [.contacts, .calls, .chats, .feed, .card, .music, .gallery, .chess, .settings]
    private var selected: MTLibraryIconStyle { MTLibraryIconStyle(rawValue: savedStyle) ?? .initial }
    private func card(_ style: MTLibraryIconStyle) -> some View {
        Button {
            savedStyle = style.rawValue
            MontanaTrace.mark("library_icons", "style=" + style.rawValue)
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(style.title).font(.headline).foregroundColor(.white)
                    Spacer(minLength: 0)
                    Image(systemName: selected == style ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected == style ? MontanaOctagon.platformBlue : Color.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), alignment: .top)], spacing: 18) {
                    ForEach(preview) { app in
                        VStack(spacing: 7) {
                            MTApplicationIcon(app: app, side: 56, style: style)
                            Text(app.title).font(.caption2).foregroundColor(.white)
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(style.title))
        .accessibilityAddTraits(selected == style ? .isSelected : [])
    }
    var body: some View {
        List {
            // THE DRAWER'S VIEW (the author's word 29.09): the list as it stood on 1949 by default; the icons' grid by choice,
            // chosen here, where the icons' style is chosen -- the drawer itself carries no heading and no search any more.
            Section("View") {
                Picker("View", selection: $icons) {
                    Label("List", systemImage: "list.bullet").tag(false)
                    Label("Icons", systemImage: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }.listRowBackground(MTGlassRowPlate())
            ForEach(MTLibraryIconStyle.allCases) { style in
                Section {
                    card(style)
                }.listRowBackground(MTGlassRowPlate())
            }
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()
        .navigationTitle("Application icons")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

enum MTLibraryCommand: String, CaseIterable, Identifiable {
    case open, pin
    var id: String { rawValue }
    func title(pinned: Bool) -> String {
        switch self {
        case .open: return String(localized: "Open", bundle: MTLanguage.bundle)
        case .pin: return pinned ? String(localized: "Unpin", bundle: MTLanguage.bundle) : String(localized: "Pin", bundle: MTLanguage.bundle)
        }
    }
    func glyph(pinned: Bool) -> String {
        switch self {
        case .open: return "arrow.up.forward.app"
        case .pin: return pinned ? "pin.slash" : "pin"
        }
    }
}

struct MTLibrarySection: Identifiable {
    let id: String
    let title: String
    var apps: [MTApplication]

    static func ordered(apps: [MTApplication], query: String, searching: Bool, pins: Set<MTApplication>) -> [Self] {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = apps.filter {
            word.isEmpty || $0.title.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], locale: MTLanguage.locale) != nil
        }.sorted { $0.title.compare($1.title, options: [.caseInsensitive, .numeric], locale: MTLanguage.locale) == .orderedAscending }
        var result: [Self] = []
        if !searching {
            let favorites = matches.filter { pins.contains($0) }
            if !favorites.isEmpty {
                result.append(Self(id: "favorites", title: String(localized: "Favorites", bundle: MTLanguage.bundle), apps: favorites))
            }
            for group in MTLibraryGroup.allCases {
                let entries = matches.filter { $0.group == group && !pins.contains($0) }
                if !entries.isEmpty { result.append(Self(id: group.rawValue, title: group.title, apps: entries)) }
            }
            return result
        }
        for app in matches {
            let letter = String(app.title.prefix(1)).uppercased(with: MTLanguage.locale)
            if let last = result.indices.last, result[last].id == letter { result[last].apps.append(app) }
            else { result.append(Self(id: letter, title: letter, apps: [app])) }
        }
        return result
    }
}

/// Both library views use the same table and search host; only the rows change their presentation.
struct MTLibraryTile: View {
    let app: MTApplication
    let pinned: Bool
    let count: Int
    let select: () -> Void
    let command: (MTLibraryCommand) -> Void
    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                MTApplicationIcon(app: app)
                    .overlay(alignment: .topTrailing) { MTCountBadge(count) }
                Text(app.title).font(.caption).foregroundColor(.white)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(MTLibraryCommand.allCases) { item in
                Button { command(item) } label: {
                    Label(item.title(pinned: pinned), systemImage: item.glyph(pinned: pinned))
                }
            }
        }
    }
}
