//
//  MontanaFeeds.swift
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
import ImageIO
import Network
import AVKit
import MediaPlayer
import AVFoundation
import LocalAuthentication
import UniformTypeIdentifiers
import CoreImage
import QuickLook
import QuickLookThumbnailing
import Photos
import CoreLocation
import ContactsUI
import Contacts


struct MontanaLogoPattern: View {
    var body: some View {
        GeometryReader { geo in
            let tile: CGFloat = 140          // sparser (larger cell)
            let cols = Int(geo.size.width / tile) + 2
            let rows = Int(geo.size.height / tile) + 2
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { _ in
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: tile * 0.3, height: tile * 0.3)
                                .frame(width: tile, height: tile)
                        }
                    }
                    .offset(x: r % 2 == 0 ? 0 : tile / 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .opacity(0.035)          // even fainter, to avoid flicker
        .allowsHitTesting(false)
    }
}
struct MontanaChatGround: View {
    var body: some View {
        ZStack { montanaDarkGradient; MontanaLogoPattern() }.ignoresSafeArea()
    }
}
/// THE GROUND OF ONE CONVERSATION AND OF THE PAGES (the author's word 22.09): a wallpaper chosen for a
/// chat stands over the general choice of Appearance; the general choice stands where none is chosen;
/// the pages (the chats, the contacts, the settings) have a ground of their own — the crest, or the
/// person's picture. One owner of the storage and of the files; every reader asks here ([C-1]).
enum MTWallpaper {
    enum Choice: Hashable {
        case general                 // Appearance's choice (for a chat); the crest (for the pages): my page's «No background»
        case named(String)           // "default" / "black" / "dark" / "blue"
        case photo(String)           // a file in the wallpapers folder
    }
    /// THE GROUNDS ARE SEEN, NOT READ (the author's word 22.09): every ground is drawn here once and
    /// shown as its own thumbnail — the chooser holds no words at all. The names stay for the voice
    /// that reads the screen aloud, and they are keys of the catalogue like every other word.
    /// Indigo keeps the name it was born with: phones store «aurora» and correspondents receive «n:aurora».
    static let indigo = "aurora"
    static let burgundy = "burgundy"
    /// THE AUTHOR'S GOLD (the author's word 03.10: «the gold ground by default», his file in Media byte for byte).
    static let gold = "gold"
    static let names: [(String, LocalizedStringKey)] = [
        (gold, "Gold ground"), ("montana", "Montana ground"), ("default", "Default ground"), ("black", "Black ground"), ("dark", "Dark ground"), ("blue", "Blue ground"),
        ("sky", "Sky"), ("dusk", "Dusk"), ("water", "Water"), (indigo, "Indigo"), (burgundy, "Burgundy"), ("rose", "Rose"), ("forest", "Forest"),
    ]
    static func name(_ key: String) -> LocalizedStringKey { names.first { $0.0 == key }?.1 ?? "Default ground" }
    /// The two Montana grounds are separate from the platform-style catalogue. Indigo remains «aurora» in saved and shared data.
    static let montanaOffered = [gold, indigo, burgundy]
    static let systemOffered = names.map(\.0).filter { !montanaOffered.contains($0) }
    /// ONE PAINT PER GROUND ([C-1]): the full screen and the thumbnail draw the very same view, so a
    /// ground can never look one way in the chooser and another in the chat. Drawn by us, because the
    /// platform hands no wallpaper of its own to an app — every picture here is ours.
    @ViewBuilder static func paint(_ n: String) -> some View {
        switch n {
        case "montana":
            // THE AUTHOR'S PICTURE, HIS FILE AS IT CAME (the author's word 30.09): the asset is his file byte for byte, filling the
            // ground edge to edge -- nothing drawn over it, nothing drawn in its place.
            Color.clear.overlay { Image("MontanaWallpaper").resizable().scaledToFill() }.clipped()
        case "black": Color.black
        case "dark": montanaDarkGradient
        case "blue":
            LinearGradient(colors: [Color(red: 0.10, green: 0.20, blue: 0.32), Color(red: 0.05, green: 0.10, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom)
        case "sky":
            ZStack {
                LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 0.86), Color(red: 0.74, green: 0.86, blue: 0.94)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.white.opacity(0.55), .clear], center: .init(x: 0.7, y: 0.22), startRadius: 4, endRadius: 320)
            }
        case "dusk":
            ZStack {
                LinearGradient(colors: [Color(red: 0.13, green: 0.12, blue: 0.28), Color(red: 0.58, green: 0.32, blue: 0.36),
                                        Color(red: 0.95, green: 0.62, blue: 0.36)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.60).opacity(0.7), .clear],
                               center: .init(x: 0.5, y: 0.86), startRadius: 2, endRadius: 260)
            }
        case "water":
            ZStack {
                LinearGradient(colors: [Color(red: 0.62, green: 0.80, blue: 0.84), Color(red: 0.90, green: 0.93, blue: 0.94),
                                        Color(red: 0.55, green: 0.72, blue: 0.80)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                AngularGradient(colors: [Color.white.opacity(0.35), .clear,
                                         Color(red: 0.70, green: 0.85, blue: 0.90).opacity(0.4), .clear],
                                center: .init(x: 0.4, y: 0.4)).blendMode(.softLight)
            }
        case burgundy:
            Color.clear.overlay { Image("MontanaBurgundy").resizable().scaledToFill() }.clipped()   // the author's file as it came
        case gold:
            Color.clear.overlay { Image("MontanaGoldGround").resizable().scaledToFill() }.clipped()   // the author's file as it came (03.10)
        case indigo:
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.04, blue: 0.12), Color(red: 0.08, green: 0.10, blue: 0.24)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 0.25, green: 0.85, blue: 0.75).opacity(0.65), .clear],
                               center: .init(x: 0.32, y: 0.38), startRadius: 2, endRadius: 280)
                RadialGradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.6), .clear],
                               center: .init(x: 0.72, y: 0.60), startRadius: 2, endRadius: 300)
            }
        case "rose":
            ZStack {
                LinearGradient(colors: [Color(red: 0.42, green: 0.10, blue: 0.36), Color(red: 0.95, green: 0.35, blue: 0.62)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 1, green: 0.75, blue: 0.85).opacity(0.5), .clear],
                               center: .init(x: 0.3, y: 0.75), startRadius: 2, endRadius: 280)
            }
        case "forest":
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.18, blue: 0.16), Color(red: 0.12, green: 0.36, blue: 0.30),
                                        Color(red: 0.06, green: 0.14, blue: 0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(red: 0.55, green: 0.85, blue: 0.60).opacity(0.28), .clear],
                               center: .init(x: 0.65, y: 0.3), startRadius: 2, endRadius: 260)
            }
        default: ZStack { montanaDarkGradient; MontanaLogoPattern() }
        }
    }
    /// THE PAGE'S OWN GROUND (the author's word 24.09: «the page's background by the same algorithm, by SSOT, as the
    /// chat's»): chosen, placed, kept and drawn exactly as a chat's ground, under a key no conversation wears — a
    /// conversation's key is its pipe's reference. It stands behind the face at the top of my page (MTFacePage), where
    /// the page does not scroll; the page's general choice is its plain black.
    static let page = "page"
    /// Whose page a face heads (MTFacePage): mine, or a correspondent's — the page's ground is decided from this alone.
    enum PageOf: Equatable { case me, peer(String) }
    /// The key of a page's ground: mine, or the ground a correspondent sent of their page (MTPageGround), kept the same way.
    static func pageKey(_ of: PageOf) -> String {
        switch of {
        case .me: return page
        case .peer(let conv): return page + "." + conv
        }
    }
    static func isPageKey(_ k: String?) -> Bool { k == page || (k?.hasPrefix(page + ".") ?? false) }
    /// The one bit the screens observe: a change of any wallpaper.
    final class Book: ObservableObject { static let shared = Book(); @Published var rev = 0 }
    private static func parse(_ s: String?) -> Choice {
        guard let s else { return .general }
        if s.hasPrefix("named:") { return .named(String(s.dropFirst(6))) }   // COMPAT-LOCAL: a stored choice, never on the wire
        if s.hasPrefix("photo:") { return .photo(String(s.dropFirst(6))) }   // COMPAT-LOCAL: a stored choice, never on the wire
        return .general
    }
    private static func encode(_ c: Choice) -> String? {
        switch c { case .general: return nil; case .named(let n): return "named:" + n; case .photo(let f): return "photo:" + f }
    }
    /// The one default: every page and every chat that chose none wear my page's ground, so nothing chosen reads here.
    /// «No background» chosen by hand is stored, never read as nothing chosen.
    static let byDefault = gold   // the author's word 03.10: the gold ground by default
    static func choice(for conv: String) -> Choice {
        let s = UserDefaults.standard.string(forKey: "chatWall." + conv)
        if s == nil, conv == page { return .named(byDefault) }
        return parse(s)
    }
    static func set(_ c: Choice, for conv: String) {
        // COMPAT-LOCAL: a stored choice, never on the wire -- my page's «No background», told apart from nothing chosen
        UserDefaults.standard.set(encode(c) ?? (conv == page ? "general" : nil), forKey: "chatWall." + conv)
        Book.shared.rev += 1
    }
    /// The picture a conversation's own ground stands on, if it stands on one: a copy that leaves the
    /// conversation out leaves its picture behind with it (23.09).
    static func photoFile(for conv: String) -> String? {
        if case .photo(let f) = choice(for: conv) { return f }
        return nil
    }
    /// THE PAGES HAVE NO GROUND OF THEIR OWN ANY MORE (the author's word 23.09: «remove the pages' background from
    /// Appearance completely»). A choice nobody can reach again must not keep acting: what an older build stored
    /// for the pages — the picture, its softness, the three kept pictures — is forgotten once, files and all, and
    /// the pages stand on the crest with its own softness.
    static let pagesForgotten: Void = {
        let d = UserDefaults.standard
        var files = (d.array(forKey: "pagesWallRecent") as? [String]) ?? []
        if let s = d.string(forKey: "pagesWall"), s.hasPrefix("photo:") { files.append(String(s.dropFirst(6))) }   // COMPAT-LOCAL: a stored choice, never on the wire
        for f in Set(files) { try? FileManager.default.removeItem(at: folder().appendingPathComponent(f)) }
        for k in ["pagesWall", "pagesWallBlur", "pagesWallRecent"] { d.removeObject(forKey: k) }
    }()
    /// THE SOFTNESS OF -> CHAT'S OWN GROUND (the author's word 23.09: the slider belongs to the chat's
    /// background too). The pages had it and a chat did not — by my decree, not his: "a chat's ground is
    /// sharp and asks nothing" was written here in my own hand. It is kept per conversation, as the choice
    /// of the ground itself is, and zero is sharp: every chat that has not been touched stands exactly as
    /// it stood.
    static func blurKey(_ conv: String) -> String { "chatWallBlur." + conv }
    static func blur(for conv: String) -> CGFloat {
        CGFloat((UserDefaults.standard.object(forKey: blurKey(conv)) as? Double) ?? 0)
    }
    static func setBlur(_ v: Double, for conv: String) {
        UserDefaults.standard.set(v, forKey: blurKey(conv)); Book.shared.rev += 1
    }
    /// MY PAGE'S GROUND RIDES INTO AN EMPTIED SEAT (the author's word 03.10: «the login page always wears the chosen cover, not
    /// the default; a second account keeps it»): the ground the person leaving wore -- its choice, its softness, its picture --
    /// is laid again on the seat emptied for a new person, so the first screen stands on it and the person born there keeps it;
    /// the person on the shelf keeps their own.
    struct Carried { let choice: Choice; let blur: Double; let photo: Data? }
    static func carry() -> Carried {
        let c = choice(for: page)
        var d: Data? = nil
        if case .photo(let f) = c { d = try? Data(contentsOf: folder().appendingPathComponent(f)) }
        return Carried(choice: c, blur: Double(blur(for: page)), photo: d)
    }
    static func wear(_ g: Carried) {
        if case .photo(let f) = g.choice {
            guard let d = g.photo else { return }
            do { try d.write(to: folder().appendingPathComponent(f)) }
            catch { MontanaLog.event("WALLPAPER carry FAILED \(d.count)B: \(error.localizedDescription)"); return }
        }
        set(g.choice, for: page)
        setBlur(g.blur, for: page)
    }
    /// Application Support, beside the avatars: outside Files, outside the sealed media folder.
    static func folder() -> URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Wallpapers")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    /// The picture at the screen's scale and no larger: a wallpaper is drawn full-screen, nothing more.
    static func savePhoto(_ data: Data) -> String? {
        guard let ui = UIImage(data: data) else { return nil }
        let win = MTScene.size()   // OUR window and its pixels, never the shared display (the guard 22.09)
        let side = max(win.width, win.height) * MTScene.scale()
        let k = min(1, side / max(ui.size.width * ui.scale, ui.size.height * ui.scale))
        let size = CGSize(width: ui.size.width * k, height: ui.size.height * k)
        let small = UIGraphicsImageRenderer(size: size).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpg = small.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "wall_\(UUID().uuidString).jpg"
        do { try jpg.write(to: folder().appendingPathComponent(name)); return name }
        catch { MontanaLog.event("WALLPAPER write FAILED \(jpg.count)B: \(error.localizedDescription)"); return nil }
    }
    /// A picture already placed and taken from the screen (MTWallpaperCropView): kept LOSSLESS, as PNG, so the chat
    /// wears the preview's own pixels byte for byte (the author's word 23.09), not a JPEG's approximation of them.
    static func saveRendered(_ ui: UIImage) -> String? {
        guard let png = ui.pngData() else { return nil }
        let name = "wall_\(UUID().uuidString).png"
        do { try png.write(to: folder().appendingPathComponent(name)); return name }
        catch { MontanaLog.event("WALLPAPER write FAILED \(png.count)B: \(error.localizedDescription)"); return nil }
    }
    /// THE PAGE'S GROUND, KEPT LIGHT (the author's word 25.09: «crop it after it is placed and compress it at once, without
    /// loss, so that it weighs little and passes easily»): the placed rendering -- the window as it stood, already cropped --
    /// at the window's pixels and no larger, as HEIC at a quality the eye does not tell from the original (JPEG where the
    /// encoder is missing). A chat's ground stays the lossless PNG of its preview (the author's word 23.09): it never leaves.
    static let lightBudget = 3_000_000
    static func lightData(_ ui: UIImage) -> Data? {
        let win = MTScene.size()
        let side = max(win.width, win.height) * MTScene.scale()
        let w = ui.size.width * ui.scale, h = ui.size.height * ui.scale
        guard 0 < w, 0 < h else { return nil }
        let k = min(1, side / max(w, h))
        let size = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let flat = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        if let cg = flat.cgImage {
            let out = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(out, "public.heic" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                if CGImageDestinationFinalize(dest), isLight(out as Data) { return out as Data }
            }
        }
        guard let jpg = flat.jpegData(compressionQuality: 0.85), isLight(jpg) else { return nil }
        return jpg
    }
    /// A light picture: HEIC or JPEG, within the budget a letter's cargo carries with room to spare.
    static func isLight(_ d: Data) -> Bool {
        guard 12 <= d.count, d.count <= lightBudget else { return false }
        let b = [UInt8](d.prefix(12))
        if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return true }                      // JPEG
        return b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70              // «ftyp»: HEIC
    }
    /// A light picture kept as it came -- no second encoding, no loss added: the page's ground set here, or the ground a
    /// correspondent sent. Anything else is not kept here.
    static func keep(_ d: Data?) -> String? {
        guard let d, isLight(d), UIImage(data: d) != nil else { return nil }
        let name = "wall_\(UUID().uuidString)" + (d.first == 0xFF ? ".jpg" : ".heic")
        do { try d.write(to: folder().appendingPathComponent(name)); return name }
        catch { MontanaLog.event("WALLPAPER write FAILED \(d.count)B: \(error.localizedDescription)"); return nil }
    }
    static func remove(_ file: String) { try? FileManager.default.removeItem(at: folder().appendingPathComponent(file)); cache[file] = nil }
    private static var cache: [String: UIImage] = [:]
    static func image(_ file: String) -> UIImage? {
        if let c = cache[file] { return c }
        guard let ui = UIImage(contentsOfFile: folder().appendingPathComponent(file).path) else { return nil }
        cache[file] = ui
        return ui
    }
}
/// MY PAGE'S GROUND ON A CORRESPONDENT'S SCREEN (the author's word 25.09: «from T3 I opened T1's page and see no
/// background»). The ground rides as my words about myself do (E2E.sendGroundIfNeeded): its content is "" for none,
/// "n:" + a drawn ground's name, or "p:" + the picture as it is kept, light (MTWallpaper.lightData) -- sent as it lies,
/// never encoded at a send. A correspondent's ground is kept exactly as mine is (MTWallpaper, under their page's key) and drawn on
/// their page by the chat's own ground view; the tag of what I hold of them rides my presence word («G»).
enum MTPageGround {
    static let limit = 4_000_000   // a received picture's bytes, at most
    private static let lock = NSLock()
    private static var made: (file: String, g: String, tag: String)? = nil
    private static var making: String? = nil

