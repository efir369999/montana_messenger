import UIKit

// The «Saved Messages» conversation's storage key. The key is English and is NOT translated
// (otherwise history is lost on a language change); only what the user sees is translated.
// It lives in the file every target of the client compiles: the share sheet finds one's own face by it.
let savedMessagesKey = "Saved Messages"

// The SSOT of a face: palette, initial, glyph share, display name. One file for both targets
// (the app and the notification extension): a banner must draw exactly what the list draws.
enum MontanaAvatar {
    static let paletteHex = ["#007AFF", "#34C759", "#FF9500", "#AF52DE",
                             "#FF2D55", "#FF3B30", "#30B0C7", "#5856D6"]
    static func colorIndex(_ name: String) -> Int {
        var h: UInt32 = 2166136261
        for b in name.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return Int(h % UInt32(paletteHex.count))
    }
    static func colorHex(_ name: String) -> String { paletteHex[colorIndex(name)] }
    // Initial: mt-address → 2 characters after the prefix (distinguishable), otherwise the first letter.
    /// Whether this is a glyph. The file goes into extensions too, where there is no network view, so
    /// the check stands here on its own instead of being borrowed from a screen.
    static func isEmoji(_ c: Character) -> Bool {
        if c.unicodeScalars.count > 1 { return c.unicodeScalars.contains { $0.properties.isEmoji } }
        guard let s = c.unicodeScalars.first else { return false }
        return s.properties.isEmoji && s.value > 0x238C
    }

    /// How large a glyph is inside the circle. A letter is a caption under a face and a small share is
    /// enough for it; a glyph IS the face itself, and drawing it at letter size shows a dot instead of a face.
    /// One place for the whole client: the list, the header, the profile and the full view ask this one.
    static func glyphScale(_ initial: String) -> CGFloat {
        guard let f = initial.first, isEmoji(f) else { return 0.40 }
        return 0.62
    }

    /// The name FOR DISPLAY in text: if the first character is an emoji, it already stands in the avatar
    /// circle, so we take it out of the name text (no duplication). The unstripped name stays with the
    /// avatar, with the sending to the peer and in the editing field. One source for the whole client ([C-1]).
    static func spokenName(_ name: String) -> String {
        guard let f = name.first, isEmoji(f) else { return name }
        return String(name.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    static func initial(title: String, name: String) -> String {
        if name.lowercased().hasPrefix("mt"), name.count > 4 {
            return String(name.dropFirst(2).prefix(2)).uppercased()
        }
        let t = title.isEmpty ? name : title
        // A glyph the person put first IS their face: drawing a letter over it means arguing with their
        // choice. One place for the whole client -- the circle in the list, in the header, in the banner
        // and on the call screen all ask this one.
        if let f = t.first, isEmoji(f) { return String(f) }
        return String(t.prefix(1)).uppercased()
    }
}


// -- Common to the app and the extensions: the list mirror reader and the circle renderer --
// The banner, the call screen and the list must show ONE face ([C-1]).
enum MontanaFace {
    struct Entry { let title: String?; let initial: String?; let colorHex: String?; let thumb: Data? }

    /// A list mirror record by chat key (and by the fallback opening key).
    static func mirrorEntry(_ key: String, alt: String? = nil) -> Entry? {
        guard let d = MontanaKeychain.get("shareChats"),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] else { return nil }
        let hit = arr.first(where: { $0["name"] == key }) ?? alt.flatMap { a in arr.first(where: { $0["name"] == a }) }
        guard let h = hit else { return nil }
        return Entry(title: h["title"], initial: h["initial"], colorHex: h["colorHex"],
                     thumb: h["thumb"].flatMap { Data(base64Encoded: $0) })
    }

    /// The circle exactly as the avatar in the profile and in the list: a BLACK circle, the glyph in
    /// gold (an emoji draws itself), the MontanaAvatar.glyphScale share. The palette does not live here
    static func circleImage(glyph: String, colorHex: String? = nil, side: CGFloat = 120) -> UIImage {
        _ = colorHex   // the former palette input; a face is everywhere on black, as in the profile
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.black.setFill(); ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: side * MontanaAvatar.glyphScale(glyph), weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para]
            let sNS = glyph as NSString
            let r = sNS.boundingRect(with: size, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            sNS.draw(in: CGRect(x: 0, y: (size.height - r.height) / 2, width: size.width, height: r.height),
                     withAttributes: attrs)
        }
    }
}

// The platform's glass for a UIKit plate -- one owner for the app and the share sheet, which compiles no view of the app
// (the author's word 30.09: the share panel is glass, as the big player is).
enum MTGlassKit {
    static func plate(corner: CGFloat, interactive: Bool = false) -> UIVisualEffectView {
        let v: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = interactive
            v = UIVisualEffectView(effect: glass)
        } else {
            v = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        }
        v.clipsToBounds = true
        v.isUserInteractionEnabled = false
        v.layer.cornerRadius = corner
        v.layer.cornerCurve = .continuous
        return v
    }
}

/// THE SHARE SHEET STANDS IN THE CHATS' ORDER BETWEEN THE APP'S RUNS (the author's word 30.09 23:21: «on the share page Send to
/// Montana the order must match the chats»). The app writes the sheet's mirror in the list's own order (ChatStore.listOrder) when
/// it runs; a letter that lands while it sleeps -- read by the notification service -- moved its chat up the list and left the
/// mirror where it was. The list's one rule, applied by whoever reads the letter: the chat goes to the head of its block -- the
/// mesh wall (rank 0), the pinned (1), the rest (2) -- as ChatStore.listOrder puts the freshest first within each.
enum MTShareOrder {
    static let key = "shareChats"
    static func raise(_ conv: String) {
        guard !conv.isEmpty, let d = MontanaKeychain.get(key),
              var rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: String]],
              let i = rows.firstIndex(where: { $0["name"] == conv }) else { return }
        let row = rows.remove(at: i)
        let rank = row["rank"] ?? "2"
        let at = rows.firstIndex(where: { rank <= ($0["rank"] ?? "2") }) ?? rows.count
        guard at != i else { return }   // already the head of its block
        rows.insert(row, at: at)
        if let out = try? JSONSerialization.data(withJSONObject: rows) { MontanaKeychain.set(key, out) }
    }
    /// The order as the diary may say it: the first eight chats, each a short digest of its name -- never the name itself.
    static func print(_ names: [String]) -> String {
        names.prefix(8).map { n in
            var h: UInt32 = 2166136261
            for b in n.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
            return String(format: "%04x", h & 0xffff)
        }.joined(separator: ".")
    }
}
