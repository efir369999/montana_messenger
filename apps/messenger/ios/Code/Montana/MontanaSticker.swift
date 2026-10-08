import SwiftUI
import UIKit
import Vision
import CoreImage
import ImageIO

/// THE SUBJECT IS THE PLATFORM'S OWN WORK (the author's word 22.09: a region copied out of a
/// photograph has to leave as a sticker).
///
/// A pasted picture is called a sticker by its transparency alone (MontanaMedia.hasTransparency,
/// 10.09) -- and a region cut out of a photograph is OPAQUE, so it left as a photograph and stood
/// in a bubble. The platform carries the answer itself: VNGenerateForegroundInstanceMaskRequest
/// lifts the foreground instances off the background -- the very mechanism the system's own «lift
/// subject» uses. The deployment target of this app is 17.2, so every phone of ours has it:
/// nothing is downloaded, no model of ours is trained, no library is added.
///
/// The cut is OFFERED, never forced: an opaque paste stays a photograph until the person points at
/// the subject's miniature. Deciding for them would turn every pasted photograph into a sticker.
enum MontanaStickerCut {
    /// The long side of a sticker that rides. Everything above is scaled down to it; nothing is
    /// scaled up -- an enlarged cut is a blur, not a sticker.
    static let side: CGFloat = 512

