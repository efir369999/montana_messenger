import Foundation

// The call sign of a person who has claimed no name ([I-10]/[C-1]).
//
// A person without a nickname is still a person, and an address is not a way to call one. The set
// says how it is chosen: seven bits taken from that person's own reference pick one of the hundred
// and twenty-eight rows shipped beside the app. Nobody issues it and nowhere is it registered — it
// follows from the seed, so the same person carries the same call sign on every device of theirs
// and after any reinstall, while nobody else computes it without knowing the reference.
//
// It is data, not code: the rows live in `callsigns.tsv`, and a row is read in the language of the
// device -- English, Russian or Chinese -- so the same person is "Tiger" to one reader and another
// another without either being told anything new.
enum MontanaCallsign {

    private struct Row { let en: String; let ru: String; let zh: String; let emoji: String }

    private static let lock = NSLock()
    private static var rows: [Row] = []

    private static func table() -> [Row] {
        lock.lock(); defer { lock.unlock() }
        if !rows.isEmpty { return rows }
        guard let u = Bundle.main.url(forResource: "callsigns", withExtension: "tsv"),
              let text = try? String(contentsOf: u, encoding: .utf8) else { return [] }
        var out: [Row] = []
        for line in text.split(separator: "\n") {
            guard !line.hasPrefix("#") else { continue }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 5 else { continue }
            // A row glyph is DATA, like the row itself: it lives in the same table and changes without
            // one edit of code. It also becomes the face of whoever took the callsign: the first
            // character of a name is the avatar, and there is no second place for this decision.
            out.append(Row(en: String(f[1]), ru: String(f[2]), zh: String(f[4]),
                           emoji: f.count >= 6 ? String(f[5]) : ""))
        }
        rows = out
        return out
    }

    /// Every call sign, in the app's one language (MTLanguage) — for the screen where a person picks one.
    static func all() -> [String] {
        let lang = MTLanguage.code.lowercased()
        return table().map { named($0, lang) }
    }

    /// A row with its own glyph in front -- the one place where they are joined.
    private static func named(_ r: Row, _ lang: String) -> String {
        let word = lang.hasPrefix("ru") ? r.ru : (lang.hasPrefix("zh") ? r.zh : r.en)
        return r.emoji.isEmpty ? word : r.emoji + " " + word
    }

    /// The row this reference lands on, in the language of the device. Empty when the table is
    /// missing — a person is then shown by the short form of their reference, exactly as before.
    static func of(_ reference: String) -> String {
        let t = table()
        guard !t.isEmpty, !reference.isEmpty else { return "" }
        // The pick covers the WHOLE list (author's rule): a deterministic fold of the
        // reference modulo the row count — any row in the file can be somebody's call sign.
        var sum: UInt32 = 0
        for b in Array(reference.utf8).prefix(8) { sum = sum &* 31 &+ UInt32(b) }
        let row = t[Int(sum % UInt32(t.count))]
        return named(row, MTLanguage.code.lowercased())
    }
}
