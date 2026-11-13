//
//  MontanaProfile.swift
//  Montana — a Montana messenger
//
//  Cut out of ContentView.swift whole, declaration by declaration (the author's word 10.09):
//  nothing here was renamed or rewritten; the file holds one screen and what only it reads.
//

import SwiftUI
import VisionKit
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



// ════════════════════════════════════════════════════════════
// PROFILEVIEW — PROFILE PAGE
// ════════════════════════════════════════════════════════════
// profile avatar gallery: swipe to browse, set as main, delete
struct AvatarGalleryView: View {
    let photos: [String]
    var onSetMain: (String) -> Void
    var onDelete: (String) -> Void
    var onClose: () -> Void
    @State private var index = 0
    @State private var current: [String] = []
    @State private var dragY: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !current.isEmpty {
                TabView(selection: $index) {
                    ForEach(Array(current.enumerated()), id: \.offset) { i, name in
                        if let ui = MontanaMediaVault.image(name) {
                            Image(uiImage: ui).resizable().scaledToFit().tag(i)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            VStack {
                HStack {
                    Button { onClose() } label: {
                        Image(systemName: "xmark").foregroundColor(.white).font(.title2).padding()   // TOUCH-OK: the platform's 16-point padding around the glyph makes a target of 52 points
                    }
                    Spacer()
                    Text(current.isEmpty ? "" : "\(index + 1) of \(current.count)")
                        .foregroundColor(.primary).font(.subheadline)
                    Spacer()
                    Image(systemName: "xmark").foregroundColor(.clear).font(.title2).padding()
                }
                Spacer()
                if !current.isEmpty {
                    HStack(spacing: 14) {
                        Button {
                            onSetMain(current[min(index, current.count - 1)])
                        } label: {
                            Label("Make primary", systemImage: "star.fill")
                                .font(.subheadline).foregroundColor(.black)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.accentColor).clipShape(Capsule())
                        }
                        Button {
                            let name = current[min(index, current.count - 1)]
                            onDelete(name)
                            current.removeAll { $0 == name }
                            if index >= current.count { index = max(0, current.count - 1) }
                            if current.isEmpty { onClose() }
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.subheadline).foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.red.opacity(0.85)).clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .offset(y: dragY)
        .gesture(
            DragGesture()
                .onChanged { v in if v.translation.height > 0 { dragY = v.translation.height } }
                .onEnded { v in
                    if v.translation.height > 120 { onClose() }
                    else { withAnimation(.spring()) { dragY = 0 } }
                }
        )
        .onAppear { current = photos }
    }
}

/// The profile page's fields — for system cursor management.
enum ProfileField: Hashable { case first, bio, link }

struct ProfileView: View {
    var onboarding: Bool = false
    var onFinish: (() -> Void)? = nil
    /// A row of the editor: its glyph WHITE (the author's word 26.09: «on the edit page the icons of change photo, background and
    /// call sign white»), its word as it stood.
    private func editRow(_ t: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.primary).frame(width: 26)
            Text(LocalizedStringKey(t)).foregroundColor(onboarding ? Color.white : Color.accentColor)   // on the making only white (word 18949)
        }
    }
    @AppStorage("userName") private var name: String = ""
    @AppStorage("profileBio") private var bio: String = ""     // a few lines about oneself (24.09)
    @AppStorage("profileLink") private var link: String = ""   // one link, opened by whoever reads the profile (24.09)
    @AppStorage("avatarData") private var avatarData: Data = Data()
    @AppStorage("avatarGallery") private var avatarGalleryJSON: String = ""
    @Environment(\.dismiss) private var dismiss
    /// The page's own way out ([C-1], 19.09): the sliding container's close when the page is hosted
    /// there — the system's dismiss has nothing to dismiss in a hosted page — else the system's own.
    @Environment(\.montanaClose) private var montanaClose
    private func leave() { mtLeavePage(montanaClose, dismiss) }

    @State private var pickerItem: PhotosPickerItem?
    @State private var showAvatarGallery = false
    @State private var pageGround = false   // the page's ground being chosen (MTWallpaperPicker, the page's task)
    @State private var showPhotoPicker = false
    @State private var tName = ""
    @State private var tBio = ""
    @State private var tLink = ""
    @State private var info = ""
    @State private var fieldsSave: Task<Void, Never>?
    @State private var showInfo = false
    /// Where the cursor stands. The cursor is also dismissed through it — the system road,
    /// not a hand-rolled first-responder intercept.
    @FocusState private var focus: ProfileField?

    @ViewBuilder private var profilePartOne: some View {
                // ── The face ──
                Section {
                    HStack {
                        Spacer(minLength: 0)
                        // The circle is ONE label of one system photo picker: no photo -- the tap opens the system gallery; a
                        // photo -- the system menu with two outcomes, replace or delete. No custom sheet, no custom gesture.
                        avatarChooser
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    // The row's empty space dismisses the cursor and does not open the gallery.
                    .contentShape(Rectangle())
                    .onTapGesture { focus = nil }
                    // The one presenter of the library for the face: the circle's menu and the row's menu both ask it.
                    .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
                }
                .listRowBackground(Color.clear)   // the ground stands behind the whole editor (25.09): the face's row shows it as it always did

                // ── The photo and the page's ground, in the page's own bubble (the author's word 25.09: «the buttons "change page
                // background" and "change photo" in a bubble, in the same style as the other buttons of the edit page») ──
                Section {
                    photoRow
                    if !onboarding {
                        // THE PAGE'S GROUND (the author's word 24.09): the chat's own chooser with the page's task -- a photo placed
                        // by the finger or a drawn ground; the page's ground is every page's and every chat's (rule 30).
                        Button { focus = nil; pageGround = true } label: {
                            HStack { editRow("Change page background", "photo.on.rectangle"); Spacer() }.contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .listRowBackground(MTGlassRowPlate())

                // ── First name / Last name ──
                Section {
                    // Length limit: first and last name 64 characters each.
                    // Without it the field accepts a string of any length.
                    TextField("First name", text: $tName).foregroundColor(.primary)
                        .focused($focus, equals: .first)
                        .onChange(of: tName) { _, v in
                            let p = MTCrown.plain(v)   // a crown is given, never typed (03.10)
                            if p != v { tName = p } else if v.count > 64 { tName = String(v.prefix(64)) }
                        }
                    callsignRow
                }
                .listRowBackground(MTGlassRowPlate())

                // ── Bio and link (the author's word 24.09): the platform's own fields in the page's own rows ──
                if !onboarding {
                    Section {
                        TextField("Bio", text: $tBio, axis: .vertical).foregroundColor(.primary)
                            .lineLimit(1...4)
                            .focused($focus, equals: .bio)
                            .onChange(of: tBio) { _, v in if v.count > MTPeerAbout.bioLimit { tBio = String(v.prefix(MTPeerAbout.bioLimit)) } }
                        TextField("Link", text: $tLink).foregroundColor(.primary)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focus, equals: .link)
                            .onChange(of: tLink) { _, v in if v.count > MTPeerAbout.linkLimit { tLink = String(v.prefix(MTPeerAbout.linkLimit)) } }
                    } footer: {
                        Text("Your bio and link are seen by the people you write to.").foregroundColor(.gray)
                    }
                    .listRowBackground(MTGlassRowPlate())
                    // No row leads to my page: the editor opens from it, by its mark top right (the author's word 25.09).

                }

    }

    @ViewBuilder private var profilePartTwo: some View {
                // ── What leaves the device (first run only) ──
                if onboarding {
                    Section {
                    } footer: {
                        Text("Everything here stays on your device. Nothing is published: your correspondent sees only what you choose to show. Leave the name empty and your call sign is used.").foregroundColor(.white).font(.subheadline)
                    }
                    .listRowBackground(MTGlassRowPlate())
                }

                // «Forget this device» lives on the Privacy page (the author's word 18.09).
    }

    private var profileList0: some View {
        List {
                profilePartOne
                profilePartTwo
            }
    }

    /// Pick a callsign from the full list — the same table that yields the default callsign,
    /// in this device's language.
    private var callsignRow: some View {
        NavigationLink { MontanaCallsignPicker(onMaking: onboarding) } label: {
            HStack {
                Image(systemName: "person.text.rectangle").foregroundColor(.primary)   // the ground's ink, as the editor's other glyphs (26.09; black on the gold since 21.10)
                Text("Choose a call sign").foregroundColor(.primary)
                Spacer()
            }
        }
    }

    private var profileList1: some View {
        profileList0
            .scrollContentBackground(.hidden)
            // A swipe over the list dismisses the keyboard — system behaviour, no custom gesture.
            .scrollDismissesKeyboard(.interactively)
            .background(
                // Tapping empty space dismisses the cursor. The transparent layer sits BEHIND
                // the list: it does not intercept row taps and does not hinder scrolling.
                // THE PAGE'S GROUND BEHIND THE WHOLE EDITOR (the author's word 25.09: the fields on glass, the ground under
                // them as it already is): the very ground my page wears, window-aligned, drawn once behind the list -- the
                // drawer stands on it the same way -- and every row above it is the tree's glass (MTGlassRowPlate); none
                // chosen -- the page's black, as the editor always stood.
                // On the making the editor stands on the one black of the login's pages (word 18938), never a ground of its own.
                ZStack { Color.black; if onboarding { MTWallpaper.paint(MTWallpaper.byDefault) } else { MTPageGroundWindow() } }.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { focus = nil }
            )
            .navigationBarTitleDisplayMode(.inline)
    }

    private var profileList2: some View {
        profileList1
            .toolbar {
                // The «Cancel» and «Done» buttons live ONLY in onboarding: there the person is
                // still naming themselves and the step has an end. Inside the app the page has
                // no end — every change is already saved and there is nothing to confirm; a
                // «Done» button would promise nothing was written before it, which is untrue.
                ToolbarItem(placement: .topBarTrailing) {
                    if onboarding {
                    MontanaDoneMark {
                        // The person leaves here NAMED. Wrote no name — they go by the
                        // callsign, and the callsign lands in the name field itself rather
                        // than being substituted at display time: otherwise the person sees
                        // emptiness where they have a name. Wrote a name or chose a face —
                        // what was written and chosen is saved.
                        if tName.trimmingCharacters(in: .whitespaces).isEmpty {
                            let sign = MontanaCallsign.of(MontanaSeed.twin ?? "")
                            if !sign.isEmpty {
                                tName = sign; name = sign
                                MontanaTrace.mark("callsign_assigned", "len=\(sign.count)")
                            }
                        }
                        save(); if onboarding { onFinish?() }
                    }
                    } else {
                        // The same native checkmark as on the card page (the author's word 16.09): every
                        // change is already saved, the mark closes the page — one glyph for «done» everywhere.
                        MontanaDoneMark { save(); leave() }
                    }
                }
            }
            .onAppear { tName = name; tBio = bio; tLink = link }
            // 2) Every change saves ITSELF. The typing pause is not for confirmation but so
            // the peers receive the whole name, not each letter of it.
            .onChange(of: tName) { _, _ in saveFieldsSoon() }
            .onChange(of: tBio) { _, _ in saveFieldsSoon() }
            .onChange(of: tLink) { _, _ in saveFieldsSoon() }
            .mtFaceCrop($pickerItem) { jpeg in   // the one door of a face (MTFaceCropDoor)
                if let nm = saveToDocs(jpeg, ext: "jpg") {
                    var list = loadAvatarGallery(); list.insert(nm, at: 0); saveAvatarGallery(list)
                }
                MontanaSelfFace.set(jpeg)
            }
            .fullScreenCover(isPresented: $showAvatarGallery) {
                AvatarGalleryView(
                    photos: loadAvatarGallery(),
                    onSetMain: { nm in if let d = try? Data(contentsOf: attachmentURL(nm)) { MontanaSelfFace.set(d) } },
                    onDelete: { nm in
                        var list = loadAvatarGallery(); list.removeAll { $0 == nm }; saveAvatarGallery(list)
                        if let first = list.first, let d = try? Data(contentsOf: attachmentURL(first)) { MontanaSelfFace.set(d) }
                        else if list.isEmpty { MontanaSelfFace.clear() }
                    },
                    onClose: { showAvatarGallery = false })
            }
    }

    private var profileList3: some View {
        profileList2
            .alert(info, isPresented: $showInfo) { Button("Got it", role: .cancel) {} }
        .preferredColorScheme(.dark)
    }

    var body: some View {
        NavigationStack {
            profileList3
        }
        .montanaPage(isPresented: $pageGround, key: "page-ground") { MTWallpaperPicker(task: .page) }
    }

    /// Save the page's fields while staying on it. One typing pause for all fields.
    func saveFieldsSoon() {
        fieldsSave?.cancel()
        fieldsSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            if !tName.trimmingCharacters(in: .whitespaces).isEmpty { name = tName }
            E2E.shared.broadcastName()
            keepAbout()
        }
    }
    /// The bio and the link are kept as typed; what leaves is the bio trimmed and the link only when it is one.
    private func keepAbout() {
        guard !onboarding else { return }
        bio = tBio; link = tLink.trimmingCharacters(in: .whitespacesAndNewlines)
        E2E.shared.broadcastAbout()
    }

    func save() {
        if !tName.trimmingCharacters(in: .whitespaces).isEmpty { name = tName }
        MontanaTelemetry.shared.event("PROFILE saved onboarding=\(onboarding) name=\(name.isEmpty ? 0 : 1) avatar=\(avatarData.count)B")
        if !onboarding {
            E2E.shared.broadcastAvatar()
            E2E.shared.broadcastName()   // renamed -> peers receive the new name
            keepAbout()
            leave()
        }
    }


    /// No photo — the label opens the system gallery. A photo — the same label opens the
    /// system menu with two outcomes: replace or delete. Hoisted out of the list body: the
    /// compiler does not digest such an expression inside a section in reasonable time.
    @ViewBuilder
    var avatarChooser: some View {
        if avatarData.isEmpty {
            PhotosPicker(selection: $pickerItem, matching: .images) { avatarPuck.contentShape(Circle()) }
                .buttonStyle(.plain).fixedSize()
        } else {
            Menu {
                Button { showPhotoPicker = true } label: { Label("Change photo", systemImage: "photo") }
                Button(role: .destructive) { MontanaSelfFace.clear() } label: {
                    Label("Remove photo", systemImage: "trash")
                }
            } label: { avatarPuck.contentShape(Circle()) }
            .buttonStyle(.plain).fixedSize()
        }
    }

    /// THE PHOTO'S ROW IN THE PAGE'S BUBBLE (the author's word 25.09: «the buttons "change page background" and "change photo"
    /// in a bubble, in the same style as the other buttons of the edit page»): the face's own two outcomes, as a row of the
    /// page's glass -- the system gallery when there is no photo, the system menu (replace or delete) when there is one.
    @ViewBuilder
    var photoRow: some View {
        if avatarData.isEmpty {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack { editRow("Choose photo", "photo"); Spacer() }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                Button { showPhotoPicker = true } label: { Label("Change photo", systemImage: "photo") }
                Button(role: .destructive) { MontanaSelfFace.clear() } label: {
                    Label("Remove photo", systemImage: "trash")
                }
            } label: {
                HStack { editRow("Change photo", "photo"); Spacer() }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// MY FACE ON THE EDIT PAGE IS THE ONE FACE VIEW (the author's word 25.09: one owner of the avatar and its drawing, no
    /// gold rim, the platform's own look): AvatarCircle with the picture in hand, exactly as the drawer draws me -- the glyph
    /// by the one resolver (E2E.myFaceGlyph), the shape the skin's, nothing around it. Separate from MTPeerHeader because
    /// that one carries ITS OWN photo picker, and nesting one system picker inside another is not allowed.
    var avatarPuck: some View {
        MTSelfFace(size: 108)
    }

    func loadAvatarGallery() -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(avatarGalleryJSON.utf8))) ?? []
    }
    func saveAvatarGallery(_ list: [String]) {
        avatarGalleryJSON = String(data: (try? JSONEncoder().encode(list)) ?? Data(), encoding: .utf8) ?? ""
    }
}

/// MY PROFILE AS THE PEOPLE I WRITE TO SEE IT (the author's word 24.09): the one face owner (MTFacePage),
/// at its circle as on every page, with my name as it leaves this phone (E2E.myDisplayName), my words and my link
/// as they leave it (MTPeerAbout) — the very header a correspondent's page draws for me, closing into the circle as there.
/// Nothing on this page is drawn by a hand of its own.
struct MontanaMyProfileView: View {
    @AppStorage("avatarData") private var avatarData: Data = Data()
    @AppStorage("userName") private var displayName: String = ""
    @AppStorage("profileBio") private var bio: String = ""
    @AppStorage("profileLink") private var link: String = ""
    @StateObject private var face = MTFaceDock()
    @State private var editing = false   // the page's editor over it (25.09)

    var body: some View {
        let _ = displayName   // the page follows the name as it is typed
        MTFacePage(face: face, glyph: E2E.myFaceGlyph(), name: E2E.myDisplayName(),
                   bio: MTPeerAbout.said(bio), links: MTPeerAbout.links(link), of: .me) { head in
            ScrollView {
                head   // the face, the page's first row: it scrolls away with the page (25.09)
                Color.clear.frame(height: 1)
                    .background(face.probe)   // the scroll up closes the face; only a tap opens it
                #if !MONTANA_MESSENGER
                MTApps.wall?.pane(owner: nil)   // my own wall, as the people I write to see it (the author's word 24.09)
                #endif
            }
            .scrollBounceBehavior(.always)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(face.dock == 2 ? .hidden : .automatic, for: .navigationBar)   // the whole screen is the face's
        // THE PAGE'S AUTHOR EDITS IT FROM IT (the author's word 25.09: «the edit button in the top right corner when the
        // page's author looks; take it away from the settings»): the profile's own mark opens the editor over the page;
        // the editor closes itself, never the page under it.
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MontanaEditMark { editing = true } } }
        .sheet(isPresented: $editing) { ProfileView().environment(\.montanaClose, nil).montanaMotionMeter() }   // measured (25.09)
        .onChange(of: avatarData, initial: true) { _, d in face.load(d) }
    }
}

/// MY PAGE FROM THE DRAWER (the author's word 24.09: «the face with the name top left of the side panel opens the
/// person's page, as the «My profile» button of Settings opens it»): the one page (MontanaMyProfileView) in a stack
/// of its own, left by the platform's back chevron -- the sliding container's own close, as the chat's back leaves --
/// or by the screen-edge swipe. The chevron wears the label colour, as the chat's back does.
struct MTMyPageFromDrawer: View {
    @Environment(\.montanaClose) private var close
    var body: some View {
        NavigationStack {
            MontanaMyProfileView()
                .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaBackMark { close?() }.tint(.primary) } }
        }
    }
}