    /// My ground's content and its tag. A picture leaves AS IT IS KEPT (the author's word 25.09: «crop it and compress it at
    /// once, when it is set, so that it weighs little and passes easily»): kept light at the checkmark, read here as it lies
    /// -- no encoding at a send, nothing lost with the process. nil only while a picture an older build kept heavy is made
    /// light, once; it goes to everyone when it is ready.
    static func mine() -> (g: String, tag: String)? {
        switch MTWallpaper.choice(for: MTWallpaper.page) {
        case .general: return ("", "0")
        case .named(let n):
            let g = "n:" + n
            return (g, MontanaDeliveryEngine.Announced.groundTag(g))
        case .photo(let f):
            lock.lock(); let m = made; lock.unlock()
            if let m, m.file == f { return (m.g, m.tag) }
            if let d = try? Data(contentsOf: MTWallpaper.folder().appendingPathComponent(f)), MTWallpaper.isLight(d) {
                let g = "p:" + d.base64EncodedString()
                let tag = MontanaDeliveryEngine.Announced.groundTag(g)
                lock.lock(); made = (f, g, tag); lock.unlock()
                MontanaTrace.mark("ground_made", "kept bytes=\(d.count) tag=\(tag)")
                return (g, tag)
            }
            lighten(f)
            return nil
        }
    }
    /// A picture an older build kept heavy (the lossless PNG of the window) is made light ONCE, off the main thread, and kept
    /// so: from then on the page wears the light file, and it goes to every correspondent who lacks it.
    private static func lighten(_ file: String) {
        lock.lock()
        if making == file { lock.unlock(); return }
        making = file
        lock.unlock()
        let url = MTWallpaper.folder().appendingPathComponent(file)
        DispatchQueue.global(qos: .userInitiated).async {
            let light = UIImage(contentsOfFile: url.path).flatMap { MTWallpaper.lightData($0) }
            DispatchQueue.main.async {
                lock.lock(); if making == file { making = nil }; lock.unlock()
                guard case .photo(let now) = MTWallpaper.choice(for: MTWallpaper.page), now == file else { return }   // set anew meanwhile
                guard let kept = MTWallpaper.keep(light) else {
                    MontanaTrace.mark("ground_made", "FAILED -- the kept picture could not be made light")
                    return
                }
                MTWallpaper.set(.photo(kept), for: MTWallpaper.page)
                MTWallpaper.remove(file)
                MontanaTrace.mark("ground_made", "lightened bytes=\(light?.count ?? 0)")
                E2E.shared.broadcastGround()   // to every correspondent who lacks it
            }
        }
    }
    /// My ground changed on this phone: to every correspondent who reads the word — a picture once it is made.
    static func changed() {
        if mine() != nil { E2E.shared.broadcastGround() }
    }
    /// The body of a «ground» letter: the content and the moment it was said.
    static func word(_ g: String) -> String? {
        guard let d = try? JSONSerialization.data(withJSONObject: ["g": g, "at": Date().timeIntervalSince1970] as [String: Any]) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func heldKey(_ conv: String) -> String { "pgHeld." + conv }
    /// The tag of a correspondent's ground on my screen, and the moment they said it («tag@at»).
    private static func held(_ conv: String) -> (tag: String, at: Double)? {
        guard let s = UserDefaults.standard.string(forKey: heldKey(conv)) else { return nil }
        let p = s.split(separator: "@", maxSplits: 1).map(String.init)
        guard p.count == 2, let at = Double(p[1]) else { return nil }
        return (p[0], at)
    }
    static func heldTag(_ conv: String) -> String { held(conv)?.tag ?? "0" }
    /// A correspondent's ground arrived: kept as mine is, the latest word winning; an older word changes nothing.
    static func note(_ conv: String, g: String, at: Double) {
        guard Thread.isMainThread else { DispatchQueue.main.async { note(conv, g: g, at: at) }; return }
        if let h = held(conv), at < h.at { return }
        let key = MTWallpaper.pageKey(.peer(conv))
        let old = MTWallpaper.photoFile(for: key)
        var choice = MTWallpaper.Choice.general
        if g.hasPrefix("n:") {
            let n = String(g.dropFirst(2))
            if MTWallpaper.names.contains(where: { $0.0 == n }) { choice = .named(n) }
        // COMPAT-GATED: «n:» and «p:» are the content of the «ground» word, read only inside it
        } else if g.hasPrefix("p:"), let d = Data(base64Encoded: String(g.dropFirst(2))), d.count <= limit,
                  let f = MTWallpaper.keep(d) ?? MTWallpaper.savePhoto(d) {   // kept as it came; an older sender's picture made light here
            choice = .photo(f)
        }
        MTWallpaper.set(choice, for: key)
        if let old, old != MTWallpaper.photoFile(for: key) { MTWallpaper.remove(old) }
        UserDefaults.standard.set(MontanaDeliveryEngine.Announced.groundTag(g) + "@" + String(at), forKey: heldKey(conv))
        MontanaTrace.mark("ground_rx", "from=\(String(conv.prefix(10))) kind=\(g.isEmpty ? "none" : String(g.prefix(1)))")
    }
}
/// The conversation whose wallpaper the ground draws — set at the chat's root, read by the ground and
/// the edge washes alike; nil = the general choice.
private struct MTWallpaperConvKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var mtWallpaperConv: String? { get { self[MTWallpaperConvKey.self] } set { self[MTWallpaperConvKey.self] = newValue } }
}
/// THE CHAT'S GROUND, ONE VIEW (the author's word 11.09: the appearance preview must show exactly
/// what is set): the conversation draws it and the preview draws it — the chat's own choice, the
/// person's general choice, the custom photo or gradient, or the tree's own ground. No second copy
/// of the choice. `candidate` — a choice being previewed before it is set (the author's word 22.09).
struct MontanaChatBackdrop: View {
    var conv: String? = nil
    var candidate: MTWallpaper.Choice? = nil
    /// THE PREVIEW DRAWS THROUGH THIS VERY VIEW (the author's word 23.09: «the blurred photo does not stand on the
    /// chat's background exactly as in the preview»). A softness being tried and a picture placed but not yet kept
    /// are handed in here, so the preview and the chat draw one ground by one code: the same picture view, the
    /// same blur, the same one texture.
    var soft: CGFloat? = nil
    var candidatePicture: UIImage? = nil
    /// The page's ground drawn sharp: for its own softening (MTSoftGround) and the preview alone.
    var sharp = false
    @State private var softened: UIImage? = MTSoftGround.kept
    @Environment(\.mtWallpaperConv) private var envConv
    @ObservedObject private var book = MTWallpaper.Book.shared
    @AppStorage("chatBg") private var chatBg: String = "default"
    @AppStorage("chatBgPhoto") private var chatBgPhoto: Data = Data()
    @AppStorage("bubbleStyle") private var bubbleStyle: String = "montana"
    @AppStorage("cbBgOn") private var cbBgOn = false
    @AppStorage("cbBgType") private var cbBgType = "gradient"
    @AppStorage("cbBg1") private var cbBg1 = BT.bg1
    @AppStorage("cbBg2") private var cbBg2 = BT.bg2
    @AppStorage("cbBgPhoto") private var cbBgPhotoData = Data()
    private var own: MTWallpaper.Choice {
        if let candidate { return candidate }
        if let c = conv ?? envConv { return MTWallpaper.choice(for: c) }
        return .general
    }
    var body: some View {
        let _ = book.rev   // a set wallpaper redraws the open chat
        if !sharp, candidate == nil, soft == nil, candidatePicture == nil, wearsPageGround {
            pageSoftened
        } else {
            sharpBody
        }
    }
    /// THE PAGE'S GROUND IS SOFT WHEREVER IT STANDS (the author's words 28.09: «the page's ground blurred on every page and every
    /// place where it stands -- the chats and every page included»): my page's own ground, and a chat that chose none wearing it
    /// (rule 30) -- the one still picture MTSoftGround made when the ground was set, on the disk since. A chat's own ground keeps
    /// its own softness (its slider); the page's general black has nothing to soften.
    private var wearsPageGround: Bool {
        let page = MTWallpaper.choice(for: MTWallpaper.page)
        guard page != .general else { return false }
        let c = conv ?? envConv
        if c == MTWallpaper.page { return true }
        if MTWallpaper.isPageKey(c) { return false }   // a correspondent's page ground is theirs, drawn as it came
        return own == .general
    }
    @ViewBuilder private var pageSoftened: some View {
        ZStack {
            if let softened {
                Color.black
                Color.clear.overlay { Image(uiImage: softened).resizable().scaledToFill() }.clipped()
            } else {
                sharpBody   // the first moment of a device, before the picture exists
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: "\(book.rev)/" + MTSoftGround.key()) {
            if let made = await MTSoftGround.picture(rev: book.rev, ground: { ZStack { Color.black; MontanaChatBackdrop(conv: MTWallpaper.page, sharp: true) } }) {
                softened = made
            }
        }
    }
    @ViewBuilder private var sharpBody: some View {
        // THE SOFTNESS THE PERSON CHOSE (the author's word 23.09): zero for every ground nobody has
        // softened, and then this is the very picture it always was. A softened ground is drawn ONCE into
        // one texture: the glass of the bars above samples the ground every frame of a scroll, and a
        // full-screen Gaussian recomputed per frame killed the app on the first scroll of 1436. In the
        // preview the slider drives the blur, so the stored number stands aside there.
        let softness = soft ?? (candidate == nil ? MTWallpaper.blur(for: conv ?? envConv ?? "") : 0)
        if softness > 0 { paint.blur(radius: softness, opaque: true).drawingGroup() } else { paint }
    }
    @ViewBuilder private var paint: some View {
        if let ui = candidatePicture { Self.picture(ui) } else { chosen }
    }
    @ViewBuilder private var chosen: some View {
        switch own {
        case .photo(let f):
            if let ui = MTWallpaper.image(f) { Self.picture(ui) } else { general }
        case .named(let n):
            Self.named(n, photo: chatBgPhoto)
        case .general:
            general
        }
    }
    @ViewBuilder private var general: some View {
        if MTWallpaper.isPageKey(conv ?? envConv) {
            Color.black.ignoresSafeArea()   // the page's own ground, none chosen: the page's black, not a chat's Appearance
        } else {
            // THE PAGE'S GROUND IS EVERY CHAT'S (the author's word 25.09, rule 30: «the page's ground is the ground of all pages
            // and chats, except the chats in which a personal ground is chosen for that chat»): a chat that chose nothing wears
            // my page's ground while one is set -- the same picture or paint, by this very view; none set -- the general ground
            // of Appearance, as it stood.
            switch MTWallpaper.choice(for: MTWallpaper.page) {
            case .photo(let f):
                if let ui = MTWallpaper.image(f) { Self.picture(ui) } else { appearance }
            case .named(let n):
                Self.named(n, photo: chatBgPhoto)
            case .general:
                appearance
            }
        }
    }
    /// The general ground of Appearance: the custom style's own picture or gradient, else the named ground chosen there.
    @ViewBuilder private var appearance: some View {
        if bubbleStyle == "custom", cbBgOn, cbBgType == "photo", let ui = UIImage(data: cbBgPhotoData) {
            Image(uiImage: ui).resizable().scaledToFill().ignoresSafeArea()
        } else if bubbleStyle == "custom", cbBgOn {
            LinearGradient(colors: [Color(montanaHexString: BT.hex("cbBg1", cbBg1)), Color(montanaHexString: BT.hex("cbBg2", cbBg2))],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        } else {
            Self.named(chatBg, photo: chatBgPhoto)
        }
    }
    /// A person's picture as a chat's ground: filling the screen, a quarter darkened so the words stay readable.
    static func picture(_ ui: UIImage) -> some View {
        GeometryReader { g in
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(width: g.size.width, height: g.size.height).clipped()
                .overlay(Color.black.opacity(0.25))
        }
        .ignoresSafeArea()
    }
    @ViewBuilder static func named(_ n: String, photo: Data) -> some View {
        if n == "photo" {
            if let ui = UIImage(data: photo) { picture(ui) } else { MontanaChatGround() }
        } else {
            MTWallpaper.paint(n).ignoresSafeArea()   // the one paint of every ground ([C-1])
        }
    }
}
struct MTUnderBarGround: View {
    var still = false
    @ObservedObject private var book = MTWallpaper.Book.shared
    @Environment(\.mtSoftGround) private var soft
    @State private var softened: UIImage? = MTSoftGround.kept
    var body: some View {
        let _ = book.rev   // a ground set or taken away redraws the pages
        if still {
            GeometryReader { g in
                let at = g.frame(in: .global).origin
                let win = MTScene.size()
                layers.frame(width: win.width, height: win.height).offset(x: -at.x, y: -at.y)
            }
            .clipped()
            .allowsHitTesting(false)   // a ground answers no finger: clipping bounds its drawing, not its touch (the critic 26.09)
        } else {
            layers
        }
    }
    /// THE GROUND, AND OVER IT THE SOFTENED PICTURE WHILE THE PAGE ASKS FOR IT (MTSoftGround): the picture comes in over the ground,
    /// and the ground, covered, goes out after it -- while the chats stand, the screen composes the one still picture and nothing
    /// under it; leaving, the ground is back at once and the picture goes out over it.
    @ViewBuilder private var layers: some View {
        let shown = soft && softened != nil
        ZStack {
            ground
                .opacity(shown ? 0 : 1)
                .animation(.easeInOut(duration: 0.3).delay(shown ? 0.3 : 0), value: shown)
            if let softened {
                Color.clear
                    .overlay { Image(uiImage: softened).resizable().scaledToFill() }
                    .clipped()
                    .opacity(shown ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: shown)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .task(id: soft ? "\(book.rev)/" + MTSoftGround.key() : "") {
            guard soft else { return }
            if let made = await MTSoftGround.picture(rev: book.rev, ground: { ground }) { softened = made }
        }
    }
    @ViewBuilder private var ground: some View {
        if MTWallpaper.choice(for: MTWallpaper.page) == .general {
            MontanaCrestGround()
        } else {
            ZStack { Color.black; MontanaChatBackdrop(conv: MTWallpaper.pageKey(.me), sharp: true) }.ignoresSafeArea()   // softened by the layer above
        }
    }
}
/// THE CHATS PAGE SOFTENS ITS GROUND (the author's words 28.09): said by the chats page for the ground under it and under the
/// search's results over it; no other page says it, so every other page stands on the ground as it was.
private struct MTSoftGroundKey: EnvironmentKey { static let defaultValue = true }   // every page (28.09): a place may say false for itself
extension EnvironmentValues {
    var mtSoftGround: Bool {
        get { self[MTSoftGroundKey.self] }
        set { self[MTSoftGroundKey.self] = newValue }
    }
}

/// THE CHATS PAGE'S GROUND, SOFTENED ONCE (the author's words 28.09: «the page's ground blurred as the App Library's», «the ground
/// must weigh nothing at all», «the chats' ground must not draw itself again -- set, it turns into a very light picture with the
/// same softness»). The ground is drawn ONE time, when it is set -- at a quarter of the window's points; the platform's Gaussian
/// softens that small picture off the main thread and dims it as the App Library dims its wallpaper; the picture is kept on the
/// disk under what it is made of, and every launch after meets it there, drawn by nobody. The page shows the one still picture
/// scaled to the window: no live blur, no material, no texture drawn again per frame.
enum MTSoftGround {
    /// The softness in the window's points: no edge of the picture is readable under the lines, as under the App Library's.
    static let radius: CGFloat = 36
    /// The share of the window's points the ground is drawn at before it is softened.
    static let scale: CGFloat = 0.25
    /// The light the softened ground keeps: the App Library's wallpaper stands dimmed under its words.
    static let light: CGFloat = 0.72
    private static var made: (key: String, image: UIImage)?
    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// What the picture is made of: my page's choice, its own softness and the window's size -- nothing that moves between launches.
    static func key() -> String {
        let w = MTScene.size()
        return "\(MTWallpaper.choice(for: MTWallpaper.page))/\(MTWallpaper.blur(for: MTWallpaper.pageKey(.me)))/\(Int(w.width))x\(Int(w.height))"
    }
    /// The one file of the softened picture, named by what it is made of.
    private static func file(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("soft-ground-" + name + ".jpg")
    }
    /// The picture in memory, else the one the last setting of the ground left on the disk -- read once a launch, decoded when drawn.
    static var kept: UIImage? {
        if let made { return made.image }
        let k = key()
        guard let image = UIImage(contentsOfFile: file(k).path) else { return nil }
        made = ("\(MTWallpaper.Book.shared.rev)/" + k, image)
        return image
    }
    /// The softened picture of `ground`: the kept one while nothing it is made of changed; drawn anew when the ground was set.
    @MainActor static func picture<G: View>(rev: Int, @ViewBuilder ground: () -> G) async -> UIImage? {
        let k = key()
        let live = "\(rev)/" + k
        if let made, made.key == live { return made.image }
        if made == nil, let stored = kept { return stored }
        // The first picture of a device waits out the launch's own frames (T3: the chats tab's first seconds already stand 0.6-0.7 s
        // on the main thread); the sharp ground stands meanwhile and the softened one comes in over it.
        if made == nil { try? await Task.sleep(nanoseconds: 600_000_000) }
        guard !Task.isCancelled else { return made?.image }
        guard let image = await soft(ground) else { return made?.image }
        made = (live, image)
        let url = file(k)
        Task.detached(priority: .utility) { store(image, at: url) }
        MontanaTrace.mark("soft_ground", "made px=\(Int(image.size.width))x\(Int(image.size.height)) radius=\(Int(radius))")
        return image
    }
    /// A ground as the pages wear it -- one road for my page's picture and for every miniature of a ground offered for it
    /// (MTGroundMiniature), so the two cannot differ.
    @MainActor static func soft<G: View>(@ViewBuilder _ ground: () -> G) async -> UIImage? {
        let size = MTScene.size()
        guard size.width > 1, size.height > 1 else { return nil }
        let renderer = ImageRenderer(content: ZStack { Color.black; ground() }.frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let small = renderer.cgImage else { return nil }
        guard let done = await Task.detached(priority: .utility, operation: { soften(small) }).value else { return nil }
        return UIImage(cgImage: done)
    }
    /// The picture on the disk, the one of it: a ground set anew leaves no older picture behind.
    private static func store(_ image: UIImage, at url: URL) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let dir = url.deletingLastPathComponent()
        let older = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("soft-ground-") && $0.lastPathComponent != url.lastPathComponent }
        for f in older { try? FileManager.default.removeItem(at: f) }
        try? data.write(to: url, options: .atomic)
    }
    private static func soften(_ small: CGImage) -> CGImage? {
        let input = CIImage(cgImage: small)
        let out = input.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius * scale))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: light, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: light, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: light, w: 0)])
            .cropped(to: input.extent)
        return context.createCGImage(out, from: input.extent)
    }
}

