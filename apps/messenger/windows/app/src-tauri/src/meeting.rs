//! THE ONE MEETING RESOLVER, the scanner's side (iOS MontanaMeeting + MontanaCard.expand/meet; Android Meeting.kt): a link
//! names an invitation -> the card is fetched from the node under it and opened (or it answers «spent») -> one encapsulation
//! to the card's key, the first secret, the pipe born, the chat standing with the card's name -> the first letter the person
//! writes rides the invitation's box carrying the ciphertext, and every letter after it does too, until the other side
//! answers under the pipe. One link, one conversation: a repeated scan returns to the chat it opened.

use crate::book::Book;
use crate::card::{perm_bid, rdv_bid, rdv_key, Card, SPENT_MAGIC};
use crate::profile::strip_crown;
use crate::vault::Vault;
use crate::wire::{b64, b64url, unb64, unb64url};
use crate::{crypto, doors};
use serde_json::{json, Map, Value};
use std::sync::Mutex;

const FIRSTS: &str = "pipeFirst"; // ref -> {ct, inv}: the introduction still unanswered
const SCANS: &str = "rdvScanned"; // invitation -> ref (iOS scanBook)
const CARDS: &str = "cardMetByRoot"; // card root -> ref (iOS cardBook)
static GATE: Mutex<()> = Mutex::new(());

#[derive(Debug, PartialEq, serde::Serialize)]
#[serde(tag = "kind", content = "chat")]
pub enum Outcome {
    Opened(String),
    Spent,
    Refused,
    Own,
    /// not a Montana invitation at all (iOS «This link is not a Montana invitation.»)
    Foreign,
}

fn jmap(v: &Vault, name: &str) -> Map<String, Value> {
    match v.get(name).and_then(|b| serde_json::from_slice(&b).ok()) {
        Some(Value::Object(o)) => o,
        _ => Map::new(),
    }
}

fn jsave(v: &Vault, name: &str, o: Map<String, Value>) {
    v.set(name, Value::Object(o).to_string().as_bytes());
}

/// The link as a messenger may have mangled it: percent bytes, glued punctuation, a capitalised scheme (iOS normalizeLink).
pub fn normalize(s: &str) -> String {
    let mut raw = s.trim().to_string();
    if raw.contains('%') {
        raw = percent_decode(&raw);
    }
    while raw.ends_with(|c: char| ".,;:!?)]}>»›\"'’”…".contains(c)) {
        raw.pop();
    }
    if let Some(i) = raw.find("://") {
        raw = raw[..i].to_lowercase() + &raw[i..];
    }
    raw
}

fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Ok(x) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                out.push(x);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8(out).unwrap_or_else(|_| s.to_string())
}

/// The 32-byte invitation inside a short link, or None (iOS MontanaCard.invite(inShort:)): /r/, /perp/ and /temp/ of
/// montana.quest and montana.xxx (the Business writes there), and montana://r/.
pub fn invite(link: &str) -> Option<Vec<u8>> {
    let t = normalize(link);
    let mut forms: Vec<String> = Vec::new();
    for h in ["montana.quest", "montana.xxx", "www.montana.xxx"] {
        for k in ["r", "perp", "temp"] {
            forms.push(format!("https://{h}/{k}/"));
        }
    }
    forms.push("montana://r/".into());
    let form = forms.iter().find(|f| t.starts_with(f.as_str()))?;
    let code = t[form.len()..].split(['?', '#']).next()?.trim_end_matches('/');
    unb64url(code).filter(|i| i.len() == 32)
}

/// The card under an invitation, opened; SPENT for a tombstone; None when no door gave it (iOS expand, four tries).
fn expand(inv: &[u8]) -> Option<Vec<u8>> {
    for attempt in 0..4 {
        if let Some(sealed) = doors::get_blob(&rdv_bid(inv)) {
            if let Some(p) = crypto::open(&rdv_key(inv), &sealed) {
                if p == SPENT_MAGIC || (1184..=1184 + 64).contains(&p.len()) {
                    return Some(p);
                }
            }
        }
        if attempt < 3 {
            std::thread::sleep(std::time::Duration::from_millis(900));
        }
    }
    None
}