/// THE CODE IS A GRID, NOT TEXT, and its geometry comes from screen pixels, never from the
/// reader's font. The system text-size setting changes text metrics; whatever derives its
/// size from them starts breathing with them, and a grid that breathes stops being a grid.
///
/// Second and main: a module must occupy a WHOLE number of device pixels. The picture used to
/// be built a thousand pixels a side and shown in a frame set in points — the rescale came
/// out fractional, and under honest no-smoothing drawing neighbouring module rows would
/// merge or vanish. To the eye that reads as distortion, to a camera as a grid with an
/// uneven pitch. Here the picture is built at exactly the size it will be shown, so there is
/// no rescale at all: one module — a whole number of pixels at any system font size.
enum MontanaQR {
    /// The code image for a `side` of points, built at the given display `scale` — the scale of
    /// the window that will show it, never the shared screen: mirroring, an external display and
    /// split screen answer with different numbers, and the grid must be built for the pixels it
    /// will actually occupy. Returned with that scale baked in, so it renders one-to-one:
    /// neither `resizable` nor `scaledToFit` is needed, and both are harmful.
    static func image(_ payload: Data, side: CGFloat, scale: CGFloat, correction: String = "L") -> UIImage? {
        // The card as TEXT is 1579 characters and the largest code version, where a module is
        // thinner than a reading camera's pixel; the same card as BYTES is 1188, and correction L
        // spends seven percent on redundancy instead of thirty. Together they take about a third
        // off the side.
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(payload, forKey: "inputMessage")
        f.setValue(correction, forKey: "inputCorrectionLevel")
        guard let ci = f.outputImage, ci.extent.width >= 1 else { return nil }
        let modules = Int(ci.extent.width.rounded())
        let screen = max(1, scale)
        // A whole number of pixels per module is the one thing that keeps a grid a grid.
        let perModule = max(1, Int((side * screen) / CGFloat(modules)))
        let big = ci.transformed(by: CGAffineTransform(scaleX: CGFloat(perModule), y: CGFloat(perModule)))
        guard let cg = CIContext().createCGImage(big, from: big.extent) else { return nil }
        return UIImage(cgImage: cg, scale: screen, orientation: .up)
    }
}

