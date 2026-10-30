//! THE CARD OF A LINK (iOS MTLinkPreview): built the Montana way -- the SENDER reads the page's own description (og:*) and the
//! card rides inside the sealed letter, its seventh field. The receiver never touches the site before tapping: the only honest
//! reader of a link is the person who chose to share it. A card that rides the box's envelope carries no picture (iOS
//! withoutImage: the envelope is 2048 bytes); its words are cut as iOS cuts them.

use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// A page read once is not read again while the program lives (iOS read / readNothing).
static READ: Mutex<Option<HashMap<String, Option<Value>>>> = Mutex::new(None);

/// Every web link of the words, in their order (iOS webURLs): http and https with a host.
pub fn urls(text: &str) -> Vec<String> {
    let mut out = vec![];
    for word in text.split(|c: char| c.is_whitespace() || c == '<' || c == '>' || c == '"') {
        let lower = word.to_ascii_lowercase();
        let Some(at) = lower.find("https://").or_else(|| lower.find("http://")) else { continue };
        let link = word[at..].trim_end_matches(['.', ',', ';', ':', '!', '?', ')', ']', '}', '»', '\'', '…']);
        let rest = link.split_once("://").map_or("", |(_, r)| r);
        let host = rest.split(['/', '?', '#']).next().unwrap_or("");
        if !host.is_empty() && host.contains('.') && !host.contains('@') {
            out.push(link.to_string());
        }
    }
    out
}

/// The card of the first link of the words that has a face (iOS buildBounded: three links at most, four seconds over them all).
pub fn build(text: &str) -> Option<Value> {
    let start = Instant::now();
    for u in urls(text).into_iter().take(3) {
        if start.elapsed() > Duration::from_secs(4) {
            break;
        }
        if let Some(card) = card_of(&u) {
            return Some(card);
        }
    }
    None
}

fn card_of(url: &str) -> Option<Value> {
    if let Some(held) = READ.lock().unwrap().get_or_insert_with(HashMap::new).get(url) {
        return held.clone();
    }
    let card = if let Some((id, music)) = youtube(url) { tube_card(url, &id, music) } else { page_card(url) };
    READ.lock().unwrap().get_or_insert_with(HashMap::new).insert(url.to_string(), card.clone());
    card
}

fn page_card(url: &str) -> Option<Value> {
    let (code, bytes) = crate::http::get(url, 3_000, 64 * 1024, true)?;
    if !(200..300).contains(&code) {
        return None;
    }
    let html = String::from_utf8_lossy(&bytes).into_owned();
    let host = host_of(url);
    let site = meta(&html, "og:site_name").or(host);
    let title = meta(&html, "og:title").or_else(|| tag_title(&html));
    let desc = meta(&html, "og:description").or_else(|| meta(&html, "description"));
    let mut card = Map::new();
    card.insert("u".into(), json!(url));
    put(&mut card, "s", clean(site, 64));
    put(&mut card, "t", clean(title, 300));
    put(&mut card, "d", clean(desc, 800));
    if !card.contains_key("t") && !card.contains_key("d") {
        return None; // a card with nothing to say is noise, not a preview
    }
    // the picture's address is remembered (iOS: read on its own road); the receiver never reads it
    if let Some(p) = meta(&html, "og:image").or_else(|| meta(&html, "og:image:secure_url")).or_else(|| meta(&html, "twitter:image")) {
        if let Some(abs) = absolute(url, &p) {
            card.insert("p".into(), json!(abs));
        }
    }
    Some(Value::Object(card))
}