/// Was the link a permanent one? The mark beside the card says so (iOS isPermanent).
fn is_permanent(inv: &[u8]) -> bool {
    doors::get_blob(&perm_bid(inv)).and_then(|s| crypto::open(&rdv_key(inv), &s)).is_some_and(|p| p == b"mt-rdv-perm")
}

/// Meets what the link hands over; the network is asked, so this runs off the window's thread.
pub fn meet(v: &Vault, book: &Book, link: &str) -> Outcome {
    let Some(inv) = invite(link) else { return Outcome::Foreign };
    let inv64 = b64url(&inv);
    // a repeated scan of the same code returns into the conversation it opened (iOS meet_rescan)
    if let Some(known) = jmap(v, SCANS).get(&inv64).and_then(|r| r.as_str()).filter(|r| book.secret(r).is_some()) {
        return Outcome::Opened(known.to_string());
    }
    // the card's own invitations are not a meeting with oneself
    if (Card { vault: v }).outstanding_invites().contains(&inv) {
        return Outcome::Own;
    }
    let Some(payload) = expand(&inv) else { return Outcome::Refused };
    if payload == SPENT_MAGIC {
        return Outcome::Spent;
    }
    let root = payload[..1184].to_vec();
    let name = String::from_utf8_lossy(&payload[1184..]).trim().to_string();
    let root64 = b64url(&root);
    // ONE ROOT, ONE TUNNEL (iOS cardBook): whatever door the same card came by, the same chat
    let _g = GATE.lock().unwrap();
    if let Some(known) = jmap(v, CARDS).get(&root64).and_then(|r| r.as_str()).filter(|r| book.secret(r).is_some()).map(str::to_string) {
        let mut s = jmap(v, SCANS);
        s.insert(inv64, Value::String(known.clone()));
        jsave(v, SCANS, s);
        return Outcome::Opened(known);
    }
    // one encapsulation, and the correspondence exists; the ciphertext waits for the first letter (iOS MontanaCard.meet)
    let Some((ct, ss)) = crypto::mlkem_encaps(&root) else { return Outcome::Refused };
    let Some(secret) = crypto::first_secret(&ss, &root, &ct) else { return Outcome::Refused };
    let Some(r) = book.establish(&secret) else { return Outcome::Refused };
    let mut f = jmap(v, FIRSTS);
    f.insert(r.clone(), json!({ "ct": b64(&ct), "inv": b64(&inv) }));
    jsave(v, FIRSTS, f);
    let mut s = jmap(v, SCANS);
    s.insert(inv64, Value::String(r.clone()));
    jsave(v, SCANS, s);
    let mut c = jmap(v, CARDS);
    c.insert(root64, Value::String(r.clone()));
    jsave(v, CARDS, c);
    drop(_g);
    book.open(&r, &strip_crown(&name), is_permanent(&inv));
    Outcome::Opened(r)
}

/// The ciphertext and the invitation the next letter to `r` must carry, while the introduction is unanswered.
pub fn first(v: &Vault, r: &str) -> Option<(Vec<u8>, Vec<u8>)> {
    let o = jmap(v, FIRSTS).get(r)?.clone();
    Some((unb64(o["ct"].as_str()?)?, unb64(o["inv"].as_str()?)?))
}

/// The other side wrote under the pipe: the introduction is over, the ciphertext is spent (iOS firstContactDone).
pub fn first_done(v: &Vault, r: &str) -> bool {
    let _g = GATE.lock().unwrap();
    let mut f = jmap(v, FIRSTS);
    let ended = f.remove(r).is_some();
    if ended {
        jsave(v, FIRSTS, f);
    }
    ended
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_invitation_is_read_from_every_form_a_link_takes() {
        let inv = vec![9u8; 32];
        let code = b64url(&inv);
        for link in [
            format!("https://montana.quest/perp/{code}"),
            format!("HTTPS://montana.quest/temp/{code}."),
            format!("https://montana.xxx/r/{code}?x=1"),
            format!("https://www.montana.xxx/r/{code}/"),
            format!("montana://r/{code}"),
        ] {
            assert_eq!(invite(&link), Some(inv.clone()), "{link}");
        }
        assert_eq!(invite("https://example.com/perp/AAAA"), None);
        assert_eq!(invite(&format!("https://montana.quest/perp/{}", b64url(&[1u8; 31]))), None);
    }
}
