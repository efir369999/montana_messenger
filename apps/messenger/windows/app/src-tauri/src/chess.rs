//! CHESS ON THE WIRE (iOS MTChessWire): a game's letters are ordinary receipted letters -- «♟ » and a title, then the line
//! `montana://chess/1/` and the letter's JSON in base64 («+» written «-», «/» written «_»). Once a game is made the chat holds
//! only its invitation: every later letter is the board's alone -- no bubble, no unread, no banner, a silent push -- and two
//! letters of a game ring, the invitation and the one that ends it (iOS isStep, rings). The board itself -- the rules, the
//! replay of the letters, the clocks -- is the window's (Chess.jsx); here the feed only knows which letters are steps.

use serde_json::Value;

pub const LINK: &str = "montana://chess/1/";

/// The letter a chess text carries, as iOS parses its frame: «♟ » first, at most 2048 bytes, the link on the last line, the
/// JSON an object naming its game, its own name and its kind. The window judges the rest.
pub fn letter(text: &str) -> Option<Value> {
    if !text.starts_with("♟ ") || text.len() > 2048 {
        return None;
    }
    let line = text.rsplit('\n').next()?;
    let code = line.strip_prefix(LINK)?.replace('-', "+").replace('_', "/");
    let o: Value = serde_json::from_slice(&crate::wire::unb64(&code)?).ok()?;
    let named = |k: &str| o[k].as_str().is_some_and(|s| s.len() == 36);
    (named("game") && named("id") && o["kind"].is_string()).then_some(o)
}

/// A letter of a game after its invitation (iOS isStep): the board's alone.
pub fn is_step(text: &str) -> bool {
    letter(text).is_some_and(|o| o["kind"] != "invite")
}

/// The invitation and the letter that ends a game ring (iOS rings); every other letter of it is silent.
pub fn rings(text: &str) -> bool {
    letter(text).is_some_and(|o| o["kind"] == "invite" || o["end"].is_object())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(o: &str) -> String {
        format!("♟ Шахматы\n{LINK}{}", crate::wire::b64(o.as_bytes()).replace('+', "-").replace('/', "_"))
    }

    #[test]
    fn a_games_letters_are_known_by_their_frame() {
        let g = "0f8fad5b-d9cb-469f-a165-70867728950e";
        let m = "7c9e6679-7425-40de-944b-e07fc1f90ae7";
        let invite = text(&format!(r#"{{"game":"{g}","id":"{g}","parent":"","kind":"invite","at":1,"seconds":0}}"#));
        let mv = text(&format!(r#"{{"game":"{g}","id":"{m}","parent":"{g}","kind":"move","at":2,"move":"e2e4"}}"#));
        let end = text(&format!(r#"{{"game":"{g}","id":"{m}","parent":"{g}","kind":"resign","at":3,"end":{{"outcome":"lost","cause":"resign","moves":1}}}}"#));
        assert!(!is_step(&invite) && rings(&invite), "the invitation stands in the chat and rings");
        assert!(is_step(&mv) && !rings(&mv), "a move is the board's alone");
        assert!(is_step(&end) && rings(&end), "the end is a step that rings");
        assert!(!is_step("♟ Шахматы") && letter("привет").is_none());
        assert!(letter(&format!("{invite}{}", "x".repeat(2048))).is_none(), "a letter past 2048 bytes is no game's");
    }
}