/// THE CREST BEHIND THE CHATS TAB (the author's word 10.09): centred on the whole screen — under
/// the bar, the rows and the tab bar alike, so every glass plate blurs it — half blurred and half
/// transparent. One drawing; its numbers live here and nowhere else.
struct MontanaCrestGround: View {
    /// The crest's own softness — SwiftUI's Gaussian radius in points (0 = sharp): 12, then 9, now 8 (the author's word 10.09).
    static let blur: CGFloat = 8
    static let opacity: Double = 0.5
    /// The crest at seven tenths of the glass's width, strictly at the centre.
    static let scale: CGFloat = 0.7
    /// The same picture filling the glass edge to edge as a haze: nothing under the top plate or
    /// the tab bar is flat black any more — their glass blurs the crest's own gold.
    static let hazeBlur: CGFloat = 48
    static let hazeOpacity: Double = 0.35
    @ObservedObject private var book = MTWallpaper.Book.shared
    var body: some View {
        let _ = book.rev
        let _ = MTWallpaper.pagesForgotten   // the pages' own ground of older builds, forgotten once (23.09)
        crest
    }
    /// THE CREST IS THE CREST THE AUTHOR PUT THERE (his word 22.09): the Dream Department's arms stand
    /// behind the pages by his choice — I took them for a stray of another project and removed them;
    /// they are back, with the very same numbers, and nothing here is to be «cleaned up» again.
    private var crest: some View {
        // Drawn ONCE into one texture (drawingGroup): the glass of the bars above samples the
        // ground every frame of a scroll, and two Gaussian blurs of a full-screen picture
        // recomputed per frame killed the app on the first scroll of 1436 (T1, 17:59:17Z: worst
        // frame 510 ms, relaunch three seconds later). Centred by the screen's own geometry.
        GeometryReader { g in
            ZStack {
                Color.black
                Image("ChatsCrest")
                    .resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height)
                    .blur(radius: Self.hazeBlur)
                    .opacity(Self.hazeOpacity)
                Image("ChatsCrest")
                    .resizable().scaledToFit()
                    .frame(width: g.size.width * Self.scale)
                    .blur(radius: Self.blur)
                    .opacity(Self.opacity)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
            .drawingGroup()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
/// One container for every piece of glass on a bar (the system asks for it: glass beside glass
/// outside a container is drawn separately and costs a backdrop pass each). Plain content before iOS 26.
struct MTGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer { content() }
        } else {
            content()
        }
    }
}

/// The system's own photos glyph: eight petals of the spectrum around one centre.
struct MontanaPetalsGlyph: View {
    var size: CGFloat = 24
    var tint: Color? = nil   // one colour for all petals (the bar's grey); nil — the spectrum
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Ellipse()
                    .fill((tint ?? Color(hue: Double(i) / 8, saturation: 0.72, brightness: 0.96)).opacity(0.85))
                    .frame(width: size * 0.30, height: size * 0.62)
                    .offset(y: -size * 0.19)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
        .frame(width: size, height: size)
    }
}

/// A MOMENT ASKED FOR IN THE VIEWER (25.09): the gallery's tile names the moment; the chats page hosts the platform's viewer
/// over everything at it (MTMomentsViewer), and the ask is cleared when the viewer leaves.
struct MTMediaView: Identifiable, Equatable { let id: String }

/// ONE MOMENT OF THE GALLERY: a photo or a video that lies in a conversation, or one of my own stories -- the file by its one
/// name, where it lies, whose it is (the caption: the correspondent's name, mine, or «Your Story»), when it was made, and the
/// conversation and letter it lies in (none for a story). Built by the one builder (ChatStore.mediaLibrary).
struct MTMoment: Identifiable, Equatable {
    let id: String; let url: URL; let caption: String; let own: Bool
    let at: Double; let chat: String; let mid: MID?
    var photo: Bool = false             // a still picture; else a video
}

/// THE GALLERY UNDER THE TIME PANEL (the author's word 25.09: «the same as the network page; check why it lags and how many
/// owners it has; every button native; split by dates; and at the bottom»): a page of the finger's row (UIState.Pane.gallery)
/// in the dynamic glyph's slot while the glyph is the gallery's, on the one container of the pages under the bar
/// (MontanaTimePanelList) -- the rows to the screen's edges, the page's own ground. Every moment of every conversation and my
/// own stories, in the order the platform's photos keep: the days oldest to newest, each day a header row and its tiles three
/// to a row (as the wall's), the newest at the bottom, the list opened at its end (endFirst). The moments have ONE builder
/// kept until the letters change (ChatStore.mediaLibrary): the chats page used to walk every letter twice and ask the disk for
/// every file on every pass of its body while the gallery stood, and the page itself was born anew in the sliding slot at
/// every opening -- a grid of 567 tiles and two dozen hosted cells built inside the touch's own turn of the loop (T1, 1945,
/// 13:42:51Z: a second and a half from the touch to the first frame). A tile is the letter's one small picture at once and
/// the file's sharp drawing after it (MTGalleryTile); a tap opens THE PLATFORM'S OWN VIEWER at that moment over everything
/// (the author's word 25.09: «take the feed out of the gallery; viewing as native as it gets, as the phone's photos» --
/// MTMomentsViewer, hosted by the chats page); a hold on a tile opens the platform's own menu with the moment's deeds (show in
/// chat, forward, delete my story); the plus, bottom right as on every page, is the platform's own picker -- videos from the
/// library into my stories by the one import road. The page searches itself, as the music and the wall do: the word narrows
/// the moments by the name of the conversation they lie in.
struct GalleryTabView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    let panel: MontanaTimePanel
    var query = ""
    let stories: [StoryMedia]                         // my own stories, handed by their one reader (the chats page)
    let onView: (String) -> Void                      // a tap on a tile: the platform's viewer at this moment, over everything
    let onAdd: ([PhotosPickerItem]) -> Void           // the plus: the one import road of my stories
    let onOpen: (String, MID) -> Void                 // the menu: the conversation at the letter
    let onForward: (String, MID) -> Void              // the menu: the letter forwarded by the conversation's own executor
    let onDelete: (String) -> Void                    // the menu: my own story deleted
    @State private var picks: [PhotosPickerItem] = []
    @State private var deleting: String?              // my story under the platform's question before it goes
    private static let dayMark = "day:"
    private static let tilesMark = "tiles:"
    private static let columns = 3
    private static let printNames = ["id", "moments"]

    private var word: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The moments the page shows, oldest first; a word at the head keeps the moments of the conversations it names.
    private func moments() -> [MTMoment] {
        let all = store.mediaLibrary(stories: stories)
        guard !word.isEmpty else { return all }
        return all.filter { $0.caption.localizedStandardContains(word) }
    }
    /// The rows: a day's header, then its tiles three to a row -- a row is named by its day and its place in the day.
    private func rows(_ list: [MTMoment]) -> (rows: [Chat], tiles: [String: [MTMoment]]) {
        var rows: [Chat] = []
        var tiles: [String: [MTMoment]] = [:]
        let cal = Calendar.current
        var day = -1.0, k = 0
        for c in list {
            let start = cal.startOfDay(for: Date(timeIntervalSince1970: c.at)).timeIntervalSince1970
            if start != day {
                day = start; k = 0
                rows.append(Self.chatRow(Self.dayMark + String(Int(start))))
            }
            let id = Self.tilesMark + String(Int(start)) + ":" + String(k / Self.columns)
            if tiles[id] == nil { rows.append(Self.chatRow(id)) }
            tiles[id, default: []].append(c)
            k += 1
        }
        return (rows, tiles)
    }
    private static func chatRow(_ id: String) -> Chat { Chat(name: id, lastMessage: "", time: "", unread: 0, status: "", convId: id) }
    /// A row's print: its name and its moments -- a day's header moves never, a row of tiles when a moment joins or leaves it.
    private static func rowPrint(_ c: Chat, _ tiles: [MTMoment]?) -> [Int] {
        func p<T: Hashable>(_ v: T) -> Int { var h = Hasher(); h.combine(v); return h.finalize() }
        return [p(c.id), p((tiles ?? []).map { $0.id + ($0.photo ? "p" : "v") })]
    }

    var body: some View {
        let _ = MTFrameMeter.shared.body("gallery")   // the page's passes while a motion is measured
        let built = rows(moments())
        // THE ROWS RUN ON TO THE SCREEN'S EDGES, AS THE CHATS' (the author's word 25.09): the one construction of the pages
        // under the bar, the panel list's own law; the ground is the page's one crest.
        MontanaTimePanelList(panel: panel, rows: built.rows,
                             fingerprint: { c in Self.rowPrint(c, built.tiles[c.id]) },
                             swipeLeading: { _ in [] }, swipeTrailing: { _ in [] }, swipesEnabled: false,
                             onOpen: { _ in },   // a tile answers by itself; a day's header answers nothing
                             rowContent: { c in AnyView(cell(c, built.tiles[c.id])) },
                             page: "gallery", fieldNames: Self.printNames, endFirst: true)
            // THE PLUS, bottom right as on every page under the bar (the music's plus, the chats' write): the platform's own
            // picker -- videos from the library into my stories, by the one import road (the chats page's).
            .mtPageAction {
                PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .videos) {
                    Image(systemName: "plus").font(.system(size: 27, weight: .medium)).foregroundColor(MontanaOctagon.barGlyph)
                        .montanaOctagonFace(square: true, bar: true)
                }
            }
            .overlay {
                if built.rows.isEmpty {
                    VStack(spacing: 12) {
                        if word.isEmpty {
                            MontanaPetalsGlyph(size: 56)
                            Text("No photos yet").font(.subheadline).foregroundColor(.gray)
                        } else {
                            Text("Nothing found").foregroundColor(.gray)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: picks) { _, items in
                guard !items.isEmpty else { return }
                onAdd(items); picks = []
            }
            // My own story goes only after the platform's own question (the feed's law, kept).
            .confirmationDialog("Delete this video?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let d = deleting { onDelete(d) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
            // AT EVERY OPENING OF THE PAGE, by the pane's choice: the page stands built in the row before it is looked at.
            .onChange(of: ui.pane, initial: true) { _, p in
                guard p == .gallery else { return }
                MontanaTrace.mark("gallery_tab", "rows=\(built.rows.count) moments=\(built.tiles.values.reduce(0) { $0 + $1.count })")
            }
    }

    /// Every row of the page, drawn by its name: a day's header as the platform's photos name a day -- bold, at the leading
    /// edge, over its tiles -- or a row of tiles, three to a row, the last row filled out with empty room.
    @ViewBuilder private func cell(_ c: Chat, _ tiles: [MTMoment]?) -> some View {
        if c.id.hasPrefix(Self.dayMark), let s = Double(c.id.dropFirst(Self.dayMark.count)) {
            Text(LocalizedStringKey(MTDayLabel.of(s)))
                .font(.title3.weight(.semibold)).foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 6)
        } else if let tiles {
            HStack(spacing: 2) {
                ForEach(tiles) { clip in
                    MTGalleryTile(clip: clip) { onView(clip.id) }
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        // THE MOMENT'S DEEDS ON A HOLD (25.09): the platform's own menu, as the phone's photos wear it.
                        .contextMenu {
                            if let m = clip.mid {
                                Button { onOpen(clip.chat, m) } label: { Label("Show in chat", systemImage: "text.bubble") }
                                Button { onForward(clip.chat, m) } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
                            }
                            if clip.own {
                                Button(role: .destructive) { deleting = clip.id } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                }
                ForEach(0..<max(0, Self.columns - tiles.count), id: \.self) { _ in
                    Color.clear.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
        }
    }
}

/// A tile of the gallery: the letter's one small picture at once (MTLetterThumb -- the picture the list row already draws),
/// then, for a photo, the file's own sharp drawing at the tile's size, decoded off the frame once and kept by its cost (the
/// sharp drawings keep 96 MB); a video wears its poster and its glyph. The tile is the whole target.
struct MTGalleryTile: View {
    let clip: MTMoment
    let action: () -> Void
    @State private var img: UIImage?
    var body: some View {
        Button(action: action) {
            Color(white: 0.16)
                .overlay { if let img { Image(uiImage: img).resizable().scaledToFill() } }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if !clip.photo {
                        Image(systemName: "video.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            .shadow(radius: 2).padding(6)
                    }
                }
                .contentShape(Rectangle())   // TOUCH-OK: the gallery tile is far larger than 44 points -- the shape is the tile
        }
        .buttonStyle(.plain)
        .task(id: clip.id) {
            let c = clip
            if let s = mtTileSharp.object(forKey: c.id as NSString) { img = s; return }
            // The small copy at once, the sharp drawing after it -- both off the frame.
            let small = await Task.detached(priority: .userInitiated) { mtTileSmall(c) }.value
            if img == nil, let small { img = small }
            guard c.photo else { return }
            let got = await Task.detached(priority: .utility) { mtTileSharpen(c) }.value
            if let got { img = got }
        }
    }
}

/// The sharp drawings of the tiles, one store: a tile's side is a third of the width, three screen pixels to the point. Born
/// through the one door of the picture caches (MontanaCaches, the critic 25.09): emptied when the screen is left and at the
/// system's warning, as every picture cache of the app.
private let mtTileSharp: NSCache<NSString, UIImage> = MontanaCaches.kept("gallery-sharp", cost: 96 * 1024 * 1024)
/// The letter's one small picture, asked off the frame (the road the list row takes, MTLetterThumb).
private func mtTileSmall(_ c: MTMoment) -> UIImage? {
    MTLetterThumb.picture(kind: c.photo ? "img" : "vid", file: c.id)
}
/// The file's own drawing at the tile's size (480 pixels on the long side), kept by its cost.
private func mtTileSharpen(_ c: MTMoment) -> UIImage? {
    guard let s = CGImageSourceCreateWithURL(c.url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                 kCGImageSourceThumbnailMaxPixelSize: 480,
                                 kCGImageSourceCreateThumbnailWithTransform: true,
                                 kCGImageSourceShouldCacheImmediately: true]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary) else { return nil }
    let ui = UIImage(cgImage: cg)
    mtTileSharp.setObject(ui, forKey: c.id as NSString, cost: cg.bytesPerRow * cg.height)
    return ui
}

/// One clip on the system player layer: it plays its WHOLE length while its page is the
/// current one and nobody paused it (the author's word 09.09), starts again only after the
/// last frame, and rests at its first frame when the page is scrolled away. Every stop that
/// nobody asked for is named in the diary and healed: a paused status while the page wants
/// playing, a stall, an item that failed, an audio interruption that ended (the author's word
/// 10.09: «the clip broke off again» — the reason had nowhere to be seen).
struct MontanaClipPlayer: UIViewRepresentable {
    let url: URL
    let active: Bool
    let paused: Bool
    var onProgress: (Double) -> Void
    /// A FILE NOT YET WHOLE plays through its loader (25.09, the feed's videos): the asset in place of the file's url,
    /// a few seconds buffered ahead. `muted`: a tile without sound — it takes the audio session from nobody.
    var asset: AVURLAsset? = nil
    var muted = false
    var quiet = false
    final class ClipView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        let player = AVPlayer()
        var wantPlaying = false
        var onProgress: ((Double) -> Void)?
        private var timeToken: Any?
        private var tokens: [NSObjectProtocol] = []
        private var statusWatch: NSKeyValueObservation?
        private var itemWatch: NSKeyValueObservation?
        private var healing = false
        /// THE HEALING BACKS OFF AND GIVES UP (29.09). A clip that could not buffer stood paused, was healed a beat later, paused
        /// again and was healed again -- 130 heals a minute on T1 (00:14-00:15Z, two tiles), every play() asking the loader for
        /// bytes anew: 36 MB through the tunnel in the first minute after it came up, 106 MB in three. Each heal in a row waits
        /// twice as long as the last (0.4 s to 10 s), the eighth is the last until the clip plays again or the page asks anew.
        private var healStreak = 0
        private static let healCap = 8
        func load(_ item: AVPlayerItem) {
            player.actionAtItemEnd = .none
            player.replaceCurrentItem(with: item)
            if let l = layer as? AVPlayerLayer { l.player = player; l.videoGravity = .resizeAspectFill }
            timeToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
                guard let self, let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return }
                self.onProgress?(max(0, min(1, t.seconds / d)))
            }
            let nc = NotificationCenter.default
            tokens.append(nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                self?.player.seek(to: .zero)   // the whole length has run — only now from the start again
                if self?.wantPlaying == true { self?.player.play() }
            })
            tokens.append(nc.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] n in
                let why = (n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "?"
                MontanaTrace.mark("video_feed", "failed-to-end \(why)")
                self?.heal("failed-to-end")
            })
            tokens.append(nc.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
                MontanaTrace.mark("video_feed", "stalled at \(Int(self?.player.currentTime().seconds ?? 0))s")
                self?.heal("stalled")
            })
            tokens.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
                let raw = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
                MontanaTrace.mark("video_feed", "audio interruption \(raw == AVAudioSession.InterruptionType.began.rawValue ? "began" : "ended")")
                if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.heal("interruption-ended") }
            })
            itemWatch = item.observe(\.status, options: [.new]) { it, _ in
                if it.status == .failed {
                    MontanaTrace.mark("video_feed", "item failed \(it.error?.localizedDescription ?? "?")")
                }
            }
            statusWatch = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
                guard let self else { return }
                switch p.timeControlStatus {
                case .playing:
                    self.healStreak = 0   // it plays: the next stop is judged afresh
                case .paused:
                    if self.wantPlaying, !self.atEnd {
                        MontanaTrace.mark("video_feed", "paused unasked at \(Int(p.currentTime().seconds))s rate=\(p.rate) err=\(p.error?.localizedDescription ?? "-")")
                        self.heal("paused-unasked")
                    }
                case .waitingToPlayAtSpecifiedRate:
                    MontanaTrace.mark("video_feed", "waiting \(p.reasonForWaitingToPlay?.rawValue ?? "-")")
                default: break
                }
            }
        }
        private var atEnd: Bool {
            guard let it = player.currentItem, it.duration.seconds.isFinite else { return false }
            return player.currentTime().seconds >= it.duration.seconds - 0.3
        }
        /// The page wants the clip playing: one re-issue, a beat later, never a storm -- and the beats grow (healStreak).
        private func heal(_ why: String) {
            guard wantPlaying, !healing else { return }
            guard healStreak < Self.healCap else {
                MontanaTrace.markFolded("video_feed", "heal given up after \(Self.healCap) -- \(why)", window: 60, key: "heal-cap")
                return
            }
            healing = true
            let delay = min(10, 0.4 * pow(2, Double(healStreak)))
            healStreak += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.healing = false
                guard self.wantPlaying, self.player.timeControlStatus != .playing else { return }
                if !self.player.isMuted { MontanaAudioSession.activatePlayback() }   // a silent tile leaves the session as it is
                self.player.play()
                MontanaTrace.mark("video_feed", "healed after \(why) try=\(self.healStreak) wait_ms=\(Int(delay * 1000))")
            }
        }
        func tear() {
            wantPlaying = false
            healStreak = 0
            player.pause()
            if let t = timeToken { player.removeTimeObserver(t) }; timeToken = nil
            tokens.forEach { NotificationCenter.default.removeObserver($0) }; tokens.removeAll()
            statusWatch = nil; itemWatch = nil
        }
    }
    func makeUIView(context: Context) -> ClipView {
        let v = ClipView()
        v.isUserInteractionEnabled = !quiet
        v.backgroundColor = .black
        v.onProgress = onProgress
        let item = asset.map { AVPlayerItem(asset: $0) } ?? AVPlayerItem(url: url)
        if asset != nil { item.preferredForwardBufferDuration = 5 }   // a buffer, never the whole file (25.09)
        v.player.isMuted = muted
        if muted { MontanaAudioSession.playSilentClip() }   // a tile without sound mixes with every other app's sound
        v.load(item)
        return v
    }
    func updateUIView(_ v: ClipView, context: Context) {
        v.isUserInteractionEnabled = !quiet
        v.onProgress = onProgress
        v.player.isMuted = muted
        v.wantPlaying = active && !paused
        if active && !paused { if v.player.timeControlStatus != .playing { v.player.play() } }
        else if !active { v.player.pause(); v.player.seek(to: .zero) }
        else { v.player.pause() }
    }
    static func dismantleUIView(_ v: ClipView, coordinator: ()) { v.tear() }
}

