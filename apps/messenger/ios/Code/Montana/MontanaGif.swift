import SwiftUI
import UIKit
import ImageIO

/// A MOVING PICTURE IS THE PLATFORM'S OWN WORK (22.09). The reference carries a renderer of its
/// own for animation (rlottie, its multi-animation renderer, its frame cache) because it plays
/// vector stickers and video files as well. A GIF needs none of that: ImageIO reads and plays the frames
/// itself -- CGAnimateImageAtURLWithBlock over the source's own durations, one frame in memory at a time
/// (MTGifView for a letter, MTGifLoopView for a tile of the choosing).
enum MontanaGif {
    static func isGif(_ name: String) -> Bool { name.lowercased().hasSuffix(".gif") }

    /// THE PICTURE'S SHAPE WITHOUT ITS FRAMES: the file's own header says its pixel size, so the plate
    /// is laid out before a single frame is decoded. Kept per file for the run.
    nonisolated(unsafe) private static var sizes: [String: CGSize] = [:]
    private static let sizeLock = NSLock()
    static func size(at url: URL) -> CGSize? {
        sizeLock.lock(); let have = sizes[url.path]; sizeLock.unlock()
        if let have { return have }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              0 < w, 0 < h else { return nil }
        let size = CGSize(width: w, height: h)
        sizeLock.lock(); sizes[url.path] = size; sizeLock.unlock()
        return size
    }

    /// One frame, the first — what the plate shows before the animator hands it the next.
    static func firstFrame(at url: URL) -> CGImage? { frame(at: url, index: 0) }
    /// One frame of the file — the one a stopped picture stands on.
    static func frame(at url: URL, index: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let n = CGImageSourceGetCount(src)
        return CGImageSourceCreateImageAtIndex(src, n > 0 ? min(max(0, index), n - 1) : 0, nil)
    }
}

/// THE PLAY OF EVERY MOVING PICTURE, ONE OWNER PER FILE (23.09, the author: «why do some gifs stop on a tap and
/// some do not; make them play their cycle three times when sent, and then only on a tap — three cycles — and a tap
/// at any moment stops them»). The stop used to live in the bubble (@State): the feed rebuilds its bubbles on every
/// receipt, arrival and scroll, the state was born anew each time, and a gif the finger had stopped went on — so
/// some stopped and some did not. Now this book owns it by the file's name, and nothing that rebuilds a bubble can
/// reset it. What it counts is FRAMES: three cycles are three times the file's own frame count, so they are whole
/// wherever they begin. A first showing plays its three cycles once in the file's life (the mark survives a
/// relaunch); after that only a tap plays them, and a tap on a playing one stops it on the frame it stands on.
final class MTGifPlay {
    static let shared = MTGifPlay()
    static let cycles = 3
    static let changed = Notification.Name("mtGifPlayChanged")
    private let lock = NSLock()
    private var left: [String: Int] = [:]        // frames still to play, by file
    private var standing: [String: Int] = [:]    // the frame each stands on
    private var ranList: [String]                // files whose first three cycles have begun, oldest first
    private var ran: Set<String>
    private static let ranKey = "gifFirstRun"
    private static let ranCap = 3000
    private init() {
        ranList = UserDefaults.standard.stringArray(forKey: Self.ranKey) ?? []
        ran = Set(ranList)
    }
    /// A copy laid (23.09): the pictures that already played their cycles are read from the store again, so a
    /// restored feed does not play every moving picture anew.
    func reread() {
        let l = UserDefaults.standard.stringArray(forKey: Self.ranKey) ?? []
        lock.lock(); ranList = l; ran = Set(l); lock.unlock()
    }
    static func frameCount(_ url: URL) -> Int {
        max(1, CGImageSourceCreateWithURL(url as CFURL, nil).map { CGImageSourceGetCount($0) } ?? 1)
    }
    /// Frames the file has left to play; a file never shown before is handed its first three cycles. The mark
    /// «its first cycles were played» is written only when a frame has really been shown (shown(_:at:)): a start
    /// the animator refused must not spend them.
    func framesLeft(_ key: String, frames: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        if let l = left[key] { return l }
        if ran.contains(key) { left[key] = 0; return 0 }
        let n = Self.cycles * max(1, frames)
        left[key] = n
        return n
    }
    /// One frame shown: it is where the file stands, and one frame less to play. Zero stops the animator.
    func shown(_ key: String, at index: Int) -> Int {
        lock.lock()
        standing[key] = index
        let l = max(0, (left[key] ?? 0) - 1)
        left[key] = l
        var keep: [String]? = nil
        if !ran.contains(key) {
            ran.insert(key); ranList.append(key)
            if ranList.count > Self.ranCap { let drop = ranList.prefix(ranList.count - Self.ranCap); ranList.removeFirst(drop.count); drop.forEach { ran.remove($0) } }
            keep = ranList
        }
        lock.unlock()
        if let keep { UserDefaults.standard.set(keep, forKey: Self.ranKey) }
        return l
    }
    /// The file's bytes were replaced under the same name (the full picture behind the light one at the tap):
    /// what it played of the old bytes says nothing about the new ones, and the new ones play their three cycles.
    func renew(_ key: String) {
        lock.lock(); left[key] = nil; standing[key] = nil; ran.remove(key); lock.unlock()
        NotificationCenter.default.post(name: Self.changed, object: key)
    }
    /// Where a file stands when it rests: its first frame, as it stood before it played.
    func rest(_ key: String) {
        lock.lock(); standing[key] = 0; lock.unlock()
    }
    func standingAt(_ key: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return standing[key]
    }
    /// The finger: a playing file stops on its frame; a standing one plays three cycles from there.
    @discardableResult
    func toggle(_ url: URL) -> Bool {
        let key = url.lastPathComponent
        let frames = Self.frameCount(url)
        lock.lock()
        let playing = (left[key] ?? 0) > 0
        left[key] = playing ? 0 : Self.cycles * frames
        if !ran.contains(key) { ran.insert(key); ranList.append(key) }
        let keep = ranList
        lock.unlock()
        UserDefaults.standard.set(keep, forKey: Self.ranKey)
        NotificationCenter.default.post(name: Self.changed, object: key)
        return !playing
    }
}

