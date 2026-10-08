package quest.montana.app

/**
 * THE FILTER (iOS MontanaContentFilter, Guideline 1.2): a letter from another person that carries a word from the list stands
 * folded, «Hidden by the filter», and the person's own tap unfolds it. The list is small and blunt on purpose: it names the
 * words nobody wants to meet by surprise, not every rude one; the person's own letters are never folded. Matched on the
 * lowercased text as whole words. One list for the feed, the list's row and the banner ([C-1]); the switch is on until the
 * person turns it off (iOS MontanaSafety.filterOn).
 */
object ContentFilter {
    private val WORDS = setOf(
        // English
        "fuck", "fucking", "fucker", "motherfucker", "shit", "bullshit", "cunt", "bitch", "asshole", "dick", "cock", "pussy",
        "whore", "slut", "faggot", "fag", "nigger", "nigga", "retard", "kike", "spic", "chink", "tranny", "rape", "rapist",
        "pedo", "paedo", "pedophile",
        // Russian
        "хуй", "хуя", "хуе", "хуи", "хую", "нахуй", "похуй", "пизда", "пизде", "пизду", "пиздец", "пиздато", "блядь", "блять",
        "бля", "ебать", "ебал", "ебаный", "ебаная", "ебанный", "ёбаный", "заебал", "заебали", "выебу", "уебок", "уёбок", "ебло",
        "сука", "суки", "сучка", "пидор", "пидорас", "пидар", "педик", "гандон", "мудак", "мудила", "шлюха",
        "шалава", "чурка", "хач", "жид", "нигер", "дебил", "педофил",
    )
    val on: Boolean get() = Prefs.bool("objectionableFilterOn", true)
    // the same words have the same verdict: a bubble asks at every pass of its body (iOS «the verdict is kept by the words»)
    private val kept = android.util.LruCache<String, Boolean>(4096)
    fun flags(text: String): Boolean {
        if (text.isEmpty()) return false
        kept.get(text)?.let { return it }
        return walk(text).also { kept.put(text, it) }
    }
    private fun walk(text: String): Boolean {
        val word = StringBuilder()
        for (ch in text.lowercase()) {
            if (ch.isLetterOrDigit()) { word.append(ch); continue }
            if (word.isNotEmpty()) { if (word.toString() in WORDS) return true; word.setLength(0) }
        }
        return word.isNotEmpty() && word.toString() in WORDS
    }
    /** A letter of theirs the list hides, wherever it is only told of (the list's row, the banner): hidden whatever was opened. */
    fun hides(mine: Boolean, text: String) = !mine && on && flags(text)
    private val opened = HashSet<String>()
    /** Folded in the feed: hidden, and not yet opened by the person's own tap (iOS MTFilterFold). */
    fun folded(m: Msg) = m.mid !in opened && hides(m.mine, m.text)
    fun open(mid: String) { opened.add(mid) }
}