/// THE note window (the author's word 10.09): the shape a note is recorded in and played back
/// in — the skin decides (a circle under Native, an octagon under Geometric), and the ring on
/// its rim follows the same outline. One shape for the recorder and the bubble.
struct MontanaNoteWindow: Shape {
    /// A dual note's badge (the author's word 15.09): the front camera's small window on the big
    /// one's rim, a third of it inside, the rest past the rim — as a notification badge on an app
    /// icon — in the corner the person chose (0 TL, 1 TR, 2 BL, 3 BR; nil — no badge).
    var badge: Int? = nil
    /// Under the finger (the recorder) or from the file's own track (the player): the badge's
    /// centre as an offset from the middle in the circle's measure (its diameter = 1).
    var badgeAt: CGPoint? = nil
    /// The room around the circle inside the rect, in sides: a frame that holds the badge past
    /// the rim is wider than the circle by this on every side (0 — the rect is the circle's).
    var room: CGFloat = 0
    /// The badge in the window's own measure (the camera's numbers over the circle's 400): its
    /// centre on the diagonal, past the rim by two thirds of its own radius; its radius is its own.
    /// NO RIM ROUND THE SECOND CIRCLE (the author's word 24.09: «take the black rim off the second circle,
    /// the same style with no outline as the big one»): the window cuts the small circle at its own edge,
    /// so a note recorded with the old dark rim shows none of it past the big circle either.
    static let badgeReach: CGFloat = (0.5 + 72.0 / 400.0 / 3) / 2.0.squareRoot()
    static let badgeRadius: CGFloat = 72.0 / 400.0
    /// How far the badge stands past the circle's square, in sides — the room a frame must add.
    static let overhang: CGFloat = badgeReach + badgeRadius - 0.5
    static func badgeOffset(corner k: Int) -> CGPoint {
        CGPoint(x: (k % 2 == 0 ? -1 : 1) * badgeReach, y: (k < 2 ? -1 : 1) * badgeReach)
    }
    /// THE WINDOW IS THE FILE'S SHAPE (the critic's word 15.09): the file holds a circle with a
    /// round badge, the same for every skin and every build that reads it — so the window is a
    /// circle under every skin (the round note is a thing the author named; the octagon stays
    /// with the buttons and the plates). An octagon window cut the round badge into a square with
    /// clipped corners under the Geometric skin.
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / (1 + 2 * room)
        let c = CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s)
        var p = Path(ellipseIn: c)
        if let at = badgeAt ?? badge.map({ Self.badgeOffset(corner: $0) }) {
            let r = Self.badgeRadius * s
            let b = CGPoint(x: c.midX + at.x * s, y: c.midY + at.y * s)
            p.addPath(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: 2 * r, height: 2 * r)))
        }
        return p
    }
}
struct MontanaNoteRing: View {
    let progress: Double
    var color: Color = Color.accentColor
    /// THE RECORDER'S RING IS GREY GLASS (the author's word 22.09): the minute fills in the platform's
    /// grey through the system's material, no gold, no timer under the circle — the ring is the clock.
    var glass = false
    var body: some View {
        ZStack {
            MontanaNoteWindow().stroke(Color.white.opacity(0.25), lineWidth: 4)
            if glass {
                MontanaNoteWindow().trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                    .stroke(.thinMaterial, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .overlay {
                        MontanaNoteWindow().trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                            .stroke(Color(uiColor: .systemGray2).opacity(0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    }
                    .rotationEffect(.degrees(-90))   // the circle starts at the top
            } else {
                MontanaNoteWindow().trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))   // the circle starts at the top
            }
        }
    }
}

/// The note's picture in its window. The file's canvas is wider than its circle — the badge's
/// room around it — so the picture is framed to let the circle fill the window; the window's own
/// bounds are wider than the circle by the badge's overhang on every side (SwiftUI clips to the
/// bounds as well as to the shape — measured 15.09: the badge past the square was cut), while
/// the layout keeps the circle's footprint. A dual note (its name says so) gets the badge.
struct MontanaNoteFrame<Content: View>: View {
    let badge: Int?
    let badgeAt: CGPoint?
    let side: CGFloat
    @ViewBuilder let content: () -> Content
    init(file: String, side: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.init(badge: MontanaVideoNoteCamera.badgeCorner(file), side: side, content: content)
    }
    init(badge: Int?, badgeAt: CGPoint? = nil, side: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.badge = badge; self.badgeAt = badgeAt; self.side = side; self.content = content
    }
    var body: some View {
        let k = CGFloat(MontanaVideoNoteCamera.canvas) / CGFloat(MontanaVideoNoteCamera.side)
        let o = MontanaNoteWindow.overhang
        let f = side * (1 + 2 * o)
        content()
            .frame(width: side * k, height: side * k)
            .frame(width: f, height: f)
            .clipShape(MontanaNoteWindow(badge: badge, badgeAt: badgeAt, room: o))
            .frame(width: side, height: side)
    }
}

/// The note in its bubble: the poster in the note window, the ring on the rim showing the
/// dock's progress when this note is the one playing — the dock owns the one player, the bubble
/// owns nothing that plays. It only DRAWS: the tap is the bubble root's (primaryTap), as with
/// every message — a second gesture node here fired together with the root's (the critic's word
/// 15.09: the whole frame rose over the circle on one tap).
struct MontanaNotePlayback: View {
    let file: String
    let side: CGFloat
    let onDisk: Bool
    let thumbTick: Int
    let frameBox: MTFrameBox   // where the circle stands on the screen — the open note flies out of here
    @ObservedObject private var dock = MontanaVideoDock.shared
    var body: some View {
        let mine = dock.file == file
        ZStack {
            let _ = thumbTick
            // NO RIM (the author's word 23.09: «no outline and no ring around the circle, in the chat and when it is
            // watched — only the clean cut-out picture, and the second circle if there is one»).
            // ONE circle (the author's word 15.09): the note flies out of its bubble and opens over
            // the feed, and flies back on close — while it is out, the bubble holds nothing at all.
            MontanaNoteFrame(file: file, side: side) {
                if mine {
                    Color.clear
                } else if let t = videoThumbCached(file) {
                    Image(uiImage: t).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    Color.black
                }
            }
            .background(GeometryReader { g -> Color in frameBox.rect = g.frame(in: .global); return Color.clear })
            if !mine {
                Image(systemName: onDisk ? "play.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 40)).foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(width: side, height: side)
    }
}

/// THE video dock: one player for the round note. It plays IN THE CHAT, as a voice does (the
/// author's word 15.09) — in its bubble and in the one player bar above the field; there is no
/// page of its own. Every view attaches a layer to this one player, so nothing restarts the clip.
/// The bar shows one thing: opening a note stops the voice, starting a voice closes the note.
final class MontanaVideoDock: NSObject, ObservableObject {
    static let shared = MontanaVideoDock()
    @Published var file: String?
    @Published var chat = ""
    @Published var caption = ""
    @Published var playing = false
    @Published var progress: Double = 0
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    /// The badge's place at this moment of the note, in the circle's measure (nil — no badge):
    /// from the file's own badge timeline (the author's word 15.09: the reader shows exactly
    /// what the sender saw — the badge where it was, only while it was; BY FACT ONLY, the
    /// author's word 15.09 again — a file without the timeline shows no badge window at all,
    /// never the dark ground in a badge that was not there).
    @Published var badgeAt: CGPoint?
    /// The bubble's circle on the screen the note flew out of (nil — opened from the bar): the
    /// open note grows from here and shrinks back here on close.
    @Published var origin: CGRect?
    @Published var closing = false
    /// The chat's notes in feed order, set when one opens (as the voice's queue is): the end of one
    /// opens the next, A to B directly, the bar standing (the author's word 18.09).
    var queue: [(file: String, caption: String)] = []
    let player = AVPlayer()
    private var timeToken: Any?
    private var endToken: NSObjectProtocol?
    private var statusWatch: NSKeyValueObservation?
    /// THE BADGE TIMELINE, READ WHOLE AT OPEN (T2 21:43, 1608: the badge stood cut at the rim
    /// on playback — the pushed timed metadata never reached the window): every word with its
    /// range, and the place looked up by the player's own clock on every tick and every seek —
    /// no delegate, no push, nothing to arrive late.
    private var track: [(CMTimeRange, CGPoint?)] = []
    private var reading: String?

    func open(file: String, chat: String, caption: String, from origin: CGRect? = nil, queue: [(file: String, caption: String)] = []) {
        self.origin = origin; closing = false
        if !queue.isEmpty { self.queue = queue }
        if self.file != file {
            VoicePlayer.shared.stepAside()   // one thing plays: a voice stands down, a track steps aside with its place (26.09)
            self.file = file; self.chat = chat; self.caption = caption; progress = 0; elapsed = 0; duration = 0
            let url = MontanaMediaVault.playableURL(file) ?? attachmentURL(file)
            track = []; reading = file; badgeAt = nil
            MontanaNoteBadgeTrack.read(url) { [weak self] words in
                guard let self, self.reading == file else { return }
                self.track = words
                MontanaTrace.mark("vnote_open", "timeline=\(words.count)")
                self.place(self.player.currentTime())
            }
            let item = AVPlayerItem(url: url)
            player.actionAtItemEnd = .pause
            playing = false   // the swap is no pause nobody asked for: a second note over a playing first
            player.replaceCurrentItem(with: item)
            if let e = endToken { NotificationCenter.default.removeObserver(e) }
            // The end opens the chat's next note when there is one (the voice's own law since 14.09),
            // else closes the note, as a voice's end takes its bar down.
            endToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                guard let self else { return }
                if let i = self.queue.firstIndex(where: { $0.file == file }), i + 1 < self.queue.count {
                    let n = self.queue[i + 1]
                    MontanaTrace.mark("vnote_next", "i=\(i + 1) n=\(self.queue.count)")
                    self.open(file: n.file, chat: self.chat, caption: n.caption)
                } else {
                    self.close()
                }
            }
            if timeToken == nil {
                // The frames' own pace: the badge follows its track as it moved under the finger.
                timeToken = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 24), queue: .main) { [weak self] t in
                    guard let self, t.seconds.isFinite else { return }
                    // THE CLOCK RUNS FROM THE FIRST FRAME (the author's word 18.09): it used to wait for the
                    // item to name its duration, and stood still until it did. The elapsed is the player's
                    // own moment; the share needs the duration and waits for it alone.
                    self.elapsed = t.seconds
                    if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                        self.duration = d
                        self.progress = max(0, min(1, t.seconds / d))
                    }
                    self.place(t)
                }
            }
            watchStatus()
            // The length is asked of the file at once (not of the first tick): a scrub before the
            // first frame has a length to scrub against.
            Task { [weak self] in
                if let d = try? await item.asset.load(.duration), d.seconds.isFinite, d.seconds > 0 {
                    await MainActor.run { if let self, self.file == file, self.duration == 0 { self.duration = d.seconds } }
                }
            }
        }
        MontanaAudioSession.activatePlayback()
        play()
    }
    /// THE NOTE STOPS ONLY WHEN ASKED (the author's word 18.09: the clock stood still now and then).
    /// The system player pauses by itself — an audio interruption, a stall, a session taken by
    /// another sound — and nothing of ours knew: the dock still said «playing» and the clock stood.
    /// The player's own status is watched (the clip player's road since 10.09): a pause nobody asked
    /// for is named in the diary and the play is re-issued once, a beat later. The end is not a pause:
    /// the end closes the note itself.
    private func watchStatus() {
        guard statusWatch == nil else { return }
        statusWatch = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            guard p.timeControlStatus == .paused else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.playing, self.file != nil, !self.closing else { return }
                if let it = self.player.currentItem, it.duration.seconds.isFinite,
                   self.player.currentTime().seconds >= it.duration.seconds - 0.3 { return }
                MontanaTrace.mark("vnote_pause", "unasked at=\(Int(self.player.currentTime().seconds))s err=\(self.player.error?.localizedDescription ?? "-")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, self.playing, self.file != nil, self.player.timeControlStatus != .playing else { return }
                    MontanaAudioSession.activatePlayback()
                    self.player.play(); self.player.rate = VoicePlayer.shared.voiceRate
                    MontanaTrace.mark("vnote_pause", "healed")
                }
            }
        }
    }
    /// The badge's place at a moment of the note: the timeline's word whose range holds it
    /// (the last word begun before it); none without a timeline.
    private func place(_ t: CMTime) {
        let at = track.last(where: { CMTimeCompare($0.0.start, t) <= 0 })?.1 ?? track.first?.1
        if at != badgeAt { badgeAt = at }
    }
    /// A note is a spoken word: it plays at the voice's speed (one speed for both).
    func play() { player.play(); player.rate = VoicePlayer.shared.voiceRate; playing = true }
    func pause() { player.pause(); playing = false }
    func toggle() { if playing { pause() } else { play() } }
    func applyRate() { if playing { player.rate = VoicePlayer.shared.voiceRate } }
    func seek(to fraction: Double) {
        let d = player.currentItem.map { $0.duration.seconds }.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? duration
        guard d > 0 else { return }
        let t = max(0, min(d - 0.2, d * fraction))
        let ct = CMTime(seconds: t, preferredTimescale: 600)
        // THE SYSTEM PLAYER SEEKS ON THE FLY — its own road (the author's word 18.09: the note went
        // dead after a scrub, the thumb jumped, the clock stood after a seek to the start). A pause of
        // ours around the seek with a play in its completion left the note standing when the
        // completion came late or came for an interrupted seek; AVPlayer plays through a seek by
        // itself and its clock follows the landing. Nothing of ours is published here: the scrubber
        // holds the asked place until the clock confirms it. The audio player's road (pause, position,
        // play) is that player's own and stays there.
        place(ct)
        player.seek(to: ct, toleranceBefore: .zero, toleranceAfter: .zero)
        MontanaTrace.mark("seek", "note to=\(Int(t))s playing=\(playing ? 1 : 0)")
    }
    /// Close: the circle flies back into its bubble first (when it came from one), then the
    /// player lets go.
    func close() {
        pause()
        guard !closing else { return }
        if origin != nil {
            closing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.letGo() }
        } else { letGo() }
    }
    private func letGo() {
        let had = file != nil
        player.replaceCurrentItem(with: nil)
        file = nil; progress = 0; elapsed = 0; duration = 0; badgeAt = nil; track = []; reading = nil; origin = nil; closing = false
        if had { VoicePlayer.shared.noteClosed() }   // the track that stepped aside for the note comes back (26.09)
    }
}