/// Showing the code. The size comes from the picture itself (already built for pixels), and
/// `fixedSize` keeps the layout from crushing the code when a large font grows neighbouring
/// text: the code is not text, and
/// anyone else must yield — never the code.
struct MontanaQRCode: View {
    let payload: Data
    let side: CGFloat
    var corner: CGFloat = 0
    /// The time symbol in the tree's hexagon at the centre (the author's word 08.09). A code that
    /// carries a mark is built with correction M: the mark covers about three percent of the
    /// modules, and level M restores fifteen — the reader never sees the hole.
    var logo: Bool = false
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        if let img = MontanaQR.image(payload, side: side, scale: displayScale, correction: logo ? "M" : "L") {
            Image(uiImage: img)
                .interpolation(.none)
                .frame(width: img.size.width, height: img.size.height)
                .fixedSize()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: corner))
                .overlay {
                    if logo {
                        MontanaHexagon().fill(Color.black)
                            .overlay(Image("Logo").resizable().scaledToFit().padding(side * 0.045))
                            .overlay(MontanaHexagon().stroke(Color.white, lineWidth: 2))
                            .frame(width: side * 0.22, height: side * 0.22)
                    }
                }
        }
    }
}

// ════════════════════════════════════════════════════════════
// STORIES — stories
// ════════════════════════════════════════════════════════════

struct StoryItem: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    var media: [StoryMedia] = []   // story content (photo and/or video)
    var avatarAsset: String? = nil // profile photo for the circle
    var isOwn: Bool = false        // whether this is my story (can be pinned)
}

// a single story item: photo or video (file in the stories folder)
struct StoryMedia: Codable {
    let type: String       // "image" or "video"
    let file: String       // file name
    var created: Double     // creation time (for "lives 24 hours")
    var pinned: Bool        // whether pinned (then it doesn't disappear)

    init(type: String, file: String, created: Double = 0, pinned: Bool = false) {
        self.type = type; self.file = file; self.created = created; self.pinned = pinned
    }
    enum CodingKeys: String, CodingKey { case type, file, created, pinned }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        file = try c.decode(String.self, forKey: .file)
        created = (try? c.decode(Double.self, forKey: .created)) ?? 0
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    }
}

// folder for story files
func storiesDir() -> URL {
    let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("stories")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}
func storyFileURL(_ name: String) -> URL { storiesDir().appendingPathComponent(name) }

// for loading a video from the gallery
struct MovieFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = storiesDir().appendingPathComponent("vid_\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }
}

// video in a story (autoplay)
struct StoryVideo: View {
    let url: URL
    @State private var player: AVPlayer?
    /// The story's sound is held by the story's own name while it stands on the screen (16.10).
    private var hold: String { "story " + url.lastPathComponent }
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                MontanaAudioSession.activatePlayback(hold)
                let p = AVPlayer(url: url)
                player = p
                p.play()
            }
            .onDisappear { player?.pause(); MontanaAudioSession.release(hold) }
    }
}