    /// The foreground of a picture on a transparent ground, or nil when the platform finds none.
    /// Heavy work: never called on the screen's thread.
    static func subject(of image: UIImage) -> UIImage? {
        guard let cg = upright(image).cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            MontanaTrace.mark("sticker_cut", "the platform refused the picture")
            return nil
        }
        guard let found = request.results?.first, !found.allInstances.isEmpty,
              let masked = try? found.generateMaskedImage(ofInstances: found.allInstances,
                                                          from: handler,
                                                          croppedToInstancesExtent: true) else {
            MontanaTrace.mark("sticker_cut", "no subject in the picture")
            return nil
        }
        let ci = CIImage(cvPixelBuffer: masked)
        guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
        let cut = fit(UIImage(cgImage: out))
        MontanaTrace.mark("sticker_cut", "subject \(Int(cut.size.width))x\(Int(cut.size.height))")
        return cut
    }

    /// The picture with its turns already applied: the mask request reads pixels, not orientation.
    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Down to the sticker canvas, keeping the shape of the cut. Never up.
    static func fit(_ image: UIImage, side: CGFloat = MontanaStickerCut.side) -> UIImage {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0, side < max(w, h) else { return image }
        let k = side / max(w, h)
        let size = CGSize(width: (w * k).rounded(), height: (h * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// A STICKER IS LIGHT OR IT IS NOT A STICKER (the author's word 22.09). A cut of a photograph
    /// written as PNG weighs half a megabyte: PNG keeps photographic pixels losslessly, and a cut
    /// of a photograph is photographic almost always. The reference keeps its stickers in WebP and
    /// carries an encoder of its own for it; ImageIO READS WebP but does not WRITE it (measured:
    /// CGImageDestinationCopyTypeIdentifiers holds heic, png, jpeg -- no webp), so the platform's
    /// own light format with transparency is HEIC.
    ///
    /// Measured on a 512-point cut with a soft edge and photographic pixels:
    ///   PNG 575 KB - HEIC q0.9 129 KB - q0.8 81 KB - q0.7 61 KB.
    /// Eight tenths is taken: seven times lighter, the edge still clean. A phone that cannot write
    /// HEIC falls back to PNG -- lighter is better, broken is not an option.
    static let quality: CGFloat = 0.8

    static func encode(_ image: UIImage) -> Data? {
        if let heic = heicData(image, quality: quality), !heic.isEmpty { return heic }
        return image.pngData()
    }

    /// The suffix those bytes deserve: a name tells the truth about what lies under it.
    static func suffix(for data: Data) -> String {
        guard data.count > 12 else { return "png" }
        let tag = data.subdata(in: 4..<12)
        return String(data: tag, encoding: .ascii)?.hasPrefix("ftyp") == true ? "heic" : "png"
    }

    private static func heicData(_ image: UIImage, quality: CGFloat) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, "public.heic" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return out as Data
    }
}

/// MY OWN STICKERS AND THE SETS TAKEN FROM OTHERS -- ONE BOOK, ONE OWNER ([C-1]).
///
/// A sticker this phone made is filed under the name it is born with, and that name never changes
/// while the sticker lives (the rule of 22.09: the key a thing is looked up by does not move under
/// it). The book holds the ORDER and nothing else; the pictures lie in the media store beside every
/// other picture of the app, so they are protected, kept out of the backup and swept by the same
/// hand. The ceiling is a person's set, not a warehouse: the oldest leaves with its file.
///
/// The set's own NAME is born once too: sha256(this phone's address, sixteen bytes of its own
/// randomness). Nobody else can mint that name, no register hands it out, nothing has to be asked
/// of anybody -- and it does not move when a sticker is added, because the set is the same set.
///
/// The book is not pinned to an actor: it is a list of names over the media store, and every hand
/// that writes it already stands on the screen's thread.
final class MontanaStickerBook: ObservableObject {
    static let shared = MontanaStickerBook()
    /// The set's ceiling: a person's own set, not a warehouse.
    static let ceiling = 120
    private static let shelf = "montana.stickers.mine"
    private static let idKey = "montana.stickers.packid"
    private static let packsKey = "montana.stickers.packs"
    private static let portsKey = "montana.stickers.passports"
    private static let giversKey = "montana.stickers.givers"
    private static let idsKey = "montana.stickers.ids"

    /// A set taken from another person: its name, who owns it, and the stickers that have arrived.
    struct Pack: Codable, Identifiable {
        let id: String
        var title: String
        var owner: String
        var names: [String]
        var expected: Int
    }
    /// What a sticker letter says about itself: the set it belongs to, the sticker, the glyph, and
    /// the letter it answers -- a sticker sent as a reply carries its quote here, because the
    /// picture road carries none (22.09).
    struct Passport: Codable {
        let pack: String
        let sticker: String
        var emoji: String
        var title: String
        var owner: String
        var quote: String = ""
        var quoteMid: String = ""
    }

    @Published private(set) var names: [String] = []
    @Published private(set) var packs: [Pack] = []
    private var passports: [String: Passport] = [:]
    private var givers: [String: String] = [:]
    /// THE BOOK KNOWS A STICKER BY ITS BYTES WITHOUT READING THE DISK (the critic 22.09): asking
    /// «do I already hold this picture» by reading every file of the set cost a hundred and twenty
    /// file reads -- seven megabytes off the disk on the screen's thread -- for every sticker sent
    /// or received. The content name of each sticker is written down once, at its birth, and the
    /// question is answered from memory.
    private var ids: [String: String] = [:]

    private init() { load() }
    /// The shelves as the store holds them — at birth, and again when a copy was laid under them (23.09):
    /// kept from the moment before, the next sticker added would write the old shelf over the restored one.
    func reread() { load() }
    private func load() {
        let d = UserDefaults.standard
        names = (d.stringArray(forKey: Self.shelf) ?? []).filter { MontanaMediaStore.exists($0) }
        packs = (d.data(forKey: Self.packsKey).flatMap { try? JSONDecoder().decode([Pack].self, from: $0) }) ?? []
        passports = (d.data(forKey: Self.portsKey).flatMap { try? JSONDecoder().decode([String: Passport].self, from: $0) }) ?? [:]
        givers = (d.dictionary(forKey: Self.giversKey) as? [String: String]) ?? [:]
        ids = (d.dictionary(forKey: Self.idsKey) as? [String: String]) ?? [:]
        // A book written before this index fills it once, in the background: the screen never waits
        // for the disk, and until it is filled the only cost is a sticker filed twice.
        if ids.isEmpty, !names.isEmpty {
            let known = names
            DispatchQueue.global(qos: .utility).async {
                var found: [String: String] = [:]
                for n in known {
                    if let data = try? Data(contentsOf: MontanaMediaStore.url(n)) {
                        found[MontanaMedia.blobIdHex(data)] = n
                    }
                }
                DispatchQueue.main.async {
                    for (k, v) in found where self.ids[k] == nil { self.ids[k] = v }
                    self.save()
                }
            }
        }
    }

    // -- my own set -------------------------------------------------------------------------

    /// The name of this phone's set, minted once and never moved.
    var mineId: String {
        let d = UserDefaults.standard
        if let known = d.string(forKey: Self.idKey), !known.isEmpty { return known }
        let born = MontanaStickerPack.mint(owner: MontanaPhoneNode.myRef())
        d.set(born, forKey: Self.idKey)
        return born
    }

    /// A name born once: eight bytes of the app's own randomness and the suffix of what it is.
    static func mintName(suffix: String = "heic") -> String {
        "stk_" + montanaRandom(8).map { String(format: "%02x", $0) }.joined() + "." + suffix
    }

    /// A picture already lying in the media store joins the book under a name of its own -- the
    /// bytes are copied, so a letter's file may be swept without taking the set's sticker with it.
    @discardableResult
    func adopt(file: String) -> String? {
        guard let data = try? Data(contentsOf: MontanaMediaStore.url(file)) else { return nil }
        return add(png: data)
    }

    /// A STICKER USED IS A STICKER KEPT, AND KEPT ONCE (the author's word 22.09). The same picture
    /// used again does not breed a second copy: it is the same sticker, and it moves to the front,
    /// where the panel's strip shows what the hand reaches for. The name minted at its birth stays
    /// with it -- only its place in the row changes.
    @discardableResult
    func add(png: Data) -> String? {
        let id = MontanaMedia.blobIdHex(png)
        if let known = ids[id], names.contains(known) {
            if names.first != known {
                names.removeAll { $0 == known }
                names.insert(known, at: 0)
                save()
            }
            return known
        }
        let name = Self.mintName(suffix: MontanaStickerCut.suffix(for: png))
        guard MontanaMediaStore.put(name, data: png) else {
            MontanaTrace.mark("sticker_book", "FAIL store")
            return nil
        }
        names.insert(name, at: 0)
        ids[id] = name
        while Self.ceiling < names.count, let last = names.last {
            names.removeLast()
            ids = ids.filter { $0.value != last }
            MontanaMediaStore.remove([last])
        }
        save()
        MontanaTrace.mark("sticker_book", "add n=\(names.count) bytes=\(png.count)")
        return name
    }

    func forget(_ name: String) {
        guard names.contains(name) else { return }
        names.removeAll { $0 == name }
        ids = ids.filter { $0.value != name }
        MontanaMediaStore.remove([name])
        save()
        MontanaTrace.mark("sticker_book", "forget n=\(names.count)")
    }

    /// The sticker's own name inside a set: the content itself, so two phones that hold the same
    /// picture hold the same sticker and nothing is stored twice.
    func stickerId(of name: String) -> String {
        if let known = ids.first(where: { $0.value == name })?.key { return known }   // from memory, not the disk
        guard let d = try? Data(contentsOf: MontanaMediaStore.url(name)) else { return "" }
        let id = MontanaMedia.blobIdHex(d)
        ids[id] = name
        return id
    }

    // -- the sets of other people -----------------------------------------------------------

    func pack(_ id: String) -> Pack? { packs.first { $0.id == id } }
    func holds(_ id: String) -> Bool { id == mineId || pack(id) != nil }

    /// A set's word arrived: the set is known by name before a single sticker of it has landed.
    func meet(pack id: String, title: String, owner: String, expected: Int) {
        if let i = packs.firstIndex(where: { $0.id == id }) {
            packs[i].title = title
            packs[i].owner = owner
            if expected > 0 { packs[i].expected = expected }
        } else {
            packs.insert(Pack(id: id, title: title, owner: owner, names: [], expected: expected), at: 0)
        }
        save()
    }

    /// A sticker of another person's set landed: filed under its own name, once.
    @discardableResult
    func land(pack id: String, sticker: String, png: Data) -> String? {
        guard let i = packs.firstIndex(where: { $0.id == id }) else { return nil }
        if let known = ids[sticker], packs[i].names.contains(known) { return known }
        let name = Self.mintName(suffix: MontanaStickerCut.suffix(for: png))
        guard MontanaMediaStore.put(name, data: png) else { return nil }
        packs[i].names.append(name)
        ids[sticker] = name
        save()
        return name
    }

    func drop(pack id: String) {
        guard let i = packs.firstIndex(where: { $0.id == id }) else { return }
        MontanaMediaStore.remove(packs[i].names)
        packs.remove(at: i)
        save()
    }

    // -- what a letter says about itself -----------------------------------------------------

    /// THE LETTER'S NAME HAS ONE SPELLING HERE (22.09): rows wear «mid:» before it and the wire
    /// does not, so the book keeps the bare name and every asker is answered the same.
    static func bare(_ letter: String) -> String {
        letter.hasPrefix("mid:") ? String(letter.dropFirst(4)) : letter
    }

    func note(passport: Passport, for letter: String) {
        let letter = Self.bare(letter)
        guard !letter.isEmpty else { return }
        passports[letter] = passport
        if 512 < passports.count, let first = passports.keys.first { passports.removeValue(forKey: first) }
        save()
    }
    func passport(forLetter letter: String) -> Passport? { passports[Self.bare(letter)] }

    /// WHO GAVE THE LINK (22.09): a pack link carries no address of anybody -- the giver is
    /// remembered at the moment the letter carrying it lands, and that is who the set is asked of.
    func note(giver: String, for pack: String) {
        guard !giver.isEmpty, !pack.isEmpty, givers[pack] != giver else { return }
        givers[pack] = giver
        save()
    }
    func giver(of pack: String) -> String? {
        if let p = self.pack(pack), !p.owner.isEmpty { return p.owner }
        return givers[pack]
    }

    /// EVERY FILE THIS BOOK HOLDS, for the one hand that sweeps the store (the author's word 22.09:
    /// «it did not survive a restart»). The sweep carries off whatever no LETTER names, and a set's
    /// pictures are named by no letter at all -- so the book names them itself, here, and the sweep
    /// asks the book before it lifts anything.
    var allFiles: Set<String> {
        var out = Set(names)
        for p in packs { out.formUnion(p.names) }
        return out
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(names, forKey: Self.shelf)
        if let x = try? JSONEncoder().encode(packs) { d.set(x, forKey: Self.packsKey) }
        if let x = try? JSONEncoder().encode(passports) { d.set(x, forKey: Self.portsKey) }
        d.set(givers, forKey: Self.giversKey)
        d.set(ids, forKey: Self.idsKey)
    }
}

/// THE SET'S NAME IS BORN ONCE, FROM ITS OWNER AND HIS OWN RANDOMNESS -- no register, no short
/// name to be claimed, nothing to ask of anybody, and no way for two sets to collide by accident
/// or on purpose. The name does not move when the set changes: the set is the same set.
enum MontanaStickerPack {
    static func mint(owner: String) -> String {
        var seed = Data(owner.utf8)
        seed.append(montanaRandom(16))
        return MontanaMedia.blobIdHex(seed)
    }
    /// The link a person copies: the set's name and its title, and not one address of anybody.
    static func link(id: String, title: String) -> String {
        var c = URLComponents()
        c.scheme = "montana"          // NOT-UI
        c.host = "pack"               // NOT-UI
        c.path = "/" + id
        if !title.isEmpty { c.queryItems = [URLQueryItem(name: "n", value: title)] }
        return c.url?.absoluteString ?? ("montana://pack/" + id)
    }
    /// The set's name inside a line of text, wherever it stands among the words.
    static func idIn(text: String) -> (id: String, title: String)? {
        guard let r = text.range(of: "montana://pack/", options: .caseInsensitive) else { return nil }
        let tail = text[r.upperBound...]
        let id = String(tail.prefix(while: { $0.isHexDigit }))
        guard id.count == 64 else { return nil }
        var title = ""
        if let q = tail.range(of: "?n=") {
            title = String(tail[q.upperBound...].prefix(while: { !$0.isWhitespace })).removingPercentEncoding ?? ""
        }
        return (id, title)
    }
}

/// THE STICKER'S SIZE IS THE SINGLE GLYPH'S, THREE TIMES OVER (the author's word 22.09). A letter
/// of one emoji is drawn at the glyph size below; a sticker's long side is three of them. One
/// number, one owner ([C-1]) -- the two cannot drift apart, and the emoji bubble reads it too.
enum MTStickerLook {
    static let glyph: CGFloat = 64
    static var side: CGFloat { glyph * 3 }
    /// The sticker's picture fitted into its square, keeping the shape it was cut in.
    static func box(_ aspect: CGSize) -> CGSize {
        let w = max(aspect.width, 1), h = max(aspect.height, 1)
        let k = side / max(w, h)
        return CGSize(width: (w * k).rounded(), height: (h * k).rounded())
    }
}