/// A layer on the dock's one player — the bubble-sized bar and the full-width window alike.
struct MontanaDockLayerView: UIViewRepresentable {
    let player: AVPlayer
    final class LayerView: UIView { override static var layerClass: AnyClass { AVPlayerLayer.self } }
    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.backgroundColor = .black
        if let l = v.layer as? AVPlayerLayer { l.player = player; l.videoGravity = .resizeAspectFill }
        return v
    }
    func updateUIView(_ v: LayerView, context: Context) {}
}

/// THE OPEN NOTE (the author's word 15.09): the note that plays rises to the centre of the VISIBLE
/// feed and opens to the width the screen allows — a layer on the dock's one player, the ring on
/// its rim, a tap for play and pause; the bar below owns seek, speed and close. The keyboard
/// shortens the feed and the note follows its centre, as the voice orb does.
struct MontanaNoteOpen: View {
    @ObservedObject private var dock = MontanaVideoDock.shared
    /// THE note's open size (one SSOT for the player and the recorder): as wide as the visible
    /// feed lets the circle AND its badge stand — the badge reaches past the circle's rim by
    /// badgeReach + badgeRadius of the side, and a circle that filled the width to the margins
    /// had its badge cut at the screen's edge on playback (the author's word 15.09); never taller
    /// than the feed leaves after what stands below the note.
    static func side(in sz: CGSize, below: CGFloat = 0) -> CGFloat {
        let reach = MontanaNoteWindow.badgeReach + MontanaNoteWindow.badgeRadius   // the badge's far edge, in sides from the centre
        return max(120, min((sz.width / 2 - 6) / reach, sz.width - 36, sz.height - 40 - below))
    }
    /// THE STAGE (the author's word 15.09: after the recording the playback looks as the
    /// recording did, one to one): the circle over a row of the bar's tier — the recorder's
    /// buttons stand in it, the player leaves it empty — the pair centred in the visible feed;
    /// the same side and the same centre by the same numbers for both.
    static let rowGap: CGFloat = 14
    /// NOTHING UNDER THE CIRCLE (the author's word 22.09: no timer for the note — the ring is its clock;
    /// the recorder's buttons stand on the bar's line): the circle takes the visible part, its badge's
    /// room counted, centred in it — the recorder and the player by the same numbers.
    static func stageSide(in sz: CGSize) -> CGFloat { side(in: sz) }
    static func stageCentre(in sz: CGSize) -> CGPoint { CGPoint(x: sz.width / 2, y: sz.height / 2) }
    @State private var grown = false
    /// THE FLIGHT'S OWN FACTS (the author's word 15.09: «the circle returns, and then something
    /// flashes in the centre — its shadow and the gold ring»): the bubble it flew out of and the
    /// fact of closing are taken once, here, and never read live again. The dock lets go
    /// (origin nil, closing false) while this view is still fading out — read live, the circle
    /// jumped back to the centre at full size with its shadow and ring for the fade's length.
    @State private var from: CGRect?
    @State private var closed = false
    var body: some View {
        GeometryReader { g in
            let full = Self.stageSide(in: g.size)
            let here = g.frame(in: .global)
            // The flight (the author's word 15.09): the circle starts where the bubble's stands
            // and grows to the open size; on close it shrinks back there.
            let origin = from.map { CGRect(x: $0.minX - here.minX, y: $0.minY - here.minY, width: $0.width, height: $0.height) }
            let out = grown && !closed
            let side = out || origin == nil ? full : origin!.width
            let centre = out || origin == nil ? Self.stageCentre(in: g.size) : CGPoint(x: origin!.midX, y: origin!.midY)
            ZStack {
                // The dim is the recorder's (one to one): the feed behind goes dark under the note;
                // a tap on it closes the note, as the bar's cross does.
                Color.black.opacity(0.62).opacity(out ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { dock.close() }
                ZStack {
                    // No rim while it plays either (23.09): the clean picture; the bar below keeps the time.
                    MontanaNoteFrame(badge: nil, badgeAt: dock.badgeAt, side: side) { MontanaDockLayerView(player: dock.player) }
                    if !dock.playing, out {
                        Image(systemName: "play.fill").font(.system(size: 54)).foregroundColor(.white.opacity(0.9))
                    }
                }
                .shadow(color: .black.opacity(out ? 0.5 : 0), radius: 12, y: 4)
                .contentShape(MontanaNoteWindow())
                .onTapGesture { dock.toggle() }
                .position(centre)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: out)
            .frame(width: g.size.width, height: g.size.height)
            .onAppear { from = dock.origin; DispatchQueue.main.async { grown = true } }
            .onChange(of: dock.closing) { _, v in if v { closed = true } }
        }
    }
}

/// A control of the recorder's window reports where it stands, so the top window takes touches
/// there and nowhere else (the held button, the lock, the pause, the bin beneath keep theirs).
struct MTNoteTouchable: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content.background(GeometryReader { g -> Color in MTHoldOverlayState.shared.touchable[id] = g.frame(in: .global); return Color.clear }
            .onDisappear { MTHoldOverlayState.shared.touchable[id] = nil })   // a control gone from the screen takes no touch
    }
}

