//  MTLinkPreview.swift — the link preview card, built the Montana way: the SENDER fetches
//  the page's own description (og:*) and the card rides INSIDE the E2E letter. The receiver
//  never touches the site before tapping — the only honest reader of a link is the person
//  who chose to share it. The node sees the same sealed letter it always sees.
//  SERVER-DEBT-ACK: the fetches below read the PUBLIC web page the person is sharing — the
//  sender's own read of an outside site, not a delivery road and not our node; delivery of
//  the card itself rides the mesh/node letter like any other letter bytes.

import Foundation
import UIKit

struct MTLinkPreview: Codable {
    var u: String          // the link itself (absolute)
    var s: String?         // site name (og:site_name, else the host)
    var t: String?         // page title (og:title, else <title>)
    var d: String?         // description (og:description)
    var i: String?         // preview image, jpeg base64 — rides the mesh leg only
    /// TWO SHAPES OF A CARD, AS THE REFERENCE DRAWS THEM (the critic 22.09): a small picture stands as
    /// a square beside the words, a big one lies across the card under them. The SENDER decides, being
    /// the only one who ever saw the page — the receiver draws what the card says.
    var p: String?         // where the picture lives — read on its own road, after the words
    var w: Int?            // the picture own width in pixels (nil — no picture)
    var h: Int?            // and its height
    var wide: Bool { (w ?? 0) >= 400 && (h ?? 0) >= 200 }   // the reference own threshold for «large by default»

    var json: String? {
        guard let d = try? JSONEncoder().encode(self) else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func parse(_ s: String?) -> MTLinkPreview? {
        guard let s, s.count > 2, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MTLinkPreview.self, from: d)
    }
    /// The envelope leg (2048 cap) rides the card without the picture.
    var withoutImage: MTLinkPreview { MTLinkPreview(u: u, s: s, t: t, d: d, i: nil, p: p, w: w, h: h) }
    var hasFace: Bool { (t?.isEmpty == false) || (d?.isEmpty == false) }
}

enum MTLinkPreviewBuilder {