/// A MOVING PICTURE OF A LETTER PLAYS BY THE PLATFORM'S OWN ANIMATOR (23.09): ImageIO's CGAnimateImageAtURLWithBlock
/// reads the file frame by frame with the file's own delays, one frame in memory at a time — nothing is decoded
/// ahead, nothing on a render (the 417 MB and the glitch of 1901). How much it plays is the book's (MTGifPlay); the
/// view only asks it and plays while it is on the screen.
///
/// THE START IS NEVER PAST THE LAST FRAME (23.09, T1 fell twice on 1904, SIGTRAP inside IIOImageAnimator::start):
/// ImageIO does not refuse a start index at or past the frame count — it traps the process (measured on the Mac
/// with the same framework: a two-frame gif started at 0 or 1 plays, started at 2 dies with signal 5). The next
/// frame after the one it stands on wraps to the first.
final class MTGifView: UIView {
    private(set) var url: URL?
    private var key = ""
    private var frames = 1
    private var run = 0           // the animation of the moment; an older one stops at its next frame

    override init(frame: CGRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: MTGifPlay.changed, object: nil)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: MTGifPlay.changed, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    /// THE PLATE IS NEVER LEFT EMPTY (23.09, the author's screenshot: a gif's plate stood as the bubble's own ground).
    /// A view took a file as shown even when no frame could be read from it at that moment, and never asked again —
    /// the plate stayed empty for the life of the bubble. Now a file is taken only with a frame in hand; without one
    /// the view asks again in half a second, twenty times at most, and the diary says so.
    private var asked = 0
    private var refused = 0
    private var stamp = 0         // the file's size when it was taken: new bytes under the same name are taken anew
    private static func size(_ u: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.intValue ?? 0
    }
    func show(_ u: URL) {
        guard u != url || Self.size(u) != stamp else { return }
        let k = u.lastPathComponent
        let n = MTGifPlay.frameCount(u)
        guard let first = MontanaGif.frame(at: u, index: (MTGifPlay.shared.standingAt(k) ?? 0) % n) else {
            MontanaTrace.markFolded("gif_frame", "no frame yet — the file is not whole; asked again", window: 30)
            asked += 1
            guard asked <= 20 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.show(u) }
            return
        }
        asked = 0
        url = u
        stamp = Self.size(u)
        key = k
        frames = n
        run &+= 1
        layer.contents = first
        play()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { run &+= 1 } else { play() }
    }

    @objc private func changed(_ n: Notification) {
        guard (n.object as? String) == key else { return }
        if let u = url, Self.size(u) != stamp { url = nil; show(u); return }   // new bytes under the same name
        run &+= 1        // whatever plays now stops at its next frame, on the frame it stands on
        play()           // and plays again only if the book now says so
    }

    private func play() {
        guard let url, window != nil else { return }
        let count = frames
        guard MTGifPlay.shared.framesLeft(key, frames: count) > 0 else { return }
        run &+= 1
        let mine = run
        let key = self.key
        let start = MTGifPlay.shared.standingAt(key).map { ($0 + 1) % count } ?? 0
        let opts = [kCGImageAnimationStartIndex as String: start] as CFDictionary
        let status = CGAnimateImageAtURLWithBlock(url as CFURL, opts) { [weak self] index, image, stop in
            // The platform hands the frames on the main queue (the crash stacks of 1904 show it there); a
            // frame from anywhere else is not drawn — the screen's state is the main thread's alone.
            guard Thread.isMainThread, let self, self.run == mine else { stop.pointee = true; return }
            self.layer.contents = image
            if MTGifPlay.shared.shown(key, at: index) == 0 {
                stop.pointee = true
                // THREE CYCLES END WHERE THEY BEGAN (the author's word 23.09: «they stop crookedly»): the picture
                // rests on its first frame, as it stood before it played — not on whatever frame the count hit.
                if let f0 = MontanaGif.frame(at: url, index: 0) { self.layer.contents = f0; MTGifPlay.shared.rest(key) }
                MontanaTrace.markFolded("gif_play", "three cycles played — it rests on its first frame", window: 10)
            }
        }
        if status != 0 {
            // A start the animator refused spends nothing (the first cycles are marked only by a shown frame);
            // it is named, and asked again in a second while the plate is on the screen — five times at most.
            MontanaTrace.markFolded("gif_start", "the animator refused status=\(status); asked again", window: 30)
            refused += 1
            guard refused <= 5 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.run == mine else { return }
                self.play()
            }
        }
    }
}

