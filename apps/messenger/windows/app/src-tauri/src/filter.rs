//! THE FILTER (iOS MontanaContentFilter; App Store Guideline 1.2): a letter from another person that carries a word from the
//! list is shown folded -- «hidden by the filter», a tap unfolds it. The list is small and blunt on purpose: it names the words
//! nobody wants to meet by surprise, not every rude one; the person's own letters are never folded. Matched on the lowercased
//! words as whole words. ONE WORD LIST for the feed, the list row and the banner.

use std::sync::atomic::{AtomicBool, Ordering};

/// The person's switch in Privacy (iOS objectionableFilterOn): on by default.
static ON: AtomicBool = AtomicBool::new(true);

pub fn set_on(on: bool) {
    ON.store(on, Ordering::SeqCst);
}

pub fn on() -> bool {
    ON.load(Ordering::SeqCst)
}

const WORDS: &[&str] = &[
    // English
    "fuck", "fucking", "fucker", "motherfucker", "shit", "bullshit", "cunt", "bitch", "asshole", "dick", "cock", "pussy",
    "whore", "slut", "faggot", "fag", "nigger", "nigga", "retard", "kike", "spic", "chink", "tranny", "rape", "rapist",
    "pedo", "paedo", "pedophile",
    // Russian
    "хуй", "хуя", "хуе", "хуи", "хую", "нахуй", "похуй", "пизда", "пизде", "пизду", "пиздец", "пиздато", "блядь", "блять",
    "бля", "ебать", "ебал", "ебаный", "ебаная", "ебанный", "ёбаный", "заебал", "заебали", "выебу", "уебок", "уёбок", "ебло",
    "сука", "суки", "сучка", "пидор", "пидорас", "пидар", "педик", "гандон", "мудак", "мудила", "шлюха",
    "шалава", "чурка", "хач", "жид", "нигер", "дебил", "педофил",
];

/// Whether the words carry one from the list, as a whole word (a letter or a digit is a word's, anything else ends it).
pub fn flags(text: &str) -> bool {
    text.to_lowercase().split(|c: char| !c.is_alphanumeric()).any(|w| !w.is_empty() && WORDS.contains(&w))
}

/// A letter folds when it is theirs, the filter is on and its words flag.
pub fn folds(mine: bool, words: &str) -> bool {
    !mine && on() && flags(words)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_listed_word_folds_their_letter_as_a_whole_word_only() {
        assert!(flags("What the FUCK is this"));
        assert!(flags("ну ты и Сука!"));
        assert!(flags("ёбаный стыд"));
        assert!(!flags("Dickens wrote it; a cockpit and a classic"), "a word inside another is no word of the list");
        assert!(!flags("сукабля"), "two listed words run together are neither");
        assert!(!flags(""));
        assert!(folds(false, "shit happens"));
        assert!(!folds(true, "shit happens"), "my own letter never folds");
        set_on(false);
        assert!(!folds(false, "shit happens"), "the filter turned off folds nothing");
        set_on(true);
    }
}