/// A YouTube link's card (iOS youtubeCard): its title and channel by YouTube's own oEmbed, its picture's address.
fn tube_card(url: &str, id: &str, music: bool) -> Option<Value> {
    let ask = format!("https://www.youtube.com/oembed?url={}&format=json", encode(url));
    let words: Value = crate::http::get(&ask, 2_500, 16_384, false).filter(|(c, _)| *c == 200)
        .and_then(|(_, b)| serde_json::from_slice(&b).ok()).unwrap_or_default();
    let mut card = Map::new();
    card.insert("u".into(), json!(url));
    card.insert("s".into(), json!(if music { "YouTube Music" } else { "YouTube" }));
    put(&mut card, "t", clean(words["title"].as_str().map(str::to_string), 300));
    put(&mut card, "d", clean(words["author_name"].as_str().map(str::to_string), 200));
    card.insert("p".into(), json!(format!("https://i.ytimg.com/vi/{id}/hqdefault.jpg")));
    card.insert("w".into(), json!(480));
    card.insert("h".into(), json!(360));
    (card.contains_key("t") || card.contains_key("d")).then_some(Value::Object(card))
}

fn put(card: &mut Map<String, Value>, k: &str, v: Option<String>) {
    if let Some(v) = v {
        card.insert(k.into(), json!(v));
    }
}

/// The card as the box's envelope carries it (iOS withoutImage + fitting): no picture, and only a card that says something.
pub fn wire(lp: &str) -> Option<String> {
    let mut card = parse(lp)?;
    card.as_object_mut()?.remove("i");
    let j = card.to_string();
    (j.len() > 64 && j.len() <= 16_384).then_some(j)
}

/// The card as a long road carries it -- a group's word «lp», the letter's own copy (iOS fitting): whole with its picture when it
/// fits 16 KB (the window cut the picture to fit), else its words alone.
pub fn fitted(lp: &str) -> Option<String> {
    let j = parse(lp)?.to_string();
    if j.len() > 64 && j.len() <= 16_384 {
        return Some(j);
    }
    wire(lp)
}

/// A CARD THAT LEARNED ITS PICTURE (iOS enrichLinkPreview): a row with no card takes the one that came; a row whose card has no
/// picture takes the picture of a card of the same link; a card that came without a picture never takes one away.
pub fn enrich(standing: &str, fresh: &str) -> Option<String> {
    let fresh_card = parse(fresh)?;
    let Some(old) = parse(standing) else { return Some(fresh_card.to_string()) };
    let has = |c: &Value| c.get("i").and_then(|i| i.as_str()).is_some_and(|i| !i.is_empty());
    if has(&old) || !has(&fresh_card) || old["u"] != fresh_card["u"] {
        return None;
    }
    let mut filled = old;
    for k in ["i", "w", "h", "p"] {
        if let Some(v) = fresh_card.get(k) {
            filled[k] = v.clone();
        }
    }
    Some(filled.to_string())
}

/// A card that came with a letter (iOS MTLinkPreview.parse): a JSON object naming an http(s) link.
pub fn parse(lp: &str) -> Option<Value> {
    let v: Value = serde_json::from_str(lp).ok()?;
    let u = v["u"].as_str()?;
    (u.starts_with("https://") || u.starts_with("http://")).then_some(v)
}

/// The video a YouTube address names (iOS youtube): its id of eleven signs, and whether it is the music host.
pub fn youtube(url: &str) -> Option<(String, bool)> {
    let rest = url.split_once("://")?.1;
    let (host, path) = rest.split_once('/').unwrap_or((rest, ""));
    let host = host.to_ascii_lowercase();
    let bare = host.strip_prefix("www.").unwrap_or(&host);
    let music = bare == "music.youtube.com";
    if !["youtu.be", "youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com"].contains(&bare) {
        return None;
    }
    let (path, query) = path.split_once('?').unwrap_or((path, ""));
    let parts: Vec<&str> = path.split('/').filter(|p| !p.is_empty()).collect();
    let picked = if bare == "youtu.be" {
        parts.first().map(|s| s.to_string())
    } else if parts.len() > 1 && ["shorts", "embed", "live", "v"].contains(&parts[0]) {
        Some(parts[1].to_string())
    } else {
        query.split('&').find_map(|kv| kv.strip_prefix("v=")).map(str::to_string)
    }?;
    let ok = picked.len() == 11 && picked.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    ok.then_some((picked, music))
}

fn host_of(url: &str) -> Option<String> {
    let rest = url.split_once("://")?.1;
    Some(rest.split(['/', '?', '#']).next()?.to_string()).filter(|h| !h.is_empty())
}