/// The round video note under the finger (the author's word 10.09): the camera in the note
/// window over the feed, the ring for the minute and the seconds under it. The held camera
/// button below owns the gesture; a swipe up locks it hands-free. The one control here is the
/// camera flip (the author's word 15.09) — the call screen's face, and a tap on the window
/// itself flips too, as the reference does; the recording runs on through the flip.
struct MontanaVideoNoteHold: View {
    @ObservedObject var cam: MontanaVideoNoteCamera
    @State private var drag: CGSize = .zero
    var body: some View {
        GeometryReader { g in
        // The recorder stands on the player's stage (the author's word 15.09: one to one): the
        // same side at the same centre by the same numbers; nothing under the circle (22.09) — the
        // buttons stand on the bar's line (the crown's row), the grey glass ring is the clock.
        let side = MontanaNoteOpen.stageSide(in: g.size)
        let f = CGFloat(MontanaVideoNoteCamera.side) / side
        ZStack {
            ZStack {
                MontanaNoteRing(progress: min(1, cam.elapsed / MontanaVideoNoteCamera.maxSeconds), glass: true).frame(width: side + 14, height: side + 14)
                // The window frames the canvas as every reader does; the badge shows while both record.
                MontanaNoteFrame(badge: cam.dual ? cam.corner : nil,
                                 badgeAt: cam.dual ? CGPoint(x: cam.badgeOffset.x / CGFloat(MontanaVideoNoteCamera.side),
                                                             y: cam.badgeOffset.y / CGFloat(MontanaVideoNoteCamera.side)) : nil,
                                 side: side) { MontanaVideoNotePreview(camera: cam) }
            }
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .contentShape(MontanaNoteWindow())
            .onTapGesture { cam.flip() }
            // The badge under the finger (the author's word 15.09): the call's miniature, one to
            // one — a handle on the badge itself, dragged in GLOBAL space (the local space moves
            // with what it drags and the picture jitters), a spring to the nearest corner on release.
            .overlay {
                if cam.dual {
                    let r = MontanaNoteWindow.badgeRadius * side
                    Color.clear.frame(width: 2 * r, height: 2 * r).contentShape(Circle())
                        .gesture(DragGesture(coordinateSpace: .global)
                            .onChanged { v in
                                drag = v.translation
                                cam.dragBadge(CGSize(width: v.translation.width * f, height: v.translation.height * f))
                            }
                            .onEnded { _ in drag = .zero; cam.dragEnded() })
                        .offset(x: cam.badgeOffset.x / f, y: cam.badgeOffset.y / f)
                }
            }
            // A pinch on the big circle zooms its camera (the author's word 15.09).
            .simultaneousGesture(MagnificationGesture().onChanged { cam.pinch($0) }.onEnded { _ in cam.pinchEnded() })
            .modifier(MTNoteTouchable(id: "window"))
            .position(MontanaNoteOpen.stageCentre(in: g.size))
        }
        .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// The preview IS the file: the view shows the very frames the pipeline writes — the same
/// circle, the same square, both cameras composed the same way — so nothing on the screen can
/// differ from what leaves. A capture preview layer showed the sensor, not the note.
struct MontanaVideoNotePreview: UIViewRepresentable {
    let camera: MontanaVideoNoteCamera
    final class PreviewView: UIView {}
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.layer.contentsGravity = .resizeAspectFill
        camera.previewLayer = v.layer
        return v
    }
    func updateUIView(_ v: PreviewView, context: Context) { camera.previewLayer = v.layer }
}

/// THE ROUND NOTE IS A SQUARE WITH THE CIRCLE BAKED IN (the critic's word 15.09, the
/// reference's pipeline): every frame is oriented, scaled so its short side is the note's side,
/// cut to the centre square and masked with a circle over its own blurred, darkened copy; the
/// file is 400×400. What the person saw in the window is what leaves; outside the circle the
/// file holds no living picture, and any reader anywhere shows a circle.
///
/// ONE SESSION, BOTH CAMERAS (the author's word 15.09): where the hardware runs two cameras at
/// once, both stand on the session from the start, each with its own output and connection;
/// the flip and the dual button only enable connections — nothing is rewired mid-note. Three
/// modes: the front, the back, or BOTH — the back camera fills the circle and the front sits
/// inside it as a smaller circle, a ring on a ring. Hardware that runs one camera keeps the
/// single-camera road (the input swapped on a flip) and shows no dual button.
/// THE NOTE'S PICTURE QUALITY (the author's word 18.09): three steps a person chooses in the
/// appearance settings — the source's height and the encoder's rate; the file's square (480) and
/// the circle (400) never change, so every build reads every note. The camera takes the step's
/// source when the hardware carries it and steps down by itself when it does not (the pair's cost).
enum MontanaNoteQuality: String, CaseIterable {
    case low, medium, high
    static let key = "noteQuality"
    static var current: MontanaNoteQuality { MontanaNoteQuality(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .medium }   // medium by default (the author's word 21.09)
    var minHeight: Int32 { switch self { case .low: return 480; case .medium: return 720; case .high: return 1080 } }
    var preset: AVCaptureSession.Preset { switch self { case .low: return .vga640x480; case .medium: return .hd1280x720; case .high: return .hd1920x1080 } }
    var bitRate: Int { switch self { case .low: return 900_000; case .medium: return 1_500_000; case .high: return 2_500_000 } }
    var lower: MontanaNoteQuality? { switch self { case .low: return nil; case .medium: return .low; case .high: return .medium } }
}

final class MontanaVideoNoteCamera: NSObject, ObservableObject,
                                    AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published var elapsed: Double = 0
    @Published var finished: String? = nil
    /// The fill light: the white screen at full brightness for the front camera, the torch for the back.
    @Published var flash = false
    @Published private(set) var front = true
    /// Both cameras in one circle — the back around, the front within.
    @Published private(set) var dual = false
    /// The tape stands (the author's word 15.09, as the voice's pause): frames and sound are not
    /// written while it stands, and the file's clock skips the pause — no frozen stretch inside.
    @Published private(set) var paused = false
    /// A NOTE IS BEING RECORDED — ONE OWNER (16.09, as the voice's `isRecording`): true from the
    /// hold that starts the tape until the writer closes by any road — the arrow, the bin, the
    /// chat left behind, the length; the chat derives everything from it and keeps no flag of
    /// its own (a flag set by hand in two places outlived the tape when a third road ended it).
    @Published private(set) var live = false
    private var standing = false        // the tape stands (the frames' queue)
    private var pauseAt: CMTime?        // the source clock when it stood
    private var resumeFix = false       // the first frame after it went on sets the clock's shift
    private var shift = CMTime.zero     // the paused time removed from the file's clock
    private var lastSource: CMTime?
    func togglePause() {
        paused.toggle()
        let p = paused
        q.async {
            self.lock.lock(); self.standing = p; self.lock.unlock()
            if p { self.pauseAt = self.lastSource } else { self.resumeFix = self.pauseAt != nil }
        }
        MontanaTrace.mark("vnote_pause", p ? "stand" : "go")
    }
    /// The file's clock for a source moment: the source less every pause so far.
    private func fileTime(_ pts: CMTime) -> CMTime {
        if resumeFix, let at = pauseAt {
            resumeFix = false; pauseAt = nil
            let gap = CMTimeSubtract(CMTimeSubtract(pts, at), CMTime(value: 1, timescale: 24))
            if gap.seconds > 0 { lock.lock(); shift = CMTimeAdd(shift, gap); lock.unlock() }
        }
        return CMTimeSubtract(pts, shift)
    }
    static let cornerTags = ["tl", "tr", "bl", "br"]
    /// The name says whether the note carries the badge and where: vnote_D + tl|tr|bl|br + id.
    static func badgeTag(_ f: String) -> String? {
        guard f.hasPrefix("vnote_D") else { return nil }
        let tag = String(f.dropFirst("vnote_D".count).prefix(2))
        return cornerTags.contains(tag) ? tag : "br"
    }
    static func badgeCorner(_ f: String) -> Int? { badgeTag(f).flatMap { cornerTags.firstIndex(of: $0) } }
    /// THE NOTE'S NAME IS MINTED ONCE, AT THE FINISH (the critic 22.09). The tape records under a working
    /// name that is never a row's name (rec_…), and the note takes its one name here — the badge and its
    /// corner known by then. A name born early and renamed at the end is the class of the transcode
    /// boundary (a key that changes while the thing lives); no reader can key on a name that does not exist.
    /// Carries the encoder's mark: the send road transcodes nothing marked.
    static func noteName(badgeCorner: Int?) -> String {
        "vnote_" + (badgeCorner.map { "D" + cornerTags[$0] } ?? "") + UUID().uuidString + MontanaVideoMark.suffix + ".mov"
    }
    /// The badge's corner (0 TL, 1 TR, 2 BL, 3 BR), remembered between notes.
    @Published private(set) var corner: Int = UserDefaults.standard.object(forKey: "vnoteCorner") == nil ? 3 : UserDefaults.standard.integer(forKey: "vnoteCorner")
    /// The badge's centre as an offset from the canvas's middle, in file pixels, y down — at its
    /// corner, under the finger, or on its way to a corner (the screen's copy; the frames' queue
    /// holds its own, badgeNow, and eases it toward badgeTarget frame by frame).
    @Published private(set) var badgeOffset: CGPoint = MontanaVideoNoteCamera.cornerOffset(3)
    private var badgeNow: CGPoint = MontanaVideoNoteCamera.cornerOffset(3)
    private var badgeTarget: CGPoint?
    private var dragStart: CGPoint?
    static var reach: CGFloat { (CGFloat(side) / 2 + CGFloat(inner) / 6) / 2.0.squareRoot() }
    static func cornerOffset(_ k: Int) -> CGPoint { CGPoint(x: (k % 2 == 0 ? -1 : 1) * reach, y: (k < 2 ? -1 : 1) * reach) }
    /// THE BADGE TRACK: the badge's place rides in the file as timed metadata — a word per change
    /// («x,y» in file pixels, y down; «-» for none) — so a reader shows the badge where it was and
    /// only while it was, exactly as the sender saw it. Old readers do not look for the track.
    static let badgeMetaID = "mdta/quest.montana.note.badge"
    static func badgeWord(_ p: CGPoint?) -> String { p.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded()))" } ?? "-" }
    static func badgePlace(_ s: String) -> CGPoint? {
        let parts = s.split(separator: ","); guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
        return CGPoint(x: x, y: y)
    }
    private var badgeWordWritten: String?
    func setCorner(_ c: Int) {
        guard (0...3).contains(c) else { return }
        let o = Self.cornerOffset(c)
        q.async { self.badgeTarget = o }   // the frames ease there; the screen follows the frames
        guard c != corner else { return }
        corner = c; UserDefaults.standard.set(c, forKey: "vnoteCorner")
        MontanaTrace.mark("vnote_corner", Self.cornerTags[c])
    }
    func dragBadge(_ t: CGSize) {
        if dragStart == nil { dragStart = badgeOffset }
        guard let s = dragStart else { return }
        let r = Self.reach
        let o = CGPoint(x: max(-r, min(r, s.x + t.width)), y: max(-r, min(r, s.y + t.height)))
        badgeOffset = o
        q.async { self.badgeNow = o; self.badgeTarget = nil }
    }
    func dragEnded() {
        dragStart = nil
        setCorner((badgeOffset.x > 0 ? 1 : 0) + (badgeOffset.y > 0 ? 2 : 0))
    }
    /// One step of the badge's way to its corner (the frames' queue): a spring's ease, the
    /// screen's copy updated with it.
    private func easeBadge() {
        guard let t = badgeTarget else { return }
        let dx = t.x - badgeNow.x, dy = t.y - badgeNow.y
        if abs(dx) < 0.5, abs(dy) < 0.5 { badgeNow = t; badgeTarget = nil } else { badgeNow = CGPoint(x: badgeNow.x + dx * 0.35, y: badgeNow.y + dy * 0.35) }
        let o = badgeNow
        DispatchQueue.main.async { self.badgeOffset = o }
    }
    static let dualCapable = AVCaptureMultiCamSession.isMultiCamSupported
    private var savedBrightness: CGFloat?
    static let side = 400                       // the note's circle, the reference's number
    static let canvas = 480                     // the file's square: the circle and the badge's room around it; a multiple of 16 — H.264 skews any other width
    static let inner = 144                      // the front camera's badge on the big circle's rim
    private var usedDual = false                // the note ends with the badge: its name says so (the poster's state)
    static let maxSeconds: Double = 399         // 6:39, the note's length (the author's word 15.09)
    let session: AVCaptureSession = MontanaVideoNoteCamera.dualCapable ? AVCaptureMultiCamSession() : AVCaptureSession()
    // two cameras (multi-camera hardware): an input, an output and a connection each
    private var frontIn: AVCaptureDeviceInput?
    private var backIn: AVCaptureDeviceInput?
    private let frontOut = AVCaptureVideoDataOutput()
    private let backOut = AVCaptureVideoDataOutput()
    private var frontConn: AVCaptureConnection?
    private var backConn: AVCaptureConnection?
    // one camera (the fallback): the input swapped on a flip
    private let videoOut = AVCaptureVideoDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private let audioOut = AVCaptureAudioDataOutput()
    private let q = DispatchQueue(label: "montana.note.frames")
    private let sessionQueue = DispatchQueue(label: "montana.note.session", qos: .userInitiated)
    /// THE SOUND HAS A QUEUE OF ITS OWN (the author's word 16.09: in a two-circle note the sound
    /// drifted from the picture). The sound used to arrive on the frames' queue, behind the
    /// composition of every frame — two cameras, a blur, a mask — and the capture drops the
    /// sound it cannot deliver in time; a file whose sound has holes plays its sound short, and
    /// the picture runs on without it. The sound now comes on a queue nothing else stands in,
    /// and the writer's gate is read under the lock the frames' queue writes it with.
    private let aq = DispatchQueue(label: "montana.note.sound", qos: .userInteractive)
    private var soundSeconds: Double = 0   // the sound written, in seconds — beside the picture's length in the diary
    private var soundDropped = 0           // the sound the writer would not take
    private var timer: Timer?
    private var fileName = ""
    private var cancelled = false
    private var configured = false   // inputs and the outputs are wired once; every hold reuses them
    private var configuredQuality: MontanaNoteQuality?   // the source the session runs at; a changed setting re-picks it
    private var busy = false
    weak var previewLayer: CALayer?
    // the writer of one note
    private var writer: AVAssetWriter?
    private var videoIn: AVAssetWriterInput?
    private var audioIn: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var badgeWords: [(CMTime, String)] = []   // the badge's word at every change, in the file's time
    private var recording = false
    private var stopping = false
    private var firstPTS: CMTime?
    private var lastPTS: CMTime?
    private let lock = NSLock()
    private var request = 0
    private var requested = false
    private var previewPending = false
    private func wants(_ ticket: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return requested && request == ticket
    }
    private func isRequest(_ ticket: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return request == ticket
    }
    private func endRequest() {
        lock.lock(); requested = false; lock.unlock()
    }
    private var length: Double = 0
    private var lastSmall: CIImage?   // the badge camera's latest frame, composed into the big one's in dual mode
    // the circle pipeline (the reference's CameraRoundVideoFilter, in CoreImage)
    private let ci = CIContext(options: [.useSoftwareRenderer: false])
    /// A disc mask: white inside the circle, black outside. The big circle's disc bleeds two
    /// pixels past its square so the window's clip (the same circle) never meets a half-dark
    /// edge; the circle ∩ square is still the whole circle, nothing flat shows. THE BADGE'S DISC
    /// DOES NOT BLEED (the author's word 15.09: «a square is cut inside the small circle, the
    /// edge does not end in the circle»): a disc of radius 74 cut by its 144 square left four
    /// flat sides 34 px long where the rim went thick and straight — the badge's circle is its
    /// square's inscribed circle exactly, and it lies on the big picture as it is, with no rim (24.09).
    private static func disc(_ n: CGFloat, bleed: CGFloat = 2) -> CIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: n, height: n), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let img = r.image { c in
            UIColor.black.setFill(); c.fill(CGRect(x: 0, y: 0, width: n, height: n))
            UIColor.white.setFill(); c.cgContext.fillEllipse(in: CGRect(x: -bleed, y: -bleed, width: n + 2 * bleed, height: n + 2 * bleed))
        }
        return CIImage(image: img)!
    }
    private let mask = MontanaVideoNoteCamera.disc(CGFloat(MontanaVideoNoteCamera.side))
        .transformed(by: CGAffineTransform(translationX: CGFloat(MontanaVideoNoteCamera.canvas - MontanaVideoNoteCamera.side) / 2,
                                           y: CGFloat(MontanaVideoNoteCamera.canvas - MontanaVideoNoteCamera.side) / 2))
    private let innerMask = MontanaVideoNoteCamera.disc(CGFloat(MontanaVideoNoteCamera.inner), bleed: 0)

    /// Music played when the tape began (the author's word 24.09): the session mixes and nothing of it stands down.
    private var keepMusic = false
    @discardableResult
    func start() -> Bool {
        guard !busy else { MontanaTrace.mark("vnote_busy", "refused"); return false }
        busy = true; cancelled = false; live = true
        lock.lock(); request += 1; requested = true; stopping = false; let ticket = request; lock.unlock()
        MontanaScreenAwake.hold("note")   // the screen stays awake while the note records (the author's word 18.09)
        // A NOTE KEEPS THE MUSIC (the author's word 24.09): read before anything of ours stands down.
        keepMusic = MontanaAudioSession.musicPlays
        MontanaPlayerBar.standDown(keepingMusic: keepMusic)   // a tape holds what plays at its place (26.09); the music plays on (24.09)
        admits(.video, "camera") { okCamera in
            guard self.wants(ticket) else { return }
            guard okCamera else { self.endRequest(); self.stopSession(); return }
            self.admits(.audio, "microphone") { okMicrophone in
                guard self.wants(ticket) else { return }
                guard okMicrophone else { self.endRequest(); self.stopSession(); return }
                self.sessionQueue.async { self.configureAndRun(ticket: ticket) }
            }
        }
        return true
    }
    /// A DOOR THIS APP MAY NOT OPEN IS NAMED, AND THE REFUSAL HAS A ROAD (28.09, the author's word: «recording a
    /// round note must ask for access to the camera»; on an iPhone 17 no circle showed at all). The note asked the
    /// platform blind and read only «yes»: a refusal -- or an answer given once, on another day, on a phone handed
    /// over with its switches already set -- ended the tape in silence, with no circle, no word, and nothing the
    /// person could do about it. The state is asked first: unasked -- the platform's own question; refused -- the
    /// platform's own alert with the one road to Settings (no road when the device's owner restricted the door,
    /// which this app's own Settings cannot lift); allowed -- straight through. Every answer is a line in the diary.
    private func admits(_ kind: AVMediaType, _ word: String, _ then: @escaping (Bool) -> Void) {
        let state = AVCaptureDevice.authorizationStatus(for: kind)
        MontanaTrace.mark("vnote_access", "\(word) status=\(state.rawValue)")
        switch state {
        case .authorized: then(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: kind) { ok in
                MontanaTrace.mark("vnote_access", "\(word) asked granted=\(ok ? 1 : 0)")
                DispatchQueue.main.async {
                    if !ok { Self.tellOff(kind) }
                    then(ok)
                }
            }
        default:
            DispatchQueue.main.async { Self.tellOff(kind); then(false) }
        }
    }
    private static func tellOff(_ kind: AVMediaType) {
        let title = kind == .video
            ? String(localized: "Camera is off for Montana", bundle: MTLanguage.bundle)
            : String(localized: "Microphone is off for Montana", bundle: MTLanguage.bundle)
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        if AVCaptureDevice.authorizationStatus(for: kind) == .denied {
            alert.addAction(UIAlertAction(title: String(localized: "Open Settings", bundle: MTLanguage.bundle), style: .default) { _ in MontanaSystemSettings.open() })
            alert.addAction(UIAlertAction(title: String(localized: "Cancel", bundle: MTLanguage.bundle), style: .cancel))
        } else {
            alert.addAction(UIAlertAction(title: String(localized: "OK", bundle: MTLanguage.bundle), style: .default))
        }
        MTTop.present(alert, kind: "alert")
    }
    func reset() { finished = nil; if !live { elapsed = 0 } }
    /// The tape is over, by whichever road: the one fact every screen reads.
    private func over() {
        MontanaScreenAwake.release("note")
        // The tape is over: the microphone road closes with it (28.09). The word is said ON THE MAIN THREAD, where
        // the owners of sound live -- this road ends on the writer's own queue, and the ledger asks the player and
        // the dock whether anything of ours still sounds before it lowers the session.
        MontanaAudioSession.release("video note")
        if live { live = false }
    }
    private func configureAndRun(ticket: Int) {
        guard wants(ticket) else { return }
        // The route is the system's (1583): a headset holds the microphone when it is connected -- unless
        // music plays, and then the headset keeps its full road and the phone's microphone hears (24.09).
        // The one recording door of the tree (the author's word 17.09): the same session as the
        // voice tape's; the capture session is told not to write its own over it.
        guard MontanaAudioSession.record("video note", keepMusic: keepMusic) else {
            endRequest(); stopSession(); return
        }
        if !configured {
            configured = true
            session.automaticallyConfiguresApplicationAudioSession = false
            session.beginConfiguration()
            if Self.dualCapable { wireBothCameras() } else {
                wireCamera(position: .front)
                videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                videoOut.alwaysDiscardsLateVideoFrames = true
                videoOut.setSampleBufferDelegate(self, queue: q)
                if session.canAddOutput(videoOut) { session.addOutput(videoOut) }
                orientOutput()
            }
            wireMicrophone()
            session.commitConfiguration()
        }
        applyQuality()
        refreshOrientation()
        frontConn?.isEnabled = front || dual
        backConn?.isEnabled = !front || dual
        guard wants(ticket) else { stopSession(); return }
        if !session.isRunning { session.startRunning() }
        // The finger may have lifted while the camera woke: nothing to record then.
        guard wants(ticket) else { stopSession(); return }
        // Born in its final form (480, H.264 High at the chosen rate, AAC); the finished note carries the
        // encoder's mark in its name (noteName) so the send road transcodes nothing (a transcode would drop
        // the badge timeline the file carries in its metadata — T1 → T2 on 1605: the badge cut at the rim).
        // The tape records under a WORKING name that no row ever wears: the note's name is minted once,
        // at the finish, when the badge and its corner are known.
        let name = "rec_\(UUID().uuidString).mov"
        fileName = name
        q.async {
            guard self.wants(ticket) else { return }
            self.openWriter(name)
        }
        DispatchQueue.main.async {
            guard self.wants(ticket) else { return }
            self.timer?.invalidate()
            // NATIVE-CHECKED: the length is the writer's own reading — the presentation stamps of the
            // frames (CMTime), as the voice's currentTime; the timer only asks it ten times a second.
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); let d = self.length; self.lock.unlock()
                self.elapsed = d
                if d >= Self.maxSeconds { self.finish() }   // the note's length
            }
        }
    }
    /// THE SOURCE AT THE CHOSEN STEP, AS HIGH AS THE HARDWARE CARRIES (the author's word 18.09):
    /// the single camera at the step's preset; the pair at the smallest multi-camera formats of
    /// the step's height — and when the pair's cost passes what the hardware carries, one step
    /// down, until it fits. The chosen formats and the cost go to the diary (vnote_format).
    private func applyQuality() {
        let want = MontanaNoteQuality.current
        guard configuredQuality != want else { return }
        var q: MontanaNoteQuality? = want
        while let step = q {
            session.beginConfiguration()
            if Self.dualCapable {
                for dev in [frontIn?.device, backIn?.device].compactMap({ $0 }) { pickPairFormat(dev, minHeight: step.minHeight) }
            } else if session.canSetSessionPreset(step.preset) {
                session.sessionPreset = step.preset
            }
            session.commitConfiguration()
            if let m = session as? AVCaptureMultiCamSession, m.hardwareCost > 1 { q = step.lower; continue }
            break
        }
        configuredQuality = want
        let dims = [frontIn?.device, backIn?.device, videoInput?.device].compactMap { $0 }.map { d -> String in
            let x = CMVideoFormatDescriptionGetDimensions(d.activeFormat.formatDescription); return "\(x.width)x\(x.height)"
        }.joined(separator: "+")
        MontanaTrace.mark("vnote_format", "heat=\(ProcessInfo.processInfo.thermalState.rawValue) \(want.rawValue) \(dims) cost=\((session as? AVCaptureMultiCamSession).map { String(format: "%.2f", $0.hardwareCost) } ?? "-")")
    }
    /// Multi-camera hardware: both cameras on the session at once, each at the smallest format
    /// the pair can run together, 24 frames a second, its own output, its own connection.
    private func wireBothCameras() {
        for (pos, out) in [(AVCaptureDevice.Position.front, frontOut), (.back, backOut)] {
            guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
                  let inp = try? AVCaptureDeviceInput(device: dev), session.canAddInput(inp) else { continue }
            pickPairFormat(dev)
            session.addInputWithNoConnections(inp)
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: q)
            guard session.canAddOutput(out) else { continue }
            session.addOutputWithNoConnections(out)
            guard let port = inp.ports(for: .video, sourceDeviceType: dev.deviceType, sourceDevicePosition: pos).first else { continue }
            let c = AVCaptureConnection(inputPorts: [port], output: out)
            guard session.canAddConnection(c) else { continue }
            session.addConnection(c)
            orient(c, device: dev, mirrored: pos == .front)
            if pos == .front { frontIn = inp; frontConn = c } else { backIn = inp; backConn = c }
        }
    }
    /// The note's calm 24 frames (the reference: preferLowerFramerate) are asked only of a format whose own
    /// range holds them: outside every range the system answers with an exception nothing here can catch
    /// (23.09, the critic -- the fallback camera asked it of any format, the pair camera already asked first).
    private static func holds24(_ f: AVCaptureDevice.Format) -> Bool {
        f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 24 && 24 <= $0.maxFrameRate }
    }
    private func pickPairFormat(_ dev: AVCaptureDevice, minHeight: Int32 = 720) {
        let supported = dev.formats.filter { $0.isMultiCamSupported }
        let calm = supported.filter { Self.holds24($0) }
        let pair = calm.isEmpty ? supported : calm
        func px(_ f: AVCaptureDevice.Format) -> Int {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription); return Int(d.width) * Int(d.height)
        }
        let tall = pair.filter { CMVideoFormatDescriptionGetDimensions($0.formatDescription).height >= minHeight }
        guard let f = (tall.isEmpty ? pair : tall).min(by: { px($0) < px($1) }), (try? dev.lockForConfiguration()) != nil else { return }
        dev.activeFormat = f
        if Self.holds24(f) {
            dev.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24)
            dev.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 24)
        }
        dev.unlockForConfiguration()
    }
    private func wireMicrophone() {
        guard let mic = AVCaptureDevice.default(for: .audio), let inp = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(inp) else { return }
        audioOut.setSampleBufferDelegate(self, queue: aq)
        if Self.dualCapable {
            session.addInputWithNoConnections(inp)
            guard session.canAddOutput(audioOut) else { return }
            session.addOutputWithNoConnections(audioOut)
            let ports = inp.ports(for: .audio, sourceDeviceType: mic.deviceType, sourceDevicePosition: .unspecified)
            let c = AVCaptureConnection(inputPorts: ports, output: audioOut)
            if session.canAddConnection(c) { session.addConnection(c) }
        } else {
            session.addInput(inp)
            if session.canAddOutput(audioOut) { session.addOutput(audioOut) }
        }
    }
    /// One camera (the fallback) on the session, inside a configuration: the old input leaves,
    /// the new one enters at the note's calm frame rate (the reference: preferLowerFramerate).
    private func wireCamera(position: AVCaptureDevice.Position) {
        if let old = videoInput { session.removeInput(old); videoInput = nil }
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let inp = try? AVCaptureDeviceInput(device: cam), session.canAddInput(inp) else { return }
        session.addInput(inp); videoInput = inp
        if (try? cam.lockForConfiguration()) != nil {
            if Self.holds24(cam.activeFormat) {
                cam.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24)
                cam.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 24)
            }
            cam.unlockForConfiguration()
        }
    }
    /// The output's connection: upright frames (the crop needs no orientation of its own),
    /// mirrored for the front camera as a person expects a mirror, straight for the back one.
    /// THE ANGLE IS THE CAMERA'S OWN (the author's word 18.09: the newest phone recorded the note
    /// sideways — its front sensor is mounted square, and a fixed quarter turn is not upright
    /// there): the platform's rotation coordinator names the angle that levels the horizon for
    /// this very camera as the phone is held now; the fixed quarter turn stays only where no
    /// device is known. Asked again at every hold, so the phone's hold at that moment counts.
    private var rotators: [ObjectIdentifier: AVCaptureDevice.RotationCoordinator] = [:]
    private func orient(_ c: AVCaptureConnection, device: AVCaptureDevice?, mirrored: Bool) {
        var angle: CGFloat = 90
        if let device {
            let r = rotators[ObjectIdentifier(device)] ?? AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            rotators[ObjectIdentifier(device)] = r
            angle = r.videoRotationAngleForHorizonLevelCapture
        }
        if c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
        if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = mirrored }
        MontanaTrace.mark("vnote_orient", "\(device?.position == .front ? "front" : "back") angle=\(Int(angle))")
    }
    private func orientOutput() {
        guard let c = videoOut.connection(with: .video) else { return }
        orient(c, device: videoInput?.device, mirrored: videoInput?.device.position == .front)
    }
    private func refreshOrientation() {
        if Self.dualCapable {
            if let c = frontConn { orient(c, device: frontIn?.device, mirrored: true) }
            if let c = backConn { orient(c, device: backIn?.device, mirrored: false) }
        } else { orientOutput() }
    }
    /// The modes on the two connections: the front alone, the back alone, or both.
    private func applyModes() {
        guard Self.dualCapable else { return }
        let f = front, d = dual
        sessionQueue.async {
            self.frontConn?.isEnabled = f || d
            self.backConn?.isEnabled = !f || d
            self.q.async { self.lastSmall = nil }
        }
    }
    /// Front ↔ back while the note records (the author's word 15.09): the writer keeps its clock,
    /// the frames simply come from the other side after the switch.
    func flip() {
        front.toggle()
        if Self.dualCapable { applyModes(); applyFlash(); MontanaTrace.mark("vnote_flip", front ? "front" : "back"); return }
        let toFront = front
        sessionQueue.async {
            guard self.configured, self.session.isRunning else { return }
            self.session.beginConfiguration()
            self.wireCamera(position: toFront ? .front : .back)
            self.orientOutput()
            self.session.commitConfiguration()
            self.applyFlash()
            MontanaTrace.mark("vnote_flip", toFront ? "front" : "back")
        }
    }
    /// Both cameras in one circle (the author's word 15.09): the back around, the front within.
    func toggleDual() {
        guard Self.dualCapable else { return }
        dual.toggle()
        if dual { front = false }   // both on: the back fills the circle, the front sits in the badge — the flip swaps them (18.09)
        usedDual = dual
        applyModes(); applyFlash()
        MontanaTrace.mark("vnote_dual", dual ? "on" : "off")
    }
    // ── the zoom of the big circle's camera: a pinch scales from where the last pinch left it
    private var zoomBase: CGFloat = 1
    private var bigDevice: AVCaptureDevice? {
        Self.dualCapable ? (front ? frontIn?.device : backIn?.device) : videoInput?.device
    }
    func pinch(_ scale: CGFloat) {
        let base = zoomBase
        sessionQueue.async {
            guard let dev = self.bigDevice, (try? dev.lockForConfiguration()) != nil else { return }
            dev.videoZoomFactor = max(1, min(min(dev.maxAvailableVideoZoomFactor, 8), base * scale))
            dev.unlockForConfiguration()
        }
    }
    func pinchEnded() {
        sessionQueue.async {
            let z = self.bigDevice?.videoZoomFactor ?? 1
            DispatchQueue.main.async { self.zoomBase = z }
        }
    }
    func toggleFlash() { flash.toggle(); applyFlash() }
    /// The light follows the side: the screen for the front camera, the torch for the back one —
    /// both when both cameras record.
    private func applyFlash() {
        let lit = flash && (front || dual)
        let torch = flash && (!front || dual)
        DispatchQueue.main.async {
            if lit, self.savedBrightness == nil, let sc = self.screen { self.savedBrightness = sc.brightness; sc.brightness = 1 }
            if !lit, let b = self.savedBrightness { self.screen?.brightness = b; self.savedBrightness = nil }
        }
        sessionQueue.async {
            let dev = Self.dualCapable ? self.backIn?.device : self.videoInput?.device
            guard let dev, dev.position == .back, dev.hasTorch, (try? dev.lockForConfiguration()) != nil else { return }
            dev.torchMode = torch && dev.isTorchModeSupported(.on) ? .on : .off
            dev.unlockForConfiguration()
        }
    }
    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen
    }
    private func openWriter(_ name: String) {
        let url = mediaTmpURL(name)
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mov) else { endRequest(); stopSession(); return }
        let n = Self.canvas
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: n, AVVideoHeightKey: n,
            // THE ENCODER AT THE CHOSEN STEP (the author's word 18.09): the High profile with CABAC, as the
            // reference encodes its round video (1 Mbit/s there); the rate is the quality step's
            // (0.9 / 1.5 / 2.5 Mbit/s); a key frame every two seconds, so a seek lands close and cheap.
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: MontanaNoteQuality.current.bitRate, AVVideoExpectedSourceFrameRateKey: 24,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                                              AVVideoMaxKeyFrameIntervalKey: 48]])
        v.expectsMediaDataInRealTime = true
        let a = AVAssetWriterInput(mediaType: .audio, outputSettings: MontanaVoiceSound.settings)   // the voice tape's sound, one setting ([C-1])
        a.expectsMediaDataInRealTime = true
        if w.canAdd(v) { w.add(v) }
        if w.canAdd(a) { w.add(a) }
        // THE PICTURE IS NEVER AT THE MERCY OF THE BADGE TRACK (T1 17:46, 17:48: the recorder's
        // writer died with -17771 on notes whose badge had moved): the recorder writes the picture
        // and the sound alone; the badge's words are kept here and written into the finished file
        // by a second pass — and if that pass fails, the note leaves without the track.
        badgeWords = []; badgeWordWritten = nil
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: v, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: n, kCVPixelBufferHeightKey as String: n])
        writer = w; videoIn = v; audioIn = a
        lock.lock(); firstPTS = nil; stopping = false; standing = false; shift = .zero; length = 0; soundSeconds = 0; soundDropped = 0; lock.unlock()
        lastPTS = nil; pauseAt = nil; resumeFix = false; lastSource = nil
        badgeNow = Self.cornerOffset(corner); badgeTarget = nil
        DispatchQueue.main.async { self.usedDual = self.dual; self.zoomBase = 1; self.badgeOffset = Self.cornerOffset(self.corner); self.paused = false }
        for dev in [frontIn?.device, backIn?.device, videoInput?.device].compactMap({ $0 }) where dev.videoZoomFactor != 1 {
            if (try? dev.lockForConfiguration()) != nil { dev.videoZoomFactor = 1; dev.unlockForConfiguration() }
        }
        lock.lock(); recording = true; lock.unlock()
    }
    /// A frame → a square of the given side: scale by the short edge, cut the centre.
    private func square(_ src: CIImage, _ n: CGFloat) -> CIImage {
        let scale = n / min(src.extent.width, src.extent.height)
        let img = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (img.extent.width - n) / 2, dy = (img.extent.height - n) / 2
        return img.transformed(by: CGAffineTransform(translationX: -img.extent.minX - dx, y: -img.extent.minY - dy))
            .cropped(to: CGRect(x: 0, y: 0, width: n, height: n))
    }
    /// One frame → the canvas: the circle of the note's side in the middle, over the blurred
    /// darkened copy that fills the canvas — the reference's filter, step by step.
    private func circled(_ src: CIImage) -> CIImage {
        let N = CGFloat(Self.canvas), n = CGFloat(Self.side)
        let ground = square(src, N)
        let blurred = ground.clampedToExtent().applyingGaussianBlur(sigma: 30).cropped(to: ground.extent)
        let dark = blurred.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.25, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.25, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.25, w: 0)])
        let img = square(src, n).transformed(by: CGAffineTransform(translationX: (N - n) / 2, y: (N - n) / 2))
        return img.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: dark, kCIInputMaskImageKey: mask])
    }
    /// Both cameras: one fills the circle, the other sits on its rim in the chosen corner as a
    /// notification badge on an app icon (the author's word 15.09) — a smaller circle, a third of it
    /// inside the big circle, the rest past it into the canvas's room, in front; no dark rim round it,
    /// the same clean edge as the big one (the author's word 24.09).
    /// WHICH IS WHICH IS THE FLIP'S (the author's word 18.09): `front` names the camera in the big
    /// circle — the back by default, the front after the middle button or a tap on the window.
    private func nested(big: CIImage, small: CIImage) -> CIImage {
        let outer = circled(big)
        let n = CGFloat(Self.inner), N = CGFloat(Self.canvas)
        easeBadge()
        let at = badgeNow                                         // at its corner, under the finger, or on its way
        let x = N / 2 + at.x - n / 2, y = N / 2 - at.y - n / 2   // CoreImage's origin is bottom-left
        let clear = CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: n, height: n))
        let inner = square(small, n).applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: innerMask])
            .transformed(by: CGAffineTransform(translationX: x, y: y))
        return inner.composited(over: outer)
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if output === audioOut {
            // The sound comes on its own queue: the gate and the append stand under the lock, so
            // the writer is never finished under a sample on its way in.
            lock.lock(); defer { lock.unlock() }
            guard recording, !stopping, !standing, firstPTS != nil, let a = audioIn else { return }
            guard a.isReadyForMoreMediaData else { soundDropped += 1; return }
            var moved: CMSampleBuffer? = sampleBuffer
            if shift != .zero {
                // The sound's clock is shifted as the frames' is: a copy with the moved timing.
                var count = 0
                CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
                var infos = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
                CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &infos, entriesNeededOut: &count)
                for i in infos.indices {
                    infos[i].presentationTimeStamp = CMTimeSubtract(infos[i].presentationTimeStamp, shift)
                    if infos[i].decodeTimeStamp.isValid { infos[i].decodeTimeStamp = CMTimeSubtract(infos[i].decodeTimeStamp, shift) }
                }
                moved = nil
                CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sampleBuffer, sampleTimingEntryCount: count, sampleTimingArray: &infos, sampleBufferOut: &moved)
            }
            if let moved, a.append(moved) {
                let d = CMSampleBufferGetDuration(sampleBuffer).seconds
                if d.isFinite { soundSeconds += d }
            } else { soundDropped += 1 }
            return
        }
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let img = CIImage(cvPixelBuffer: pb)
        if Self.dualCapable {
            if dual {
                // The big circle's camera composes the frame; the badge's camera only leaves its latest.
                let big = (output === frontOut) == front
                if big { if let s = lastSmall { emit(nested(big: img, small: s), pts) } }
                else if output === frontOut || output === backOut { lastSmall = img }
            } else if (output === frontOut) == front, output === frontOut || output === backOut {
                emit(circled(img), pts)
            }
        } else if output === videoOut {
            emit(circled(img), pts)
        }
    }
    /// One composed frame: to the file while it records (and the tape is not standing), to the
    /// window always.
    private func emit(_ frame: CIImage, _ source: CMTime) {
        lastSource = source
        // ONE COMPOSITION A FRAME (28.09, the author's word: «check why an iPhone 17 began to heat up badly»). The
        // circle -- two cameras, the disc mask, the badge nested in the rim -- was composed TWICE for every frame:
        // once into the file's buffer and once more into the picture the window shows, twenty-four times a second.
        // The window now takes the very buffer the file took, and composes on its own only while nothing is written.
        var window = frame
        if recording, !stopping, !standing, let w = writer, let v = videoIn, let ad = adaptor {
            let pts = fileTime(source)
            if firstPTS == nil, w.startWriting() { w.startSession(atSourceTime: pts); lock.lock(); firstPTS = pts; lock.unlock() }
            // The two cameras run their own pipelines: when the frames start coming from the
            // other one (dual on, a flip) its first frame can carry a moment EARLIER than the last
            // written — a frame back in time kills the writer (T1 17:39, the dual note never left).
            // Such a frame is shown and not written.
            let late = lastPTS.map { CMTimeCompare(pts, $0) <= 0 } ?? false
            if firstPTS != nil, !late, v.isReadyForMoreMediaData, let pool = ad.pixelBufferPool {
                var out: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
                if let dst = out {
                    ci.render(frame, to: dst)
                    window = CIImage(cvPixelBuffer: dst)   // composed once: the window shows what the file took
                    if ad.append(dst, withPresentationTime: pts) {
                        lastPTS = pts
                        if let f = firstPTS { lock.lock(); length = CMTimeSubtract(pts, f).seconds; lock.unlock() }
                        writeBadgeWord(at: pts)
                    }
                }
            }
        }
        lock.lock()
        let show = requested && !previewPending
        let ticket = request
        if show { previewPending = true }
        lock.unlock()
        guard show else { return }
        guard let cg = ci.createCGImage(window, from: window.extent) else {
            lock.lock(); previewPending = false; lock.unlock(); return
        }
        DispatchQueue.main.async {
            if self.wants(ticket) {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                self.previewLayer?.contents = cg
                CATransaction.commit()
            }
            self.lock.lock(); self.previewPending = false; self.lock.unlock()
        }
    }
    /// The badge's word at this moment, kept when it changes (the first frame keeps the first).
    private func writeBadgeWord(at pts: CMTime) {
        let word = Self.badgeWord(dual ? badgeNow : nil)
        guard word != badgeWordWritten else { return }
        badgeWords.append((CMTimeSubtract(pts, firstPTS ?? pts), word)); badgeWordWritten = word
    }
    func finish() { endRequest(); lightOff(); q.async { self.closeWriter() } }
    func cancel() { endRequest(); cancelled = true; lightOff(); q.async { self.closeWriter() } }
    private func lightOff() { DispatchQueue.main.async { if self.flash { self.flash = false; self.applyFlash() } } }
    private func closeWriter() {
        guard recording, !stopping else { if !recording && !stopping { stopSession() }; return }
        lock.lock(); stopping = true; recording = false; lock.unlock()
        let name = fileName
        let finalCorner = usedDual ? corner : nil
        let keep = !cancelled && firstPTS != nil && length >= 0.6
        guard let w = writer, w.status == .writing else {
            MontanaTrace.mark("vnote_close", "writer=\(writer?.status.rawValue ?? -1) err=\(writer?.error.map { "\($0)" } ?? "-") len=\(Int(length))")
            stopSession(); try? FileManager.default.removeItem(at: mediaTmpURL(name))
            return
        }
        videoIn?.markAsFinished(); audioIn?.markAsFinished()
        w.finishWriting { [weak self] in
            guard let self else { return }
            let ok = keep && w.status == .completed && FileManager.default.fileExists(atPath: mediaTmpURL(name).path)
            MontanaTrace.mark("vnote_close", "ok=\(ok ? 1 : 0) keep=\(keep ? 1 : 0) status=\(w.status.rawValue) err=\(w.error.map { "\($0)" } ?? "-") len=\(Int(length)) dual=\(self.usedDual ? 1 : 0) snd=\(String(format: "%.1f", self.soundSeconds)) drop=\(self.soundDropped)")
            if !ok { try? FileManager.default.removeItem(at: mediaTmpURL(name)) }
            let words = self.badgeWords
            self.writer = nil; self.videoIn = nil; self.audioIn = nil; self.adaptor = nil
            self.stopSession()
            // The recorder is free the moment its file is complete (the second pass below can
            // never hold it — T1 18:01: a pass that hung kept busy and every next note was refused).
            guard ok else { return }
            // The second pass: the badge timeline into the finished file — only when a badge was
            // ever there; a failure leaves the file as it is (the window then shows no badge).
            let deliver: () -> Void = {
                DispatchQueue.main.async {
                    // A note that ends with the badge says so in its name — every reader here draws
                    // the window with the badge; older builds see the prefix they know and a plain circle.
                    // The tape takes its one name now (noteName): the working name never reaches a row.
                    let final = Self.noteName(badgeCorner: finalCorner)
                    guard (try? FileManager.default.moveItem(at: mediaTmpURL(name), to: mediaTmpURL(final))) != nil else {
                        MontanaTrace.mark("vnote_close", "the tape could not take its name — nothing to hand over")
                        try? FileManager.default.removeItem(at: mediaTmpURL(name))
                        return
                    }
                    self.finished = final
                }
            }
            if words.contains(where: { $0.1 != "-" }) {
                MontanaNoteBadgeTrack.write(words, into: mediaTmpURL(name)) { MontanaTrace.mark("vnote_track", $0); deliver() }
            } else { deliver() }
        }
    }
    private func stopSession() {
        lock.lock(); let ticket = request; lock.unlock()
        DispatchQueue.main.async {
            guard self.isRequest(ticket) else { return }
            self.timer?.invalidate(); self.timer = nil; self.previewLayer?.contents = nil
        }
        sessionQueue.async {
            guard self.isRequest(ticket) else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                guard self.isRequest(ticket) else { return }
                self.over(); self.busy = false
            }
        }
    }
}