// full-screen story viewer (several photos/videos, tap — next)
struct StoryViewer: View {
    let story: StoryItem
    var uploadedAt: Double = 0          // when posted (for the time label)
    var onClose: () -> Void
    var onPin: (String) -> Void = { _ in }
    var onDelete: (String) -> Void = { _ in }
    var onSend: (String) -> Void = { _ in }
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var dragY: CGFloat = 0
    @State private var pinnedLocal: Set<String> = []
    @State private var replyText = ""
    @State private var toast: String?
    @State private var replyFocused = false   // the field's own focus (MTInputField's binding)
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    // "when posted" label under the author's name
    var agoText: String {
        let ts = (index < story.media.count && story.media[index].created > 0)
            ? story.media[index].created : uploadedAt
        guard ts > 0 else { return "" }
        let d = Date().timeIntervalSince1970 - ts
        if d < 60 { return "just now" }
        if d < 3600 { return "\(Int(d / 60)) min ago" }
        return "\(Int(d / 3600)) h ago"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            mediaContent.id(index)
            VStack {
                // progress segments (fill over time)
                HStack(spacing: 4) {
                    ForEach(0..<max(story.media.count, 1), id: \.self) { i in
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.35))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.white)
                                        .frame(width: geo.size.width * segmentFill(i))
                                }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.horizontal).padding(.top, 10)
                // header
                HStack(spacing: 10) {
                    Circle().fill(story.color).frame(width: 32, height: 32)
                        .overlay(Text(String(story.name.prefix(1)))
                            .foregroundColor(.white).font(.caption).bold())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(story.name).foregroundColor(.primary).bold()
                        if !agoText.isEmpty {
                            Text(agoText).foregroundColor(.white.opacity(0.7)).font(.caption2)
                        }
                    }
                    Spacer()
                    // delete own story
                    if story.isOwn, index < story.media.count {
                        Button {
                            onDelete(story.media[index].file)
                            onClose()
                        } label: {
                            Image(systemName: "trash").foregroundColor(.white).font(.headline)
                                .montanaFingerRoom(layout: 20)
                        }
                    }
                    Button { onClose() } label: {
                        Image(systemName: "xmark").foregroundColor(.white).font(.headline)
                            .montanaFingerRoom(layout: 20)
                    }
                }
                .padding()
                Spacer()
                bottomControls
            }
            // "sent" toast
            if let t = toast { MontanaToastLabel(text: t) }   // the one notice look (its own window)
        }
        .offset(y: dragY)
        .gesture(
            DragGesture()
                .onChanged { v in if v.translation.height > 0 { dragY = v.translation.height } }
                .onEnded { v in
                    if v.translation.height > 120 { onClose() }
                    else { withAnimation(.spring()) { dragY = 0 } }
                }
        )
        .onReceive(tick) { _ in
            guard !replyFocused else { return }   // pause while typing a reply
            progress += 0.05 / currentDuration()
            if progress >= 1 { advance() }
        }
    }

    // bottom: own story → pin; someone else's → reactions and reply 
    @ViewBuilder var bottomControls: some View {
        if story.isOwn {
            if index < story.media.count {
                let file = story.media[index].file
                let isPinned = pinnedLocal.contains(file) || story.media[index].pinned
                Button {
                    pinnedLocal.insert(file)
                    onPin(file)
                } label: {
                    Label(isPinned ? "Pinned" : "Pin to Page",
                          systemImage: isPinned ? "pin.fill" : "pin")
                        .font(.subheadline).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 30)
            }
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 18) {
                    ForEach(["❤️", "🔥", "👍", "😂", "😮", "😢"], id: \.self) { e in
                        Button { sendReaction(e) } label: {
                            Text(e).font(.system(size: 30))
                        }
                    }
                }
                // The chat's own field under the page (MTComposeRow, the author's word 22.09).
                MTComposeRow(text: $replyText, focused: $replyFocused, placeholder: "Reply...", onSend: { sendReply() })
            }
            .padding(.bottom, 14)
        }
    }

    func sendReaction(_ e: String) {
        onSend(e)
        showToast("\(e) sent")
    }
    func sendReply() {
        let t = replyText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        onSend(t)
        replyText = ""; replyFocused = false
        showToast("Reply sent")
    }
    func showToast(_ s: String) {
        withAnimation { toast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { toast = nil } }
    }

    @ViewBuilder var mediaContent: some View {
        if !story.media.isEmpty, index < story.media.count {
            let m = story.media[index]
            let url = storyFileURL(m.file)
            if m.type == "video" {
                StoryVideo(url: url).ignoresSafeArea()
            } else if let ui = UIImage(contentsOfFile: url.path) {
                Image(uiImage: ui).resizable().scaledToFit()
            } else {
                placeholder
            }
        } else {
            placeholder
        }
    }

    var placeholder: some View {
        ZStack {
            LinearGradient(colors: [story.color.opacity(0.7), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Image(systemName: "photo").font(.system(size: 60)).foregroundColor(.white.opacity(0.5))
        }
    }

    // how full segment i is
    func segmentFill(_ i: Int) -> CGFloat {
        if i < index { return 1 }
        if i == index { return CGFloat(min(progress, 1)) }
        return 0
    }

    // duration: photo 10 sec, video 30 sec
    func currentDuration() -> Double {
        guard !story.media.isEmpty, index < story.media.count else { return 10 }
        return story.media[index].type == "video" ? 30 : 10
    }

    func advance() {
        progress = 0
        if index < story.media.count - 1 { index += 1 } else { onClose() }
    }
}

// ════════════════════════════════════════════════════════════
// CHATINFOVIEW — contact profile
// ════════════════════════════════════════════════════════════
// what we show full-screen in the profile (avatar/photo/video) — a single modifier
// Full-screen avatar viewer
// The ONE full-screen photo viewer (SSOT). Behaviour — the avatar reference from Settings:
// a swipe in any direction drags the photo with the finger and dims the backdrop, past the
// threshold — close; short of it — spring back. Pinch 1-4x, double tap 2x; while zoomed a
// swipe pans instead of closing. Every place that shows a photo (avatars, chats, profiles,
// media) must use ONLY this mechanism — two implementations already gave different responses
// on different screens.
// A picked image boxed for fullScreenCover(item:) — UIImage itself is not Identifiable.
struct MTCropSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// THE ONE DOOR OF A FACE (11.11.2026, OZ 1 p.5, the author's word 19316 p.2: «the group's avatar settings by SSOT, as the
/// person's»): every face set on this phone -- the person's own, a correspondent's, a group's, a channel's -- goes from the
/// picker through the one crop (MTAvatarCropView). A screen hands over its picked item and takes the kept square; no screen
/// loads, resizes or crops a face of its own (before: the group's page and its birth resized the photo uncut).
struct MTFaceCropDoor: ViewModifier {
    @Binding var item: PhotosPickerItem?
    let kept: (Data) -> Void
    @State private var source: MTCropSource?
    func body(content: Content) -> some View {
        content
            .onChange(of: item) { _, picked in
                Task {
                    if let data = try? await picked?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        source = MTCropSource(image: img)   // the circle decides what the face keeps
                    }
                }
            }
            .fullScreenCover(item: $source) { src in
                MTAvatarCropView(image: src.image) { jpeg in
                    source = nil
                    if let jpeg { kept(jpeg) }
                }
            }
    }
}
extension View {
    func mtFaceCrop(_ item: Binding<PhotosPickerItem?>, kept: @escaping (Data) -> Void) -> some View {
        modifier(MTFaceCropDoor(item: item, kept: kept))
    }
}

// The avatar crop: the picked photo under the HEXAGON — pinch and pan set what the
// hexagon keeps; «Done» renders the hexagon's bounding square at 640 (every screen clips
// it to the same hexagon). The person sees the face the way every screen will show it.
// It is the one crop of the app (MTFrameCropView) with the square frame and the hexagon's rim.
struct MTAvatarCropView: View {
    let image: UIImage
    var onDone: (Data?) -> Void   // nil = cancelled

    var body: some View {
        MTFrameCropView(image: image) { kept in onDone(kept.flatMap { Self.render(image, $0) }) }
    }

    /// Renders exactly what the hexagon's square frames onto a 640-point square — the part the crop kept, mapped whole
    /// onto it: what you see is byte-for-byte what everyone gets.
    static func render(_ image: UIImage, _ kept: MTPictureFrame) -> Data? {
        let drawW = 640 / CGFloat(max(0.0001, kept.w))
        let drawH = 640 / CGFloat(max(0.0001, kept.h))
        let ox = -CGFloat(kept.x) * drawW
        let oy = -CGFloat(kept.y) * drawH
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1   // true 640 pixels: the screen's 3x turned the face into 1920px/844KB
        fmt.opaque = true   // a JPEG has no transparency: what is not painted must be black, never white
        let out = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 640), format: fmt).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 640))
            image.draw(in: CGRect(x: ox, y: oy, width: drawW, height: drawH))
        }
        return out.jpegData(compressionQuality: 0.85)
    }
}