/// The letter's moving picture in SwiftUI: the file; how much it plays is the book's (MTGifPlay).
struct MTGifPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> MTGifView {
        let v = MTGifView()
        // THE TOUCH IS THE BUBBLE'S (the author's word 23.09: «some gifs stop on a tap and some do not»; T1's diary:
        // five taps landed in MTGifView and one reached the bubble). A UIKit view inside the SwiftUI bubble took
        // the finger for itself, so only a tap on the plate's edge or its time pill reached the bubble's tap.
        v.isUserInteractionEnabled = false
        v.contentMode = .scaleAspectFit
        v.layer.contentsGravity = .resizeAspect
        v.clipsToBounds = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: MTGifView, context: Context) {
        v.show(url)
    }
}

/// A PICTURE OF THE CHOOSING PLAYS BY THE LETTER'S OWN ANIMATOR (23.09, the critic). The tiles of the panel and
/// the book played through UIImageView over every frame decoded ahead, and those frames lived on a shelf of up to a
/// hundred and twenty pictures for the whole run and again in the panel's own state: T1 was killed by the system
/// seconds after leaving the screen four times on 23.09 — at 1 725, 846, 1 345 and 834 MB — each time in a run that
/// had opened the pictures, while its runs without them stood under 500 MB. A tile now plays its file by ImageIO's
/// CGAnimateImageAtURLWithBlock, as a letter does (MTGifView): one frame in memory at a time, looping as the file
/// says, and only while it is on the screen. Unlike a letter's picture it is not counted in cycles — it is a choosing.
final class MTGifLoopView: UIView {
    private var url: URL?
    private var run = 0           // the animation of the moment; an older one stops at its next frame