/// THE BADGE TIMELINE, WRITTEN BY THE SYSTEM'S OWN PASS (T1 18:32, 18:43, 18:47 on 1607–1609:
/// a timed metadata track appended by hand died with -17771 on the phone every time, in the
/// live writer and in a second writer alike, while the Mac took both): the finished note goes
/// through the system's passthrough export — the compressed picture and sound copied as they
/// are — with the badge's words as ONE static metadata item of the file («ms:word;ms:word;…»,
/// the word «x,y» in file pixels, y down, or «-» for none). Static metadata is the road every
/// export and every reader knows; nothing is appended by hand. The pass has a deadline; whatever
/// its outcome, the note leaves — with the timeline when the export says «completed».
enum MontanaNoteBadgeTrack {
    private static let q = DispatchQueue(label: "montana.note.track")
    static func line(_ words: [(CMTime, String)]) -> String {
        words.map { "\(Int(($0.0.seconds * 1000).rounded())):\($0.1)" }.joined(separator: ";")
    }
    static func write(_ words: [(CMTime, String)], into url: URL, done: @escaping (String) -> Void) {
        q.async {
            let out = url.deletingPathExtension().appendingPathExtension("track.mov")
            try? FileManager.default.removeItem(at: out)
            guard let ex = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetPassthrough) else { done("no-export"); return }
            ex.outputURL = out; ex.outputFileType = .mov
            let item = AVMutableMetadataItem()
            item.identifier = AVMetadataIdentifier(rawValue: MontanaVideoNoteCamera.badgeMetaID)
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            item.value = line(words) as NSString
            ex.metadata = [item]
            let fin = DispatchSemaphore(value: 0)
            ex.exportAsynchronously { fin.signal() }
            guard fin.wait(timeout: .now() + 30) == .success else {
                ex.cancelExport(); try? FileManager.default.removeItem(at: out); done("timeout"); return
            }
            guard ex.status == .completed else {
                try? FileManager.default.removeItem(at: out)
                done("failed \(ex.status.rawValue) \(ex.error.map { "\($0)" } ?? "")"); return
            }
            if (try? FileManager.default.replaceItemAt(url, withItemAt: out)) != nil { done("ok words=\(words.count)") }
            else { try? FileManager.default.removeItem(at: out); done("replace-failed") }
        }
    }
    /// The timeline read back, in the circle's measure: each word from its moment to the next,
    /// the last to the end; empty when the file carries none.
    static func read(_ url: URL, _ done: @escaping ([(CMTimeRange, CGPoint?)]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: url)
            let end = asset.duration
            var out: [(CMTimeRange, CGPoint?)] = []
            if let s = asset.metadata.first(where: { $0.identifier?.rawValue == MontanaVideoNoteCamera.badgeMetaID })?.value as? String {
                let side = CGFloat(MontanaVideoNoteCamera.side)
                let words: [(CMTime, CGPoint?)] = s.split(separator: ";").compactMap { e in
                    let p = e.split(separator: ":", maxSplits: 1)
                    guard p.count == 2, let ms = Double(p[0]) else { return nil }
                    return (CMTime(seconds: ms / 1000, preferredTimescale: 600),
                            MontanaVideoNoteCamera.badgePlace(String(p[1])).map { CGPoint(x: $0.x / side, y: $0.y / side) })
                }
                for (k, w) in words.enumerated() {
                    let next = k + 1 < words.count ? words[k + 1].0 : end
                    out.append((CMTimeRange(start: w.0, end: next), w.1))
                }
            }
            DispatchQueue.main.async { done(out) }
        }
    }
}