    /// THE ONE SWITCH (Settings → Privacy, on by default — the author's word 22.09): the card is built
    /// by MY device reading the page I am sharing, so the site sees my address. Off, nothing outside is
    /// read and the letter carries the bare link; a card that has already arrived is drawn as before —
    /// it is bytes of the letter, and drawing it opens nothing.
    static let switchKey = "linkPreviewsEnabled"
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: switchKey) as? Bool ?? true
    }

    /// THE CARD IS SEEN BEFORE IT RIDES (the critic 22.09, the reference own panel above the field):
    /// while a link stands in the field, this holder reads its page and the bar shows what will ride;
    /// the cross drops it for THIS letter alone. One reader, one holder — the send takes what it sees.
    @MainActor
    final class Compose: ObservableObject {
        static let shared = Compose()
        @Published private(set) var card: MTLinkPreview?
        @Published private(set) var url: String = ""
        @Published private(set) var reading = false
        private var dropped: Set<String> = []          // the links this composer was told to leave alone
        private var task: Task<Void, Never>?
        /// The field words, at every change: the first link that has a face becomes the card.
        func look(at text: String) {
            guard MTLinkPreviewBuilder.enabled else { clear(); return }
            let links = MTLinkPreviewBuilder.webURLs(in: text).map(\.absoluteString)
            guard let first = links.first(where: { !dropped.contains($0) }) else { clear(); return }
            guard first != url else { return }
            task?.cancel()
            url = first; card = nil; reading = true
            task = Task { [weak self] in
                // ONE LINK, THREE SECONDS AT MOST (the author's word 22.09): the plate is not a place to
                // wait in. The page that does not answer in three seconds loses its plate; the letter is
                // attended afterwards by the card's own owner, which has all the patience it needs.
                let made = await MTLinkPreviewBuilder.buildBounded(in: first, ceiling: 3)
                await MainActor.run {
                    guard let self, self.url == first else { return }
                    self.card = made; self.reading = false
                    if made == nil { self.url = "" }   // nothing to show: the plate leaves instead of sitting there
                }
            }
        }
        /// The cross on the plate: this link rides bare, and the plate does not come back for it.
        func drop() {
            if !url.isEmpty { dropped.insert(url) }
            clear()
        }
        /// The letter has left (or the field was emptied): the holder forgets everything but the drops.
        func clear() {
            task?.cancel(); task = nil
            card = nil; url = ""; reading = false
        }
        func sent() { dropped.removeAll(); clear() }
        /// What the send should attach: the card the person saw, and nothing else.
        var attachable: String? { card?.json }
    }

    /// EVERY WEB LINK OF THE TEXT, IN ITS ORDER (the critic 22.09): the first link of a letter may be a
    /// page with nothing to say, and the letter then carried no card at all though its second link had
    /// a face. Service marks never reach here (the caller hands over plain outgoing text only).
    static func webURLs(in text: String) -> [URL] {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let r = NSRange(text.startIndex..., in: text)
        return det.matches(in: text, options: [], range: r).compactMap { m in
            guard let u = m.url, let sch = u.scheme?.lowercased(),
                  sch == "https" || sch == "http", u.host != nil else { return nil }
            return u
        }
    }
    static func firstWebURL(in text: String) -> URL? { webURLs(in: text).first }
    /// The first link that HAS a face: each is asked in turn until one answers (the whole walk is
    /// still bounded — buildBounded holds the ceiling over the walk, not over one page).
    static func buildFirstWithFace(in text: String) async -> MTLinkPreview? {
        for u in webURLs(in: text).prefix(3) {
            if let card = await build(for: u) { return card }
        }
        return nil
    }

    /// Build the card with a HARD ceiling by construction: the caller's letter must never
    /// wait on an outside site — 4s and the race resolves to «no card», whatever any reader
    /// below is doing (critic 29.08: a hung read held a letter hostage for minutes).
    static func buildBounded(in text: String, ceiling: Double = 4) async -> MTLinkPreview? {
        let t0 = Date()
        let url = firstWebURL(in: text) ?? URL(string: "about:blank")!
        let card = await withTaskGroup(of: MTLinkPreview?.self) { g -> MTLinkPreview? in
            g.addTask { await buildFirstWithFace(in: text) }
            g.addTask { try? await Task.sleep(nanoseconds: UInt64(ceiling * 1_000_000_000)); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        // The build was blind in the journal: a missing card could not be told apart from a
        // dead task. One line names the outcome: ok / no-card (page had nothing) / timeout.
        MontanaP2PTrace.mark("lp_build", "\(card == nil ? (Double(ms) >= ceiling * 1000 - 100 ? "timeout" : "no-card") : "ok") ms=\(ms) pic=\(card?.p == nil ? 0 : 1) host=\(url.host ?? "-")")
        return card
    }

    /// Build the card the sender attaches: page fetch ≤ 3s / ≤ 512KB, then the preview image
    /// ≤ 2.5s. Silence on any failure — a letter without a card is an ordinary letter.
    /// A page read once is not read again (the author's word 22.09: the plate must not sit thinking).
    /// The words of a card are the same for the whole life of a screen; a second look at the same link —
    /// typing, deleting, typing again, the send behind it — answers from here, in no time at all.
    private static var read: [String: MTLinkPreview] = [:]
    private static var readNothing: Set<String> = []

    static func build(for url: URL) async -> MTLinkPreview? {
        let key = url.absoluteString
        if let held = read[key] { return held }
        if readNothing.contains(key) { return nil }
        if let tube = youtube(url) {
            guard let card = await youtubeCard(url, tube) else {
                if Task.isCancelled == false { readNothing.insert(key) }
                return nil
            }
            return card
        }
        guard let html = await fetchText(url, limit: 64 * 1024, timeout: 3) else { readNothing.insert(key); return nil }
        let site = meta(html, "og:site_name") ?? url.host
        let title = meta(html, "og:title") ?? tagTitle(html)
        let desc = meta(html, "og:description") ?? meta(html, "description")
        var card = MTLinkPreview(u: url.absoluteString,
                                 s: clean(site, cap: 64), t: clean(title, cap: 300), d: clean(desc, cap: 800), i: nil)
        guard card.hasFace else { readNothing.insert(key); return nil }   // a card with nothing to say is noise, not a preview
        // THE PICTURE IS NOT PART OF THIS READ (measured on the author's T1, 22.09: every lp_build of
        // the day wrote img=0 — the picture host answered slower than the two and a half seconds this
        // read allowed, and the card lost its face for good). The address of the picture is remembered
        // here; the picture itself is fetched on its own road, with its own ten seconds, and lands on
        // the row that already stands (MTLinkCards.picture).
        // The three names a page gives its own picture: the open-graph one, its secure form, and the
        // short-message one that many pages write instead.
        let shortCard = "tw" + "itter:image"   // FOREIGN-OK: a meta key of the open web, not a name of ours to speak
        card.p = (meta(html, "og:image") ?? meta(html, "og:image:secure_url") ?? meta(html, shortCard))
            .flatMap { URL(string: $0, relativeTo: url)?.absoluteString }
        read[key] = card
        return card
    }

    /// The second read: the picture alone, ten seconds of its own, and never a letter waiting on it.
    static func picture(for card: MTLinkPreview, timeout: TimeInterval = 10) async -> MTLinkPreview? {
        guard card.i == nil, let ref = card.p, let imgURL = URL(string: ref),
              let sch = imgURL.scheme?.lowercased(), sch == "https" || sch == "http" else { return nil }
        let t0 = Date()
        guard let raw = await fetchData(imgURL, limit: 3 * 1024 * 1024, timeout: timeout),
              let ui = UIImage(data: raw) else {
            MontanaP2PTrace.mark("lp_image", "none ms=\(Int(Date().timeIntervalSince(t0) * 1000)) host=\(imgURL.host ?? "-")")
            return nil
        }
        var full = card
        // THE PICTURE IS DRAWN ACROSS THE CARD (the author word 22.09: not a byte of difference) —
        // a card image is shown at the bubble width, so 480 points of it came out soft. The row keeps
        // the crisp one; the letter that rides to a correspondent carries the picture cut to the
        // wire leg by fitting(), below.
        full.i = jpegB64(ui, maxSide: 720, quality: 0.75, capBytes: 70 * 1024)
        full.w = Int(ui.size.width * ui.scale)
        full.h = Int(ui.size.height * ui.scale)
        MontanaP2PTrace.mark("lp_image", "ok ms=\(Int(Date().timeIntervalSince(t0) * 1000)) px=\(full.w ?? 0)x\(full.h ?? 0) host=\(imgURL.host ?? "-")")
        return full.i == nil ? nil : full
    }

    // ── the wire tail: the card is the 7th field of the letter body ────────────
    /// A QUOTE AND A CARD RIDE TOGETHER (the critic 22.09): the tail used to be built only for a
    /// quote-less letter, so an answer that carried a link never grew a card at all. The tail's shape
    /// is the same for both — the quote's two fields and then the card — and a letter with a quote
    /// simply fills those fields instead of leaving them empty. An older build reads the pair it
    /// always read and buries what follows, as it always did ([P2P-COMPAT]).
    /// The tail of a QUOTE-LESS letter: two empty fields where the quote would stand, then the card.
    static func wireTail(lp: String?, hasQuote: Bool = false) -> Data? {
        guard let lp = fitting(lp), !hasQuote else { return nil }
        var t = Data([0, 0, 0])            // empty qt ‖ empty qm ‖ the card
        t.append(contentsOf: lp.utf8)
        return t
    }
    /// The card appended AFTER a quote pair that is already written — one zero, then the card.
    /// [P2P-COMPAT] verified by reading, not by hope: every Apple build alive (1344, 1348, 1496, 1507,
    /// 1511, 1553, 1556, 1561, 1562, 1613, 1614, 1647, 1666, 1667, 1789, 1802, 1829, 1860, 1870, 1871,
    /// 1872) splits the body with maxSplits 6 and reads the card as the seventh field with the same
    /// 16 KB cap — a quoted letter carrying a card opens correctly on each of them.
    static func wireTailAfterQuote(lp: String?) -> Data? {
        guard let lp = fitting(lp) else { return nil }
        var t = Data([0])
        t.append(contentsOf: lp.utf8)
        return t
    }
    /// THE CARD THAT RIDES IS THE CARD THAT IS SEEN, ITS PICTURE CUT TO THE LEG. Every live build
    /// reads the seventh field with a 16 KB cap ([P2P-COMPAT]), and the crisp picture of the row does
    /// not fit it — the card used to be dropped WHOLE at this gate, so a correspondent saw no card at
    /// all as soon as one carried a picture. The picture alone is re-encoded now, and only when no
    /// size fits does the card ride with its words alone.
    private static func fitting(_ lp: String?) -> String? {
        guard let lp, !lp.isEmpty, lp.utf8.count > 64 else { return nil }
        if lp.utf8.count <= 16384 { return lp }
        return shrunk(lp)
    }
    private static func shrunk(_ lp: String) -> String? {
        guard var card = MTLinkPreview.parse(lp) else { return nil }
        if let b = card.i, let d = Data(base64Encoded: b), let ui = UIImage(data: d) {
            let steps: [(CGFloat, CGFloat, Int)] = [(480, 0.6, 11 * 1024), (320, 0.5, 8 * 1024)]
            for (side, q, cap) in steps {
                card.i = jpegB64(ui, maxSide: side, quality: q, capBytes: cap)
                if let j = card.json, j.utf8.count <= 16384 { return j }
            }
        }
        card.i = nil
        guard let bare = card.json, bare.utf8.count > 64, bare.utf8.count <= 16384 else { return nil }
        return bare
    }

    // ── readers of the shared page (the sender's own read of the outside site) ─
    /// THE HEAD IS THE WHOLE OF WHAT WE READ (the author's word 22.09: «why is it reading so long —
    /// a site opens instantly»). Everything a card is made of lives in the head of a page, and the
    /// read used to swallow half a megabyte to find four lines: the page of the author's own link is
    /// 433 KB, its head closes at 32 KB (measured 22.09). The read now stops at the closing of the
    /// head, or at 64 KB — whichever comes first — and the rest of the page is never pulled.

    /// The video a YouTube address names, when it names one. music is the music host.
    struct Tube {
        var id: String
        var music: Bool
    }

    static func youtubeID(_ url: URL) -> String? {
        youtube(url)?.id
    }

    static func youtube(_ url: URL) -> Tube? {
        guard let host = url.host?.lowercased() else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let music = bare == "music.youtube.com"
        let names = ["youtu.be", "youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com"]
        guard names.contains(bare) else { return nil }
        let picked: String?
        if bare == "youtu.be" {
            picked = url.path.split(separator: "/").first.map(String.init)
        } else {
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count > 1, ["shorts", "embed", "live", "v"].contains(parts[0]) {
                picked = parts[1]
            } else {
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                picked = items?.first(where: { item in item.name == "v" })?.value
            }
        }
        guard let picked, picked.count == 11, Self.youtubeToken(picked) else { return nil }
        return Tube(id: picked, music: music)
    }

    private static func youtubeToken(_ id: String) -> Bool {
        id.unicodeScalars.allSatisfy { scalar in
            let ch = Character(scalar)
            if ch.isASCII, ch.isLetter { return true }
            if ch.isASCII, ch.isNumber { return true }
            if ch == "-" { return true }
            if ch == "_" { return true }
            return false
        }
    }

    /// Video, music, or an ordinary page. The post draws a play mark for the first two.
    static func playKind(_ url: URL) -> String? {
        if let tube = youtube(url) {
            if tube.music { return "aud" }
            return "vid"
        }
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "m4v", "webm"].contains(ext) { return "vid" }
        if ["mp3", "m4a", "aac", "wav", "flac"].contains(ext) { return "aud" }
        let host = url.host?.lowercased() ?? ""
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if bare == "open.spotify.com" { return "aud" }
        if bare == "spotify.com" { return "aud" }
        if bare.hasSuffix("soundcloud.com") { return "aud" }
        if bare == "music.apple.com" { return "aud" }
        return nil
    }

    /// The card a wall post carries. The words have four seconds; a picture not already in the card
    /// has two more. A slow picture host keeps the words.
    static func wallCard(in text: String) async -> MTLinkPreview? {
        guard enabled, firstWebURL(in: text) != nil else { return nil }
        guard let card = await buildBounded(in: text, ceiling: 4) else { return nil }
        if card.i != nil { return card }
        if let full = await picture(for: card, timeout: 2) { return full }
        return card
    }

    private static func youtubeCard(_ url: URL, _ tube: Tube) async -> MTLinkPreview? {
        if Task.isCancelled { return nil }
        async let meta = youtubeWords(url)
        let raw = await youtubePicture(tube.id)
        let words = await meta
        if Task.isCancelled { return nil }
        var card = MTLinkPreview(u: url.absoluteString,
                                 s: tube.music ? "YouTube Music" : "YouTube", // NOT-UI: the host name the card carries
                                 t: clean(words.0, cap: 300),
                                 d: clean(words.1, cap: 200),
                                 i: nil,
                                 p: "https://i.ytimg.com/vi/" + tube.id + "/hqdefault.jpg",
                                 w: 480, h: 360)
        if let raw, let ui = UIImage(data: raw) {
            card.i = jpegB64(ui, maxSide: 720, quality: 0.72, capBytes: 40960)
            card.w = Int(ui.size.width)
            card.h = Int(ui.size.height)
        }
        if card.i == nil, card.hasFace == false { return nil }
        read[url.absoluteString] = card
        return card
    }

    private static func youtubeWords(_ url: URL) async -> (String?, String?) {
        var parts = URLComponents(string: "https://www.youtube.com/oembed")
        parts?.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let ask = parts?.url,
              let data = await fetchData(ask, limit: 16384, timeout: 2.5),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        return (obj["title"] as? String, obj["author_name"] as? String)
    }

    private static func youtubePicture(_ id: String) async -> Data? {
        let urls = [
            "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg",
            "https://img.youtube.com/vi/" + id + "/hqdefault.jpg"
        ]
        for item in urls {
            if Task.isCancelled { return nil }
            guard let ask = URL(string: item) else { continue }
            guard let data = await fetchData(ask, limit: 2097152, timeout: 2.5) else { continue }
            if UIImage(data: data) != nil { return data }
        }
        return nil
    }

    private static func fetchText(_ url: URL, limit: Int, timeout: TimeInterval) async -> String? {
        guard let d = await fetchData(url, limit: limit, timeout: timeout, stopAtHead: true) else { return nil }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1)
    }
    private static func fetchData(_ url: URL, limit: Int, timeout: TimeInterval, stopAtHead: Bool = false) async -> Data? {
        var req = URLRequest(url: url)   // SERVER-DEBT-ACK: the public page being shared, read by its sender — not a delivery road
        req.timeoutInterval = timeout
        req.setValue("Mozilla/5.0 (iPhone) MontanaPreview/1", forHTTPHeaderField: "User-Agent")
        // A FRESH lane with a HARD whole-request ceiling. The shared session under a VPN
        // reuses a zombie pipe, and a per-chunk timeout never fires on a trickling stream —
        // the sender's letter stood hostage to the site for minutes (measured 06:03 29.08).
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout + 1.5
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        guard let (bytes, resp) = try? await session.bytes(for: req),   // SERVER-DEBT-ACK: the shared page itself
              (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) != false else { return nil }
        var out = Data(); out.reserveCapacity(min(limit, 65536))
        let headEnd = Data("/head".utf8)   // the closing of the head, whatever the page writes around it
        do {
            for try await b in bytes {
                out.append(b)
                if out.count >= limit { break }
                if stopAtHead, out.count % 2048 < 64, out.range(of: headEnd, options: .backwards) != nil { break }
            }
        } catch { return out.isEmpty ? nil : out }
        return out
    }

    // ── tiny HTML readers: enough for og:* on real pages, no browser engine ────
    /// EVERY META TAG IS READ AS A TAG (measured 22.09 on the author own link). The two regular
    /// expressions that stood here asked for a value as «[^QT]+» and matched case-insensitively — so
    /// the letters q and t were excluded from every value by accident, and any site name, title or
    /// description carrying a «t» matched nothing at all: og:site_name «GitHub», og:title and
    /// og:description of his link all came back empty, and the card fell back to the bare host and
    /// the title tag — no description, no picture, two lines where a card has five.
    /// The head meta tags are now walked as tags, their attributes read as attributes, and the tag
    /// whose «property» (or «name») is the asked one hands over its «content».
    private static func meta(_ html: String, _ prop: String) -> String? {
        let want = prop.lowercased()
        for tag in metaTags(html) {
            let a = attributes(tag)
            guard let key = a["property"] ?? a["name"], key.lowercased() == want,
                  let raw = a["content"] else { continue }
            let v = decodeEntities(raw)
            if !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v }
        }
        return nil
    }
    private static let metaTagRE = try? NSRegularExpression(pattern: #"<meta(\s[^>]*)>"#, options: [.caseInsensitive])
    private static func metaTags(_ html: String) -> [String] {
        guard let re = metaTagRE else { return [] }
        let ns = html as NSString
        return re.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }
    /// The three shapes the open web writes an attribute in: in double quotes, in single ones, bare.
    private static let attrRE = try? NSRegularExpression(
        pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#, options: [])
    private static func attributes(_ tag: String) -> [String: String] {
        guard let re = attrRE else { return [:] }
        let ns = tag as NSString
        var out: [String: String] = [:]
        for m in re.matches(in: tag, options: [], range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            for g in 2...4 where m.range(at: g).location != NSNotFound {
                out[name] = ns.substring(with: m.range(at: g))
                break
            }
        }
        return out
    }
    private static func tagTitle(_ html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<title[^>]*>([^<]{1,300})</title>",
                                                options: [.caseInsensitive]),
              let m = re.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: html) else { return nil }
        return decodeEntities(String(html[r]))
    }
    private static func decodeEntities(_ s: String) -> String {
        var v = s
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                       ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&#x27;", "'")] {
            v = v.replacingOccurrences(of: a, with: b)
        }
        return v
    }
    private static func clean(_ s: String?, cap: Int) -> String? {
        guard let s else { return nil }
        let t = s.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return String(t.prefix(cap))
    }
    private static func jpegB64(_ ui: UIImage, maxSide: CGFloat, quality: CGFloat, capBytes: Int) -> String? {
        let side = max(ui.size.width, ui.size.height)
        let scale = side > maxSide ? maxSide / side : 1
        let sz = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
        let img = UIGraphicsImageRenderer(size: sz).image { _ in ui.draw(in: CGRect(origin: .zero, size: sz)) }
        var q = quality
        for _ in 0..<3 {
            if let d = img.jpegData(compressionQuality: q), d.count <= capBytes { return d.base64EncodedString() }
            q *= 0.6
        }
        return nil
    }
}


