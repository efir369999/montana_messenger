import Foundation

// ONE WORD LIST for the app and the push extension ([C-1]): the fold in the feed, the list
// row and the banner all read it. Foundation only, so the extension can carry it.
/// THE FILTER: a letter from another person that carries a word from the list is shown folded
/// — «hidden by the filter», a tap unfolds it. The list is small and blunt on purpose: it names
/// the words nobody wants to meet by surprise, not every rude one; the person's own letters
/// are never folded. Matched on the lowercased text as whole words.
enum MontanaContentFilter {
    private static let words: Set<String> = [
        // English
        "fuck", "fucking", "fucker", "motherfucker", "shit", "bullshit", "cunt", "bitch", "asshole", "dick", "cock", "pussy",
        "whore", "slut", "faggot", "fag", "nigger", "nigga", "retard", "kike", "spic", "chink", "tranny", "rape", "rapist",
        "pedo", "paedo", "pedophile",
        // Russian
        "хуй", "хуя", "хуе", "хуи", "хую", "нахуй", "похуй", "пизда", "пизде", "пизду", "пиздец", "пиздато", "блядь", "блять",   // CYRILLIC-DATA-OK: the filter's own word list
        "бля", "ебать", "ебал", "ебаный", "ебаная", "ебанный", "ёбаный", "заебал", "заебали", "выебу", "уебок", "уёбок", "ебло",   // CYRILLIC-DATA-OK: the filter's own word list
        "сука", "суки", "сучка", "пидор", "пидорас", "пидар", "педик", "гандон", "мудак", "мудила", "шлюха",   // CYRILLIC-DATA-OK: the filter's own word list
        "шалава", "чурка", "хач", "жид", "нигер", "дебил", "педофил",   // CYRILLIC-DATA-OK: the filter's own word list
    ]
    /// THE VERDICT IS KEPT BY THE WORDS (28.09): a correspondent's bubble asks at every pass of its body, and the walk lowers and
    /// spells the whole letter a character at a time -- every letter in view again at every tick of the player or a transfer. The
    /// same words have the same verdict; it is kept under them, in the platform's own cache, safe from any thread.
    private final class Verdict { let flags: Bool; init(_ flags: Bool) { self.flags = flags } }
    private static let kept: NSCache<NSString, Verdict> = { let c = NSCache<NSString, Verdict>(); c.countLimit = 4096; return c }()
    static func flags(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let key = text as NSString
        if let known = kept.object(forKey: key) { return known.flags }
        let verdict = walk(text)
        kept.setObject(Verdict(verdict), forKey: key)
        return verdict
    }
    private static func walk(_ text: String) -> Bool {
        let lower = text.lowercased()
        var word = ""
        for ch in lower {
            if ch.isLetter || ch.isNumber { word.append(ch); continue }
            if !word.isEmpty { if words.contains(word) { return true }; word = "" }
        }
        return !word.isEmpty && words.contains(word)
    }
}