/// THE DOCUMENT PAGE (the author's word 19.09: «the whole screen; out by the edge swipe or the
/// platform's own cross»): a page in the sliding slot over EVERYTHING (UIState.docPage — above the
/// tabs and the open chat), the platform's viewer (QLPreviewController) inside a navigation
/// controller of ours: the bar is the platform's — its close item on the left (the system's own
/// circled cross), the document's name as the title, the viewer's own share on the right — and the
/// edge swipe of the slot closes it too. The viewer is handed a link named by the document's REAL
/// name (MTDocLink): the type is told by the name, the title is the name. The absent file (legacy
/// of the old storage) shows a clear line with the same way out.
struct DocPreview: View {
    let file: String
    var title: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.montanaClose) private var montanaClose
    private func leave() { mtLeavePage(montanaClose, dismiss) }
    @State private var url: URL?
    @State private var searched = false
    private var name: String { title ?? file }

    var body: some View {
        Group {
            if let u = url {
                DocPreviewQL(items: [DocPreviewQL.Entry(url: u, title: name)], onClose: leave).ignoresSafeArea()
            } else if searched {
                VStack(spacing: 0) {
                    HStack { MontanaCloseMark { leave() }; Spacer() }.padding(.horizontal, 4).frame(height: 52)
                    VStack(spacing: 14) {
                        Image(systemName: "doc.questionmark").font(.system(size: 44)).foregroundColor(.gray)
                        Text("The file is not on this device. Ask the sender to send it again.")
                            .multilineTextAlignment(.center).foregroundColor(.gray).padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else { Color.black }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // A ready file is served at once; the legacy search through the archive leaves the
        // main thread — it walks conversations and reads from disk, and on the main thread
        // that is a frozen screen.
        .task {
            let f = file, n = name
            let found = await Task.detached(priority: .userInitiated) { () -> URL? in
                guard let u = mtMediaFileURL(f) ?? MontanaMediaVault.playableURL(f) else { return nil }
                return MTDocLink.named(u, as: n)
            }.value
            url = found; searched = true
        }
    }
}

/// THE FILE UNDER ITS OWN NAME (the reference's way): the store keeps a document under a hashed
/// name; the viewer and the share sheet are handed a hard link (a copy when linking is refused)
/// named as the person named it, so the type comes from the real name and the title reads right.
/// One link per document, remade on every open; the folder is the temporary one.
enum MTDocLink {
    private static var dir: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("MontanaDocLinks", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    /// The deleted document's links go with it (a deleted letter leaves nothing behind).
    static func forget(_ file: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(file, isDirectory: true))
    }
    static func named(_ src: URL, as name: String) -> URL {
        var clean = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        if clean.isEmpty { clean = src.lastPathComponent }
        if (clean as NSString).pathExtension.isEmpty, !src.pathExtension.isEmpty { clean += "." + src.pathExtension }
        let dst = dir.appendingPathComponent(src.lastPathComponent, isDirectory: true).appendingPathComponent(clean)
        try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dst)
        if (try? FileManager.default.linkItem(at: src, to: dst)) == nil {
            guard (try? FileManager.default.copyItem(at: src, to: dst)) != nil else { return src }
        }
        return dst
    }
}

/// THE FILE'S FACE (the author's word 19.09: «a big, coloured, native icon for a PDF»): the tile the
/// bubble and the files list draw for a document. The platform's own thumbnailer draws it — first
/// the system's icon for the type, then the document's real first page (a PDF, a text, a sheet) —
/// the same picture the Files app shows; a badge with the type's word in the type's colour stands
/// on the tile's corner (red for PDF and slides, green for sheets, amber for archives, blue else —
/// the colours the reference gives its files). Until a picture lands, or when none can be drawn,
/// the coloured plate carries the word alone. Every picture is asked once and kept.
struct MTFileIcon: View {
    let file: String
    let name: String
    var width: CGFloat = 64
    var height: CGFloat = 80
    @State private var picture: UIImage?
    @Environment(\.displayScale) private var displayScale   // the window's own scale, not the shared screen's
    private static let cache: NSCache<NSString, UIImage> = MontanaCaches.kept("feed-pictures")
    private var ext: String {
        let e = (name as NSString).pathExtension
        return (e.isEmpty ? (file as NSString).pathExtension : e).lowercased()
    }
    static func colours(_ ext: String) -> [Color] {
        switch ext {
        case "pdf", "ppt", "pptx", "key": return [Color(red: 1.0, green: 0.53, blue: 0.37), Color(red: 1.0, green: 0.31, blue: 0.41)]
        case "xls", "xlsx", "csv", "numbers": return [Color(red: 0.60, green: 0.87, blue: 0.44), Color(red: 0.37, green: 0.72, blue: 0.31)]
        case "zip", "rar", "gz", "gzip", "7z", "ai": return [Color(red: 1.0, green: 0.64, blue: 0.29), Color(red: 0.93, green: 0.44, blue: 0.36)]
        default: return [Color(red: 0.45, green: 0.84, blue: 0.99), Color(red: 0.16, green: 0.62, blue: 0.95)]
        }
    }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(width, height) * 0.18, style: .continuous)
        let word = ext.isEmpty ? "" : ext.uppercased()
        ZStack(alignment: .bottomLeading) {
            if let picture {
                Image(uiImage: picture).resizable().scaledToFill()
                    .frame(width: width, height: height).clipShape(shape)
                    .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            } else {
                shape.fill(LinearGradient(colors: Self.colours(ext), startPoint: .top, endPoint: .bottom))
                    .frame(width: width, height: height)
                    .overlay {
                        Text(verbatim: word)   // USER-DATA: the file's own type word
                            .font(.system(size: width * 0.26, weight: .bold, design: .rounded)).foregroundColor(.white)
                            .minimumScaleFactor(0.5).lineLimit(1).padding(4)
                    }
            }
            if picture != nil, !word.isEmpty {
                Text(verbatim: word)   // USER-DATA: the file's own type word
                    .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(LinearGradient(colors: Self.colours(ext), startPoint: .top, endPoint: .bottom), in: Capsule())
                    .padding(4)
            }
        }
        .frame(width: width, height: height)
        .task(id: file + "|" + String(fileOnDisk(file))) {
            let f = file, n = name, w = width, h = height, sc = displayScale
            if let c = Self.cache.object(forKey: f as NSString) { picture = c; return }
            guard let src = mtMediaFileURL(f) else { return }
            let url = await Task.detached { MTDocLink.named(src, as: n) }.value
            let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: w, height: h),
                                                   scale: sc, representationTypes: [.icon, .thumbnail])
            for await img in Self.pictures(req) {
                Self.cache.setObject(img, forKey: f as NSString); picture = img
            }
        }
    }
    /// The thumbnailer's answers as they come — the icon at once, the page when drawn.
    private static func pictures(_ req: QLThumbnailGenerator.Request) -> AsyncStream<UIImage> {
        AsyncStream { cont in
            // The generator is cancelled ONLY when the consumer leaves (the tile's task cancelled): a
            // cancel on finish ran inside the generator's own callback, on its own queue — a trap
            // (T1 19.09 21:51Z, signal 5 under MTFileIcon.pictures at the stream's finish).
            cont.onTermination = { reason in if case .cancelled = reason { QLThumbnailGenerator.shared.cancel(req) } }
            QLThumbnailGenerator.shared.generateRepresentations(for: req) { rep, type, _ in
                if let rep { cont.yield(rep.uiImage) }
                if type == .thumbnail { cont.finish() }   // the last of the asked types, drawn or refused
            }
        }
    }
}

/// The platform's viewer in a navigation controller of ours: the bar is the platform's own — the
/// system close item on the left, the name in the middle, the viewer's share on the right.
/// SEVERAL ITEMS, ONE VIEWER (25.09, the gallery's moments): the items are handed by their index as the viewer asks, it
/// opens at the asked one and pages between them -- the platform's own swipe, pinch and player, as the phone's photos.
struct DocPreviewQL: UIViewControllerRepresentable {
    struct Entry { let url: URL; let title: String }
    let items: [Entry]
    var index = 0
    let onClose: () -> Void
    func makeUIViewController(context: Context) -> UINavigationController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        c.currentPreviewItemIndex = min(max(0, index), max(0, items.count - 1))
        c.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in onClose() })
        let nav = UINavigationController(rootViewController: c)
        nav.overrideUserInterfaceStyle = .dark
        nav.view.backgroundColor = .black
        return nav
    }
    func updateUIViewController(_ c: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    /// The item carries the document's name as its title.
    final class Item: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?
        init(url: URL, title: String) { previewItemURL = url; previewItemTitle = title }
    }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let items: [Entry]
        private var made: [Int: Item] = [:]   // an item once made is the same object on every ask
        init(items: [Entry]) { self.items = items }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { items.count }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            if let have = made[index] { return have }
            let e = items[index]
            let it = Item(url: e.url, title: e.title)
            made[index] = it
            return it
        }
    }
}

/// THE MOMENTS' VIEWER (the author's word 25.09: «take the feed out of the gallery; viewing as native as it gets, as the
/// phone's photos»): the platform's own viewer (QLPreviewController) over the whole gallery of moments, opened at the tapped
/// one -- the swipe between the moments, the pinch, the system's player for a video, the share on the bar -- inside the
/// sliding page over everything, with the page's own close on the left; the edge swipe closes it like every page. A file
/// whose name carries no type is handed under a name that does (MTDocLink), so the viewer knows what it holds.
struct MTMomentsViewer: View {
    let moments: [MTMoment]
    let initial: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.montanaClose) private var montanaClose
    private func leave() { mtLeavePage(montanaClose, dismiss) }
    var body: some View {
        let at = moments.firstIndex { $0.id == initial } ?? 0
        DocPreviewQL(items: moments.map { m in DocPreviewQL.Entry(url: Self.typed(m), title: m.caption) }, index: at, onClose: leave)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onAppear {
                let photo = moments.indices.contains(at) && moments[at].photo
                // A video speaks through the movie session, as the feed's clips did (the platform's player takes the session as it is).
                if moments.contains(where: { !$0.photo }) { MontanaAudioSession.activatePlayback() }
                MontanaTrace.mark("gallery_view", "moments=\(moments.count) at=\(at) photo=\(photo ? 1 : 0)")
            }
    }
    /// The file under a name with its type, when its own name has none (the viewer tells the type by the name).
    private static func typed(_ m: MTMoment) -> URL {
        guard m.url.pathExtension.isEmpty else { return m.url }
        return MTDocLink.named(m.url, as: m.id + (m.photo ? ".jpg" : ".mp4"))
    }
}