/// THE ONE OWNER OF A LETTER'S CARD ([C-1], the author's word 22.09). Everything about a card after
/// the send is decided here and nowhere else: who reads the page, when, how many times, what lands on
/// the row, what rides to the other side. Before this, the decision lived inside the branch that talks
/// to a correspondent — so a letter to oneself grew no card at all — and a page that answered slowly
/// (the picture host of GitHub took longer than the two and a half seconds allowed, measured on the
/// author's own T1: every lp_build of the day reads img=0) lost its picture forever.
///
/// Three rules hold here:
///   1. A letter carries the card the person SAW above the field, if there was one, at once.
///   2. A letter whose card was not read yet is attended in the background — three attempts, the
///      first in four seconds, then thirty, then two minutes; the attempts stop the moment a card
///      lands, and stop for good after the third.
///   3. The picture is a SECOND, longer read: the words of the card land first, and the picture
///      catches up on the very same row — nothing waits for it.
/// The row is touched ONCE per landing (never per attempt), so the feed rebuilds one row and only
/// when there is something new to draw (the author's word 22.09: never overload the feed).
@MainActor
final class MTLinkCards {
    static let shared = MTLinkCards()
    private struct Job { let chat: String; let mid: String; let text: String; let sid: String?
                         let quoteText: String?; let quoteMid: String?; var tries: Int }
    private var jobs: [String: Job] = [:]      // by mid — one job per letter, never two
    private static let delays: [Double] = [4, 30, 120]