/// ONE CROP FOR EVERY FRAME (the author's word 24.09: a post's picture takes a frame of its own — «its size, the field
/// of it the post shows»). The picked photo under a frame: pinch and pan set what the frame keeps, the photo always
/// covering it. The face is this crop with the square frame and the hexagon's rim; a post's picture is it with the
/// tile's rim and, under the frame, the shapes a post takes — each a miniature of the picture itself in that shape.
/// The answer is the part kept, in the picture's own proportions (MTPictureFrame); nil — left.
struct MTFrameCropView: View {
    enum Rim { case hexagon, tile }
    let image: UIImage
    var rim: Rim = .hexagon
    /// The shapes offered under the frame, width over height; empty — the square alone, nothing under the frame.
    var shapes: [Double] = []
    var onDone: (MTPictureFrame?) -> Void

    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var shape: Double
    @State private var placed = false
    private let start: MTPictureFrame?

    init(image: UIImage, rim: Rim = .hexagon, shapes: [Double] = [], start: MTPictureFrame? = nil,
         onDone: @escaping (MTPictureFrame?) -> Void) {
        self.image = image
        self.rim = rim
        self.shapes = shapes
        self.start = start
        self.onDone = onDone
        let own = MTPictureFrame.held(Double(image.size.width / max(image.size.height, 1)))
        _shape = State(initialValue: shapes.isEmpty ? 1 : (start.map { MTPictureFrame.held($0.a) } ?? own))
    }

    /// The frame on the screen: its sides, the fill-scale at which the photo covers it, and how far it stands above the
    /// window's centre so the shapes under it have their room.
    private struct Dims { let fw: CGFloat; let fh: CGFloat; let base: CGFloat; let lift: CGFloat }
    private static let chooserRoom: CGFloat = 88
    private func dims(_ s: Double, _ geo: GeometryProxy) -> Dims {
        let chooser: CGFloat = shapes.isEmpty ? 0 : Self.chooserRoom
        // The frame's side: the width less the margins, and never so tall that it meets the bar —
        // the reader is the whole window, so the bar and the notch are subtracted here, once.
        let roomW = geo.size.width - 48
        let roomH = geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 2 * 56 - chooser
        let a = CGFloat(s)
        let fw = max(120, min(roomW, roomH * a))
        let fh = fw / a
        let base = max(fw / max(image.size.width, 1), fh / max(image.size.height, 1))
        let lift = shapes.isEmpty ? 0 : (geo.safeAreaInsets.bottom + chooser - geo.safeAreaInsets.top) / 2
        return Dims(fw: fw, fh: fh, base: base, lift: lift)
    }

    var body: some View {
        NavigationStack {
        GeometryReader { geo in
            let d = dims(shape, geo)
            let z = max(zoom * pinch, 1)
            // ONE SPACE, ONE CENTRE (the author's word 20.09: «a white circle and a grey circle»): the
            // dimming used to ignore the safe area on its own — its hole was centred on the window
            // while the picture and the rim were centred on the bar's remainder, so the two frames
            // stood apart by half the bar on every device with a notch. Nothing inside ignores the
            // safe area now; the whole reader does, once, below — the picture, the dimming, the rim
            // and the render share one centre by construction.
            ZStack {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .frame(width: image.size.width * d.base, height: image.size.height * d.base)
                    .scaleEffect(z)
                    .offset(covering(pan, z: z, d))
                    .offset(y: -d.lift)
                // Everything outside the frame darkens; the frame itself stays clear.
                Rectangle().fill(Color.black.opacity(0.6))
                    .overlay(hole(d).offset(y: -d.lift).blendMode(.destinationOut))
                    .compositingGroup()
                    .allowsHitTesting(false)
                rimLine(d).offset(y: -d.lift).allowsHitTesting(false)
            }
            // THE MARKS ARE THE BAR'S (the author's word 18.09): the cross top left, the checkmark
            // top right — the platform's own places, the one bar mark (44 points, first touch).
            // A text «Cancel» and a checkmark at the bottom stood here, outside every rule of ours.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaCloseMark { onDone(nil) } }
                ToolbarItem(placement: .topBarTrailing) { MontanaDoneMark { onDone(kept(d)) } }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .updating($pinch) { v, st, _ in st = v }
                    .onEnded { v in zoom = min(max(zoom * v, 1), 5) }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { v in
                        pan = covering(CGSize(width: lastPan.width + v.translation.width,
                                              height: lastPan.height + v.translation.height),
                                       z: max(zoom * pinch, 1), d)
                    }
                    .onEnded { _ in lastPan = pan }
            )
            .onChange(of: zoom) { _, z in pan = covering(pan, z: z, d); lastPan = pan }
            // THE SHAPE CHANGES, THE PLACE STAYS: the new frame stands around the middle of what the old one kept.
            .onChange(of: shape) { old, new in
                let was = kept(dims(old, geo))
                place(MTPictureFrame.around(was.x + was.w / 2, was.y + was.h / 2, shape: new, of: image.size), dims(new, geo))
            }
            .onAppear {
                guard !placed else { return }
                placed = true
                if let start { place(start, d) }
            }
            // The shapes stand over the gestures, not inside them: a scroll of the row never pans the photo.
            .overlay(alignment: .bottom) {
                if !shapes.isEmpty { chooser.padding(.bottom, geo.safeAreaInsets.bottom + 12) }
            }
        }
        .ignoresSafeArea()   // ONE SPACE: the reader is the whole window; every frame inside shares its centre
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)   // the photo runs under the bar, the marks stand on their own circles
        .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @ViewBuilder private func hole(_ d: Dims) -> some View {
        switch rim {
        case .hexagon: MontanaHexagon().frame(width: d.fw, height: d.fh)
        case .tile: RoundedRectangle(cornerRadius: 10, style: .continuous).frame(width: d.fw, height: d.fh)
        }
    }
    @ViewBuilder private func rimLine(_ d: Dims) -> some View {
        switch rim {
        case .hexagon: MontanaHexagon().stroke(Color.white.opacity(0.8), lineWidth: 1.5).frame(width: d.fw, height: d.fh)
        case .tile:
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                .frame(width: d.fw, height: d.fh)
        }
    }

    /// THE SHAPES, AS MINIATURES OF THE PICTURE ITSELF (the rule of 22.09: a choice of a thing seen is shown by the thing,
    /// not named by a word): the picture's own shape first, then the shapes a post takes — each the picture's middle cut to
    /// it; the chosen one wears the white rim.
    private var chooser: some View {
        let own = MTPictureFrame.held(Double(image.size.width / max(image.size.height, 1)))
        var options: [(a: Double, own: Bool)] = [(own, true)]
        for a in shapes where !options.contains(where: { abs($0.a - a) < 0.001 }) { options.append((a, false)) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { i in
                    let o = options[i]
                    let chosen = abs(o.a - shape) < 0.001
                    let side: CGFloat = 44
                    let w = 1 <= o.a ? side : side * CGFloat(o.a)
                    let h = 1 <= o.a ? side / CGFloat(o.a) : side
                    Button { shape = o.a } label: {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: w, height: h).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.white.opacity(chosen ? 1 : 0.3), lineWidth: chosen ? 2 : 1))
                            .frame(width: 56, height: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(o.own ? Text("Original") : Text(verbatim: Self.ratio(o.a)))   // USER-DATA: a shape's ratio, digits only
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 64)
    }
    /// A shape's ratio in digits, for the voice: «4:5», «16:9».
    private static func ratio(_ a: Double) -> String {
        for (w, h) in [(1, 1), (4, 5), (3, 4), (9, 16), (4, 3), (16, 9)] where abs(Double(w) / Double(h) - a) < 0.001 {
            return String(w) + ":" + String(h)
        }
        return String(format: "%.2f", a)
    }