    func show(_ u: URL?) {
        guard u != url else { return }
        url = u
        run &+= 1
        layer.contents = u.flatMap { MontanaGif.frame(at: $0, index: 0) }
        play()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { run &+= 1 } else { play() }
    }

    private func play() {
        guard let url, window != nil else { return }
        run &+= 1
        let mine = run
        let status = CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak self] _, image, stop in
            guard Thread.isMainThread, let self, self.run == mine else { stop.pointee = true; return }
            self.layer.contents = image
        }
        if status != 0 {
            MontanaTrace.markFolded("gif_start", "the animator refused a tile status=\(status)", window: 30)
        }
    }
}

/// A tile of the choosing in SwiftUI: its file, played by MTGifLoopView. The finger is the tile's button's.
struct MTGifLoop: UIViewRepresentable {
    let url: URL?
    var fill: Bool = true

    func makeUIView(context: Context) -> MTGifLoopView {
        let v = MTGifLoopView()
        v.isUserInteractionEnabled = false
        v.clipsToBounds = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: MTGifLoopView, context: Context) {
        v.layer.contentsGravity = fill ? .resizeAspectFill : .resizeAspect
        v.show(url)
    }
}

/// THE MOVING PICTURES THIS PHONE KEEPS -- one book, one owner, the sticker book's own shape: a
/// list of names over the media store, newest first, a ceiling, and one copy per picture.
final class MontanaGifBook: ObservableObject {
    static let shared = MontanaGifBook()
    static let ceiling = 60
    private static let shelf = "montana.gifs.mine"

    @Published private(set) var names: [String] = []

    private init() { reread() }
    /// The shelf as the store holds it — at birth, and again when a copy was laid under it (23.09).
    func reread() {
        names = (UserDefaults.standard.stringArray(forKey: Self.shelf) ?? []).filter { MontanaMediaStore.exists($0) }
    }

    @discardableResult
    func add(data: Data) -> String? {
        let name = "gif_" + montanaRandom(8).map { String(format: "%02x", $0) }.joined() + ".gif"
        guard MontanaMediaStore.put(name, data: data) else { return nil }
        names.insert(name, at: 0)
        while Self.ceiling < names.count, let last = names.last {
            names.removeLast()
            MontanaMediaStore.remove([last])
        }
        save()
        MontanaTrace.mark("gif_book", "add n=\(names.count) bytes=\(data.count)")
        return name
    }

    func forget(_ name: String) {
        guard names.contains(name) else { return }
        names.removeAll { $0 == name }
        MontanaMediaStore.remove([name])
        save()
    }

    /// Every file this book holds -- the sweep asks it before it lifts anything (22.09).
    var allFiles: Set<String> { Set(names) }

    private func save() { UserDefaults.standard.set(names, forKey: Self.shelf) }
}

/// THE SEARCH FOR MOVING PICTURES GOES THROUGH OUR OWN NODE (the author's word 22.09, road B).
///
/// The reference searches through ITS OWN SERVER: the client resolves a bot named «gif» and the
/// server asks the picture house for that bot's results (GifContext: resolvePeerByName,
/// requestContextResults) — the phone never speaks to the house. We keep that shape and change the
/// server for our own node: the node holds the key, the node asks the house, and the house learns
/// one address — the node's — never a person's. The phone opens no connection outside our own
/// doors, and nothing of a conversation, a name or a letter is anywhere near this road.
///
/// What is disclosed and to whom, named plainly (the rule of absolute privacy): the picture house
/// sees the node and the word searched, never who asked; OUR OWN node sees the word and the asking
/// address, as it does for every other capability it carries, and writes neither into its journal
/// — the line it keeps holds a number and nothing else. A node without a key does not announce the
/// capability at all, and then the panel says so instead of asking anybody.
enum MontanaGifSearch {
    /// What the search brings back: a name the node remembers, and the picture's shape.
    struct Found: Identifiable {
        let id: String
        let width: Int
        let height: Int
    }

    /// The doors that carry this capability, the elected one first — the tree's own one owner.
    private static func doors() -> [String] {
        MontanaWakePush.electedFirst(MontanaWakePush.orderedBases(for: "gif"))
    }