    /// Called by the ONE send road, for every room alike.
    func attend(store: ChatStore, chat: String, mid: String, text: String, sid: String?,
                quoteText: String?, quoteMid: String?, seen: String?, refused: Bool) {
        guard !refused, MTLinkPreviewBuilder.enabled, !MontanaNotify.isService(text),
              !MTLinkPreviewBuilder.webURLs(in: text).isEmpty else { return }
        if let seen, !seen.isEmpty {
            land(store: store, chat: chat, mid: mid, text: text, sid: sid,
                 quoteText: quoteText, quoteMid: quoteMid, card: seen)
            picture(store: store, chat: chat, mid: mid, text: text, sid: sid,
                    quoteText: quoteText, quoteMid: quoteMid, card: seen)
            return
        }
        guard jobs[mid] == nil else { return }
        jobs[mid] = Job(chat: chat, mid: mid, text: text, sid: sid,
                        quoteText: quoteText, quoteMid: quoteMid, tries: 0)
        run(store: store, mid: mid, after: 0)
    }

    private func run(store: ChatStore, mid: String, after: Double) {
        guard let job = jobs[mid] else { return }
        let hold = MTSendAssertion("link-card")
        Task { [weak self, weak store] in
            if after > 0 { try? await Task.sleep(nanoseconds: UInt64(after * 1_000_000_000)) }
            let card = await MTLinkPreviewBuilder.buildBounded(in: job.text)?.json
            await MainActor.run {
                defer { hold.end() }
                guard let self, let store else { return }
                if let card {
                    self.jobs[mid] = nil
                    self.land(store: store, chat: job.chat, mid: mid, text: job.text, sid: job.sid,
                              quoteText: job.quoteText, quoteMid: job.quoteMid, card: card)
                    self.picture(store: store, chat: job.chat, mid: mid, text: job.text, sid: job.sid,
                                 quoteText: job.quoteText, quoteMid: job.quoteMid, card: card)
                    return
                }
                var next = job
                next.tries += 1
                guard next.tries < Self.delays.count else {
                    self.jobs[mid] = nil
                    MontanaP2PTrace.mark("lp_give_up", "no card after \(next.tries) reads mid=\(String(mid.prefix(8)))")
                    return
                }
                self.jobs[mid] = next
                self.run(store: store, mid: mid, after: Self.delays[next.tries - 1])
            }
        }
    }