    /// THE PHOTO COVERS THE FRAME, ALWAYS (the author's word 11.09): a pan that dragged an edge
    /// inside the square left the rest of it empty, and the empty part rendered as white in the
    /// saved face — hidden by the hexagon in the row, in full view when the face opens. The
    /// pan is bounded by how much of the picture lies beyond the frame at the current zoom.
    private func covering(_ p: CGSize, z: CGFloat, _ d: Dims) -> CGSize {
        let mx = max(0, (image.size.width * d.base * z - d.fw) / 2)
        let my = max(0, (image.size.height * d.base * z - d.fh) / 2)
        return CGSize(width: min(max(p.width, -mx), mx), height: min(max(p.height, -my), my))
    }
    /// The part the frame keeps now, in the picture's own proportions: the same fill-scale, zoom and pan the screen draws.
    private func kept(_ d: Dims) -> MTPictureFrame {
        let z = max(zoom, 1)
        let p = covering(pan, z: z, d)
        let dw = image.size.width * d.base * z, dh = image.size.height * d.base * z
        let w = min(1, d.fw / dw), h = min(1, d.fh / dh)
        let x = min(max(0.5 - p.width / dw - w / 2, 0), 1 - w)
        let y = min(max(0.5 - p.height / dh - h / 2, 0), 1 - h)
        return MTPictureFrame(a: Double(d.fw / d.fh), x: Double(x), y: Double(y), w: Double(w), h: Double(h))
    }
    /// The zoom and the pan that keep a given part: the inverse of kept.
    private func place(_ f: MTPictureFrame, _ d: Dims) {
        let z = min(max(d.fw / (CGFloat(max(0.0001, f.w)) * image.size.width * d.base), 1), 5)
        let dw = image.size.width * d.base * z, dh = image.size.height * d.base * z
        zoom = z
        pan = covering(CGSize(width: (0.5 - CGFloat(f.x) - CGFloat(f.w) / 2) * dw,
                              height: (0.5 - CGFloat(f.y) - CGFloat(f.h) / 2) * dh), z: z, d)
        lastPan = pan
    }
}

// A frame captured during layout into a PLAIN box — never @State, so scrolling re-renders
// nothing for it; the value is read exactly once, at the moment of the tap. It is what lets
// the photo fly OUT of its own bubble without costing the feed.
final class MTFrameBox { var rect: CGRect = .zero }

/// The full view of a face or a picture (PhotoPresenter), and the picker's album.
struct MontanaPhotoViewer: View {
    let image: UIImage?
    var fallbackColor: Color = .gray
    var fallbackInitial: String = ""
    /// THE PAGES (the picker, the author's word 11.09): swiped aside, turned by a tap at the edge. Empty for a single picture. No
    /// strip of covers stands under them (the author's word 20455 p.4: «no Montana gallery while viewing anywhere again»).
    var files: [String] = []
    var startFile: String = ""
    /// PAGES FROM ELSEWHERE THAN THE MEDIA STORE (the picker, the author's word 11.09): who draws
    /// a page, whether it is a video and how it plays. Nil = the conversation's files.
    var loader: ((String) -> UIImage?)? = nil
    var videoOf: ((String) -> Bool)? = nil
    var play: ((String) -> Void)? = nil
    /// THE PICK ORDER at the top right (the picker): nil = no circle; a tap on it toggles the pick.
    var order: ((String) -> Int?)? = nil
    var onToggle: ((String) -> Void)? = nil
    /// THE PAGE, TOLD OUTWARD (the picker's send button sends the page on screen when nothing is picked).
    var onPage: ((String) -> Void)? = nil
    /// SAVE AND SHARE UNDER ONE PICTURE (the author's word 20455 p.4): the viewer of a picture seen on its own (PhotoPresenter)
    /// gives both at the bottom; Save answers whether Photos took it. Nil -- no button (a face, the picker's album).
    var onSave: (() async -> Bool)? = nil
    var onShare: (() -> Void)? = nil
    var onClose: () -> Void
    @State private var saved = false
    /// THE PAGE (the author's word 12.09: «what I opened is what I see, at once»): nil means the
    /// file the album opened on — the page is born equal to it and never turns to it later.
    @State private var pageState: String? = nil
    private var page: String { pageState ?? startFile }
    private var pageBinding: Binding<String> { Binding(get: { page }, set: { pageState = $0 }) }
    /// The album manner (the author's word 10.09): one tap on the photo hides the buttons, the next
    /// tap brings them back. A double tap stays the zoom.
    @State private var chrome = true
    private var paged: Bool { files.count > 1 }
    private var bottomInset: CGFloat { max(VideoPresenter.topVC()?.view.safeAreaInsets.bottom ?? 34, 16) }
    private func isVideo(_ f: String) -> Bool { videoOf?(f) ?? mtIsVideoName(f) }
    private func playPage(_ f: String) { (play ?? VideoPresenter.present)(f) }
    /// The picture of a page that costs nothing now: the bubble's decode cache, the poster of a
    /// video, the picker's own page. Nil = the page is born empty and fills off the main thread.
    private func pageImageCached(_ f: String) -> UIImage? {
        if let loader { return loader(f) }
        if f == startFile, let image { return image }
        return mtIsVideoName(f) ? videoThumbCached(f) : docImageCached(f)
    }
    /// The picture of a page at any price — decoded off the main thread by the page itself.
    private func pageImage(_ f: String) -> UIImage? {
        if let loader { return loader(f) }
        if f == startFile, let image { return image }
        if mtIsVideoName(f) { return videoThumbCached(f) ?? mtMediaFileURL(f).flatMap(videoPosterImage) }
        if let i = docImage(f) { return i }
        guard let u = mtMediaFileURL(f), let i = UIImage(contentsOfFile: u.path) else { return nil }
        return i.preparingForDisplay() ?? i
    }

    @State private var drag: CGSize = .zero
    /// NATIVE ZOOM (the author's word 11.09): the page is the system's own zooming scroll view
    /// (MTZoomImage) — pinch, pan while enlarged, double tap in and out, the way Photos does it.
    /// The viewer only learns whether a page stands enlarged, to keep the pull-to-close and the
    /// page turn away.
    @State private var zoomed = false
    /// The axis of the finger, decided at its first movement and held for the gesture: sideways
    /// belongs to the pages and moves nothing of ours; vertical is the pull that closes. Without
    /// the lock a sideways swipe carried its stray vertical component into the picture (12.09).
    @State private var pull: Bool? = nil

    /// A tap on a page: at the left or right edge it turns the page (the author's word 12.09);
    /// elsewhere it hides or shows the strip and the buttons.
    private func tap(_ x: CGFloat) {
        if paged, !zoomed, x < 0.15 { turn(-1) }
        else if paged, !zoomed, x > 0.85 { turn(1) }
        else { chrome.toggle() }
    }
    private func turn(_ d: Int) {
        guard let i = files.firstIndex(of: page), files.indices.contains(i + d) else { return }
        pageState = files[i + d]
    }