    /// THE MAP OF WHAT THE DOORS CAN IS WAITED FOR, NOT GUESSED AT (23.09, measured on the
    /// author's own phone: «gif_search no door with this capability» four times in seven seconds,
    /// then «found n=30» seventeen seconds later). A door names its capabilities in its own
    /// answer, and until that round has run the map holds nothing about the moving pictures --
    /// the honest answer to a name nobody claims is «nobody» (16.6.17), so the panel stood empty
    /// while every door was alive and willing. Asking the round to run and looking again costs
    /// one probe of each door, and only when the map has nothing to say.
    private static func doorsWaited() async -> [String] {
        let have = doors()
        if !have.isEmpty { return have }
        await MontanaWakePush.verifyBases()
        return doors()
    }

    static var configured: Bool { !doors().isEmpty }

    /// AN EMPTY WORD IS WHAT IS POPULAR (the author's word 23.09: «on opening, show the popular
    /// ones at once»). The node answers an empty word with the house's trending list and keeps
    /// that answer ten minutes, so a panel opened a hundred times costs the house one question.
    /// The two kinds the house keeps on two shelves: moving pictures and stickers -- the same
    /// road, the same node, one word apart (the author's word 23.09).
    enum Kind: String { case gif, sticker }

    /// A SET OF THE HOUSE: a name and nothing else -- its pictures are asked for by its own name.
    struct Pack: Identifiable, Hashable {
        let id: String
        let title: String
    }

    /// The sets the house keeps, a page at a time.
    static func packs(limit: Int = 12, offset: Int = 0) async -> [Pack] {
        let rows = await ask(["kind": "packs", "limit": limit, "offset": offset])
        return rows.compactMap { r in
            guard let id = r["pack"] as? String, let t = r["title"] as? String, !id.isEmpty else { return nil }
            return Pack(id: id, title: t)
        }
    }

    /// The pictures of one set, a page at a time.
    static func inPack(_ pack: String, limit: Int = 24, offset: Int = 0) async -> [Found] {
        found(await ask(["pack": pack, "limit": limit, "offset": offset]))
    }