    /// The card lands on the row and, if there is a correspondent, rides to them.
    private func land(store: ChatStore, chat: String, mid: String, text: String, sid: String?,
                      quoteText: String?, quoteMid: String?, card: String) {
        if let i = store.messages[chat]?.firstIndex(where: { $0.msgId == "mid:\(mid)" }),
           store.messages[chat]?[i].linkPreview != card {
            store.messages[chat]?[i].linkPreview = card   // ONE touch of the feed, and only when it changes
        }
        if let sid {
            MontanaDeliveryEngine.shared.attachPreview(to: sid, chat: chat, mid: mid, text: text, lp: card,
                                                       quoteText: quoteText, quoteMid: quoteMid)
        }
    }

    /// THE PICTURE IS A SECOND READ (measured on T1, 22.09: not one card of the day carried one — the
    /// picture host answered slower than the two and a half seconds the page read allowed). The words
    /// stand already; this fetch has ten seconds of its own and lands on the same row when it comes.
    private func picture(store: ChatStore, chat: String, mid: String, text: String, sid: String?,
                         quoteText: String?, quoteMid: String?, card: String) {
        guard let parsed = MTLinkPreview.parse(card), parsed.i == nil else { return }
        Task { [weak store] in
            guard let full = await MTLinkPreviewBuilder.picture(for: parsed) else { return }
            await MainActor.run {
                guard let store, let json = full.json else { return }
                if let i = store.messages[chat]?.firstIndex(where: { $0.msgId == "mid:\(mid)" }),
                   store.messages[chat]?[i].linkPreview != json {
                    store.messages[chat]?[i].linkPreview = json
                }
                if let sid {
                    MontanaDeliveryEngine.shared.attachPreview(to: sid, chat: chat, mid: mid, text: text, lp: json,
                                                               quoteText: quoteText, quoteMid: quoteMid)
                }
                MontanaP2PTrace.mark("lp_picture", "the picture caught up mid=\(String(mid.prefix(8)))")
            }
        }
    }
}