    var body: some View {
        let dy = paged ? drag.height : hypot(drag.width, drag.height)
        let bgOpacity = zoomed ? 1 : 1 - min(abs(dy) / 400, 0.75)
        return ZStack {
            Color.black.opacity(bgOpacity).ignoresSafeArea()
            if paged {
                // MONTANA ALBUM (the author's word 12.09): the pages are the system's page view
                // controller in its plain scrolling manner — the page follows the finger sideways
                // and settles, the way the system's own album does; nothing else moves. ONE state
                // — page — is both the shown page and the centred cover of the strip. The
                // controller is lazy by construction: it asks for a neighbour only when the finger
                // reaches for it.
                MTAlbumPager(files: files, page: pageBinding, zoomed: $zoomed) { f in AnyView(pageView(f)) }
                    .offset(drag)
                    .onChange(of: pageState) { _, _ in zoomed = false; onPage?(page) }
            } else if !startFile.isEmpty {
                // A one-item library selection still has the video's play control and loader.
                pageView(startFile).offset(drag)
            } else if let ui = image {
                MTZoomImage(image: ui, active: true, onTap: { _ in chrome.toggle() }, onZoom: { zoomed = $0 },
                            onPull: { t, end in if let end { letGo(t, end) } else { drag = t } })
                    .offset(drag)
            } else {
                // The full view is the same face, only large: the glyph takes the same share
                // of the circle as in the list, so the tap opens IT, not an empty circle.
                Circle().fill(Color.black).frame(width: 260, height: 260)
                    .overlay(Text(fallbackInitial)
                        .font(.system(size: 260 * MontanaAvatar.glyphScale(fallbackInitial), weight: .bold))
                        .foregroundColor(Color.accentColor))
            }
            if order != nil || paged {
                // The picker's control: the pick circle top right. One picture has none.
                VStack(spacing: 10) {
                    if let order {
                        HStack {
                            Spacer()
                            MTPickOrder(order: order(page))
                                .contentShape(Circle())
                                .onTapGesture { onToggle?(page) }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, max(VideoPresenter.topVC()?.view.safeAreaInsets.top ?? 47, 20))
                    }
                    Spacer()
                }
                // The ZStack ignores the safe area, so the controls claim the bottom inset by hand.
                .padding(.bottom, bottomInset)
                .opacity(zoomed || abs(dy) > 8 || !chrome ? 0 : 1)   // steps aside the moment the hands work, or on a tap
                .animation(.easeInOut(duration: 0.22), value: chrome)
            }
            if !paged, onSave != nil || onShare != nil {
                VStack {
                    Spacer()
                    HStack {
                        if let onShare {
                            Button(action: onShare) {
                                MTBarRoundMark(ringed: false) { MontanaBarGlyph(glyph: "square.and.arrow.up") }
                            }
                            .accessibilityLabel(Text("Share"))
                        }
                        Spacer()
                        if let onSave {
                            Button { Task { saved = await onSave() } } label: {
                                MTBarRoundMark(ringed: false) { MontanaBarGlyph(glyph: saved ? "checkmark" : "square.and.arrow.down") }
                            }
                            .disabled(saved)
                            .accessibilityLabel(saved ? Text("Saved") : Text("Save"))
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, bottomInset + 8)
                .opacity(zoomed || abs(dy) > 8 || !chrome ? 0 : 1)   // aside while the hands work, as the strip was
                .animation(.easeInOut(duration: 0.22), value: chrome)
            }
        }
        .ignoresSafeArea()
        .onAppear { onPage?(page) }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture()
                .onChanged { v in
                    // An enlarged page belongs to its own scroll view.
                    if zoomed || zoomOwnsPull { return }
                    if pull == nil {
                        let dx = abs(v.translation.width), dy = abs(v.translation.height)
                        guard max(dx, dy) > 6 else { return }
                        pull = paged ? dx < dy : true
                    }
                    // Sideways belongs to an album's pages.
                    guard pull == true else { return }
                    drag = CGSize(width: paged ? 0 : v.translation.width, height: v.translation.height)
                }
                .onEnded { v in
                    let wasPull = pull == true
                    pull = nil
                    if zoomed || zoomOwnsPull { return }
                    guard wasPull else { return }
                    // A pull past the threshold closes the album at once — no flight back into the
                    // bubble, no thumbnail (the author's word 12.09).
                    letGo(v.translation, v.predictedEndTranslation)
                }
        )
    }

    /// A SwiftUI gesture over a platform view is not asked on iOS 17, so one picture's pull lives in its zoom view.
    private var zoomOwnsPull: Bool { !paged && startFile.isEmpty && image != nil }
    private func letGo(_ t: CGSize, _ e: CGSize) {
        let gone = paged ? abs(t.height) : hypot(t.width, t.height)
        let flung = paged ? abs(e.height) : hypot(e.width, e.height)
        if 120 < gone || 320 < flung { onClose() } else { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = .zero } }
    }

    /// One page of the picker's album: the system zoom over the picture, the play sign over a video still.
    private func pageView(_ f: String) -> some View {
        MTAlbumPage(file: f, ready: pageImageCached(f), load: { pageImage(f) }, isVideo: isVideo(f),
                    active: f == page, onTap: { x in tap(x) }, onZoom: { if f == page { zoomed = $0 } },
                    onPlay: { playPage(f) })
    }

}

/// One page of the Montana album. The picture that is already decoded shows at once; a page born
/// empty decodes off the main thread and fills — the page turn never waits for a decode.
struct MTAlbumPage: View {
    let file: String
    let ready: UIImage?
    let load: () -> UIImage?
    let isVideo: Bool
    let active: Bool
    var onTap: (CGFloat) -> Void   // where across the page the tap landed, 0…1
    var onZoom: (Bool) -> Void
    var onPlay: () -> Void
    @State private var loaded: UIImage?
    var body: some View {
        MTZoomImage(image: ready ?? loaded, active: active, onTap: onTap, onZoom: onZoom)
            .overlay {
                // THE PLAY IN THE MIDDLE OF THE FRAME (the author's word 11.09): a video stands
                // in the gallery beside the photos as its still; a tap opens the one player.
                if isVideo {
                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill").font(.system(size: 64)).foregroundColor(.white.opacity(0.92))
                            .frame(width: 64, height: 64).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Play"))
                    .disabled(!active)
                }
            }
            .task(id: file) {
                guard ready == nil, loaded == nil else { return }
                let load = load
                loaded = await Task.detached(priority: .userInitiated) { load() }.value
            }
    }
}

/// A cover of the strip: a small picture from the system's own downsampler (no full decode), kept
/// in one cache for the album's life; the picker hands its own covers in ready.
let mtCoverCache: NSCache<NSString, UIImage> = MontanaCaches.kept("album-covers")
struct MTCover: View {
    let file: String
    let ready: UIImage?
    let isVideo: Bool
    /// THE COVER AT ITS OWN PIXELS (the author's word 25.09: «the media on a page are blurred»): the page's grid gives the
    /// cover's larger side in points, and the picture is asked so its SHORT side fills it -- 256 pixels stretched over a
    /// cell of four hundred were the blur. 0 -- the strip's small cover, 256 pixels as before.
    var side: CGFloat = 0
    @Environment(\.displayScale) private var scale
    @State private var img: UIImage?
    var body: some View {
        Group {
            if let ui = ready ?? img { Image(uiImage: ui).resizable().scaledToFill() } else { Color(white: 0.2) }
        }
        .task(id: file) {
            guard ready == nil, img == nil else { return }
            let px = side == 0 ? CGFloat(256) : (side * scale).rounded(.up)
            let key = (side == 0 ? file : file + "#" + String(Int(px))) as NSString
            if let c = mtCoverCache.object(forKey: key) { img = c; return }
            let f = file, video = isVideo, fit = side != 0
            let out: UIImage?
            if video {
                if let c = videoThumbCached(f) { out = c } else { out = await videoThumbAsync(f) }
            } else {
                out = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    if let u = mtMediaFileURL(f),
                       let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                       let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: fit ? MTCover.longest(src, short: px) : px] as CFDictionary) {
                        return UIImage(cgImage: cg)
                    }
                    return docImage(f)?.preparingThumbnail(of: CGSize(width: px, height: px))   // the archive's copy, no open file
                }.value
            }
            if let out { mtCoverCache.setObject(out, forKey: key); img = out }
        }
    }
    /// The longest side to ask so the picture's SHORT side fills `short` pixels -- never more than the picture has.
    nonisolated static func longest(_ src: CGImageSource, short: CGFloat) -> CGFloat {
        guard let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, 0 < w, 0 < h else { return short }
        let long = max(w, h), shortSide = min(w, h)
        return min(CGFloat(long), (short * CGFloat(long / shortSide)).rounded(.up))
    }
}