    static func find(_ query: String = "", limit: Int = 30, kind: Kind = .gif, offset: Int = 0) async -> [Found] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = await ask(["q": q, "limit": limit, "kind": kind.rawValue, "offset": offset])
        MontanaTrace.mark("gif_search", "kind=\(kind.rawValue) at=\(offset) found n=\(rows.count)")
        return found(rows)
    }

    private static func found(_ rows: [[String: Any]]) -> [Found] {
        rows.compactMap { r in
            guard let id = r["id"] as? String, !id.isEmpty else { return nil }
            return Found(id: id, width: (r["w"] as? Int) ?? 1, height: (r["h"] as? Int) ?? 1)
        }
    }

    /// ONE QUESTION TO THE DOORS ([C-1]): what is asked differs by the words inside, never by the
    /// road -- the doors, the timeout, the reading of the answer are one for every kind.
    private static func ask(_ body: [String: Any]) async -> [[String: Any]] {
        // THE REFUSAL NAMES ITS DOORS (23.09, the critic): «no door with this capability» was written when
        // every door refused or failed as well — T1 wrote it at 17:16:06 while Moscow answered 200 in that
        // very second. Each door's answer is kept, and the line says which it was.
        let doors = await doorsWaited()
        var said: [String] = []
        for base in doors {
            guard let url = URL(string: base + "/gif-search") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            var req = URLRequest(url: url); req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.timeoutInterval = 15
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            let host = URL(string: base)?.host ?? "-"
            do {
                let (d, resp) = try await URLSession.shared.data(for: req)   // SERVER-DEBT-ACK
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                guard code == 200,
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let rows = o["items"] as? [[String: Any]] else { said.append("\(host)=\(code)"); continue }
                return rows
            } catch {
                said.append("\(host)=\((error as NSError).code)")
            }
        }
        MontanaTrace.mark("gif_search", doors.isEmpty ? "no door with this capability"
                                                         : "every door refused: " + said.joined(separator: " "))
        return []
    }

    /// The bytes of a chosen picture, brought down through the same door. The light one fills the
    /// tiles of the choosing; the full one is asked for only when a picture is actually sent --
    /// three times the bytes, and nobody pays them for a picture merely looked at (23.09).
    static func fetch(_ found: Found, full: Bool = false) async -> Data? {
        for base in await doorsWaited() {
            if Task.isCancelled { return nil }
            guard let url = URL(string: base + "/gif-get") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            var req = URLRequest(url: url); req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.timeoutInterval = 25
            var ask: [String: Any] = ["id": found.id]
            if full { ask["full"] = true }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ask)
            let host = URL(string: base)?.host ?? "-"
            let t0 = Date()
            var code = -1
            var bytes: Data? = nil
            do {
                let (d, resp) = try await URLSession.shared.data(for: req)   // SERVER-DEBT-ACK
                code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                if code == 200, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let b64 = o["data"] as? String, let b = Data(base64Encoded: b64), !b.isEmpty { bytes = b }
            } catch {
                code = (error as NSError).code
            }
            // THE ROAD OF A PICTURE IS WRITTEN DOOR BY DOOR (23.09, the critic): the phone kept no word of
            // which door answered the full one, with what and how fast, and the 44 s of 17:16 could be split
            // only through the nodes' journals. A tile says only its refusals, folded.
            if full {
                MontanaTrace.mark("gif_get", "full at=\(host) code=\(code) bytes=\(bytes?.count ?? 0) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
            } else if bytes == nil {
                MontanaTrace.markFolded("gif_get", "tile at=\(host) code=\(code)", window: 60, key: "tile:" + host)
            }
            if let bytes { return bytes }
        }
        return nil
    }

    /// THE LETTER DOES NOT WAIT ON A ROAD WITHOUT A TERM (23.09, the critic). The full picture was asked
    /// under the per-door idle term alone, and an answer that trickles never trips it: at 17:16 the full
    /// one took 44.4 s to come down through a door the phone itself declared dead 28 s into the download,
    /// while the light one lay in hand from the tap. The full one now has a term, and past it the light
    /// one leaves — the author's own fallback, «if the full one cannot be brought».
    static let fullTerm: TimeInterval = 8
    private enum FullRace { case came(Data?); case term }
    static func fetchFull(_ found: Found) async -> Data? {
        let t0 = Date()
        let first: FullRace = await withTaskGroup(of: FullRace.self) { group in
            group.addTask {
                let d = await MontanaGifSearch.fetch(found, full: true)
                return .came(d)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(MontanaGifSearch.fullTerm * 1_000_000_000))
                return .term
            }
            let r = await group.next() ?? .term
            group.cancelAll()
            return r
        }
        switch first {
        case .came(let d): return d
        case .term:
            MontanaTrace.mark("gif_get", "full past its term of \(Int(fullTerm)) s — the light one leaves ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
            return nil
        }
    }
}

/// THE PICTURES ALREADY SEEN ARE NOT ASKED FOR TWICE -- AND NOT KEPT DECODED (23.09, the critic). The panel and the
/// page show the same popular list, so a picture brought down once is kept as its file for the run's temporary
/// folder, and a tile plays that file (MTGifLoop). The shelf of decoded pictures is gone: it held every frame of up
/// to a hundred and twenty pictures for the whole run (see MTGifLoopView).
enum MontanaGifArt {
    private static func tileFile(_ id: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(id + ".gif")
    }

    /// The light bytes a tile has already brought down, if it has (the row at the tap wears them).
    static func light(_ found: MontanaGifSearch.Found) -> Data? {
        try? Data(contentsOf: tileFile(found.id))
    }

    /// The light picture of a tile, as its file: the node's light address, and nothing of the full one.
    static func art(of found: MontanaGifSearch.Found) async -> URL? {
        let u = tileFile(found.id)
        if FileManager.default.fileExists(atPath: u.path) { return u }
        guard let d = await MontanaGifSearch.fetch(found) else { return nil }
        do { try d.write(to: u, options: .atomic) } catch { return nil }
        return u
    }
}

/// THE HOUSE IS NAMED WHERE ITS PICTURES ARE SHOWN -- the house's own condition for the search,
/// and our word given when the search was switched on (22.09).
struct MTGiphyMark: View {
    var body: some View {
        Text("Powered by GIPHY")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(0.45))
            .padding(.vertical, 5)
    }
}