fn absolute(base: &str, p: &str) -> Option<String> {
    let p = p.trim();
    if p.starts_with("https://") || p.starts_with("http://") {
        return Some(p.to_string());
    }
    let scheme = base.split_once("://")?.0;
    if let Some(r) = p.strip_prefix("//") {
        return Some(format!("{scheme}://{r}"));
    }
    let host = host_of(base)?;
    if p.starts_with('/') {
        return Some(format!("{scheme}://{host}{p}"));
    }
    None
}

fn encode(s: &str) -> String {
    s.bytes().map(|b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect()
}

/// The words of a card, made tidy (iOS clean): whitespace folded, cut to `cap` signs.
fn clean(s: Option<String>, cap: usize) -> Option<String> {
    let s = s?.split_whitespace().collect::<Vec<_>>().join(" ");
    let s: String = s.chars().take(cap).collect();
    (!s.is_empty()).then_some(s)
}

/// The content of the head's meta tag whose «property» or «name» is the one asked (iOS meta: every meta tag read as a tag).
fn meta(html: &str, prop: &str) -> Option<String> {
    let lower = html.to_ascii_lowercase();
    let mut from = 0;
    while let Some(at) = lower[from..].find("<meta") {
        let start = from + at + 5;
        let Some(end) = lower[start..].find('>').map(|e| start + e) else { break };
        let a = attributes(&html[start..end]);
        let key = a.get("property").or_else(|| a.get("name"));
        if key.is_some_and(|k| k.eq_ignore_ascii_case(prop)) {
            if let Some(v) = a.get("content").map(|c| entities(c)).filter(|v| !v.trim().is_empty()) {
                return Some(v);
            }
        }
        from = end;
    }
    None
}

/// A tag's attributes, their names in lower case: name="..." / name='...' / name=bare.
fn attributes(tag: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    let b = tag.as_bytes();
    let mut i = 0;
    while i < b.len() {
        while i < b.len() && (b[i].is_ascii_whitespace() || b[i] == b'/') {
            i += 1;
        }
        let ns = i;
        while i < b.len() && !b[i].is_ascii_whitespace() && b[i] != b'=' && b[i] != b'/' {
            i += 1;
        }
        let name = tag[ns..i].to_ascii_lowercase();
        while i < b.len() && b[i].is_ascii_whitespace() {
            i += 1;
        }
        if i < b.len() && b[i] == b'=' {
            i += 1;
            while i < b.len() && b[i].is_ascii_whitespace() {
                i += 1;
            }
            let value = if i < b.len() && (b[i] == b'"' || b[i] == b'\'') {
                let q = b[i];
                let vs = i + 1;
                let ve = tag[vs..].bytes().position(|c| c == q).map_or(tag.len(), |p| vs + p);
                i = (ve + 1).min(b.len());
                &tag[vs..ve.min(tag.len())]
            } else {
                let vs = i;
                while i < b.len() && !b[i].is_ascii_whitespace() {
                    i += 1;
                }
                &tag[vs..i]
            };
            if !name.is_empty() {
                out.entry(name).or_insert_with(|| value.to_string());
            }
        } else if name.is_empty() {
            i += 1;
        }
    }
    out
}

fn tag_title(html: &str) -> Option<String> {
    let lower = html.to_ascii_lowercase();
    let at = lower.find("<title")?;
    let open = at + lower[at..].find('>')? + 1;
    let close = open + lower[open..].find("</title")?;
    Some(entities(&html[open..close])).filter(|t| !t.trim().is_empty())
}

/// The entities a head writes: the five named ones and the numbered.
fn entities(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(at) = rest.find('&') {
        out.push_str(&rest[..at]);
        rest = &rest[at..];
        let Some(end) = rest[..rest.len().min(12)].find(';') else {
            out.push('&');
            rest = &rest[1..];
            continue;
        };
        let name = &rest[1..end];
        let ch = match name {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" | "#39" => Some('\''),
            "nbsp" => Some(' '),
            n if n.starts_with("#x") || n.starts_with("#X") => u32::from_str_radix(&n[2..], 16).ok().and_then(char::from_u32),
            n if n.starts_with('#') => n[1..].parse::<u32>().ok().and_then(char::from_u32),
            _ => None,
        };
        match ch {
            Some(c) => {
                out.push(c);
                rest = &rest[end + 1..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_links_of_the_words_are_found_in_their_order() {
        assert_eq!(urls("смотри https://montana.quest/a?b=1, и (http://x.org/p). а это не ссылка: ftp://a.b"),
                   ["https://montana.quest/a?b=1", "http://x.org/p"]);
        assert!(urls("нет ссылок, только https:// и http://localhost").is_empty());
    }

    #[test]
    fn a_head_is_read_as_tags_whatever_its_letters() {
        let html = r#"<html><head><title>Запас &amp; ещё</title>
            <meta property="og:site_name" content="GitHub">
            <meta content='Montana &#8212; the messenger' property='og:title'/>
            <meta name="description" content="Летопись &quot;времени&quot;">
            <meta property="og:image" content="/img/card.png"></head>"#;
        assert_eq!(meta(html, "og:site_name").as_deref(), Some("GitHub"), "a value with the letters q and t is read (iOS 22.09)");
        assert_eq!(meta(html, "og:title").as_deref(), Some("Montana — the messenger"));
        assert_eq!(meta(html, "description").as_deref(), Some("Летопись \"времени\""));
        assert_eq!(tag_title(html).as_deref(), Some("Запас & ещё"));
        assert_eq!(absolute("https://github.com/x/y", "/img/card.png").as_deref(), Some("https://github.com/img/card.png"));
    }

    #[test]
    fn a_youtube_link_names_its_video_and_the_wire_card_carries_no_picture() {
        assert_eq!(youtube("https://youtu.be/dQw4w9WgXcQ?t=1"), Some(("dQw4w9WgXcQ".into(), false)));
        assert_eq!(youtube("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=x"), Some(("dQw4w9WgXcQ".into(), false)));
        assert_eq!(youtube("https://music.youtube.com/watch?v=dQw4w9WgXcQ"), Some(("dQw4w9WgXcQ".into(), true)));
        assert_eq!(youtube("https://www.youtube.com/shorts/dQw4w9WgXcQ"), Some(("dQw4w9WgXcQ".into(), false)));
        assert!(youtube("https://example.com/watch?v=dQw4w9WgXcQ").is_none());
        let full = r#"{"u":"https://montana.quest","s":"Montana","t":"The messenger of time","i":"/9j/AAAA","w":800,"h":400}"#;
        let w = wire(full).unwrap();
        assert!(!w.contains("\"i\"") && w.contains("\"t\":\"The messenger of time\""));
        assert!(wire(r#"{"u":"https://a.b","t":"x"}"#).is_none(), "a card shorter than 65 bytes does not ride (iOS fitting)");
        assert!(parse(r#"{"u":"javascript:alert(1)","t":"x"}"#).is_none());
    }

    #[test]
    fn a_card_learns_its_picture_and_never_loses_it() {
        let words = r#"{"u":"https://example.org/page","s":"Example","t":"A page title that says something about the page","p":"https://example.org/a.jpg"}"#;
        let full = r#"{"u":"https://example.org/page","s":"Example","t":"A page title that says something about the page","p":"https://example.org/a.jpg","i":"/9j/AAAA","w":800,"h":400}"#;
        let got: Value = serde_json::from_str(&enrich(words, full).unwrap()).unwrap();
        assert_eq!((got["i"].as_str(), got["w"].as_i64(), got["t"].as_str()), (Some("/9j/AAAA"), Some(800), Some("A page title that says something about the page")));
        assert!(enrich(full, words).is_none(), "a card without its picture never takes one away");
        let other = full.replace("https://example.org/page", "https://example.org/other");
        assert!(enrich(words, &other).is_none(), "another link's picture is not this card's");
        assert!(enrich("", words).is_some(), "a row with no card takes the one that came");
        // the pair's envelope carries the words alone, a long road the card whole while it fits
        assert!(!wire(full).unwrap().contains("\"i\""));
        assert!(fitted(full).unwrap().contains("\"i\""));
    }
}