/// THE PAGES (the author's word 12.09: «plain scrolling under the finger, as the system's own
/// album»): the system's page view controller in its scroll manner. The page follows the finger
/// sideways and settles; the controller asks for a neighbour only as the finger reaches for it.
/// While a page stands enlarged the pages do not move — the pan is the picture's own.
struct MTAlbumPager: UIViewControllerRepresentable {
    let files: [String]
    @Binding var page: String
    @Binding var zoomed: Bool
    let content: (String) -> AnyView

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal,
                                       options: [.interPageSpacing: 16])
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        let first = files.contains(page) ? page : (files.first ?? "")
        pvc.setViewControllers([context.coordinator.controller(for: first)], direction: .forward, animated: false)
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        let co = context.coordinator
        co.parent = self
        for vc in co.live.values { vc.reroot(content) }
        // An enlarged page belongs to its own scroll view: the pages hold still under it.
        (pvc.view.subviews.first { $0 is UIScrollView } as? UIScrollView)?.isScrollEnabled = !zoomed
        // The strip or an edge tap chose a page: slide to it the way a swipe would.
        co.settle(pvc)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class MTAlbumPageVC: UIHostingController<AnyView> {
        let file: String
        init(file: String, make: (String) -> AnyView) {
            self.file = file
            super.init(rootView: MontanaHost.root(make(file)))
            MontanaHost.born(self, AnyView.self)
            view.backgroundColor = .clear
        }
        /// The page's root at an update: the birth's hand and shape (MontanaHost.reroot, 24.09).
        func reroot(_ make: (String) -> AnyView) { MontanaHost.reroot(self, make(file), why: "album") }
        @MainActor required dynamic init?(coder: NSCoder) { nil }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: MTAlbumPager
        var live: [String: MTAlbumPageVC] = [:]
        var turning = false
        init(_ p: MTAlbumPager) { parent = p }

        func controller(for f: String) -> MTAlbumPageVC {
            if let v = live[f] { return v }
            let v = MTAlbumPageVC(file: f, make: parent.content)
            live[f] = v
            return v
        }
        /// ONE STATE, ONE TURN AT A TIME (the author's word 12.09: «a tap on the edge — now a black
        /// screen, now the strip out of step»). The controller animates one turn at a time; a turn
        /// asked for while one ran used to be dropped on the floor — the page said N+2, the screen
        /// showed N+1, and nothing ever came to move it. A turn that lands mid-turn now waits and
        /// is taken the moment the running one completes; the finger's own swipe holds the same
        /// lock, so no programmatic turn is ever started under a moving gesture (the black page).
        func settle(_ pvc: UIPageViewController) {
            guard !turning, let cur = (pvc.viewControllers?.first as? MTAlbumPageVC), cur.file != parent.page,
                  let i = parent.files.firstIndex(of: parent.page), let j = parent.files.firstIndex(of: cur.file) else { return }
            turning = true
            pvc.setViewControllers([controller(for: parent.page)], direction: i > j ? .forward : .reverse, animated: true) { [weak self, weak pvc] _ in
                guard let self else { return }
                self.turning = false
                self.trim(around: self.parent.page, shown: pvc)
                if let pvc { self.settle(pvc) }
            }
        }
        /// Only the page and its two neighbours stay alive — the rest are born again when reached.
        /// What the controller has on screen this instant is never taken from under it.
        func trim(around f: String, shown pvc: UIPageViewController?) {
            guard let c = parent.files.firstIndex(of: f) else { return }
            let onScreen = Set((pvc?.viewControllers ?? []).compactMap { ($0 as? MTAlbumPageVC)?.file })
            for (k, _) in live {
                if onScreen.contains(k) { continue }
                if let i = parent.files.firstIndex(of: k), abs(i - c) <= 1 { continue }
                live[k] = nil
            }
        }
        func pageViewController(_ pvc: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            turning = true
        }
        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let f = (vc as? MTAlbumPageVC)?.file, let i = parent.files.firstIndex(of: f), i > 0 else { return nil }
            return controller(for: parent.files[i - 1])
        }
        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let f = (vc as? MTAlbumPageVC)?.file, let i = parent.files.firstIndex(of: f), i + 1 < parent.files.count else { return nil }
            return controller(for: parent.files[i + 1])
        }
        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            turning = false
            guard let f = (pvc.viewControllers?.first as? MTAlbumPageVC)?.file else { return }
            trim(around: f, shown: pvc)
            if completed, parent.page != f { DispatchQueue.main.async { self.parent.page = f } }
            else if !completed { settle(pvc) }   // the swipe fell back: a tap that landed meanwhile is honoured now
        }
    }
}

/// THE SYSTEM'S OWN ZOOM (the author's word 11.09: «zoom the photo natively»): a scroll view
/// that zooms its picture — pinch, pan while enlarged, double tap in and out — as Photos does.
/// At the fit scale the view does not scroll, so the pages' swipe and the pull-to-close pass
/// through it; enlarged, the pan is the scroll view's. One tap and a double tap are the
/// system's recognisers too, the single waiting for the double to fail.
final class MTZoomScroll: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    var onTap: ((CGFloat) -> Void)?   // where across the visible page the tap landed, 0…1
    var onZoom: ((Bool) -> Void)?
    /// A one-finger pull at the fit scale: its travel in the window, and at its end where a flick carries it.
    var onPull: ((CGSize, CGSize?) -> Void)? { didSet { settlePull() } }
    private let pullPan = UIPanGestureRecognizer()
    /// LIVE TEXT, THE PLATFORM'S OWN (the author's word 18.09: text recognition on a photo, native):
    /// VisionKit's image analysis interaction on the page's image view — select, copy, look up,
    /// call a number, read a code — exactly as Photos does; the analysis runs off the main thread
    /// when the page gets its picture and is dropped with it.
    private let liveText = ImageAnalysisInteraction()
    private let analyzer = ImageAnalyzer()
    private var analysisTask: Task<Void, Never>?
    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1; maximumZoomScale = 4
        showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
        bounces = false; bouncesZoom = true
        isScrollEnabled = false   // scrolling belongs to the enlarged picture only
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        if ImageAnalyzer.isSupported {
            liveText.preferredInteractionTypes = .automatic
            imageView.addInteraction(liveText)
        }
        addSubview(imageView)
        let two = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:))); two.numberOfTapsRequired = 2
        let one = UITapGestureRecognizer(target: self, action: #selector(singleTap(_:))); one.require(toFail: two)
        addGestureRecognizer(two); addGestureRecognizer(one)
        pullPan.maximumNumberOfTouches = 1
        pullPan.addTarget(self, action: #selector(pulled(_:)))
        addGestureRecognizer(pullPan)
        settlePull()
    }
    required init?(coder: NSCoder) { nil }
    var image: UIImage? {
        get { imageView.image }
        set {
            imageView.image = newValue; reset(); setNeedsLayout()
            analysisTask?.cancel(); analysisTask = nil
            liveText.analysis = nil
            guard ImageAnalyzer.isSupported, let img = newValue else { return }
            analysisTask = Task { [weak self] in
                let a = try? await self?.analyzer.analyze(img, configuration: ImageAnalyzer.Configuration([.text, .machineReadableCode]))
                guard !Task.isCancelled, let self, self.imageView.image === img else { return }
                self.liveText.analysis = a
            }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1, let img = imageView.image, bounds.width > 0, bounds.height > 0 {
            let fit = min(bounds.width / max(img.size.width, 1), bounds.height / max(img.size.height, 1))
            let size = CGSize(width: img.size.width * fit, height: img.size.height * fit)
            imageView.frame = CGRect(origin: .zero, size: size)
            contentSize = size
        }
        centre()
    }
    private func centre() {
        let dx = max(0, (bounds.width - contentSize.width) / 2), dy = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }
    func reset() { if zoomScale != 1 { setZoomScale(1, animated: false) } }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
        let enlarged = zoomScale > 1.02
        isScrollEnabled = enlarged
        settlePull()
        onZoom?(enlarged)
    }
    @objc private func doubleTap(_ g: UITapGestureRecognizer) {
        if zoomScale > 1.02 { setZoomScale(1, animated: true); return }
        let p = g.location(in: imageView)
        let w = bounds.width / 2.5, h = bounds.height / 2.5
        zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
    }
    @objc private func singleTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self)
        onTap?((p.x - bounds.minX) / max(bounds.width, 1))
    }
    private func settlePull() { pullPan.isEnabled = onPull != nil && zoomScale <= 1.02 }
    @objc private func pulled(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: nil)
        switch g.state {
        case .changed:
            onPull?(CGSize(width: t.x, height: t.y), nil)
        case .ended:
            // a scroll view's own deceleration, so a flick carries as the platform's do
            let v = g.velocity(in: nil), r = UIScrollView.DecelerationRate.normal.rawValue
            let k = r / (1 - r) / 1000
            onPull?(CGSize(width: t.x, height: t.y), CGSize(width: t.x + v.x * k, height: t.y + v.y * k))
        case .cancelled, .failed:
            onPull?(.zero, .zero)   // settles back
        default:
            break
        }
    }
}
struct MTZoomImage: UIViewRepresentable {
    let image: UIImage?
    let active: Bool   // the page on screen; a page swiped away returns to the fit scale
    var onTap: (CGFloat) -> Void
    var onZoom: (Bool) -> Void
    /// Nil on an album's page: the album carries its pull.
    var onPull: ((CGSize, CGSize?) -> Void)? = nil
    func makeUIView(context: Context) -> MTZoomScroll {
        let v = MTZoomScroll(); v.onTap = onTap; v.onZoom = onZoom; v.onPull = onPull; v.image = image; return v
    }
    func updateUIView(_ v: MTZoomScroll, context: Context) {
        if v.image !== image { v.image = image }
        if !active { v.reset() }
        v.onTap = onTap; v.onZoom = onZoom; v.onPull = onPull
    }
}
