//! Montana for Windows. The window (WebView2) draws; everything Montana is, is the Rust core behind it, reached through
//! the doors of mt_bindings.dll that iOS calls over its C ABI. Only what a person may see crosses into the window.

mod abi;
mod aesgcm;
mod board;
mod book;
mod pageground;
mod calls;
mod card;
mod channel;
mod channels;
mod chess;
mod clipboard;
mod coinboard;
mod coins;
mod coinvault;
mod homenode;
mod homeshelf;
mod nodesetup;
mod tip;
mod cointx;
mod core;
mod doors;
mod filter;
mod groups;
mod hello;
mod history;
mod keeping;
mod linkcard;
mod http;
mod crypto;
mod identity;
mod media;
mod meeting;
mod messenger;
mod music;
mod fabric;
mod forgotten;
mod passwords;
mod person;
mod picture;
mod genesis;
mod protocol;
mod post;
mod presence;
mod profile;
mod qr;
mod replica;
mod trackmeta;
mod rooms;
mod seats;
mod seed;
mod stickers;
mod twin;
mod vault;
mod videoconv;
mod diskuse;
mod voice;
mod vpn;
mod wallet;
mod wire;

use identity::{Failure, Person};
use messenger::Messenger;
use post::marks;
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_notification::NotificationExt;

/// The one word the window hears: the book changed, ask again.
const CHANGED: &str = "montana://changed";
/// The vault's name of the folders over the chats (iOS MTChatFolders.key).
const FOLDERS: &str = "chatFolders";
/// The ladder of one correspondent moved (the chat's name line asks again).
const PRESENCE: &str = "montana://presence";
/// A copy was laid back: what came back (chats, records, media) or why not.
const RESTORED: &str = "montana://restored";
const KEEPING: &str = "montana://keeping";
/// the walls moved: a page came, a post or a comment landed on mine
const WALL: &str = "montana://wall";
/// the book of coins moved: the wallet reads it again
const COINS: &str = "montana://coins";
/// A call's words off its lane; a call that rang by the box.
const CALL_WORDS: &str = "montana://call";
const CALL_RING: &str = "montana://ring";

fn changed(app: &AppHandle) {
    let _ = app.emit(CHANGED, ());
}

/// THE PIECES OF A LONG TEXT (iOS ChatStore.splitLong 6378-6399): at most 4500 characters each, cut back to the last line
/// break or full stop; each piece one letter, the quote on the first. A piece over one envelope rides as a blob (LB:).
const PIECE: usize = 4500;

fn pieces(text: &str) -> Vec<String> {
    let mut out = vec![];
    let mut rest: Vec<char> = text.chars().collect();
    while rest.len() > PIECE {
        let cut = rest[..PIECE].iter().rposition(|&c| c == '\n' || c == '.').map_or(PIECE, |i| i + 1);
        out.push(rest.drain(..cut).collect::<String>());
    }
    if !rest.is_empty() {
        out.push(rest.into_iter().collect());
    }
    out
}

#[tauri::command]
fn core_info() -> core::CoreInfo {
    core::info()
}

/// Who sits here and my face's version. Read on the blocking pool as copy_pages and disk_use are, and so are chats, chat_open,
/// calls_*, keep_state, bar_first, face_get, media_get, media_list, search and copy_inventory: a DPAPI unseal, a settings file
/// or a walk of a large book never holds one of the few async workers that answer every other invoke.
#[tauri::command]
async fn identity_state(app: AppHandle) -> Result<identity::State, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let mut s = identity::state(&p);
        s.face = m.self_face().map_or(0, |f| i64::from_str_radix(&post::face_tag(&f)[..12], 16).unwrap_or(1));
        Ok(s)
    }).await.map_err(|_| ())?
}

#[tauri::command]
async fn identity_create(p: State<'_, Person>, m: State<'_, Messenger>) -> Result<Vec<String>, Failure> {
    m.reseat();
    let words = identity::create(&p)?;
    if let Some(h) = seats::here() {
        seats::born(h);
    }
    Ok(words)
}

#[tauri::command]
async fn identity_restore(app: AppHandle, p: State<'_, Person>, m: State<'_, Messenger>, words: String) -> Result<(), Failure> {
    // the words of a person waiting on this computer's shelf seat that person again: no second copy of them is born (iOS lift)
    if let Some(h) = seats::here() {
        if seats::lift(h, &words).is_some() {
            trace_line("seat lifted by the words");
            app.restart();
        }
    }
    m.reseat();
    identity::restore(&p, &words)?;
    if let Some(h) = seats::here() {
        seats::born(h);
        // the archive these words left on this computer comes back and is laid as a copy is (forgotten::bring_back)
        if let Some(a) = m.archive(&p) {
            let blocks = forgotten::bring_back(&h.base, &h.folder, &a);
            if !blocks.is_empty() {
                let records: Vec<history::Record> =
                    blocks.into_iter().map(|data| history::Record { kind: history::KIND_BLOCK, name: String::new(), data }).collect();
                let done = history::restore(&a, &m.book, &m.media, Some(&m.faces), &records);
                trace_line(&format!("forgotten back chats={} records={}", done.chats, done.records));
            }
        }
    }
    take_light_then(app, true); // the history another device of these words left on the nodes comes back, then the keepers' copy (iOS takingBack)
    Ok(())
}

#[tauri::command]
async fn identity_copy_words(p: State<'_, Person>) -> Result<bool, ()> {
    Ok(identity::copy_words(&p))
}

#[tauri::command]
async fn identity_set_name(p: State<'_, Person>, name: String) -> Result<bool, ()> {
    Ok(identity::set_name(&p, &name))
}

#[tauri::command]
async fn identity_accept_terms(p: State<'_, Person>) -> Result<bool, ()> {
    Ok(identity::accept_terms(&p))
}

#[tauri::command]
async fn chats(app: AppHandle) -> Result<Vec<messenger::Row>, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        Ok(m.rows())
    }).await.map_err(|_| ())?
}

/// THE UNSENT WORDS (iOS ChatStore.draft / setDraft): what the chat's field held when it was left, and the field's words kept
#[tauri::command]
async fn chat_kept_draft(m: State<'_, Messenger>, chat: String) -> Result<String, ()> {
    Ok(m.drafts().remove(&chat).unwrap_or_default())
}

#[tauri::command]
async fn chat_keep_draft(m: State<'_, Messenger>, chat: String, text: String) -> Result<bool, ()> {
    Ok(m.keep_draft(&chat, &text))
}

#[tauri::command]
async fn chat_open(app: AppHandle, chat: String) -> Result<Option<messenger::Talk>, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        if book::is_saved(&chat) && m.book.chat(&chat).is_none() {
            m.book.edit(&chat, |_| {});   // Saved Messages is born here as it is opened (iOS seedIfNeeded)
        }
        Ok(m.talk(&chat, &p.profile.read().user_name))
    }).await.map_err(|_| ())?
}

/// A letter (a reply when `qm` names the letter answered): drawn «sending» at once, then carried off the window's thread;
/// the window hears each change.
#[tauri::command]
async fn chat_send(app: AppHandle, chat: String, text: String, qt: Option<String>, qm: Option<String>, lp: Option<String>) -> Result<String, String> {
    let text = text.trim().to_string();
    if text.is_empty() || !marks::is_row(&text) || text.starts_with(marks::MEDIA) {
        return Err("empty".into()); // words or a sticker; a file goes by chat_send_media, a word of the wire never from here
    }
    let mid = {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let d = m.desk(&p).ok_or("seat")?;
        if m.book.secret(&chat).is_none() && !groups::is_group(&chat) && !book::is_saved(&chat) {
            return Err("chat".into());
        }
        let (qt, qm) = (qt.unwrap_or_default(), qm.unwrap_or_default());
        let mids = pieces(&text).iter().enumerate()
            .map(|(i, t)| if i == 0 { d.draft(&chat, t, &qt, &qm) } else { d.draft(&chat, t, "", "") })
            .collect::<Vec<_>>();
        // the card the person saw over the field rides the piece whose words hold its link (iOS Compose.attachable)
        if let Some(card) = lp.as_deref().and_then(linkcard::parse) {
            let u = card["u"].as_str().unwrap_or("").to_string();
            if let Some(c) = m.book.chat(&chat) {
                if let Some(row) = c.msgs.iter().find(|x| mids.contains(&x.mid) && linkcard::urls(&x.text).contains(&u)) {
                    let id = row.mid.clone();
                    m.book.edit(&chat, |c| { if let Some(x) = c.msgs.iter_mut().find(|x| x.mid == id) { x.lp = card.to_string(); } });
                }
            }
        }
        mids
    };
    changed(&app);
    let a = app.clone();
    let first = mid[0].clone();
    std::thread::spawn(move || {
        let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
        if let Some(d) = m.desk(&p) {
            for id in &mid {
                d.post(&chat, id);
                changed(&a);
            }
        }
        changed(&a);
    });
    Ok(first)
}

/// THE CARD OF THE LINK IN THE FIELD (iOS MTLinkPreviewBuilder.Compose): read by this machine from the page itself -- three
/// seconds a page, four for all -- while the person still types; nothing while «Link previews» is off.
#[tauri::command]
async fn link_card(p: State<'_, Person>, text: String) -> Result<Option<String>, ()> {
    if p.profile.read().link_previews == Some(false) || linkcard::urls(&text).is_empty() {
        return Ok(None);
    }
    Ok(tauri::async_runtime::spawn_blocking(move || linkcard::build(&text).map(|c| c.to_string())).await.ok().flatten())
}

/// A LINK'S PICTURE (iOS MTLinkPreviewBuilder.picture): read on its own road after the words -- ten seconds, three megabytes, an
/// image alone; the window makes it the card's small JPEG. Nothing while «Link previews» is off.
#[tauri::command]
async fn link_picture(p: State<'_, Person>, url: String) -> Result<tauri::ipc::Response, ()> {
    if p.profile.read().link_previews == Some(false) || !(url.starts_with("https://") || url.starts_with("http://")) || url.chars().any(|c| c.is_whitespace()) {
        return Err(());
    }
    let got = tauri::async_runtime::spawn_blocking(move || http::get(&url, 10_000, 3 * 1024 * 1024, false)).await.ok().flatten();
    trace_line(&format!("lp_picture read code={} bytes={}", got.as_ref().map_or(-1, |g| g.0), got.as_ref().map_or(0, |g| g.1.len())));
    let Some((200, b)) = got else { return Err(()) };
    let image = b.starts_with(&[0xFF, 0xD8, 0xFF]) || b.starts_with(b"\x89PNG") || b.starts_with(b"GIF8") || (b.len() > 12 && &b[..4] == b"RIFF" && &b[8..12] == b"WEBP");
    if !image {
        return Err(());
    }
    Ok(tauri::ipc::Response::new(b))
}

/// THE PICTURE CAUGHT UP (iOS MTLinkCards.picture): the card of my newest letter of that link learns it; in a group the card rides
/// again with it as the group's own word (iOS carryCard); a pair's envelope carries the card's words alone, as iOS's envelope leg.
#[tauri::command]
async fn chat_card(app: AppHandle, chat: String, lp: String) -> Result<bool, ()> {
    let card = linkcard::parse(&lp).filter(|c| c.get("i").and_then(|i| i.as_str()).is_some_and(|i| !i.is_empty()) && lp.len() <= 16_384).ok_or(())?;
    let u = card["u"].as_str().unwrap_or("").to_string();
    let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
    let d = m.desk(&p).ok_or(())?;
    let mid = m.book.chat(&chat).and_then(|c| c.msgs.iter().rev()
        .find(|x| x.mine && linkcard::parse(&x.lp).is_some_and(|c| c["u"].as_str() == Some(u.as_str()) && c.get("i").is_none()))
        .map(|x| x.mid.clone())).ok_or(())?;
    m.book.edit(&chat, |c| { if let Some(x) = c.msgs.iter_mut().find(|x| x.mid == mid) { x.lp = lp.clone(); } });
    if let Some(gid) = chat.strip_prefix("grp:") {
        d.group_card(gid, &mid, &lp);
    }
    changed(&app);
    Ok(true)
}

/// A link of a letter or of its card, opened in the person's browser: http and https alone.
#[tauri::command]
async fn open_link(url: String) -> Result<bool, ()> {
    let ok = (url.starts_with("https://") || url.starts_with("http://")) && !url.chars().any(|c| c.is_whitespace() || c.is_control());
    Ok(ok && open_in_browser(&url))
}

/// A file the walk fetches by itself (iOS: by the network's kind); a bigger one waits for the person's tap.
const AUTO_FETCH: u64 = 50 * 1024 * 1024;

/// The manifest of a file the window sends, from its fields: kind, extension, name, caption, thumbnail, seconds, roundness.
fn manifest_of_meta(meta: &serde_json::Value) -> serde_json::Value {
    let mut manifest = serde_json::json!({ "k": meta["k"].as_str().filter(|k| ["img", "vid", "aud", "doc"].contains(k)).unwrap_or("doc"),
                                           "e": meta["e"].as_str().unwrap_or("bin").chars().take(8).collect::<String>().to_lowercase() });
    for k in ["n", "cap", "th"] {
        if let Some(v) = meta[k].as_str().filter(|v| !v.is_empty()) {
            manifest[k] = serde_json::json!(v);
        }
    }
    if let Some(du) = meta["du"].as_f64() {
        manifest["du"] = serde_json::json!((du * 10.0).round() / 10.0);
    }
    if meta["r"].as_bool() == Some(true) && manifest["k"] == "vid" {
        manifest["r"] = serde_json::json!(true); // a round video note (iOS vnote_: the roundness rides the manifest)
    }
    manifest
}

/// A FILE LARGER THAN 200 MB (iOS MediaSource.file: never read whole): the letter's name first; the window then hands the
/// file a stretch of whole pieces at a time (chat_big_piece), each piece kept sealed under that name, and the letter stands
/// once every piece is here (chat_big_end).
#[tauri::command]
async fn chat_big_begin(m: State<'_, Messenger>, chat: String) -> Result<String, String> {
    if m.book.secret(&chat).is_none() && !groups::is_group(&chat) && !book::is_saved(&chat) {
        return Err("chat".into());
    }
    let store = m.media.clone();
    tauri::async_runtime::spawn_blocking(move || store.sweep()).await.map_err(|_| "sweep")?;
    let mid = book::mint_mid();
    m.big.lock().unwrap().insert(mid.clone());
    Ok(mid)
}

/// A stretch of a big file: header `mid` (from chat_big_begin) and `index` (its first piece's number), the bytes raw -- whole
/// pieces of 512 KiB but the file's last.
#[tauri::command]
async fn chat_big_piece(m: State<'_, Messenger>, request: tauri::ipc::Request<'_>) -> Result<(), String> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err("raw".into()) };
    let head = |k: &str| request.headers().get(k).and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
    let (mid, index) = (head("mid"), head("index").parse::<usize>().map_err(|_| "index")?);
    if !m.big.lock().unwrap().contains(&mid) || body.is_empty() || body.len() > 16 * media::CHUNK {
        return Err("piece".into());
    }
    let (store, body) = (m.media.clone(), body.clone());
    let ok = tauri::async_runtime::spawn_blocking(move || {
        body.chunks(media::CHUNK).enumerate().all(|(i, p)| store.put_piece(&mid, index + i, p))
    }).await.unwrap_or(false);
    if ok { Ok(()) } else { Err("disk".into()) }
}

/// The big file whole: its letter stands and rides, the pieces going up a piece at a time off the window's thread.
#[tauri::command]
async fn chat_big_end(app: AppHandle, chat: String, mid: String, size: u64, meta: serde_json::Value) -> Result<(), String> {
    if !app.state::<Messenger>().big.lock().unwrap().remove(&mid) {
        return Err("mid".into());
    }
    let manifest = manifest_of_meta(&meta);
    let (qt, qm) = (meta["qt"].as_str().unwrap_or("").to_string(), meta["qm"].as_str().unwrap_or("").to_string());
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let Some(d) = m.desk(&p) else { return };
        let mid = d.draft_big(&chat, &mid, size, manifest, &qt, &qm);
        let _ = tx.send(mid.is_some());
        changed(&app);
        if let Some(mid) = mid {
            d.post(&chat, &mid);
        }
        changed(&app);
    });
    if tauri::async_runtime::spawn_blocking(move || rx.recv().unwrap_or(false)).await.unwrap_or(false) { Ok(()) } else { Err("whole".into()) }
}

/// THE PLAYER'S ROAD TO A FILE (iOS AVPlayer over the file): `http://mtfile.localhost/<letter>.<ext>` answers the ranges a
/// <video> or <audio> asks, each read from the pieces it crosses, at most 4 MiB at a time -- a big file plays without ever
/// standing whole in memory. Only this window's own page reaches it.
fn file_range(app: &AppHandle, request: &tauri::http::Request<Vec<u8>>) -> tauri::http::Response<Vec<u8>> {
    use tauri::http::{header, Response, StatusCode};
    const WINDOW: usize = 4 * 1024 * 1024;
    let path = request.uri().path().trim_start_matches('/');
    let (mut mid, ext) = path.rsplit_once('.').unwrap_or((path, ""));
    // a post's file is kept under its whole name, the extension with it (board::file_name «wall_<post>_<n>.<ext>»)
    if mid.starts_with("wall_") && !ext.is_empty() && !mid.contains('.') {
        mid = path;
    }
    let mime = match ext.to_lowercase().as_str() {
        "mp4" | "m4v" | "mov" => "video/mp4",
        "webm" => "video/webm",
        "m4a" => "audio/mp4",
        "aac" => "audio/aac",
        "mp3" => "audio/mpeg",
        "ogg" => "audio/ogg",
        "wav" => "audio/wav",
        _ => "application/octet-stream",
    };
    let refuse = |code: StatusCode| Response::builder().status(code).body(vec![]).unwrap();
    let whole_name = mid == path;
    if mid.is_empty() || !mid.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || (whole_name && c == '.')) {
        return refuse(StatusCode::NOT_FOUND);
    }
    // «bytes=a-b» or «bytes=a-»; none -- from the start
    let range = request.headers().get(header::RANGE).and_then(|v| v.to_str().ok()).and_then(|r| r.strip_prefix("bytes="))
        .and_then(|r| r.split_once('-')).map(|(a, b)| (a.trim().parse::<u64>().ok(), b.trim().parse::<u64>().ok()));
    let (start, last) = match range {
        Some((Some(a), b)) => (a, b),
        None => (0, None),
        _ => return refuse(StatusCode::RANGE_NOT_SATISFIABLE),
    };
    let most = last.map_or(WINDOW, |b| (b.saturating_sub(start) as usize + 1).min(WINDOW));
    let Some((bytes, size)) = app.state::<Messenger>().media.stretch(mid, start, most) else { return refuse(StatusCode::NOT_FOUND) };
    if start >= size {
        return Response::builder().status(StatusCode::RANGE_NOT_SATISFIABLE).header(header::CONTENT_RANGE, format!("bytes */{size}")).body(vec![]).unwrap();
    }
    Response::builder().status(StatusCode::PARTIAL_CONTENT)
        .header(header::CONTENT_TYPE, mime)
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::CONTENT_RANGE, format!("bytes {start}-{}/{size}", start + bytes.len() as u64 - 1))
        .header(header::CONTENT_LENGTH, bytes.len())
        // the bytes are a letter's file in the clear: never laid in the web view's disk cache, where the next person would find them
        .header(header::CACHE_CONTROL, "no-store")
        .body(bytes).unwrap()
}

/// A FILE AS A LETTER (iOS ChatStore.sendMedia): the window hands the bytes raw -- a 4-byte length, the manifest's JSON
/// (chat, k, e, n, cap, th, qt, qm), the file -- and the row stands at once; the pieces go up off the window's thread.
#[tauri::command]
fn chat_send_media(app: AppHandle, request: tauri::ipc::Request) -> Result<(), String> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err("raw".into()) };
    if body.len() < 4 {
        return Err("short".into());
    }
    let n = u32::from_le_bytes([body[0], body[1], body[2], body[3]]) as usize;
    let meta: serde_json::Value = body.get(4..4 + n).and_then(|j| serde_json::from_slice(j).ok()).ok_or("meta")?;
    let bytes = body[4 + n..].to_vec();
    if bytes.is_empty() || bytes.len() > media::MAX_SEND {
        return Err("size".into());
    }
    let chat = meta["chat"].as_str().unwrap_or_default().to_string();
    let manifest = manifest_of_meta(&meta);
    let (qt, qm) = (meta["qt"].as_str().unwrap_or("").to_string(), meta["qm"].as_str().unwrap_or("").to_string());
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let Some(d) = m.desk(&p) else { return };
        if m.book.secret(&chat).is_none() && !groups::is_group(&chat) && !book::is_saved(&chat) {
            return; // a group's key is no pipe: its file goes as the group's word (groups.rs group_deliver)
        }
        if let Some(mid) = d.draft_media(&chat, &bytes, manifest, &qt, &qm) {
            changed(&app);
            d.post(&chat, &mid);
        }
        changed(&app);
    });
    Ok(())
}

/// What the person chose (iOS @AppStorage of Settings): the switches, the language, the words about themselves.
#[tauri::command]
async fn settings_get(p: State<'_, Person>) -> Result<profile::Settings, ()> {
    Ok(p.profile.read())
}

/// One choice of Settings, by its iOS key; anything else is refused. The words about myself go to my correspondents with
/// the next walk.
#[tauri::command]
async fn setting_set(app: AppHandle, key: String, value: serde_json::Value) -> Result<bool, ()> {
    let p = app.state::<Person>();
    let b = value.as_bool();
    let t = value.as_str().unwrap_or("").to_string();
    let ok = match key.as_str() {
        "notifSound" => p.profile.update(|s| s.notif_sound = b),
        "notifPreview" => p.profile.update(|s| s.notif_preview = b),
        "notifSender" => p.profile.update(|s| s.notif_sender = b),
        "readReceiptsEnabled" => p.profile.update(|s| s.read_receipts = b),
        "autoDownload" => p.profile.update(|s| s.auto_download = b),
        "autoDownloadCellular" => p.profile.update(|s| s.auto_download_cellular = b),
        "linkPreviewsEnabled" => p.profile.update(|s| s.link_previews = b),
        "AppLanguage" if ["", "en", "ru"].contains(&t.as_str()) => {
            rooms::set_ru(if t.is_empty() { system_lang().starts_with("ru") } else { t == "ru" });
            p.profile.update(|s| s.language = t)
        }
        "objectionableFilterOn" => {
            filter::set_on(b != Some(false));
            p.profile.update(|s| s.objectionable_filter = b)
        }
        "presenceSharing" => {
            // turned off: «AP:0h» once to the freshest correspondents, then silence (iOS presenceSharing)
            if b == Some(false) {
                let a = app.clone();
                std::thread::spawn(move || {
                    let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
                    if let Some(d) = m.desk(&p) {
                        for r in m.rows().iter().take(128) {
                            m.presence.post(&m.book, &d.twin, &r.reference, &format!("{}0h", presence::APP));
                        }
                    }
                });
            }
            p.profile.update(|s| s.presence_sharing = b)
        }
        "profileBio" => p.profile.update(|s| s.bio = t.trim().chars().take(140).collect()),
        "profileLink" => p.profile.update(|s| s.link = profile::kept_link(&t)),
        _ => return Err(()),
    };
    changed(&app);
    Ok(ok)
}

/// THE 24 WORDS SHOWN AGAIN (iOS SeedShowView): only after Windows Hello said it is the person; the window draws them and
/// keeps them nowhere.
#[tauri::command]
async fn seed_reveal(window: tauri::WebviewWindow, p: State<'_, Person>) -> Result<Vec<String>, String> {
    let hwnd = window.hwnd().map_err(|_| "window")?.0 as isize;
    let reason = if p.lang.starts_with("ru") { "Показать секретную фразу" } else { "Show secret phrase" };
    let verdict = tauri::async_runtime::spawn_blocking(move || hello::verify(hwnd, reason)).await.map_err(|_| "refused")?;
    match verdict {
        hello::Verdict::Verified => p.seed.mnemonic().map(|m| m.split_whitespace().map(str::to_string).collect()).ok_or("none".into()),
        hello::Verdict::NotSet => Err("notset".into()),
        hello::Verdict::Refused => Err("refused".into()),
    }
}

/// DELETE THE ACCOUNT (iOS PrivacyView «Delete account»): the identity of the 24 words leaves this machine, and with it the
/// correspondences, the card, the files; the window returns to the first run.
#[tauri::command]
async fn account_delete(app: AppHandle) -> Result<(), ()> {
    // THE PERSON LEAVES AT THE NEXT START (forgotten.rs, iOS SeedScope.forget): the coin book whole on disk first (iOS writeWhole
    // before setAside), the folder marked, the program started again -- nothing of theirs stays in memory to be written back
    let h = seats::here().ok_or(())?;
    {
        let m = app.state::<Messenger>();
        WALLET_OPEN.store(false, std::sync::atomic::Ordering::SeqCst);
        coins::close_windows(&m.vault, true);
        coins::flush(&m.vault, &m.dir, &|r| groups::is_group(r));
    }
    if !forgotten::mark(&h.folder) {
        return Err(());
    }
    trace_line("account_delete marked");
    app.restart();
}

/// The files of every conversation, for the gallery and the music.
#[tauri::command]
async fn media_list(app: AppHandle) -> Result<Vec<serde_json::Value>, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        Ok(m.files())
    }).await.map_err(|_| ())?
}

/// THE COPY OF THIS MACHINE (iOS «Create backup…»): the archive and the letters' files, sealed under the words, written to
/// Downloads\Montana under the copy's own name; the folder is shown.
#[tauri::command]
async fn history_copy(app: AppHandle) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        m.fill_archive(&p);
        let a = m.archive(&p).ok_or("seat")?;
        let file = history::make_copy_planned(&a, &m.book, &m.media, my_card(&p), &history::Plan::load(&m.vault), &Default::default()).ok_or("seal")?;
        let now = chrono_moment();
        let dir = std::path::PathBuf::from(std::env::var_os("USERPROFILE").ok_or("home")?).join("Downloads").join("Montana");
        std::fs::create_dir_all(&dir).map_err(|_| "disk")?;
        let path = dir.join(history::copy_name(&a.keys().entropy, &now));
        std::fs::write(&path, &file).map_err(|_| "disk")?;
        open_in_browser(&dir.to_string_lossy());
        Ok(path.to_string_lossy().into_owned())
    }).await.map_err(|_| "stopped".to_string())?
}

/// The moment of a copy's name, as iOS writes it (yyyy-MM-dd-HHmmss, local time).
fn chrono_moment() -> String {
    #[cfg(windows)]
    {
        use windows_sys::Win32::System::SystemInformation::GetLocalTime;
        // SAFETY: a SYSTEMTIME the call fills
        let t = unsafe {
            let mut t = std::mem::zeroed();
            GetLocalTime(&mut t);
            t
        };
        format!("{:04}-{:02}-{:02}-{:02}{:02}{:02}", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond)
    }
    #[cfg(not(windows))]
    {
        format!("{}", wire::now_ms() / 1000)
    }
}

/// A COPY LAID BACK (iOS «Restore from backup…»): the file the person picked, raw; the pipes, names and letters it carries
/// come back beside what is here.
#[tauri::command]
fn history_restore(app: AppHandle, request: tauri::ipc::Request) -> Result<(), String> {
    let tauri::ipc::InvokeBody::Raw(file) = request.body() else { return Err("raw".into()) };
    let file = file.clone();
    std::thread::spawn(move || {
        // THE WINDOW HEARS AN END WHATEVER HAPPENED: a restore that broke on the way says «torn» -- left unsaid, «Restoring…» stood
        // over the page for ever and the row could not be pressed again
        let out = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
            match m.archive(&p) {
                None => json_err("seat"),
                Some(a) => match history::read_copy(&a.keys().entropy, &file) {
                    Ok(records) => {
                        lay_card(&p, &records);
                        serde_json::to_value(history::restore(&a, &m.book, &m.media, Some(&m.faces), &records)).unwrap_or_default()
                    }
                    Err(e) => json_err(&format!("{e:?}")),
                },
            }
        }))
        .unwrap_or_else(|_| json_err("Torn"));
        changed(&app);
        let _ = app.emit(RESTORED, out);
    });
    Ok(())
}

/// THE CARD OF THIS PERSON IN A COPY (iOS seedCard «s:»): the name and the words about them, so a phone opening the copy calls
/// the person by their name again.
fn my_card(p: &Person) -> Option<history::Record> {
    let s = p.profile.read();
    history::card_record(&[("userName", s.user_name), ("profileBio", s.bio), ("profileLink", s.link)])
}

/// YOUR NODE (iOS HomeNodeView over HomeNodeWatch, MontanaHomeNode): the address, a pinned certificate or none, the person's switch,
/// the level that opens the node (iOS MTLevelAccess.ownNode -- taking one's copy back asks no level), the node's word and what it
/// offers. The node is asked afresh.
#[tauri::command]
async fn home_node_state(app: AppHandle) -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let level = person::global(coins::balance(&m.vault));
        let e = p.seed.mnemonic().and_then(|w| history::keys(&w)).map(|k| k.entropy);
        let (state, caps) = match e {
            Some(e) => homenode::ask(&m.vault, &e),
            None => (homenode::State::NoHost, vec![]),
        };
        Ok(serde_json::json!({ "host": homenode::host(&m.vault), "pinned": !homenode::pin(&m.vault).is_empty(),
            "switched": homenode::switched(&m.vault), "level": level, "at": person::NODE_LEVEL, "opens": level >= person::NODE_LEVEL,
            "state": state, "caps": caps, "busy": HOME_BUSY.load(std::sync::atomic::Ordering::SeqCst) }))
    }).await.map_err(|_| ())?
}
/// YOUR NODE SET UP FROM HERE (iOS HomeNodeView.setUp over MontanaNodeSetup.run): from the node's level only; the door goes onto the
/// machine over its SSH door, the digest of the certificate it made for itself is kept, the copies are switched on and the node is
/// asked. The password is used for this one set-up and kept nowhere. The address, as kept.
#[tauri::command]
async fn home_node_setup(app: AppHandle, host: String, login: String, password: String) -> Result<String, String> {
    let m = app.state::<Messenger>();
    if person::global(coins::balance(&m.vault)) < person::NODE_LEVEL {
        return Err(format!("below level {}", person::NODE_LEVEL));
    }
    let host = homenode::set_host(&m.vault, &host);
    let user = if login.trim().is_empty() { "root".to_string() } else { login.trim().to_string() };
    match nodesetup::set_up(&host, &user, &password).await {
        Ok(fp) => {
            homenode::set_pin(&m.vault, &fp);
            homenode::set_switched(&m.vault, true);
            HOME_DUE.store(true, std::sync::atomic::Ordering::SeqCst);
            Ok(host)
        }
        Err(e) => {
            trace_line(&format!("home_node set-up refused {}", e.chars().take(120).collect::<String>()));
            Err(e)
        }
    }
}
/// The address named on the page (iOS commit): kept bare.
#[tauri::command]
fn home_node_host(m: State<'_, Messenger>, host: String) -> String {
    homenode::set_host(&m.vault, &host)
}
/// The daily copies' switch (iOS switchBinding): on -- a copy is weighed at once.
#[tauri::command]
fn home_node_switch(m: State<'_, Messenger>, on: bool) {
    homenode::set_switched(&m.vault, on);
    if on {
        HOME_DUE.store(true, std::sync::atomic::Ordering::SeqCst);
    }
}

/// One copy at a time goes to the node or comes from it (iOS HomeNodeWatch.busy).
static HOME_BUSY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
/// A daily copy weighed at the next beat of the node's walk (the switch, the launch).
static HOME_DUE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
const HOME_NODE: &str = "montana://home-node";
/// The node's road told to the page: the share of the copy sealed, sent, fetched or laid (iOS sealing / sending / fetching /
/// restoring); none -- the road is done.
fn home_road(app: &AppHandle, what: &str, f: Option<f64>) {
    let _ = app.emit(HOME_NODE, serde_json::json!({ "what": what, "share": f }));
}
/// THE COPY SEALED FOR THE NODE (iOS MontanaBackup.create for HomeNodeWatch.send): the engine's own copy into the folder of the
/// node's road, under its iOS name; with it, what it holds -- conversations, letters, files.
fn seal_copy(p: &Person, m: &Messenger, dir: &std::path::Path) -> Result<(std::path::PathBuf, serde_json::Value), String> {
    m.fill_archive(p);
    let a = m.archive(p).ok_or("seat")?;
    // the copy stays light: a file the node keeps in pieces is not sealed into it a second time (iOS: MTHomeBook.kept)
    let file = history::make_copy_planned(&a, &m.book, &m.media, my_card(p), &history::Plan::load(&m.vault), &homeshelf::kept(&m.vault)).ok_or("seal")?;
    std::fs::create_dir_all(dir).map_err(|_| "disk")?;
    let path = dir.join(history::copy_name(&a.keys().entropy, &chrono_moment()));
    std::fs::write(&path, &file).map_err(|_| "disk")?;
    let chats = m.book.all();
    let records: usize = chats.iter().map(|c| c.msgs.len()).sum();
    let media = chats.iter().flat_map(|c| c.msgs.iter()).filter(|x| x.text.starts_with(media::MARK)).count();
    Ok((path, serde_json::json!({ "chats": chats.len(), "records": records, "media": media })))
}
/// A COPY TO THE NODE NOW (iOS sendNow / the daily tick): sealed, sent whole, held only on the node's echo of its digest; the
/// copy leaves this computer either way. Refused below the node's level (iOS: a copy goes to one's own node from level 8).
fn home_send(app: &AppHandle) -> Result<serde_json::Value, String> {
    let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
    if person::global(coins::balance(&m.vault)) < person::NODE_LEVEL {
        trace_line(&format!("home_node send refused: below level {}", person::NODE_LEVEL));
        return Err("stopped".into());
    }
    let e = p.seed.mnemonic().and_then(|w| history::keys(&w)).map(|k| k.entropy).ok_or("noSeed")?;
    if HOME_BUSY.swap(true, std::sync::atomic::Ordering::SeqCst) {
        return Err("stopped".into());
    }
    home_road(app, "sealing", Some(0.0));
    let sealed = seal_copy(&p, &m, &m.dir.join("HomeNode"));
    home_road(app, "sealing", None);
    let out = sealed.and_then(|(path, tally)| {
        home_road(app, "sending", Some(0.0));
        let a = app.clone();
        let sent = homenode::send(&m.vault, &e, &path, &move |f| home_road(&a, "sending", Some(f)));
        home_road(app, "sending", None);
        let _ = std::fs::remove_file(&path); // handed: the copy leaves either way; the node's word decides what is held
        sent.map(|_| tally)
    });
    HOME_BUSY.store(false, std::sync::atomic::Ordering::SeqCst);
    out
}
#[tauri::command]
async fn home_node_send(app: AppHandle) -> Result<serde_json::Value, String> {
    tauri::async_runtime::spawn_blocking(move || home_send(&app)).await.map_err(|_| "stopped".to_string())?
}
/// THE NEWEST COPY THE NODE HOLDS comes back and is laid into this computer by the engine -- it merges, it never erases (iOS
/// takeBack); on every level. What it laid: conversations, letters, files.
#[tauri::command]
async fn home_node_take_back(app: AppHandle) -> Result<serde_json::Value, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let a = m.archive(&p).ok_or("noSeed")?;
        if HOME_BUSY.swap(true, std::sync::atomic::Ordering::SeqCst) {
            return Err("stopped".to_string());
        }
        let entropy = a.keys().entropy;
        home_road(&app, "fetching", Some(0.0));
        let b = app.clone();
        let got = homenode::take_back(&m.vault, &entropy, &m.dir.join("HomeNode"), &move |f| home_road(&b, "fetching", Some(f)));
        home_road(&app, "fetching", None);
        let out = got.and_then(|path| {
            home_road(&app, "restoring", Some(0.0));
            let read = std::fs::read(&path).map_err(|_| "disk".to_string()).and_then(|bytes| history::read_copy(&entropy, &bytes).map_err(|e| format!("{e:?}")));
            let _ = std::fs::remove_file(&path);
            let laid = read.map(|records| {
                lay_card(&p, &records);
                history::restore(&a, &m.book, &m.media, Some(&m.faces), &records)
            });
            home_road(&app, "restoring", None);
            laid.map(|r| {
                homenode::note_copied(&m.vault, wire::now_ms() as f64 / 1000.0);
                trace_line(&format!("home_node took chats={} records={} media={}", r.chats, r.records, r.media));
                serde_json::to_value(r).unwrap_or_default()
            })
        });
        HOME_BUSY.store(false, std::sync::atomic::Ordering::SeqCst);
        changed(&app);
        out
    }).await.map_err(|_| "stopped".to_string())?
}
/// THE FILES ON YOUR NODE (iOS MTHomeKeep): one pass at a time; the node's last word on the book.
static HOME_FILES_BUSY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static HOME_WORD: std::sync::Mutex<Option<serde_json::Value>> = std::sync::Mutex::new(None);
fn home_word(w: Option<(usize, u64)>) -> serde_json::Value {
    match w {
        Some((files, bytes)) => serde_json::json!({ "files": files, "bytes": bytes }),
        None => serde_json::json!({ "silent": "no answer" }),
    }
}
/// The keys of the node's files, derived from the seated person's words when the run has none yet (never the words themselves).
fn home_armed(app: &AppHandle) -> Option<homeshelf::Keys> {
    if homeshelf::armed_keys().is_none() {
        if let Some(e) = app.state::<Person>().seed.mnemonic().and_then(|w| history::keys(&w)).map(|k| k.entropy) {
            homeshelf::arm(&e);
        }
    }
    homeshelf::armed_keys()
}
/// Files ride while the copies do (the switch, the node's level, an address); taking one's own files back asks no level.
fn home_keeping(m: &Messenger) -> bool {
    homenode::switched(&m.vault) && person::global(coins::balance(&m.vault)) >= person::NODE_LEVEL && !homenode::host(&m.vault).is_empty()
}
/// THE PASS (iOS MTHomeKeep.keep): every file of the letters the node does not hold yet goes there in sealed pieces, then the
/// cache keeps itself by the person's term and ceiling; the node's word on the book after.
fn home_keep(app: &AppHandle) -> Option<serde_json::Value> {
    let m = app.state::<Messenger>();
    let k = home_armed(app)?;
    if !home_keeping(&m) || HOME_FILES_BUSY.swap(true, std::sync::atomic::Ordering::SeqCst) {
        return None;
    }
    home_road(app, "laying", Some(0.0));
    let a = app.clone();
    let w = homeshelf::keep_pass(&m.vault, &k, &m.book, &m.media, &move |f| home_road(&a, "laying", Some(f)));
    home_road(app, "laying", None);
    let (days, gb) = cache_term_of(&m.vault);
    homeshelf::trim_pass(&m.vault, &k, &m.book, &m.media, days, gb);
    HOME_FILES_BUSY.store(false, std::sync::atomic::Ordering::SeqCst);
    let word = home_word(w);
    *HOME_WORD.lock().unwrap() = Some(word.clone());
    changed(app);
    Some(word)
}
fn cache_term_of(v: &vault::Vault) -> (u64, u64) {
    let n = |k: &str| v.get(k).and_then(|b| String::from_utf8(b).ok()).and_then(|s| s.parse().ok()).unwrap_or(0);
    (n(homeshelf::KEEP_DAYS), n(homeshelf::LIMIT_GB))
}
#[tauri::command]
async fn home_files_state(app: AppHandle, ask: bool) -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        home_armed(&app);
        let bringing = homeshelf::bringing(&m.vault);
        if ask && bringing && !homeshelf::book(&m.vault).is_empty() {
            if let Some(k) = homeshelf::armed_keys() {
                *HOME_WORD.lock().unwrap() = Some(home_word(homeshelf::word(&m.vault, &k)));
            }
        }
        let (days, gb) = cache_term_of(&m.vault);
        Ok(serde_json::json!({ "word": HOME_WORD.lock().unwrap().clone(), "keeping": home_keeping(&m), "bringing": bringing,
            "laying": HOME_FILES_BUSY.load(std::sync::atomic::Ordering::SeqCst), "keepDays": days, "limitGB": gb }))
    }).await.map_err(|_| ())?
}
/// «Keep files on your node now» (iOS keep(cellular: true)): the pass at once, whatever the network.
#[tauri::command]
async fn home_files_keep(app: AppHandle) -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(move || home_keep(&app).ok_or(())).await.map_err(|_| ())?
}
/// THE CACHE CLEARED (iOS MTHomeKeep.clear): what the node holds leaves this computer on its word asked now; Err -- it did not answer.
#[tauri::command]
async fn cache_clear(app: AppHandle) -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        let k = home_armed(&app).filter(|_| homeshelf::bringing(&m.vault)).ok_or(())?;
        let (files, bytes) = homeshelf::remove_held(&m.vault, &k, &m.book, &m.media, None).ok_or(())?;
        changed(&app);
        Ok(serde_json::json!({ "files": files, "bytes": bytes }))
    }).await.map_err(|_| ())?
}
/// The person moved the term or the ceiling (iOS keepDays / cacheLimit): the cache keeps itself now, not at the next pass.
#[tauri::command]
async fn cache_term(app: AppHandle, days: u64, limit: u64) -> Result<(), ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        m.vault.set(homeshelf::KEEP_DAYS, days.to_string().as_bytes());
        m.vault.set(homeshelf::LIMIT_GB, limit.to_string().as_bytes());
        if let Some(k) = home_armed(&app).filter(|_| homeshelf::bringing(&m.vault)) {
            homeshelf::trim_pass(&m.vault, &k, &m.book, &m.media, days, limit);
            changed(&app);
        }
        Ok(())
    }).await.map_err(|_| ())?
}
/// The files of mine on their way now (iOS MTTransferBoard), for a window that opens in the middle of one.
#[tauri::command]
async fn media_board() -> Result<Vec<serde_json::Value>, ()> {
    Ok(media::board().into_iter().map(|(mid, share, word)| serde_json::json!({ "mid": mid, "share": share, "word": word })).collect())
}
/// A LOOK BRINGS IT BACK (iOS MTHomeKeep.want): a file the node's book names and this computer no longer holds comes from the
/// node when its bubble stands on the screen and the attachments download by themselves -- within the size they do.
#[tauri::command]
async fn media_look(app: AppHandle, chat: String, mid: String) -> Result<(), ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        home_armed(&app);
        if m.media.has(&mid) || !auto_download(&p) || !homeshelf::bringing(&m.vault) {
            return Ok(());
        }
        let Some(row) = m.book.chat(&chat).and_then(|c| c.msgs.into_iter().find(|x| x.mid == mid)) else { return Ok(()) };
        let name = history::file_name(&mid, &row.text);
        if homeshelf::book(&m.vault).get(&name).is_some_and(|e| e.z <= AUTO_FETCH) && homeshelf::bring_letter(&m.vault, &m.media, &mid, &row.text) {
            changed(&app);
        }
        Ok(())
    }).await.map_err(|_| ())?
}

/// THE DAILY ROAD (iOS tickSoon / tick): twelve seconds after the start and the switch, then every half hour, the node is asked
/// first; a copy is sealed and sent only when one is due -- the node holds none of ours, or this computer's last copy is a day old
/// -- on the node's level, over a network that is not the cellular one (iOS: Wi-Fi alone).
fn home_walk(app: AppHandle) {
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_secs(12));
        let mut since = std::time::Instant::now();
        let born = std::time::Instant::now();
        let mut files_due = true;
        loop {
            // the keys of the node's files, derived once the person's words are here (never the words themselves)
            if homeshelf::armed_keys().is_none() {
                if let Some(e) = app.state::<Person>().seed.mnemonic().and_then(|w| history::keys(&w)).map(|k| k.entropy) {
                    homeshelf::arm(&e);
                }
            }
            // THE FILES ON YOUR NODE AT LAUNCH (iOS MTHomeKeep.tickSoon, twenty seconds in): the pass when the files ride and the
            // network is not the cellular one; else, on a computer with no book, the node's book first
            if files_due && born.elapsed().as_secs() >= 8 {
                files_due = false;
                let m = app.state::<Messenger>();
                if home_keeping(&m) && !route_now().starts_with("c:") {
                    let a = app.clone();
                    std::thread::spawn(move || { home_keep(&a); });
                } else if homeshelf::bringing(&m.vault) && homeshelf::book(&m.vault).is_empty() {
                    if let Some(k) = homeshelf::armed_keys() {
                        homeshelf::take_book(&m.vault, &k);
                    }
                }
            }
            if HOME_DUE.swap(false, std::sync::atomic::Ordering::SeqCst) || since.elapsed().as_secs() >= 1800 {
                since = std::time::Instant::now();
                let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
                let on = homenode::switched(&m.vault) && person::global(coins::balance(&m.vault)) >= person::NODE_LEVEL;
                if on && !homenode::host(&m.vault).is_empty() && !route_now().starts_with("c:") && !HOME_BUSY.load(std::sync::atomic::Ordering::SeqCst) {
                    if let Some(e) = p.seed.mnemonic().and_then(|w| history::keys(&w)).map(|k| k.entropy) {
                        match homenode::ask(&m.vault, &e).0 {
                            homenode::State::None { .. } => { let _ = home_send(&app); }
                            homenode::State::Held { .. } if homenode::due(&m.vault, false) => { let _ = home_send(&app); }
                            homenode::State::Held { .. } => trace_line("home_node tick skipped: not due"),
                            _ => {}
                        }
                    }
                }
            }
            std::thread::sleep(std::time::Duration::from_secs(5));
        }
    });
}

/// A COPY'S CARD LAID HERE (iOS layCard «s:»): the person's own words where this machine holds none -- what stands here first.
fn lay_card(p: &Person, records: &[history::Record]) {
    let words = history::card_words(records);
    if words.is_empty() {
        return;
    }
    p.profile.update(|s| {
        for (k, v) in &words {
            match *k {
                "userName" if s.user_name.is_empty() => s.user_name = profile::kept_name(v),
                "profileBio" if s.bio.is_empty() => s.bio = v.trim().chars().take(140).collect(),
                "profileLink" if s.link.is_empty() => s.link = profile::kept_link(v),
                _ => {}
            }
        }
    });
}

fn json_err(e: &str) -> serde_json::Value {
    serde_json::json!({ "error": e })
}

/// THE LIGHT COPY (iOS MTKeeping.takeLight): what another device of these words laid on the nodes within a week comes back --
/// and with `keepers` the copy the people one writes to keep after it (iOS callAndBuild: the light first, the
/// person let in, then the slots called); every copy laid asks the correspondences it names to give theirs back.
fn take_light_then(app: AppHandle, keepers: bool) {
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let (Some(words), Some(twin), Some(a)) = (p.seed.mnemonic(), p.seed.twin(), m.archive(&p)) else { return };
        let mut sum = history::Restored::default();
        for records in history::take_light(&words, &twin, &twin::device_name(&twin, &a), &a.keys().entropy) {
            lay_card(&p, &records);
            let r = history::restore(&a, &m.book, &m.media, Some(&m.faces), &records);
            sum.chats += r.chats;
            sum.records += r.records;
            sum.media += r.media;
        }
        changed(&app);
        let _ = app.emit(RESTORED, serde_json::to_value(&sum).unwrap_or_default());
        if sum.chats > 0 {
            if let Some(d) = m.desk(&p) {
                keeping::ask_back(&d);
            }
        }
        if keepers {
            take_from_keepers(&app, &words, &twin, &a);
        }
    });
}

/// THE COPY TAKEN BACK FROM THE PEOPLE ONE WRITES TO (iOS MTKeeping.takeBack), on the calling thread: six hours at most.
fn take_from_keepers(app: &AppHandle, words: &str, twin: &str, a: &history::Archive) {
    let entropy = a.keys().entropy;
    let laid = keeping::take_back(words, twin, &twin::device_name(twin, a), &entropy, 6.0, |records| {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        lay_card(&p, &records);
        let r = history::restore(a, &m.book, &m.media, Some(&m.faces), &records);
        changed(app);
        let _ = app.emit(RESTORED, serde_json::to_value(&r).unwrap_or_default());
        let _ = app.emit(KEEPING, ());
        true
    });
    let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
    if laid {
        if let Some(d) = m.desk(&p) {
            keeping::ask_back(&d);
        }
    }
    let _ = app.emit(KEEPING, ());
}

/// THE COINS' WALK (iOS MTMintBeat, MTWalletPull, MTCoinTx.mintSoon/scan/refundDue): every second the windows whose minute passed
/// close into the book and the wallet's auto minting takes the second's coin while the wallet stands open; once a window of τ1 the
/// chain is asked to take what the book holds above it; the pairs' records every five minutes; the open sends hourly. The book is
/// written once a second, not once a coin.
static WALLET_OPEN: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
/// THE PULL SWITCHES THE AUTO MINTING ON (iOS MTWalletPull, the author's words 04.10.2026 03:52-13:33 MSK): on when the wallet's page
/// opens or the window comes back unless the Pantheon burns, by the coin held nine seconds, or by the page pulled down past its
/// trigger (never while the Pantheon burns); the page leaving or the window hidden ends it -- no touch does.
static AUTO_MINT: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
fn auto_mint(on: bool, why: &str) {
    if AUTO_MINT.swap(on, std::sync::atomic::Ordering::SeqCst) != on {
        trace_line(&if on { format!("wallet_pull auto on why={why}") } else { format!("wallet_pull auto off why={why}") });
    }
}
/// The auto minting fired (iOS MTWalletPull.fire): only while the wallet stands open; `burning` -- even while the Pantheon burns
/// (the nine seconds' hold keeps both at once).
fn auto_fire(why: &str, burning: bool) {
    if WALLET_OPEN.load(std::sync::atomic::Ordering::SeqCst) && (burning || !pantheon(|p, now| p.lit(now))) {
        auto_mint(true, why);
    }
}
/// THE CHAIN ON THE NODES IS WRITTEN IN A PERSON'S RUN (the owner's rule for tests, 21.10.2026: only test identities, and not every
/// check): a run in a folder of its own (a check's) lays no record of the coin chain unless the check asks for it
/// (MONTANA_COIN_CHAIN=1) -- the book still counts every coin.
fn coin_chain_on() -> bool {
    std::env::var_os("MONTANA_DATA_DIR").is_none() || std::env::var("MONTANA_COIN_CHAIN").as_deref() == Ok("1")
}
/// A PERSON ON THE SHELF (iOS MTShelfPost): no window; the person's own walks go on -- letters, receipts, presence, coins, the
/// wall. The process leaves when the person is seated, leaves the book, or no window's process has stood for half a minute.
fn shelf_walk(app: AppHandle) {
    std::thread::spawn(move || {
        let Some(h) = seats::here() else { return };
        trace_line("shelf stands");
        let mut gone = 0;
        loop {
            std::thread::sleep(std::time::Duration::from_secs(2));
            if seats::shelf_leaves(h, &mut gone) {
                let m = app.state::<Messenger>();
                coins::close_windows(&m.vault, true);
                coins::flush(&m.vault, &m.dir, &|r| groups::is_group(r));
                trace_line("shelf leaves");
                app.exit(0);
                return;
            }
        }
    });
}

/// The window's process keeps the shelf alive: an empty seat's folder left by its cross is swept once its files are let go
/// (every ten seconds), and every person waiting whose folder no process holds gets their process again (once a minute); the
/// drawer's faces learn the seated person's name. Montana opened a second time brings this window forward.
fn seats_walk(app: AppHandle) {
    std::thread::spawn(move || {
        let Some(h) = seats::here() else { return };
        std::thread::sleep(std::time::Duration::from_secs(3));
        let mut tick: u64 = 0;
        loop {
            if tick.is_multiple_of(5) {
                seats::sweep(h);
            }
            if std::fs::remove_file(h.base.join(seats::SHOW)).is_ok() {
                show(&app);
            }
            if tick.is_multiple_of(30) {
                seats::wake_shelf(h);
                if app.state::<Person>().seed.has_seed() {
                    seats::note_face(h, &app.state::<Person>().profile.read().user_name);
                }
            }
            tick += 1;
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
    });
}

/// The window left the person (hidden or folded): the chain of the person keeps its last second and the Global Level of now, and
/// the seconds away mint at the return (iOS MTPersonChain.left).
fn person_left(app: &AppHandle) {
    person::set_front(false);
    person::left(person::global(coins::balance(&app.state::<Messenger>().vault)));
    auto_mint(false, "background");   // the screen locked or the app left: the auto minting stops with it (iOS MTWalletPull.stop)
}

static PERSON_TICKING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static VAULT_GATHERING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static TIP_PUTTING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static TIP_GETTING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// THE NODES HELD (iOS MontanaNodes.open, MontanaDirect; channels.rs): once a person is seated, this computer holds a channel to
/// each machine of the network for the process's life; a letter of a pipe opened off a channel lands as a box letter does, and a
/// wake asks the box at once.
fn channels_walk(app: AppHandle) {
    std::thread::spawn(move || {
        let ident = loop {
            let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
            if m.desk(&p).is_some() {
                if let Some(i) = channel::identity(&m.vault) {
                    break i;
                }
            }
            std::thread::sleep(std::time::Duration::from_secs(3));
        };
        let owner_kept: std::sync::Mutex<Option<Vec<u8>>> = std::sync::Mutex::new(None);
        let (a1, a2, a3, a4) = (app.clone(), app.clone(), app.clone(), app.clone());
        channels::start(channels::Hooks {
            pipes: Box::new(move || {
                let m = a1.state::<Messenger>();
                m.book.refs().into_iter().filter(|r| !groups::is_group(r)).filter_map(|r| m.book.secret(&r).map(|s| (r, s))).collect()
            }),
            owner: Box::new(move || {
                let mut kept = owner_kept.lock().unwrap();
                if kept.is_none() {
                    *kept = a2.state::<Person>().seed.mnemonic().and_then(|w| seed::role_seed(&w, b"mt-owner-key"));
                }
                kept.clone()
            }),
            land: Box::new(move |r, plain| {
                let (p, m) = (a3.state::<Person>(), a3.state::<Messenger>());
                let Some(d) = m.desk(&p) else { return };
                if d.channel_letter(r, plain) {
                    changed(&a3);
                    ring(&a3, &p, &m, std::mem::take(&mut *d.news.lock().unwrap()));
                }
            }),
            wake: Box::new(move || {
                let (p, m) = (a4.state::<Person>(), a4.state::<Messenger>());
                if let Some(d) = m.desk(&p) {
                    if d.fetch_once() > 0 {
                        changed(&a4);
                        ring(&a4, &p, &m, std::mem::take(&mut *d.news.lock().unwrap()));
                    }
                }
            }),
        }, ident);
    });
}

fn coin_walk(app: AppHandle) {
    std::thread::spawn(move || {
        let mut tick: u64 = 0;
        let mut hands: Option<cointx::Hands> = None;
        let mut entropy: Option<[u8; 32]> = None;
        let mut started = false;
        loop {
            std::thread::sleep(std::time::Duration::from_secs(1));
            tick += 1;
            let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
            if m.desk(&p).is_none() {
                continue;
            }
            if hands.is_none() {
                hands = p.seed.mnemonic().and_then(|w| wallet::hands(&w));
            }
            if WALLET_OPEN.load(std::sync::atomic::Ordering::SeqCst) {
                if AUTO_MINT.load(std::sync::atomic::Ordering::SeqCst) {
                    coins::in_window(&m.vault, coins::PRICE, coins::PULL, 1, false);
                }
                // the devices of the words join the seconds of the person while the wallet stands open (iOS MTPersonChain.tick)
                if entropy.is_none() {
                    entropy = p.seed.mnemonic().and_then(|w| history::keys(&w)).map(|k| k.entropy);
                }
                // off this beat's thread: the nodes' answers take seconds, and the wallet mints by the second meanwhile
                if let (Some(e), false) = (entropy, PERSON_TICKING.swap(true, std::sync::atomic::Ordering::SeqCst)) {
                    std::thread::spawn(move || {
                        // the one table of the Top, read while the wallet stands open (iOS MTTopNet.read, every three seconds)
                        coinboard::read_top(&coinboard::top_row(&e));
                        person::tick(&e, coin_chain_on());
                        PERSON_TICKING.store(false, std::sync::atomic::Ordering::SeqCst);
                    });
                }
            }
            coins::close_windows(&m.vault, false);
            coins::flush(&m.vault, &m.dir, &|r| groups::is_group(r));
            // THE BOOK RIDES THE SEED (iOS MTCoinVault.gather): the seed's union gathered from the nodes and this book's moves laid there
            // a second after the start and the window's return, a second after a move between people, a minute after the minting's
            // moves, at the wallet's opening and every fifteen seconds while it stands open -- off this beat's thread
            if !started {
                started = true;
                coinvault::soon("start", 1.0);
                tip::ask("start");
            }
            // the pipes another person of this computer met this one by stand in this person's book (iOS landShelf)
            if tick.is_multiple_of(2) && seats::take_met(&m.vault, &m.book) > 0 {
                changed(&app);
            }
            if WALLET_OPEN.load(std::sync::atomic::Ordering::SeqCst) {
                if tick.is_multiple_of(15) {
                    coinvault::soon("live", 0.0);
                }
                if tick.is_multiple_of(3) {
                    tip::ask("live");   // a tip every three seconds: a coin of another device within that (iOS MTWalletScreen)
                }
            }
            // THE TIMECHAIN'S TIP (iOS MTTimeChainTip): this device's lane leaves at most once in two seconds, the others' are read in
            // one round trip -- off this beat's thread, one of each at a time
            if entropy.is_none() {
                entropy = p.seed.mnemonic().and_then(|w| history::keys(&w)).map(|k| k.entropy);
            }
            if let Some(e) = entropy {
                if !TIP_PUTTING.load(std::sync::atomic::Ordering::SeqCst) && tip::put_due() && coin_chain_on() {
                    TIP_PUTTING.store(true, std::sync::atomic::Ordering::SeqCst);
                    std::thread::spawn(move || {
                        tip::put(&coins::vault_keys(&e));
                        TIP_PUTTING.store(false, std::sync::atomic::Ordering::SeqCst);
                    });
                }
                if !TIP_GETTING.load(std::sync::atomic::Ordering::SeqCst) {
                    if let Some(why) = tip::asked() {
                        TIP_GETTING.store(true, std::sync::atomic::Ordering::SeqCst);
                        let a = app.clone();
                        std::thread::spawn(move || {
                            let m = a.state::<Messenger>();
                            if tip::gather(&m.vault, &coins::vault_keys(&e), &why).is_some_and(|g| 0 < g.1) {
                                let _ = a.emit(COINS, ());
                            }
                            TIP_GETTING.store(false, std::sync::atomic::Ordering::SeqCst);
                        });
                    }
                }
            }
            if !VAULT_GATHERING.load(std::sync::atomic::Ordering::SeqCst) {
                if let Some(why) = coinvault::due() {
                    if entropy.is_none() {
                        entropy = p.seed.mnemonic().and_then(|w| history::keys(&w)).map(|k| k.entropy);
                    }
                    if let Some(e) = entropy {
                        VAULT_GATHERING.store(true, std::sync::atomic::Ordering::SeqCst);
                        let a = app.clone();
                        std::thread::spawn(move || {
                            let was = coinvault::heard();
                            let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
                            let (_, _, _, joined, _) = coinvault::gather(&m.vault, &e, &why, coin_chain_on());
                            // the letters that landed before the book was heard mint now (iOS gather -> MTChatMint.credit)
                            let waited = if !was && coinvault::heard() { m.desk(&p).map(|d| d.mint_waiting()).unwrap_or(0) } else { 0 };
                            if waited > 0 {
                                trace_line(&format!("coins_vault letters waited minted={waited}"));
                            }
                            if joined > 0 || waited > 0 {
                                let _ = a.emit(COINS, ());
                            }
                            VAULT_GATHERING.store(false, std::sync::atomic::Ordering::SeqCst);
                        });
                    }
                }
            }
            // THE FABRIC OF TIME read again (iOS MTFabric.refresh) and its testimonies signed and given by the pair's own road
            if tick % 10 == 3 {
                fabric::refresh(person::level(person::seconds()), coins::balance(&m.vault));
            }
            coinboard::drain(&m.vault);   // the people's balances and levels their words told (iOS MTCoinBoard)
            if tick % 60 == 7 {
                coinboard::read_bins();   // the levels' colours stand on the public distribution (read only)
            }
            if fabric::has_due() {
                if let (Some(words), Some(d)) = (p.seed.mnemonic(), m.desk(&p)) {
                    for (conv, word) in fabric::signed_due(&words) {
                        d.word_kept(&conv, &book::mint_mid(), &word);
                    }
                }
            }
            wallet::beat(&m.vault);   // the chain's second rises on the screen (iOS 2305 MTCoinSplit.beat)
            let _ = app.emit(COINS, ());
            let Some(h) = hands.as_ref() else { continue };
            if !coin_chain_on() {
                continue;
            }
            // while the person is here the chain is asked every beat (iOS beHere, presentBeat): from the online cut a MINT of the
            // present seconds goes with it
            let beat = if wallet::here() { wallet::PRESENT_BEAT } else { 60 };
            if tick % beat == 5 {
                wallet::reconcile(&m.vault, h, false);
            }
            // the auto-reactions named by the letters' landings: each a SEND under its letter (iOS autoGive)
            for (r, mid, c) in wallet::auto_take() {
                let paid = m.desk(&p).is_some_and(|d| d.give(&r, &mid, c, &format!("auto:mid:{mid}"), Some(h)));
                if !paid {
                    wallet::auto_release(&m.vault, &mid);
                }
                trace_line(&format!("auto_react v3 coins={c} paid={}", paid as u8));
                changed(&app);
            }
            if tick % 300 == 20 || wallet::scan_due() {
                let pipes: Vec<(String, Vec<u8>)> = m.book.refs().into_iter().filter(|r| !groups::is_group(r)).filter_map(|r| m.book.secret(&r).map(|s| (r, s))).collect();
                if wallet::scan(&m.vault, h, &pipes) > 0 {
                    changed(&app);
                }
                // a v2 credit its sender took back leaves this book too (iOS scan → creditsGone, fold-4), asked once an hour
                wallet::credits_gone(&m.vault);
                // this computer's copy of the network's chains and its signed root, off the walk (iOS scan → MTCoinReplica.run)
                if replica::due() {
                    let a = app.clone();
                    std::thread::spawn(move || {
                        if let Some(h) = wallet::held_hands() {
                            replica::run(&a.state::<Messenger>().vault, &h, "scan");
                        }
                    });
                }
            }
            if tick % 3600 == 40 {
                wallet::refund_due(&m.vault, h);
            }
        }
    });
}

/// THE WALLET AS ITS PAGE SHOWS IT (iOS MTWalletPage): the book's balance (the time it holds), the available on the chain, the level
/// of π, the counts by source, the newest moves; the page standing open mints by the second (iOS MTWalletPull, on by default).
#[tauri::command]
async fn wallet_state(m: State<'_, Messenger>, open: Option<bool>) -> Result<serde_json::Value, ()> {
    if let Some(o) = open {
        if o && !WALLET_OPEN.load(std::sync::atomic::Ordering::SeqCst) {
            tip::ask("wallet");   // the other devices' tips in one round trip, then the seed's book (iOS MTWalletScreen.task)
            coinvault::soon("wallet", 0.0);
        }
        WALLET_OPEN.store(o, std::sync::atomic::Ordering::SeqCst);
        if o {
            auto_fire("page", false);   // iOS onAppear: if !pantheon.lit { autoMint.fire() }
        } else {
            auto_mint(false, "page");
        }
    }
    let (balance, counts, moves) = coins::state(&m.vault, 50);
    // THE SEED'S BOOK IS ON ITS WAY (iOS «Gathering your coins»): a device opened by its words says it gathers until the nodes answer,
    // never a balance of nothing -- while the book is empty or another device's tip was seen
    let gathering = !coinvault::heard() && (balance == 0 || tip::seen().is_some());
    // words opened anew show the seed's coins before the book lands (iOS MTWalletScreen.total): the balance another device's tip
    // told after it had gathered the book, until a node answered the book here
    let balance = if coinvault::heard() { balance } else { balance.max(tip::seen().unwrap_or(0)) };
    let me = wallet::MY_FROM.lock().unwrap().clone();
    // what mints now (iOS MTCoinFlash): the chains' sources of the last second and a half, the coins of the last second
    let (apps, born) = coins::flash(&m.vault);
    let flash = serde_json::json!({ "apps": apps, "coins": born });
    // the wall's rights (iOS MTBoard.wallWindows): the share of the windows minting now, and of all of them
    let w = board::wall_windows(&m.vault);
    let wall = serde_json::json!({ "now": w.iter().filter(|x| x.1).map(|x| x.0).sum::<i64>(), "rights": w.iter().map(|x| x.0).sum::<i64>() });
    // the person's own rate of the coin (iOS MTPersonalRate): their earning, its period and currency, kept on this machine alone
    let rate = m.vault.get(RATE).and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok());
    Ok(serde_json::json!({
        "balance": balance, "available": wallet::available(&m.vault), "split": wallet::split(), "gathering": gathering,
        // π's place of the person's coins (iOS MTPiLevels.place(total)): the chain's available once it spoke, else the book
        "pi": coins::pi_place(if wallet::split().is_some() { wallet::available(&m.vault) } else { balance }),
        "counts": counts, "moves": moves, "key": me, "ticker": coins::TICKER,
        "minting": WALLET_OPEN.load(std::sync::atomic::Ordering::SeqCst) && AUTO_MINT.load(std::sync::atomic::Ordering::SeqCst),
        "pantheon": pantheon(|p, now| p.shown(now)),
        "top": coinboard::top(), "shown": coinboard::shown(&m.vault),
        "flash": flash, "wall": wall, "rate": rate,
    }))
}

/// THE WHOLE BOOK FOR THE ANALYTICS (iOS MTCoinHistory.fold): every move -- its kind, coins, moment and the chain's source it
/// belongs to; the window folds it by month.
#[tauri::command]
async fn coin_moves_all(m: State<'_, Messenger>) -> Result<Vec<serde_json::Value>, ()> {
    let (_, _, moves) = coins::state(&m.vault, usize::MAX);
    let mut names: std::collections::HashMap<String, String> = Default::default();
    Ok(moves.iter().map(|e| {
        // who a move was with, as the chats tab names them (iOS MTTimeChainRows.names)
        let who = e.peer.as_ref().map(|p| names.entry(p.clone()).or_insert_with(|| m.book.chat(p)
            .map(|c| if c.alias.trim().is_empty() { c.name } else { c.alias }).unwrap_or_default()).clone());
        serde_json::json!({ "k": e.k, "c": e.c, "at": e.at, "ref": e.refr, "peer": e.peer, "who": who,
            "src": coins::source(e, e.peer.as_deref().is_some_and(groups::is_group)) })
    }).collect())
}

/// THE PERSONAL RATE OF THE COIN (iOS MTPersonalRate, the author's word 04.10.2026 19:19 MSK): what the person earns in an hour, a
/// month or a year, in their currency -- a setting of this machine, never sent; an empty word takes it back.
const RATE: &str = "coinRate.personal";
#[tauri::command]
async fn coin_rate_set(m: State<'_, Messenger>, amount: f64, per: String, code: String) -> Result<(), ()> {
    let code: String = code.chars().filter(|c| c.is_ascii_uppercase()).take(3).collect();
    if amount > 0.0 && amount.is_finite() && ["hour", "month", "year"].contains(&per.as_str()) && code.len() == 3 {
        m.vault.set(RATE, serde_json::json!({ "amount": amount, "per": per, "code": code }).to_string().as_bytes());
    } else {
        m.vault.set(RATE, b"");
    }
    Ok(())
}

/// THE PANTHEON ON FIRE of this process's person (iOS MTPantheon.shared).
static PANTHEON: std::sync::Mutex<Option<coins::Pantheon>> = std::sync::Mutex::new(None);
fn pantheon<T>(f: impl FnOnce(&mut coins::Pantheon, f64) -> T) -> T {
    let now = wire::now_ms() as f64 / 1000.0;
    f(PANTHEON.lock().unwrap().get_or_insert_with(Default::default), now)
}

/// A touch of the coin (iOS MTPantheon.tap): the second's one coin at most -- time bounds the coins, not a quicker finger -- and
/// none while the coin rests after a burn's minute.
#[tauri::command]
async fn wallet_tap(m: State<'_, Messenger>) -> Result<i64, ()> {
    if !pantheon(|p, now| p.tap(now)) {
        return Ok(0);
    }
    Ok(coins::in_window(&m.vault, 1, coins::TAP, 1, false))
}

/// A finger landed on the coin or left it (iOS MTPantheon.touched / released): the fire burns while it holds.
#[tauri::command]
fn wallet_touch(down: bool) {
    pantheon(|p, now| p.touch(now, down));
}

/// THE NINE SECONDS AND THE PULL (iOS MTCoinTapPad.armNine -> MTWalletPull.fire, MTWalletScreen.pulled; the author's words 04.10.2026
/// 12:28 and 03:52 MSK): the coin held nine seconds without a swipe turns the auto minting on, the Pantheon burning or not; the page
/// pulled down past its trigger turns it on only while the Pantheon does not burn.
#[tauri::command]
fn wallet_pull(why: String) {
    auto_fire(if why == "hold" { "hold" } else { "pull" }, why == "hold");
}

/// COINS TO A PERSON (iOS MTCoinSend.transferResult): weighed by the available; the record on my chain, then a letter in the chat
/// that tells how many and carries the confirmation link. "sent:<id>" | "short" | "pending" | "nokey".
#[tauri::command]
async fn coin_send(app: AppHandle, chat: String, coins: i64) -> Result<String, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        if coins <= 0 || groups::is_group(&chat) {
            return Err(());
        }
        if wallet::available(&m.vault) < coins {
            return Ok("short".to_string());
        }
        if !coin_chain_on() {
            return Ok("pending".to_string());
        }
        let out = send_coins(&p, &m, &chat, coins)?;
        changed(&app);
        Ok(out)
    }).await.map_err(|_| ())?
}

/// The pair's transfer (iOS MTCoinSend.transferResult): the SEND on my chain, then the telling letter in the chat.
fn send_coins(p: &Person, m: &Messenger, chat: &str, coins: i64) -> Result<String, ()> {
    let d = m.desk(p).ok_or(())?;
    let h = p.seed.mnemonic().and_then(|w| wallet::hands(&w)).ok_or(())?;
    let secret = m.book.secret(chat).ok_or(())?;
    let mut sent = wallet::send3(&m.vault, &h, chat, &secret, coins, None);
    if matches!(&sent, wallet::Sent::NotApplicable(why) if why == "no receiver key") {
        // THE KEY IS ASKED, AND THE SAME SEND GOES WHEN IT COMES (iOS transferResult, the author's word 21.10.2026 12:41 MSK): nothing
        // left the book; the correspondent's computer answers the ask with its key, a live one within seconds
        d.announce_about_asking(chat, true);
        let mut waited = 0;
        while wallet::peer_from(&m.vault, chat).is_none() && waited < 40 {
            waited += 1;
            std::thread::sleep(std::time::Duration::from_millis(250));
        }
        trace_line(&format!("coin_v3 key asked got={} waited_ms={}", wallet::peer_from(&m.vault, chat).is_some() as u8, waited * 250));
        if wallet::peer_from(&m.vault, chat).is_some() {
            sent = wallet::send3(&m.vault, &h, chat, &secret, coins, None);
        }
    }
    Ok(match sent {
        wallet::Sent::Taken(id) => {
            let text = format!("🪙 {} · {}\n{}{id}", group3(coins), coin_time(coins, p.lang.starts_with("ru")), coins::TX_LINK);
            d.draft(chat, &text, "", "");
            format!("sent:{id}")
        }
        wallet::Sent::Pending => "pending".into(),
        wallet::Sent::NotApplicable(why) => if why == "no receiver key" { "nokey".into() } else { "short".into() },
        // NOTHING LEFT, AND THE PERSON IS TOLD SO (iOS .refused, the author's word 20.10.2026 22:0x MSK): every refused road either
        // never debited the book or gave the coins back before it answered -- «being confirmed» over a refusal was a false gauge
        wallet::Sent::Failed => "refused".into(),
    })
}

/// TO ONESELF ON ANOTHER ACCOUNT (iOS MTCoinSendSheet «My other accounts», the author's word 11.10.2026 17:13 MSK, No.62; one pair,
/// sent and received, No.66): the coins ride the pipe the two persons of this computer share, born here when they have none
/// (seats::pair_with_shelf); the SEND names the other person's key (knowOwn), its RECV is laid at once with that key (landOwn),
/// and the move is laid in that person's book on the nodes, where their own gather takes it. "sent:<id>|<pipe>" | "short" |
/// "pending".
#[tauri::command]
async fn coin_send_own(app: AppHandle, seat: String, coins: i64) -> Result<String, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let h = seats::here().ok_or(())?;
        if coins <= 0 {
            return Err(());
        }
        if wallet::available(&m.vault) < coins {
            return Ok("short".to_string());
        }
        if !coin_chain_on() {
            return Ok("pending".to_string());
        }
        let words = seats::shelf_words(h, &seat).ok_or(())?;
        let (their_vault, _) = seats::shelf_vault(h, &seat).ok_or(())?;
        let conv = seats::pair_with_shelf(h, &seat, &m.book, &p.profile.read().user_name).ok_or(())?;
        let their = crate::seed::master_of(&words).and_then(|k| cointx::Hands::from_master(&k)).ok_or(())?;
        let entropy = history::keys(&words).map(|k| k.entropy).ok_or(())?;
        wallet::note_peer_from(&m.vault, &conv, &their.from());   // iOS knowOwn: the SEND commits to the other key
        let out = send_coins(&p, &m, &conv, coins)?;
        if let Some(id) = out.strip_prefix("sent:") {
            let secret = m.book.secret(&conv).ok_or(())?;
            let (taken, said) = wallet::land_own(&their, coins::balance_in(&their_vault), id, &secret);
            let laid = if taken {
                let e = coins::Entry { k: "receive".into(), c: coins, refr: format!("{}{id}", coins::TX), peer: Some(conv.clone()), on: None, at: wire::now_ms() as f64 / 1000.0 };
                coinvault::lay(&[e], &entropy)
            } else {
                0
            };
            trace_line(&format!("coin_own seat={seat} coins={coins} {said} book={laid} id={}", &id[..id.len().min(12)]));
        }
        changed(&app);
        // the pipe beside the word: one recipient's chat opens after (iOS MontanaOutsideOpen.chat)
        Ok(if out.starts_with("sent:") { format!("{out}|{conv}") } else { out })
    }).await.map_err(|_| ())?
}

/// Big numbers part their thousands with commas, in every language (iOS MTCoinText.count).
fn group3(n: i64) -> String {
    let d = n.unsigned_abs().to_string();
    let mut out = String::new();
    for (i, ch) in d.chars().enumerate() {
        if i > 0 && (d.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(ch);
    }
    if n < 0 { format!("-{out}") } else { out }
}
/// The coins as the time they are, a coin a second (iOS MTCoinText.time, abbreviated).
fn coin_time(coins: i64, ru: bool) -> String {
    let mut rest = coins.max(0);
    let spans: [(i64, &str, &str); 6] = [(31_536_000, "y", "г"), (86_400, "d", "д"), (3_600, "h", "ч"), (60, "min", "мин"), (1, "s", "с"), (0, "", "")];
    let mut parts = vec![];
    for (sec, en, r) in spans.iter().take(5) {
        let n = rest / sec;
        rest %= sec;
        if n > 0 {
            parts.push(format!("{n} {}", if ru { r } else { en }));
        }
    }
    if parts.is_empty() { if ru { "0 с".into() } else { "0 s".into() } } else { parts.into_iter().take(2).collect::<Vec<_>>().join(" ") }
}

/// THE WALL'S WALK (iOS MTBoard: the versions heard, the asks, the pages carried, the views told): every two seconds beside the
/// letters', so a page in flight never holds them up. The wall is read once at its start, and my presence word names its version
/// from then on.
fn board_walk(app: AppHandle) {
    std::thread::spawn(move || {
        let mut seated = false;
        let mut heard: std::collections::HashMap<String, String> = Default::default();
        let mut heard_g: std::collections::HashMap<String, String> = Default::default();
        let mut was = String::new();
        loop {
            std::thread::sleep(std::time::Duration::from_secs(2));
            let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
            let Some(d) = m.desk(&p) else { continue };
            if !seated {
                let _ = board::posts(&m.vault, None);
                pageground::seat(&m.vault);
                let dir = m.vault.dir().to_string_lossy().to_string();
                let vault = m.vault.clone();
                // «W» my wall's version, then «G» the ground of theirs I hold (iOS heldTail: G stands after W), then «C» my coins
                // while I show them and «L» my Global Level (iOS coinTail, levelTail)
                m.presence.set_tail(Box::new(move |r| {
                    let w = board::tail_at(&dir, r);
                    if w.is_empty() {
                        return w;
                    }
                    let g = pageground::tail_at(&dir, r);
                    if g.is_empty() { w } else { w + &g + &coinboard::tail(&vault) }
                }));
                seated = true;
            }
            let rows = m.rows();
            board::set_blocked(&m.vault, rows.iter().filter(|r| r.blocked).map(|r| r.reference.clone()).collect());
            let people: Vec<String> = rows.iter().filter(|r| !r.blocked && !r.group).map(|r| r.reference.clone()).collect();
            for r in &people {
                if let (Some(w), g) = m.presence.held_said(r) {
                    if heard.get(r) != Some(&w) {
                        heard.insert(r.clone(), w.clone());
                        board::heard_version(&m.vault, r, &w);
                    }
                    if let Some(g) = g.filter(|g| heard_g.get(r) != Some(g)) {
                        heard_g.insert(r.clone(), g.clone());
                        pageground::heard(&m.vault, r, &g);
                    }
                }
            }
            for (to, w) in board::due(&m.vault, &people) {
                d.wall_say(&to, &w);
            }
            let photo = |name: &str| m.media.get(name);
            for (to, text, tag) in pageground::due(&m.vault, &people, &photo) {
                if d.deliver(&to, &book::mint_mid(), &text) {
                    pageground::sent(&m.vault, &to, &tag);
                }
            }
            let now = board::stamp_of(&m.vault);
            if now != was {
                was = now;
                let _ = app.emit(WALL, ());
            }
        }
    });
}

/// A WALL AS THE WINDOW DRAWS IT (iOS posts(on:)): mine (no wall named), or another's as its owner last sent it; whether I may
/// write on it and whether its page was ever held. Looking at another's asks for a page not held or stale (iOS look).
#[tauri::command]
async fn wall_state(p: State<'_, Person>, m: State<'_, Messenger>, wall: Option<String>) -> Result<serde_json::Value, ()> {
    if let Some(w) = &wall {
        board::look(&m.vault, w);
    }
    let me = my_shown_name(&p, &m);
    let (posts, can, held) = board::posts(&m.vault, wall.as_deref());
    Ok(serde_json::json!({ "posts": posts.iter().map(|x| drawn(&m, &me, wall.as_deref(), x)).collect::<Vec<_>>(), "canWrite": can, "held": held }))
}

/// My own name as my posts' bylines show it (iOS E2E.myDisplayName).
fn my_shown_name(p: &Person, m: &Messenger) -> String {
    m.desk(p).map(|d| profile::strip_crown(d.my_name.trim())).unwrap_or_default()
}

/// A post as the window draws it (iOS MTBoardCell): the coins this machine's book holds on it (coinBook.coins(on: «post:»)); its
/// writer and, for a repost, the wall it came from as this machine knows them -- "" me, a correspondent's reference, or none -- with
/// the names shown for them (iOS shownName: my word for a correspondent first; name(of:said:)).
fn drawn(m: &Messenger, me: &str, wall: Option<&str>, p: &board::Seen) -> serde_json::Value {
    let mut v = serde_json::json!(p);
    v["coins"] = serde_json::json!(coins::on_target(&m.vault, &format!("post:{}", p.id)));
    let name = |r: &str, said: &str| -> String {
        let n = if r.is_empty() { me.to_string() } else { m.book.shown_name(r).unwrap_or_default() };
        if n.trim().is_empty() { said.to_string() } else { n }
    };
    let w = board::writer(&m.vault, wall, p);
    v["shown"] = serde_json::json!(w.as_deref().map_or_else(|| p.by_name.clone(), |r| name(r, &p.by_name)));
    v["writer"] = serde_json::json!(w);
    // THE POST'S LINK (iOS linkPost(p, on:)): short by the name the wall's owner claims, else long
    let owner = match wall { None => me.to_string(), Some(r) => m.book.given_name(r).unwrap_or_default() };
    v["link"] = serde_json::json!(board::link_post(&owner, p));
    if let Some(from) = &p.from {
        let s = board::source(&m.vault, wall, p);
        v["sourceName"] = serde_json::json!(s.as_deref().map_or_else(|| from.clone(), |r| name(r, from)));
        v["source"] = serde_json::json!(s);
    }
    v
}

/// THE WALL OF THOUGHTS (iOS feed): my wall and the walls of my people this machine holds, the newest first; each post with its
/// wall ("" mine) and the wall's name.
#[tauri::command]
async fn wall_feed(p: State<'_, Person>, m: State<'_, Messenger>) -> Result<Vec<serde_json::Value>, ()> {
    let holds = |w: &str| m.book.secret(w).is_some();
    let me = my_shown_name(&p, &m);
    Ok(board::feed(&m.vault, &holds).into_iter().map(|(wall, x)| {
        let name = if wall.is_empty() { String::new() } else { m.book.shown_name(&wall).unwrap_or_default() };
        let at = (!wall.is_empty()).then_some(wall.as_str());
        serde_json::json!({ "wall": wall, "wallName": name, "canWrite": board::can_write(&m.vault, at), "post": drawn(&m, &me, at, &x) })
    }).collect())
}

/// A FILE OF A POST BEING WRITTEN (iOS MTBoardDrafts.take): the picture made ready by the window, raw; kept in the media store
/// under a draft's name until the post is published.
#[tauri::command]
fn wall_file_put(app: AppHandle, request: tauri::ipc::Request) -> Result<String, ()> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err(()) };
    if body.is_empty() || body.len() > media::MAX_SEND {
        return Err(());
    }
    let name = format!("wd_{}", wire::hex(&wire::sha(&[b"mt-wall-draft\0", body])[..12]));
    if app.state::<Messenger>().media.put(&name, body) { Ok(name) } else { Err(()) }
}

/// A POST PUBLISHED (iOS publish): every file sealed and laid on the node's blind store under the letter's own key -- the media
/// road's sealing, «wall-<post>-<n>» -- then the words: onto my wall, or to the wall's owner as «post», with my small face (iOS
/// myFace). The files stay here too: the writer keeps their post from the start. The window hears each file laid (its bar, iOS
/// MTBoardProgress), and the wall's draft is the post's from then (iOS dropDraft «posted»).
#[tauri::command]
async fn wall_post(app: AppHandle, wall: Option<String>, text: String, files: Vec<serde_json::Value>, face: Option<String>) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let d = m.desk(&p).ok_or("seat")?;
        let text: String = text.trim().to_string();
        if text.is_empty() && files.is_empty() {
            return Err("empty".to_string());
        }
        let pid = board::fresh_id();
        let files: Vec<serde_json::Value> = files.into_iter().take(10).collect();
        let total: u64 = files.iter().map(|f| f["size"].as_u64().unwrap_or(0)).sum();
        let mut done = 0u64;
        let mut md = vec![];
        for (i, f) in files.iter().enumerate() {
            let draft = f["file"].as_str().unwrap_or("");
            let bytes = m.media.get(draft).filter(|_| draft.starts_with("wd_")).ok_or("file")?;
            let key = media::letter_key(&m.vault, &format!("wall-{pid}-{i}")).ok_or("key")?;
            let chunks = media::upload(&bytes, &key).ok_or("upload")?;
            let ext: String = f["ext"].as_str().unwrap_or("jpg").chars().filter(|c| c.is_ascii_alphanumeric()).take(8).collect::<String>().to_lowercase();
            m.media.put(&board::file_name(&pid, i, &ext), &bytes);
            m.media.delete(draft);
            done += bytes.len() as u64;
            let _ = app.emit("montana://wall-laid", serde_json::json!({ "done": done, "total": total.max(done) }));
            md.push(board::Media {
                kind: f["kind"].as_str().unwrap_or("img").into(), name: f["name"].as_str().unwrap_or("").chars().take(200).collect(), ext,
                size: bytes.len() as i64, key: wire::b64(&key),
                chunks: chunks.iter().map(|c| board::Chunk { bid: c["bid"].as_str().unwrap_or("").into(), cs: c["cs"].as_i64().unwrap_or(0) }).collect(),
                thumb: f["thumb"].as_str().map(str::to_string).filter(|t| t.len() <= 60_000),
                fr: serde_json::from_value(f["fr"].clone()).ok(), dur: f["dur"].as_f64().filter(|x| x.is_finite() && *x > 0.0),
            });
        }
        let name = profile::strip_crown(d.my_name.trim());
        match wall.as_deref() {
            None => board::post_mine(&m.vault, &pid, &name, &text, md, None),
            Some(w) => {
                let word = board::post_on(&m.vault, w, &pid, &name, &text, md, None, face);
                if !d.wall_say(w, &word) {
                    return Err("send".to_string());
                }
            }
        }
        for gone in board::drop_draft(&m.vault, wall.as_deref()) {
            m.media.delete(&gone);
        }
        trace_line(&format!("wall posted {} files={} kinds={} id={pid}", if wall.is_some() { "theirs" } else { "mine" }, files.len(),
                            files.iter().map(|f| f["kind"].as_str().unwrap_or("?")).collect::<Vec<_>>().join(",")));
        let _ = app.emit(WALL, ());
        Ok(pid)
    }).await.map_err(|_| "join".to_string())?
}

/// A WALL'S LINK OPENED (iOS MTBoardComments.open): the post -- and the comment -- it names among the posts this machine holds, by its
/// long name or by the short «@name/number»; none, when it names no post held here.
#[tauri::command]
async fn wall_find(p: State<'_, Person>, m: State<'_, Messenger>, link: String) -> Result<Option<serde_json::Value>, ()> {
    let me = my_shown_name(&p, &m);
    let name_of = |w: Option<&str>| match w { None => me.clone(), Some(r) => m.book.given_name(r).unwrap_or_default() };
    let hit = board::target(&m.vault, &link, &name_of);
    trace_line(&format!("wall_link {}", if hit.is_some() { "found" } else { "none" }));
    Ok(hit.map(|(wall, id, comment)| serde_json::json!({ "wall": if wall.is_empty() { None } else { Some(wall) }, "id": id, "comment": comment })))
}

/// THE WALL'S DRAFT (iOS MTBoard.draft / lay / dropDraft): the post being written, as its page was left -- read when the page opens,
/// laid at every change; a file the draft lets go leaves the media store with it.
#[tauri::command]
async fn wall_draft(m: State<'_, Messenger>, wall: Option<String>) -> Result<Option<board::Draft>, ()> {
    Ok(board::draft(&m.vault, wall.as_deref()))
}
#[tauri::command]
async fn wall_draft_set(app: AppHandle, m: State<'_, Messenger>, wall: Option<String>, draft: Option<board::Draft>) -> Result<(), ()> {
    let gone = match draft {
        Some(d) => board::lay_draft(&m.vault, wall.as_deref(), d),
        None => board::drop_draft(&m.vault, wall.as_deref()),
    };
    for f in gone {
        m.media.delete(&f);
    }
    let _ = app.emit(WALL, ());
    Ok(())
}

/// A FILE OF A POST OPENED WHERE WINDOWS OPENS SUCH A FILE (iOS MTBoardDocPresenter, QuickLook): brought whole -- a touch, so this
/// machine becomes the post's peer and the download is told once (iOS file) -- written beside the person's downloads under its own
/// name, and opened; a check's own folder keeps it and starts nothing.
#[tauri::command]
async fn wall_open(app: AppHandle, wall: Option<String>, id: String, index: usize) -> Result<bool, ()> {
    let res = wall_file(app.clone(), wall.clone(), id.clone(), index, Some(true)).await?;
    drop(res);
    let m = app.state::<Messenger>();
    let (posts, _, _) = board::posts(&m.vault, wall.as_deref());
    let md = posts.iter().find(|p| p.id == id).and_then(|p| p.media.get(index).cloned()).ok_or(())?;
    let store = board::file_name(&id, index, &md.ext);
    let given: String = md.name.chars().filter(|c| !"<>:\"/\\|?*".contains(*c) && !c.is_control()).collect();
    let ext: String = md.ext.chars().filter(|c| c.is_ascii_alphanumeric()).take(8).collect();
    let stem = if given.trim().is_empty() { format!("Montana {id}") } else { given.trim().to_string() };
    let name = if stem.to_lowercase().ends_with(&format!(".{}", ext.to_lowercase())) || ext.is_empty() { stem } else { format!("{stem}.{ext}") };
    let dir = match std::env::var_os("MONTANA_DATA_DIR") {
        Some(_) => m.dir.join("Downloads"),
        None => std::path::PathBuf::from(std::env::var_os("USERPROFILE").ok_or(())?).join("Downloads").join("Montana"),
    };
    let media = m.media.clone();
    let path = tauri::async_runtime::spawn_blocking(move || {
        std::fs::create_dir_all(&dir).ok()?;
        let mut path = dir.join(&name);
        let mut n = 2;
        while path.exists() && !media.same_as(&store, &path) {
            path = dir.join(format!("{} ({n}).{ext}", name.trim_end_matches(&format!(".{ext}"))));
            n += 1;
        }
        (path.exists() || media.write_to(&store, &path)).then_some(path)
    }).await.map_err(|_| ())?.ok_or(())?;
    trace_line(&format!("wall_open {} bytes", std::fs::metadata(&path).map(|x| x.len()).unwrap_or(0)));
    if std::env::var_os("MONTANA_DATA_DIR").is_some() {
        return Ok(true);
    }
    Ok(open_in_browser(&path.to_string_lossy()))
}

/// A FILE OF A POST, raw (iOS file): the copy this machine holds, else its pieces fetched from the node by the post's own key,
/// checked and kept.
#[tauri::command]
async fn wall_file(app: AppHandle, wall: Option<String>, id: String, index: usize, touch: Option<bool>) -> Result<tauri::ipc::Response, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        let (posts, _, _) = board::posts(&m.vault, wall.as_deref());
        let post = posts.iter().find(|p| p.id == id).cloned().ok_or(())?;
        let md = post.media.get(index).cloned().ok_or(())?;
        let name = board::file_name(&id, index, &md.ext);
        if let Some(b) = m.media.get(&name) {
            return Ok(tauri::ipc::Response::new(if md.kind == "img" { picture::viewable(b) } else { b }));
        }
        let manifest = serde_json::json!({ "bk": md.key, "chunks": md.chunks, "sz": md.size });
        let b = media::download(&manifest).map_err(|_| ())?;
        m.media.put(&name, &b);
        // A DOWNLOAD IS COUNTED ONCE PER PERSON (iOS noteDownloaded): a touch that brought the last file of the post makes this machine
        // its peer and tells the wall once; a picture brought only to be seen is no download (iOS MTBoardLook)
        if touch == Some(true) && post.media.iter().enumerate().all(|(i, x)| m.media.has(&board::file_name(&id, i, &x.ext))) {
            let said: Vec<(String, board::Word)> = board::keep(&m.vault, wall.as_deref(), &id).into_iter()
                .chain(board::downloaded(&m.vault, wall.as_deref(), &id)).collect();
            if let Some(d) = m.desk(&app.state::<Person>()) {
                for (to, w) in &said {
                    d.wall_say(to, w);
                }
            }
            let _ = app.emit(WALL, ());
        }
        Ok(tauri::ipc::Response::new(if md.kind == "img" { picture::viewable(b) } else { b }))
    }).await.map_err(|_| ())?
}

/// A like, a comment, a post taken off my wall, a pin, a post seen: the wall's acts of the window.
#[tauri::command]
async fn wall_do(app: AppHandle, act: String, wall: Option<String>, id: String, text: Option<String>, face: Option<String>) -> Result<bool, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let d = m.desk(&p).ok_or(())?;
        let name = profile::strip_crown(d.my_name.trim());
        let words = text.as_deref().unwrap_or("");
        let out: board::Said = match act.as_str() {
            "like" => board::like(&m.vault, wall.as_deref(), &id).into_iter().collect(),
            "comment" => board::comment(&m.vault, wall.as_deref(), &id, &name, words, face),
            "remove" => board::remove(&m.vault, &id).into_iter().collect(),
            "pin" => { board::pin(&m.vault, &id); vec![] }
            "hide" => { board::hide_comment(&m.vault, &id, words); vec![] }
            "view" => { if let Some(w) = &wall { board::viewed(&m.vault, w, &id) }; return Ok(true) }
            // coins on another's post (iOS MTBoard.coin): refused on a short balance before any word leaves
            // COINS ON ANOTHER'S POST ARE A SEND OF THE CHAIN (iOS 2304 MTBoard.coin): the pair's SEND under the post's name, the word
            // names it; a SEND waiting for its node's word names nothing (the owner's scan credits it); a short chain, an owner
            // without a key or a record that did not stand refuses, and nothing leaves
            "coin" => {
                let (Some(w), coins) = (wall.as_deref(), words.parse::<i64>().unwrap_or(0)) else { return Ok(false) };
                let hands = if coin_chain_on() { p.seed.mnemonic().and_then(|x| wallet::hands(&x)) } else { None };
                match (hands, m.book.secret(w)) {
                    (Some(h), Some(secret)) => {
                        if !board::coin_due(&m.vault, w, &id, coins) {
                            return Ok(false);
                        }
                        match wallet::send3(&m.vault, &h, w, &secret, coins, Some(&format!("post:{id}"))) {
                            wallet::Sent::Taken(tx) => vec![(w.to_string(), board::coin_sent(&id, &tx))],
                            wallet::Sent::Pending => return Ok(true),
                            _ => return Ok(false),
                        }
                    }
                    // no coin key in hand: the book's road of the builds before
                    _ => match board::coin(&m.vault, w, &id, coins) {
                        Some(x) => vec![x],
                        None => return Ok(false),
                    },
                }
            }
            // «Save», «Remove from saved» and «Repost» (iOS keep / unkeep / repost): the window fetched every file first
            "keep" => board::keep(&m.vault, wall.as_deref(), &id).into_iter().collect(),
            "unkeep" => board::unkeep(&m.vault, wall.as_deref(), &id).into_iter().collect(),
            "repost" => {
                let Some(w) = wall.as_deref() else { return Err(()) };
                // THE NAME A REPOST SAYS IT CAME FROM (iOS publicName): the name that wall's owner gave themselves, never my word for them
                let given = m.book.given_name(w).map(|n| n.trim().to_string()).filter(|n| !n.is_empty());
                let wall_name = given.unwrap_or_else(|| if p.lang.starts_with("ru") { "Кто-то" } else { "Someone" }.to_string());
                board::repost(&m.vault, w, &id, &wall_name).into_iter().collect()
            }
            "edit" => { let ok = board::edit(&m.vault, &id, words); let _ = app.emit(WALL, ()); return Ok(ok) }
            _ => return Err(()),
        };
        let ok = out.iter().all(|(to, w)| d.wall_say(to, w));
        trace_line(&format!("wall_do {act} words={}", out.len()));
        let _ = app.emit(WALL, ());
        let _ = app.emit(COINS, ());
        Ok(ok)
    }).await.map_err(|_| ())?
}

/// Who may write on my wall, and who may see it (iOS MTBoardRule), as the settings show them, and set.
#[tauri::command]
async fn wall_rules(m: State<'_, Messenger>) -> Result<serde_json::Value, ()> {
    let (w, s) = board::rules(&m.vault);
    Ok(serde_json::json!({ "write": w, "see": s }))
}
#[tauri::command]
async fn wall_rule_set(m: State<'_, Messenger>, act: String, rule: board::Rule) -> Result<(), ()> {
    if !["onlyMe", "everyone", "contacts", "some", "except"].contains(&rule.rule.as_str()) || !["see", "write"].contains(&act.as_str()) {
        return Err(());
    }
    board::set_rule(&m.vault, &act, rule);
    Ok(())
}

/// THE KEEPING OF A COPY (iOS MTKeeping): its own walk beside the letters' -- the words heard, the owner's rhythm, a first part
/// held told to the person -- so a copy cut and laid never holds the letters up.
fn keeping_walk(app: AppHandle) {
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_secs(5));
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let Some(d) = m.desk(&p) else { continue };
        let words = p.seed.mnemonic();
        let moved = keeping::work(&d, words.as_deref(), my_card(&p));
        let ru = p.lang.starts_with("ru");
        for (chat, bytes) in moved.told {
            // THE PERSON IS TOLD whose part this machine holds and how many bytes, the moment it first holds one (App)
            let name = m.book.chat(&chat).map(|c| if c.alias.trim().is_empty() { c.name } else { c.alias }).unwrap_or_default();
            let size = if bytes >= 1_048_576 { format!("{:.1} MB", bytes as f64 / 1_048_576.0) } else { format!("{} KB", bytes.div_ceil(1024)) };
            let (title, body) = if ru {
                ("Хранение копии".to_string(), format!("{name} хранит на этом компьютере запечатанную часть своей копии ({size}). Открыть её здесь нельзя."))
            } else {
                ("Keeping a copy".to_string(), format!("{name} keeps a sealed part of their copy on this computer ({size}). Nobody can open it here."))
            };
            let _ = app.notification().builder().title(title).body(body).show();
        }
        if moved.changed {
            let _ = app.emit(KEEPING, ());
        }
    });
}

/// THE HOUSE'S MOVING PICTURES (iOS MontanaGifSearch.find): the doors that keep them answer a word with a page of pictures --
/// an empty word, what is popular now; «sticker», the house's stickers. Ids and shapes only; the bytes come by gif_get.
#[tauri::command]
async fn gif_search(q: String, kind: String, offset: u32) -> Result<Vec<serde_json::Value>, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let kind = if kind == "sticker" { "sticker" } else { "gif" };
        let body = serde_json::json!({ "q": q.trim().chars().take(64).collect::<String>(), "limit": 30, "kind": kind, "offset": offset.min(300) });
        let mut items: Vec<serde_json::Value> = vec![];
        doors::read_machines("/gif-search", &body, 15_000, |code, v| {
            if code == 200 {
                if let Some(a) = v.as_ref().and_then(|v| v["items"].as_array()) {
                    items = a.clone();
                    return true;
                }
            }
            false
        });
        items.into_iter()
            .filter(|r| r["id"].as_str().is_some_and(|s| !s.is_empty() && s.len() <= 64 && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')))
            .map(|r| serde_json::json!({ "id": r["id"], "w": r["w"].as_i64().unwrap_or(1).max(1), "h": r["h"].as_i64().unwrap_or(1).max(1) }))
            .collect()
    }).await.map_err(|_| ())
}

/// A picture of the house (iOS MontanaGifSearch.fetch): the light one for a tile, the full one only when it is sent; base64.
#[tauri::command]
async fn gif_get(id: String, full: bool) -> Result<Option<String>, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let mut body = serde_json::json!({ "id": id });
        if full {
            body["full"] = serde_json::json!(true);
        }
        let mut got = None;
        doors::read_machines("/gif-get", &body, if full { 25_000 } else { 15_000 }, |code, v| {
            if code == 200 {
                got = v.as_ref().and_then(|v| v["data"].as_str()).filter(|d| !d.is_empty() && d.len() < 16 << 20).map(str::to_string);
            }
            got.is_some()
        });
        got
    }).await.map_err(|_| ())
}

/// THE PASSWORDS OPENED (iOS MTPasswordVault.unlock): only after Windows Hello said it is the person; open five minutes. A window
/// of the checks (MONTANA_NO_HELLO) is refused at once, as the 24 words are.
#[tauri::command]
async fn passwords_open(window: tauri::WebviewWindow, p: State<'_, Person>, m: State<'_, Messenger>) -> Result<Vec<passwords::Item>, String> {
    if let Some(items) = passwords::items(&m.vault) {
        return Ok(items);
    }
    let hwnd = window.hwnd().map_err(|_| "window")?.0 as isize;
    let reason = if p.lang.starts_with("ru") { "Откройте свои пароли" } else { "Unlock your passwords" };
    match tauri::async_runtime::spawn_blocking(move || hello::verify(hwnd, reason)).await.map_err(|_| "refused")? {
        hello::Verdict::Verified => {
            passwords::open_now();
            passwords::items(&m.vault).ok_or_else(|| "refused".to_string())
        }
        hello::Verdict::NotSet => Err("notset".into()),
        hello::Verdict::Refused => Err("refused".into()),
    }
}
#[tauri::command]
async fn passwords_save(m: State<'_, Messenger>, item: passwords::Item) -> Result<Vec<passwords::Item>, ()> {
    if !passwords::save(&m.vault, item) {
        return Err(());
    }
    passwords::items(&m.vault).ok_or(())
}
#[tauri::command]
async fn passwords_remove(m: State<'_, Messenger>, id: String) -> Result<Vec<passwords::Item>, ()> {
    passwords::remove(&m.vault, &id);
    passwords::items(&m.vault).ok_or(())
}
#[tauri::command]
async fn passwords_lock() -> Result<(), ()> {
    passwords::lock();
    Ok(())
}
/// The one-time code of a key now, and the seconds it still stands.
#[tauri::command]
async fn password_code(otp: String) -> Result<Option<(String, u64)>, ()> {
    let Some(spec) = passwords::spec(&otp) else { return Ok(None) };
    let now = (wire::now_ms() / 1000) as u64;
    Ok(passwords::code(&spec, now).map(|c| (c, spec.period.max(1) - now % spec.period.max(1))))
}
#[tauri::command]
async fn password_fresh() -> Result<String, ()> {
    Ok(passwords::fresh(20))
}
/// A secret copied out of the clipboard's history and cloud (iOS: this device alone, for ninety seconds -- then it leaves).
#[tauri::command]
async fn password_copy(value: String) -> Result<bool, ()> {
    let ok = clipboard::copy_secret(&value);
    if ok {
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_secs(90));
            clipboard::clear_if(&value);
        });
    }
    Ok(ok)
}
/// A secret shared into a chat (iOS MTSecretShareSheet): its letter rides the chat's own road, end to end.
#[tauri::command]
async fn secret_send(app: AppHandle, chat: String, id: String) -> Result<(), ()> {
    let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
    let item = passwords::item(&m.vault, &id).ok_or(())?;
    let text = passwords::letter(&item).ok_or(())?;
    let d = m.desk(&p).ok_or(())?;
    if m.book.secret(&chat).is_none() && !groups::is_group(&chat) && !book::is_saved(&chat) {
        return Err(());
    }
    let mid = d.draft(&chat, &text, "", "");
    drop(d);
    changed(&app);
    deed(app, move |d| { d.post(&chat, &mid); });
    Ok(())
}
/// The secret a letter carries, saved into my Passwords (iOS MTSecretSaveSheet): the passwords open first.
#[tauri::command]
async fn secret_take(window: tauri::WebviewWindow, p: State<'_, Person>, m: State<'_, Messenger>, chat: String, mid: String) -> Result<bool, String> {
    let text = m.book.chat(&chat).and_then(|c| c.msgs.into_iter().find(|x| x.mid == mid)).map(|x| x.text).ok_or("gone")?;
    let item = passwords::parse(&text).ok_or("unreadable")?;
    if !passwords::is_open() {
        passwords_open(window, p, m.clone()).await?;
    }
    Ok(passwords::save(&m.vault, item))
}

/// Every call sign in the person's language (iOS MontanaCallsignPicker): a person who claimed no name is given one, and may
/// take another instead.
#[tauri::command]
async fn callsigns(p: State<'_, Person>) -> Result<Vec<String>, ()> {
    Ok(profile::callsigns(&p.lang))
}

/// THE CALLEE'S RECORDING KEPT ON THIS COMPUTER (iOS: only the caller sends a recording to the chat): a file in the data folder's
/// own «recordings», named by its moment; the person is told where.
#[tauri::command]
fn recording_keep(app: AppHandle, request: tauri::ipc::Request) -> Result<String, ()> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err(()) };
    let ext = request.headers().get("ext").and_then(|v| v.to_str().ok()).filter(|e| ["m4a", "mp4"].contains(e)).unwrap_or("m4a");
    let m = app.state::<Messenger>();
    let dir = m.dir.join("recordings");
    std::fs::create_dir_all(&dir).map_err(|_| ())?;
    let name = format!("call-{}.{ext}", chrono_name());
    let path = dir.join(&name);
    std::fs::write(&path, body).map_err(|_| ())?;
    let p = app.state::<Person>();
    let ru = p.lang.starts_with("ru");
    let _ = app.notification().builder()
        .title(if ru { "Запись звонка" } else { "Call recording" })
        .body(if ru { format!("Сохранена на этом компьютере: {}", path.display()) } else { format!("Kept on this computer: {}", path.display()) })
        .show();
    Ok(path.display().to_string())
}

/// A file's name by the moment: yyyymmdd-hhmmss in UTC.
fn chrono_name() -> String {
    let s = wire::now_ms() / 1000;
    let (days, rest) = (s.div_euclid(86_400), s.rem_euclid(86_400));
    // the civil date of the days since 1970 (Howard Hinnant's algorithm)
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{y:04}{m:02}{d:02}-{:02}{:02}{:02}", rest / 3600, rest / 60 % 60, rest % 60)
}

/// THE STICKERS' BOOK as the panel draws it (iOS MontanaStickerBook): my set and the sets of others.
#[tauri::command]
async fn stickers_state(p: State<'_, Person>, m: State<'_, Messenger>) -> Result<serde_json::Value, ()> {
    Ok(stickers::state(&m.vault, &p.seed.twin().unwrap_or_default()))
}

/// A picture joins my set (made ready by the window: the long side at most 512); its name.
#[tauri::command]
fn sticker_add(app: AppHandle, request: tauri::ipc::Request) -> Result<String, ()> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err(()) };
    let m = app.state::<Messenger>();
    stickers::add(&m.vault, &m.media, body).ok_or(())
}

/// A sticker letter's picture joins my set (iOS adopt: the bytes copied, so sweeping the conversation never empties the set).
#[tauri::command]
async fn sticker_adopt(m: State<'_, Messenger>, mid: String) -> Result<Option<String>, ()> {
    Ok(m.media.get(&mid).and_then(|b| stickers::add(&m.vault, &m.media, &b)))
}

/// One sticker of my set taken out of it.
#[tauri::command]
async fn sticker_forget(m: State<'_, Messenger>, name: String) -> Result<(), ()> {
    stickers::forget(&m.vault, &m.media, &name);
    Ok(())
}

/// A sticker of the book sent: the picture letter and its passport (iOS sendStickerFile).
#[tauri::command]
async fn sticker_send(app: AppHandle, chat: String, name: String, qt: Option<String>, qm: Option<String>) -> Result<(), ()> {
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let Some(d) = m.desk(&p) else { return };
        if stickers::send(&d, &m.media, &chat, &name, qt.as_deref().unwrap_or(""), qm.as_deref().unwrap_or("")).is_some() {
            changed(&app);
        }
    });
    Ok(())
}

/// «Send me that set», asked of the one who handed it over.
#[tauri::command]
async fn sticker_ask(p: State<'_, Person>, m: State<'_, Messenger>, pack: String) -> Result<bool, ()> {
    Ok(m.desk(&p).is_some_and(|d| stickers::ask(&d, &pack)))
}

/// A sticker letter's passport here: its set's title, and whether the set is held.
#[tauri::command]
async fn sticker_passport(p: State<'_, Person>, m: State<'_, Messenger>, mid: String) -> Result<Option<serde_json::Value>, ()> {
    Ok(stickers::passport(&m.vault, &mid, &p.seed.twin().unwrap_or_default()))
}

/// THE BUSINESS CARD IS KEPT (iOS MontanaBusinessCard): the person's own card -- the name, the phone, the e-mail and the other ways
/// to reach them -- sealed in the device vault; a card never kept, or kept without a name, carries the person's own name.
#[tauri::command]
async fn card_get(p: State<'_, Person>, m: State<'_, Messenger>) -> Result<serde_json::Value, ()> {
    let mut c: serde_json::Value = m.vault.get("businessCard").and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_else(|| serde_json::json!({}));
    for k in ["name", "phone", "email", "other"] {
        if !c[k].is_string() {
            c[k] = serde_json::json!("");
        }
    }
    if c["name"].as_str().is_some_and(|n| n.trim().is_empty()) {
        c["name"] = serde_json::json!(profile::strip_crown(p.profile.read().user_name.trim()));
    }
    Ok(c)
}
#[tauri::command]
async fn card_set(m: State<'_, Messenger>, card: serde_json::Value) -> Result<bool, ()> {
    let mut c = serde_json::Map::new();
    for (k, limit) in [("name", 64), ("phone", 64), ("email", 128), ("other", 1000)] {
        let v: String = card[k].as_str().unwrap_or("").chars().take(limit).collect();
        c.insert(k.to_string(), serde_json::json!(if k == "name" { profile::strip_crown(v.trim()) } else { v }));
    }
    Ok(m.vault.set("businessCard", serde_json::Value::Object(c).to_string().as_bytes()))
}

/// A PHOTO AS A GROUND (iOS MTWallpaper.saveRendered / lightData): placed by the window and made a JPEG there at the window's
/// pixels, raw; kept sealed in this person's media store (iOS keeps it plain beside the avatars), named by its bytes. The window
/// reads it back as any picture of the store (`media_get`).
#[tauri::command]
fn ground_keep(app: AppHandle, request: tauri::ipc::Request) -> Result<String, ()> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err(()) };
    if body.len() > 8_000_000 || !body.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return Err(());
    }
    let name = format!("gnd_{}.jpg", wire::hex(&wire::sha(&[b"mt-ground\0", body])[..12]));
    if app.state::<Messenger>().media.put(&name, body) { Ok(name) } else { Err(()) }
}
/// A photo ground no choice wears any more leaves the store with it (iOS MTWallpaper.remove).
#[tauri::command]
async fn ground_forget(m: State<'_, Messenger>, name: String) -> Result<(), ()> {
    if name.starts_with("gnd_") && name.len() <= 64 {
        m.media.delete(&name);
    }
    Ok(())
}

/// MY PAGE'S GROUND as my correspondents get it (iOS MTPageGround.mine): "" none, "n:" + a drawn ground's name, "p:" + my kept
/// picture's name here; the walk carries it to every one whose build reads it.
#[tauri::command]
async fn ground_page_set(m: State<'_, Messenger>, g: String) -> Result<(), ()> {
    let ok = g.is_empty() || g.strip_prefix("n:").is_some_and(|n| pageground::NAMES.contains(&n)) || g.strip_prefix("p:").is_some_and(|n| n.starts_with("gnd_") && n.len() <= 64);
    if !ok {
        return Err(());
    }
    pageground::set_mine(&m.vault, g);
    Ok(())
}

/// The ground a correspondent's page wears here, as they sent it: a drawn one's name, or their picture's name in the store.
#[tauri::command]
async fn peer_ground(m: State<'_, Messenger>, chat: String) -> Result<Option<pageground::Theirs>, ()> {
    Ok(pageground::theirs(&m.vault, &chat))
}

/// THE GLOBE'S LAMP (iOS MTBarGlobe, MontanaPhoneNode.nodeUp / nodeUpKnown): green while this computer holds a node, red once the
/// doors were knocked and none is held, grey before the first knock -- silence before it is ignorance, not absence.
#[tauri::command]
fn node_lamp() -> serde_json::Value {
    let up = channels::nodes_held() > 0;
    serde_json::json!({ "up": up, "known": up || channels::knocked() })
}

/// THE TIME PANEL'S FIRST SLOT (iOS chatsTopBarPlate slot 0): «notifications» while Windows refuses this app's banners (the crossed
/// speaker, its way to the banners' page), «keeping» while the person chose to keep no copy with their contacts (the crossed people,
/// MTKeeping.offShown), else nothing -- the drawer's grid.
#[tauri::command]
async fn bar_first(app: AppHandle) -> Result<&'static str, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        if banners_refused(&app) {
            return Ok("notifications");
        }
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        Ok(match m.desk(&p) {
            Some(d) if keeping::told(&d) && !keeping::mine(&d) => "keeping",
            _ => "",
        })
    }).await.map_err(|_| ())?
}

/// Whether Windows refuses this app's banners (iOS MTNotifyAllowed.refused): the person's switch for the app, or all of them, off.
/// A name Windows does not know answers nothing, and nothing is refused.
#[cfg(windows)]
fn banners_refused(app: &AppHandle) -> bool {
    use windows::UI::Notifications::{NotificationSetting, ToastNotificationManager};
    let id = windows::core::HSTRING::from(app.config().identifier.as_str());
    ToastNotificationManager::CreateToastNotifierWithId(&id).and_then(|n| n.Setting()).is_ok_and(|s| s != NotificationSetting::Enabled)
}
#[cfg(not(windows))]
fn banners_refused(_: &AppHandle) -> bool {
    false
}

/// The keeping as the settings show it (iOS MTKeepingSection).
#[tauri::command]
async fn keep_state(app: AppHandle) -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        Ok(m.desk(&p).map(|d| keeping::state(&d)).unwrap_or_default())
    }).await.map_err(|_| ())?
}

/// The person's hand on the keeping: «mine» (my copy with my contacts), «others» (parts for them), «told» (the question at the
/// opening answered: keep or not now), «drop» (a person's parts let go), «take» (my copy back from my contacts), «stop».
#[tauri::command]
async fn keep_do(app: AppHandle, act: String, on: Option<bool>, chat: Option<String>) -> Result<(), ()> {
    let a2 = app.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (a2.state::<Person>(), a2.state::<Messenger>());
        let Some(d) = m.desk(&p) else { return };
        match act.as_str() {
            "mine" | "told" => keeping::set_mine(&d, on.unwrap_or(false)),
            "others" => keeping::set_others(&d, on.unwrap_or(true)),
            "drop" => { if let Some(c) = chat { keeping::drop_parts(&d, &c); } }
            "stop" => keeping::stop_taking(),
            // THE LIGHT COPY FIRST (iOS MTKeeping.takeBack: «the pipe of light is read before any call»), then the keepers' parts
            "take" if !keeping::is_taking() => take_light_then(a2.clone(), true),
            _ => {}
        }
    }).await.map_err(|_| ())?;
    let _ = app.emit(KEEPING, ());
    Ok(())
}

type PeerPage = (String, String, String, String, String);

/// A correspondent's page: the name, their words about themselves and their link (iOS PeerInfo).
#[tauri::command]
async fn peer_about(m: State<'_, Messenger>, chat: String) -> Result<Option<PeerPage>, ()> {
    Ok(m.peer(&chat))
}

/// My own name for a correspondent (iOS «Edit» on their page: first name, last name); empty -- theirs again.
#[tauri::command]
async fn peer_rename(app: AppHandle, m: State<'_, Messenger>, chat: String, first: String, last: String) -> Result<bool, ()> {
    let ok = m.rename(&chat, &first, &last);
    changed(&app);
    Ok(ok)
}

/// A correspondent's face, raw (a JPEG), or mine when `chat` is empty.
#[tauri::command]
async fn face_get(app: AppHandle, chat: String) -> Result<tauri::ipc::Response, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        let face = if chat.is_empty() { m.self_face() } else { m.faces.get(&chat) };
        face.map(picture::viewable).ok_or(())
    }).await.map_err(|_| ())?.map(tauri::ipc::Response::new)
}

/// MY FACE CHOSEN (iOS MTSelfFace.set): a square JPEG made ready by the window (640 px, at most 128 KiB), raw; an empty body
/// takes it back. Every correspondent hears it with the next walk, my card shows it.
#[tauri::command]
fn face_set(app: AppHandle, request: tauri::ipc::Request) -> Result<bool, ()> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err(()) };
    if body.len() > 131_072 || (!body.is_empty() && !body.starts_with(&[0xFF, 0xD8])) {
        return Err(());
    }
    let m = app.state::<Messenger>();
    let ok = m.set_self_face(if body.is_empty() { None } else { Some(body.as_slice()) });
    changed(&app);
    Ok(ok)
}

/// A VOICE LETTER (iOS: hold the microphone, release to send): the window hands the samples raw -- a 4-byte length, the JSON
/// (chat, rate, qt, qm), 16-bit mono PCM -- and they go as AAC in an .m4a with their length and wave, a file like any other.
#[tauri::command]
fn chat_send_voice(app: AppHandle, request: tauri::ipc::Request) -> Result<(), String> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err("raw".into()) };
    if body.len() < 4 {
        return Err("short".into());
    }
    let n = u32::from_le_bytes([body[0], body[1], body[2], body[3]]) as usize;
    let meta: serde_json::Value = body.get(4..4 + n).and_then(|j| serde_json::from_slice(j).ok()).ok_or("meta")?;
    let pcm: Vec<i16> = body[4 + n..].chunks_exact(2).map(|b| i16::from_le_bytes([b[0], b[1]])).collect();
    let rate = meta["rate"].as_u64().unwrap_or(48_000) as u32;
    let chat = meta["chat"].as_str().unwrap_or_default().to_string();
    let (qt, qm) = (meta["qt"].as_str().unwrap_or("").to_string(), meta["qm"].as_str().unwrap_or("").to_string());
    if pcm.len() < (rate / 2) as usize {
        return Err("short".into()); // under half a second: a slip of the finger, as iOS refuses it
    }
    std::thread::spawn(move || {
        let Some(m4a) = voice::encode_m4a(&pcm, rate) else { return };
        let du = (pcm.len() as f64 / rate as f64 * 10.0).round() / 10.0;
        let manifest = serde_json::json!({ "k": "aud", "e": "m4a", "du": du, "wv": wire::b64(&voice::wave(&pcm)) });
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let Some(d) = m.desk(&p) else { return };
        if let Some(mid) = d.draft_media(&chat, &m4a, manifest, &qt, &qm) {
            changed(&app);
            d.post(&chat, &mid);
        }
        changed(&app);
    });
    Ok(())
}

/// The file of a letter, raw, for the window to draw (a picture, a film, a voice).
#[tauri::command]
async fn media_get(app: AppHandle, mid: String) -> Result<tauri::ipc::Response, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        // the store's unseal, then a HEIC of iOS -- a photo, a sticker with its transparency -- as PNG: WebView2 does not draw HEIF
        m.media.get(&mid).map(picture::viewable).ok_or(())
    }).await.map_err(|_| ())?.map(tauri::ipc::Response::new)
}

/// A picture a person picks that the window cannot open (HEIC from an iPhone): raw in, PNG out, for the window to make it
/// ready as iOS sends a photo (JPEG 1600).
#[tauri::command]
async fn picture_png(request: tauri::ipc::Request<'_>) -> Result<tauri::ipc::Response, ()> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err(()) };
    let b = body.clone();
    tauri::async_runtime::spawn_blocking(move || picture::png_of(&b)).await.ok().flatten().map(tauri::ipc::Response::new).ok_or(())
}

/// The person asked for a file the walk would not fetch by itself.
#[tauri::command]
async fn media_want(app: AppHandle, mid: String) -> Result<(), ()> {
    *app.state::<Messenger>().want.lock().unwrap() = Some(mid.clone());
    deed(app, move |d| { d.fetch_media(Some(&mid), AUTO_FETCH); });
    Ok(())
}

/// A FILE OPENED (iOS: the system's preview or «Open in»): written into the person's Downloads\Montana under its own name
/// and handed to the program Windows opens it with. The file leaves the sealed store only by this tap.
#[tauri::command]
async fn media_open(m: State<'_, Messenger>, chat: String, mid: String) -> Result<bool, ()> {
    if !m.media.has(&mid) {
        return Ok(false);
    }
    let row = m.book.chat(&chat).and_then(|c| c.msgs.into_iter().find(|x| x.mid == mid)).ok_or(())?;
    let manifest: serde_json::Value = serde_json::from_str(row.text.strip_prefix(media::MARK).unwrap_or("{}")).unwrap_or_default();
    let ext: String = manifest["e"].as_str().unwrap_or("bin").chars().filter(|c| c.is_ascii_alphanumeric()).take(8).collect();
    let given: String = manifest["n"].as_str().unwrap_or("").chars().filter(|c| !"<>:\"/\\|?*".contains(*c) && !c.is_control()).collect();
    let stem = if given.trim().is_empty() || given == "montana-card" { format!("Montana {}", row.at) } else { given.trim().to_string() };
    let name = if stem.to_lowercase().ends_with(&format!(".{}", ext.to_lowercase())) { stem } else { format!("{stem}.{ext}") };
    // a check's own data folder keeps what it opens in itself, never in the person's Downloads
    let dir = match std::env::var_os("MONTANA_DATA_DIR") {
        Some(_) => m.dir.join("Downloads"),
        None => std::path::PathBuf::from(std::env::var_os("USERPROFILE").ok_or(())?).join("Downloads").join("Montana"),
    };
    let store = m.media.clone();
    // a big file goes out a piece at a time, and is compared so, off the async threads
    let path = tauri::async_runtime::spawn_blocking(move || {
        std::fs::create_dir_all(&dir).ok()?;
        let mut path = dir.join(&name);
        let mut n = 2;
        while path.exists() && !store.same_as(&mid, &path) {
            path = dir.join(format!("{} ({n}).{ext}", name.trim_end_matches(&format!(".{ext}"))));
            n += 1;
        }
        (path.exists() || store.write_to(&mid, &path)).then_some(path)
    }).await.map_err(|_| ())?.ok_or(())?;
    trace_line(&format!("media_open {} bytes", std::fs::metadata(&path).map(|x| x.len()).unwrap_or(0)));
    note_opened(&m.vault, &path);
    if std::env::var_os("MONTANA_DATA_DIR").is_some() {
        return Ok(true); // a check's folder: the file is written there, and no program of this computer is started for it
    }
    Ok(open_in_browser(&path.to_string_lossy()))
}

/// THE FILES OPENED FROM THE LETTERS (iOS MTDocLink: the copies a viewer was handed): only what this program wrote out for a viewer
/// is named -- the person's own files beside them in Downloads\Montana (a backup, a file put there by hand) are never counted or
/// cleared.
const OPENED: &str = "openedFiles";
fn opened_files(v: &vault::Vault) -> Vec<std::path::PathBuf> {
    let list: Vec<String> = v.get(OPENED).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    list.into_iter().map(std::path::PathBuf::from).filter(|p| p.is_file()).collect()
}
fn note_opened(v: &vault::Vault, path: &std::path::Path) {
    static ONE: std::sync::Mutex<()> = std::sync::Mutex::new(());
    let _one = ONE.lock().unwrap_or_else(|e| e.into_inner());
    let mut list: Vec<String> = v.get(OPENED).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    let p = path.to_string_lossy().to_string();
    if !list.contains(&p) {
        list.push(p);
        let skip = list.len().saturating_sub(4000);
        v.set(OPENED, &serde_json::to_vec(&list[skip..]).unwrap_or_default());
    }
}

/// WHAT THE COPY TAKES, COUNTED FROM THIS COMPUTER (iOS Data and Storage «BACKUP», CopyInventory): the conversations, their letters,
/// the attachments and their size.
#[tauri::command]
async fn copy_inventory(app: AppHandle) -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        let inv = inventory(&m);
        let plan = history::Plan::load(&m.vault);
        let taken: Vec<&serde_json::Value> = inv["convs"].as_array().into_iter().flatten().filter(|c| plan.takes_chat(c["id"].as_str().unwrap_or(""))).collect();
        let files: Vec<&serde_json::Value> = inv["files"].as_array().into_iter().flatten()
            .filter(|f| f["chat"].as_str().is_some_and(|c| plan.takes_file(c, f["kind"].as_str().unwrap_or("file"), f["name"].as_str().unwrap_or("")))).collect();
        Ok(serde_json::json!({ "convs": inv["convs"].as_array().map_or(0, |a| a.len()), "chats": taken.len(),
            "letters": taken.iter().map(|c| c["letters"].as_u64().unwrap_or(0)).sum::<u64>(),
            "files": files.len(), "bytes": files.iter().map(|f| f["bytes"].as_u64().unwrap_or(0)).sum::<u64>() }))
    }).await.map_err(|_| ())?
}

/// WHAT THIS COMPUTER HOLDS FOR A COPY, COUNTED (iOS CopyInventory.gather): every conversation with letters -- its name, its letters,
/// its files and their weight on this disk --, every file of the store by the name the copy gives it, its kind and its owner (a
/// file no letter names has neither), and how many files the letters name that this computer does not hold.
fn inventory(m: &Messenger) -> serde_json::Value {
    let size = |key: &str| diskuse::size(&m.media.dir().join(format!("{key}.sealed"))) + diskuse::size(&m.media.dir().join(format!("{key}.parts")));
    let (mut convs, mut files, mut missing, mut named) = (vec![], vec![], 0, std::collections::HashSet::new());
    for c in m.book.all().into_iter().filter(|c| !c.msgs.is_empty()) {
        let (mut n, mut bytes) = (0, 0u64);
        for x in c.msgs.iter().filter(|x| x.text.starts_with(media::MARK)) {
            let key = media::key_of(&x.mid);
            named.insert(key.clone());
            if !m.media.has(&x.mid) {
                missing += 1;
                continue;
            }
            let b = size(&key);
            files.push(serde_json::json!({ "name": history::file_name(&x.mid, &x.text), "mid": x.mid, "chat": c.reference,
                "kind": history::kind_of(&x.text), "bytes": b, "e": serde_json::from_str::<serde_json::Value>(&x.text[media::MARK.len()..]).ok().and_then(|v| v["e"].as_str().map(str::to_string)) }));
            n += 1;
            bytes += b;
        }
        let title = if c.alias.trim().is_empty() { c.name.clone() } else { c.alias.clone() };
        convs.push(serde_json::json!({ "id": c.reference, "title": title, "letters": c.msgs.len(), "files": n, "bytes": bytes }));
    }
    // the store's files no letter names: by their key, no kind but a file's, no owner
    let walls: std::collections::HashSet<String> = board::file_names(&m.vault).iter().map(|n| media::key_of(n)).collect();
    for e in std::fs::read_dir(m.media.dir()).into_iter().flatten().flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        let key = name.split('.').next().unwrap_or("").to_string();
        if key.is_empty() || named.contains(&key) || walls.contains(&key) || name.ends_with(".tmp") || name.contains(".tmp") {
            continue;
        }
        named.insert(key.clone());
        files.push(serde_json::json!({ "name": key, "kind": "file", "bytes": diskuse::size(&e.path()) }));
    }
    convs.sort_by(|a, b| b["bytes"].as_u64().cmp(&a["bytes"].as_u64()).then(b["letters"].as_u64().cmp(&a["letters"].as_u64())));
    serde_json::json!({ "convs": convs, "files": files, "missing": missing })
}

/// The copy's pages (iOS CopyChatsPage, CopyKindsPage, CopyFilesPage): the inventory and the plan, read together.
#[tauri::command]
async fn copy_pages(app: AppHandle) -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        let mut inv = inventory(&m);
        inv["plan"] = serde_json::to_value(history::Plan::load(&m.vault)).unwrap_or_default();
        Ok(inv)
    }).await.map_err(|_| ())?
}

/// The person's plan, kept (iOS CopyPlan.save): what the next copy leaves out.
#[tauri::command]
async fn copy_plan_set(m: State<'_, Messenger>, plan: history::Plan) -> Result<bool, ()> {
    Ok(plan.save(&m.vault))
}

/// THE COMPUTER'S COPY ONLY (iOS CopyFilesPage.deleteMany -> MTHomeShelf.removeHeld): the chosen files leave this computer on the
/// node's word asked now -- every letter stays, and a file comes back from the node when it is opened; a file the node does not
/// hold whole stays. The names gone.
#[tauri::command]
async fn copy_remove(app: AppHandle, names: Vec<String>) -> Result<Vec<String>, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        let only: std::collections::HashSet<String> = names.into_iter().collect();
        let before: Vec<(String, String)> = m.book.all().iter().flat_map(|c| c.msgs.iter().filter(|x| x.text.starts_with(media::MARK))
            .map(|x| (history::file_name(&x.mid, &x.text), x.mid.clone())).collect::<Vec<_>>()).filter(|(n, _)| only.contains(n)).collect();
        if let Some(k) = home_armed(&app).filter(|_| homeshelf::bringing(&m.vault)) {
            homeshelf::remove_held(&m.vault, &k, &m.book, &m.media, Some(&only));
        }
        let gone: Vec<String> = before.into_iter().filter(|(_, mid)| !m.media.has(mid)).map(|(n, _)| n).collect();
        trace_line(&format!("copy_remove asked={} gone={}", only.len(), gone.len()));
        if !gone.is_empty() {
            changed(&app);
        }
        Ok(gone)
    }).await.map_err(|_| ())?
}

/// WHAT THIS COMPUTER HOLDS (iOS Data and Storage «ON THIS PHONE», MTDiskUse.measure), measured off the window's thread.
#[tauri::command]
async fn disk_use(app: AppHandle) -> Result<diskuse::Use, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        let letters = m.book.all().iter().flat_map(|c| c.msgs.iter()).filter(|x| x.text.starts_with(media::MARK)).map(|x| media::key_of(&x.mid)).collect();
        let walls = board::file_names(&m.vault).iter().map(|n| media::key_of(n)).collect();
        Ok(diskuse::measure(&m.dir, &letters, &walls, &opened_files(&m.vault), &diskuse::shelf_files()))
    }).await.map_err(|_| ())?
}

/// A row's «Clear» (iOS: the copies waiting -- MontanaBackup.sweep(all); the opened files -- MTDocLink.release): the bytes freed, and
/// the files back in the chats (none here: the store never let them go).
#[tauri::command]
async fn disk_clear(app: AppHandle, what: String) -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        let freed = match what.as_str() {
            "shelf" => diskuse::clear(&diskuse::shelf_files()),
            "opened" => {
                let n = diskuse::clear(&opened_files(&m.vault));
                m.vault.set(OPENED, b"[]");
                n
            }
            _ => return Err(()),
        };
        trace_line(&format!("disk_clear {what} freed={freed}"));
        Ok(serde_json::json!({ "freed": freed, "back": 0 }))
    }).await.map_err(|_| ())?
}

/// The deeds of the letter menu (iOS MontanaMessageMenu), each off the window's thread; the window hears the change.
fn deed(app: AppHandle, f: impl FnOnce(&post::Desk) + Send + 'static) {
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        if let Some(d) = m.desk(&p) {
            f(&d);
        }
        changed(&app);
    });
}

#[tauri::command]
async fn chat_pin(app: AppHandle, chat: String, mid: String, on: bool, both: bool) -> Result<(), ()> {
    deed(app, move |d| d.pin(&chat, &mid, on, both));
    Ok(())
}

/// A CALL IN FLIGHT: its chat and seed; the switches of its lane and its knocks; the lane's wait (3 building, 10 talking).
#[derive(Clone)]
struct CallRun {
    chat: String,
    seed: String,
    stop: std::sync::Arc<std::sync::atomic::AtomicBool>,
    knocking: std::sync::Arc<std::sync::atomic::AtomicBool>,
    wait: std::sync::Arc<std::sync::atomic::AtomicU32>,
    ring_mid: Option<String>,
}

/// THE CALLS IN FLIGHT (iOS: the call in hand, the parked one and the second line, each under its own seed): every one keeps its
/// own lane, so the words of a call held or still ringing are heard while another talks.
static CALLS: std::sync::Mutex<Vec<CallRun>> = std::sync::Mutex::new(Vec::new());
/// The call in hand, a parked one and a second line: no more stand at once (a third caller is refused by the window).
const CALLS_AT_ONCE: usize = 3;

/// A call's run let go: its lane and its knocks stop.
fn call_stop(run: &CallRun) {
    run.stop.store(true, std::sync::atomic::Ordering::SeqCst);
    run.knocking.store(false, std::sync::atomic::Ordering::SeqCst);
}

/// A PACKET OF THE CALL HEARD ON A LANE (iOS handleLiveCallSignal): receipts settle my packets, each of theirs that names
/// itself is answered -- a repeat too -- and the window hears a packet once.
fn call_packet(app: &AppHandle, chat: &str, epoch: &str, words: &str) {
    let calls::Heard { answer, fresh, .. } = calls::sort_heard(epoch, words);
    if !answer.is_empty() {
        let (a, chat, epoch) = (app.clone(), chat.to_string(), epoch.to_string());
        std::thread::spawn(move || {
            let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
            if let Some(d) = m.desk(&p) {
                for q in answer {
                    calls::post_words(&m.book, &d.twin, &chat, &epoch, &calls::receipt_words(&epoch, &q));
                }
            }
        });
    }
    if let Some(w) = fresh {
        let _ = app.emit(CALL_WORDS, serde_json::json!({ "chat": chat, "epoch": epoch, "words": w }));
    }
}

/// The call's own lane, long-polled while it lives (iOS: wait 3 while it is built, 10 while it talks); its words go to the
/// window as they come, a «box» hint fetches the box.
fn call_lane(app: AppHandle, run: CallRun) {
    // my packets without their receipt go again, every two seconds, while the call lives (iOS MTCallRoute)
    let (a, again) = (app.clone(), run.clone());
    std::thread::spawn(move || {
        let epoch = calls::epoch_of(&again.seed);
        while !again.stop.load(std::sync::atomic::Ordering::SeqCst) {
            std::thread::sleep(std::time::Duration::from_secs(1));
            let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
            let Some(d) = m.desk(&p) else { return };
            for (chat, words) in calls::due(&epoch) {
                calls::post_words_all(&m.book, &d.twin, &chat, &epoch, &words);
            }
        }
    });
    std::thread::spawn(move || {
        let epoch = calls::epoch_of(&run.seed);
        while !run.stop.load(std::sync::atomic::Ordering::SeqCst) {
            let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
            let Some(d) = m.desk(&p) else { return };
            let wait = run.wait.load(std::sync::atomic::Ordering::SeqCst);
            match calls::listen(&m.book, &d.twin, &run.chat, &epoch, wait) {
                Some((words, boxed)) => {
                    for w in words {
                        call_packet(&app, &run.chat, &epoch, &w);
                    }
                    if boxed {
                        d.fetch_once();
                        changed(&app);
                    }
                }
                None => std::thread::sleep(std::time::Duration::from_secs(1)),
            }
        }
    });
}

/// A CALL BEGINS here (the caller: the ring letter, the VoIP knocks every 5 s for its life; the callee: only the lane).
#[tauri::command]
async fn call_begin(app: AppHandle, chat: String, seed: String, video: bool, outgoing: bool) -> Result<(), String> {
    if wire::unb64(&seed).map(|b| b.len()) != Some(32) {
        return Err("seed".into());
    }
    {
        // a call begun again under its own seed takes its own place; the oldest goes past the three that may stand
        let mut all = CALLS.lock().unwrap();
        all.retain(|r| if r.seed == seed { call_stop(r); false } else { true });
        while all.len() >= CALLS_AT_ONCE {
            call_stop(&all.remove(0));
        }
    }
    let run = CallRun {
        chat: chat.clone(), seed: seed.clone(),
        stop: Default::default(), knocking: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(outgoing)),
        wait: std::sync::Arc::new(std::sync::atomic::AtomicU32::new(3)), ring_mid: None,
    };
    let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
    let d = m.desk(&p).ok_or("seat")?;
    let mut run = run;
    if outgoing {
        run.ring_mid = Some(format!("ring-{}", calls::tag_of(&seed)));
    }
    CALLS.lock().unwrap().push(run.clone());
    drop(d);
    call_lane(app.clone(), run.clone());
    if outgoing {
        let a = app.clone();
        std::thread::spawn(move || {
            let born = wire::now_ms();
            let mut lettered = false;
            while run.knocking.load(std::sync::atomic::Ordering::SeqCst) && wire::now_ms() - born < calls::LIFE_S * 1000 {
                let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
                let Some(d) = m.desk(&p) else { return };
                let rung = calls::wake_voip(&m.book, &d.twin, &chat, &seed, video, d.my_name.trim(), "", born);
                if !lettered {
                    d.ring_letter(&chat, &seed, video);
                    lettered = true;
                }
                if rung == 0 {
                    break; // nobody takes VoIP wakes there: the lane and the box ring it
                }
                std::thread::sleep(std::time::Duration::from_secs(5));
            }
        });
    }
    Ok(())
}

/// The call's words onto its lane.
#[tauri::command]
async fn call_post(app: AppHandle, chat: String, epoch: String, words: String) -> Result<bool, ()> {
    let r = tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        m.desk(&p).map(|d| match calls::name_packet(&words) {
            // a packet of mine names itself and waits for its receipt (iOS sendCallSignal)
            Some((q, named)) => {
                let ok = calls::post_words(&m.book, &d.twin, &chat, &epoch, &named);
                calls::sent(&epoch, &chat, &q, &named);
                ok
            }
            None => calls::post_words(&m.book, &d.twin, &chat, &epoch, &words),
        }).unwrap_or(false)
    }).await.map_err(|_| ())?;
    Ok(r)
}

/// The far side rings, or the call talks: the knocks stop, the ring letter leaves the box; talking, the lane waits longer. The
/// call is named by its seed (an older window names none: the newest).
#[tauri::command]
async fn call_heard(talking: bool, seed: Option<String>) -> Result<(), ()> {
    let run = {
        let all = CALLS.lock().unwrap();
        match &seed {
            Some(s) => all.iter().find(|r| &r.seed == s).cloned(),
            None => all.last().cloned(),
        }
    };
    if let Some(run) = run {
        run.knocking.store(false, std::sync::atomic::Ordering::SeqCst);
        if talking {
            run.wait.store(10, std::sync::atomic::Ordering::SeqCst);
        }
        if let Some(mid) = run.ring_mid {
            std::thread::spawn(move || {
                for d in doors::all() {
                    doors::post_at(&d, "/box-del", &serde_json::json!({ "mids": [mid] }), 5_000);
                }
            });
        }
    }
    Ok(())
}

/// THE CALL ENDS (iOS endCall): its lane and its knocks stop, the seed is buried, the row is written (`row: false` -- a second
/// line declined, which iOS writes none of); a missed call of mine is told to them (MC:).
#[tauri::command]
#[allow(clippy::too_many_arguments)]
async fn call_end(app: AppHandle, chat: String, seed: String, video: bool, incoming: bool, seconds: i64, missed: bool, row: Option<bool>,
                  heard: Option<i64>) -> Result<(), ()> {
    CALLS.lock().unwrap().retain(|r| if r.seed == seed { call_stop(r); false } else { true });
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        // A CALL THAT WOVE (iOS MTFabric.callClosed): the far voice received for a minute or more is a live act both ways
        let heard = heard.unwrap_or(0);
        trace_line(&format!("fabric_call heard_s={heard}"));
        if heard >= fabric::CALL_SECONDS && !groups::is_group(&chat) {
            if let Some(s) = m.book.secret(&chat) {
                fabric::spoke(&chat);
                fabric::heard(&chat, &s);
            }
        }
        calls::bury(&m.vault, &seed);
        calls::unhold(&m.vault, Some(&seed));
        if row != Some(false) {
            calls::log_row(&m.book, &chat, video, incoming, seconds, missed);
        }
        if let Some(d) = m.desk(&p) {
            if !incoming && missed {
                d.missed_letter(&chat, &seed, video);
            }
        }
        for door in doors::all() {
            doors::post_at(&door, "/box-del", &serde_json::json!({ "mids": [format!("ring-{}", calls::tag_of(&seed))] }), 5_000);
        }
        changed(&app);
    });
    Ok(())
}

/// Whether a seed's call already ended here (a late word of it never rings again).
#[tauri::command]
async fn call_buried(m: State<'_, Messenger>, seed: String) -> Result<bool, ()> {
    Ok(calls::buried(&m.vault, &seed))
}

/// THE CALL OUTLIVES ITS PROCESS (iOS HeldCall): the window writes the standing call every few seconds; the next run reads it
/// once and judges it; a judged record goes.
#[tauri::command]
async fn call_hold(m: State<'_, Messenger>, record: String) -> Result<bool, ()> {
    Ok(calls::hold(&m.vault, &record))
}
#[tauri::command]
async fn call_held(m: State<'_, Messenger>) -> Result<Option<String>, ()> {
    Ok(calls::held(&m.vault))
}
#[tauri::command]
async fn call_unhold(m: State<'_, Messenger>) -> Result<(), ()> {
    calls::unhold(&m.vault, None);
    Ok(())
}

/// THE ROUTE THIS MACHINE REACHES THE INTERNET BY (iOS NWPathMonitor's wifi/cellular key): the connection profile Windows
/// names for the internet -- Wi-Fi, mobile, and its adapter; empty while no route stands. A call whose route changes asks
/// for fresh checks over the relays alone (iOS requestRouteRelayRecovery). MONTANA_ROUTE_FILE (a check's own) names a file
/// whose words stand for the route instead.
#[tauri::command]
async fn route_key() -> Result<String, ()> {
    tauri::async_runtime::spawn_blocking(route_now).await.map_err(|_| ())
}

/// WHETHER ATTACHMENTS COME DOWN BY THEMSELVES NOW (iOS MEDIA AUTO-DOWNLOAD: «Over mobile network» and «Over Wi-Fi»): the route
/// Windows names decides which switch speaks -- its WWAN is the mobile network, anything else (Wi-Fi, a wire) the other.
fn auto_download(p: &Person) -> bool {
    let s = p.profile.read();
    if route_now().contains('c') { s.auto_download_cellular != Some(false) } else { s.auto_download != Some(false) }
}

/// The route, read off the window's thread (the profile is asked of Windows' networking service).
fn route_now() -> String {
    if let Some(f) = std::env::var_os("MONTANA_ROUTE_FILE") {
        return std::fs::read_to_string(f).unwrap_or_default().trim().chars().take(64).collect();
    }
    #[cfg(windows)]
    {
        use windows::Networking::Connectivity::NetworkInformation;
        use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};
        // SAFETY: this worker thread joins the multithreaded apartment the runtime's objects live in
        let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
        let Ok(p) = NetworkInformation::GetInternetConnectionProfile() else { return String::new() };
        let adapter = p.NetworkAdapter().ok().and_then(|a| a.NetworkAdapterId().ok()).map(|g| format!("{g:?}")).unwrap_or_default();
        let w = if p.IsWlanConnectionProfile().unwrap_or(false) { "w" } else { "" };
        let c = if p.IsWwanConnectionProfile().unwrap_or(false) { "c" } else { "" };
        format!("{w}{c}:{adapter}")
    }
    #[cfg(not(windows))]
    String::new()
}

/// COINS ON A CORRESPONDENT'S LETTER (iOS MTCoinSend.react): false when the balance is short.
#[tauri::command]
async fn chat_coin(app: AppHandle, chat: String, mid: String, coins: i64) -> Result<bool, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let d = m.desk(&p).ok_or(())?;
        let id = crate::wire::hex(&crypto::random(16).ok_or(())?);
        let refr = format!("{}-{}-{}-{}-{}", &id[0..8], &id[8..12], &id[12..16], &id[16..20], &id[20..32]).to_uppercase();
        // the pair's SEND of version 3 needs the seed's coin key (iOS 2304 MTCoinSend.give)
        let h = if coin_chain_on() { p.seed.mnemonic().and_then(|w| wallet::hands(&w)) } else { None };
        let ok = d.give(&chat, &mid, coins, &refr, h.as_ref());
        changed(&app);
        Ok(ok)
    }).await.map_err(|_| ())?
}

/// AUTO-REACTIONS (iOS MTAutoReactPage): every pair's rule, or one set (nought lets the person go).
#[tauri::command]
async fn auto_react(m: State<'_, Messenger>, chat: Option<String>, coins: Option<i64>) -> Result<serde_json::Value, ()> {
    if let (Some(c), Some(n)) = (chat, coins) {
        if !groups::is_group(&c) {
            coins::set_auto_react(&m.vault, &c, n.clamp(0, 999_999_999_999));
        }
    }
    Ok(coins::auto_reacts(&m.vault))
}

/// THE BADGES OF THE FACES (iOS MTAvatarBadgePair): the balance on the left, the Global Level on the right, mine and each pair's.
#[tauri::command]
async fn coin_badges(m: State<'_, Messenger>) -> Result<serde_json::Value, ()> {
    Ok(coinboard::badges(&m.vault))
}

/// «Show my coins» (iOS MTCoinShow, Privacy): read, or set.
#[tauri::command]
async fn coins_shown(m: State<'_, Messenger>, on: Option<bool>) -> Result<bool, ()> {
    if let Some(on) = on {
        m.vault.set(coinboard::SHOW, if on { b"1" } else { b"0" });
    }
    Ok(coinboard::shown(&m.vault))
}

/// ACCESS BY LEVEL (iOS MTLevelAccessPage): the Global Level, the fabric beside it, and each function a level opens with the
/// person's choice for it.
#[tauri::command]
async fn levels_state(m: State<'_, Messenger>) -> Result<serde_json::Value, ()> {
    let balance = coins::balance(&m.vault);
    let level = person::global(balance);
    Ok(serde_json::json!({ "level": level, "fabric": fabric::shown(),
                           "keep": { "at": person::KEEP_LEVEL, "open": level >= person::KEEP_LEVEL, "on": person::choice(&m.vault, person::KEEP_CHOICE) },
                           "record": { "at": person::RECORD_LEVEL, "open": level >= person::RECORD_LEVEL, "on": person::choice(&m.vault, person::RECORD_CHOICE),
                                       "consent": m.vault.get("callRecordConsent").is_some() },
                           "node": { "at": person::NODE_LEVEL, "open": level >= person::NODE_LEVEL } }))
}

/// The person's choice for a function a level opens; `consent` -- the first agreement to calls recording themselves.
#[tauri::command]
async fn levels_set(m: State<'_, Messenger>, what: String, on: bool) -> Result<(), ()> {
    let key = match what.as_str() {
        "keep" => person::KEEP_CHOICE,
        "record" => person::RECORD_CHOICE,
        "consent" => "callRecordConsent",
        _ => return Err(()),
    };
    if m.vault.set(key, if on { b"1" } else { b"0" }) { Ok(()) } else { Err(()) }
}

/// THE TIMECHAINS ON THE WALLET (iOS MTTimeChainRows): every chain of this person's coins with its length, its head and whether
/// it is whole from its genesis; with `source`, that chain's links, newest first (iOS MTTimeChainPage).
#[tauri::command]
async fn timechains(m: State<'_, Messenger>, source: Option<String>) -> Result<serde_json::Value, ()> {
    let dir = m.dir.clone();
    let vault = m.vault.clone();
    tauri::async_runtime::spawn_blocking(move || match source.filter(|s| coins::SOURCES.contains(&s.as_str()) || s == "person" || s == "fabric") {
        Some(s) => serde_json::json!({ "head": coins::head(&dir, &s), "links": coins::links(&dir, &s, usize::MAX) }),
        None => {
            // THE TIMECHAIN PAGE (iOS MTTimeChainsPage): the Global Level, the person's chain, the wallet's level of π, the fabric
            // of time, every chain
            // the levels stand on what the person's chain holds for them (iOS split.available), never on the book alone
            let balance = wallet::available(&vault);
            fabric::refresh(person::level(person::seconds()), balance);
            // the node of the protocol core joins as the page opens (iOS MTNetworkNode.join), and the core says its wallet
            protocol::join(&dir);
            let core = match protocol::read() { Ok(s) => serde_json::json!({ "ok": s }), Err(why) => serde_json::json!({ "absent": why }) };
            serde_json::json!({ "heads": coins::heads(&dir), "global": person::global(balance), "person": person::shown(),
                                "pi": coins::pi_place(balance), "balance": balance, "fabric": fabric::shown(),
                                "vectors": person::level_kat() && fabric::self_check(),
                                "node": { "reached": protocol::reached(), "of": protocol::genesis_count() }, "core": core,
                                "top": coinboard::top() })
        }
    }).await.map_err(|_| ())
}

/// THE CHAINS' OWN FILES SHARED (iOS MTTimeChainsPage «Share the chains»): every wallet-*.jsonl of this person's TimeChain folder,
/// handed together to Windows' own «Поделиться»; false when there is none or the sheet would not open.
#[tauri::command]
async fn share_chains(app: AppHandle, window: tauri::WebviewWindow) -> Result<bool, ()> {
    let hwnd = window.hwnd().map_err(|_| ())?.0 as isize;
    let dir = app.state::<Messenger>().dir.join("TimeChain");
    let mut files: Vec<std::path::PathBuf> = std::fs::read_dir(&dir).map(|d| d.flatten().map(|e| e.path())
        .filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("wallet-") && n.ends_with(".jsonl"))).collect()).unwrap_or_default();
    files.sort();
    if files.is_empty() {
        return Ok(false);
    }
    let (tx, rx) = std::sync::mpsc::channel();
    app.run_on_main_thread(move || {
        let _ = tx.send(music::share_files(hwnd, "TimeChain", files));
    }).map_err(|_| ())?;
    let shown = tauri::async_runtime::spawn_blocking(move || rx.recv_timeout(std::time::Duration::from_secs(10)).unwrap_or(false)).await.unwrap_or(false);
    trace_line(&format!("share chains shown={shown}"));
    Ok(shown)
}

/// THE SYSTEM'S OWN CURRENCY (iOS Locale.current.currency): the ISO code Windows keeps for the person's region; none when it says none.
#[tauri::command]
fn system_currency() -> Option<String> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::Globalization::{GetLocaleInfoEx, LOCALE_SINTLSYMBOL};
        let mut buf = [0u16; 16];
        // SAFETY: the user's default locale (a null name), a buffer of its own length
        let n = unsafe { GetLocaleInfoEx(std::ptr::null(), LOCALE_SINTLSYMBOL, buf.as_mut_ptr(), buf.len() as i32) };
        let code = String::from_utf16_lossy(&buf[..(n.max(1) - 1) as usize]);
        if code.len() == 3 && code.chars().all(|c| c.is_ascii_uppercase()) {
            return Some(code);
        }
    }
    None
}

/// This person's coin key (iOS MTCoinTx.cachedKeyTag): the name of its whole chain in the Explorer; none before it was derived.
#[tauri::command]
fn coin_key() -> Option<String> {
    wallet::MY_FROM.lock().unwrap().clone()
}

/// The names of this person's chain files (the TimeChain page shows «Share the chains» only while there is one).
#[tauri::command]
async fn chain_files(m: State<'_, Messenger>) -> Result<usize, ()> {
    Ok(std::fs::read_dir(m.dir.join("TimeChain")).map(|d| d.flatten()
        .filter(|e| e.file_name().to_str().is_some_and(|n| n.starts_with("wallet-") && n.ends_with(".jsonl"))).count()).unwrap_or(0))
}

/// What the protocol core says of the wallet (iOS MTWalletCore.read): its snapshot, or why it says nothing.
#[tauri::command]
async fn protocol_core() -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(|| match protocol::read() {
        Ok(s) => serde_json::json!({ "ok": s }),
        Err(why) => serde_json::json!({ "absent": why }),
    }).await.map_err(|_| ())
}

/// THE APP'S ICON (iOS setAlternateIconName): the picture the window drew (its side, its side, its pixels) worn by the window, the
/// taskbar and the tray.
#[tauri::command]
fn app_icon(app: AppHandle, window: tauri::WebviewWindow, request: tauri::ipc::Request) -> Result<bool, ()> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err(()) };
    let name = request.headers().get("name").and_then(|v| v.to_str().ok()).unwrap_or("").chars().take(16).collect::<String>();
    if body.len() < 8 {
        return Err(());
    }
    let (w, h) = (u32::from_le_bytes(body[0..4].try_into().unwrap()), u32::from_le_bytes(body[4..8].try_into().unwrap()));
    if w == 0 || h == 0 || w > 512 || h > 512 || body.len() != 8 + (w * h * 4) as usize {
        return Err(());
    }
    let image = tauri::image::Image::new_owned(body[8..].to_vec(), w, h);
    // tao's set_icon gives the window its small icon, the title bar's; the taskbar and Alt+Tab wear the big one
    let worn = window.set_icon(image.clone()).is_ok() && window.hwnd().is_ok_and(|hwnd| big_icon(hwnd.0 as isize, &body[8..], w, h));
    if let Some(tray) = app.tray_by_id("montana") {
        let _ = tray.set_icon(Some(image));
    }
    trace_line(&format!("app_icon set {name} {}", if worn { "ok" } else { "refused" }));
    Ok(worn)
}

/// The window's big icon, the one the taskbar and Alt+Tab show (WM_SETICON, ICON_BIG), made of the same picture; the one it
/// replaces is let go when it was ours.
fn big_icon(hwnd: isize, rgba: &[u8], w: u32, h: u32) -> bool {
    use std::sync::atomic::{AtomicIsize, Ordering};
    use windows_sys::Win32::UI::WindowsAndMessaging::{CreateIcon, DestroyIcon, SendMessageW, ICON_BIG, WM_SETICON};
    static OURS: AtomicIsize = AtomicIsize::new(0);
    let mut bgra = rgba.to_vec();
    let mut and_mask = Vec::with_capacity(bgra.len() / 4);
    for p in bgra.chunks_exact_mut(4) {
        p.swap(0, 2);
        and_mask.push(p[3].wrapping_sub(u8::MAX));
    }
    let icon = unsafe { CreateIcon(std::ptr::null_mut(), w as i32, h as i32, 1, 32, and_mask.as_ptr(), bgra.as_ptr()) };
    if icon.is_null() {
        return false;
    }
    let old = unsafe { SendMessageW(hwnd as _, WM_SETICON, ICON_BIG as usize, icon as isize) };
    let was = OURS.swap(icon as isize, Ordering::SeqCst);
    if was != 0 && was == old {
        unsafe { DestroyIcon(was as _) };
    }
    true
}

/// THE MUSIC'S LENT FOLDERS (iOS MTMusicFolders): their names and the tracks a walk finds in them now.
#[tauri::command]
async fn music_state(m: State<'_, Messenger>) -> Result<serde_json::Value, ()> {
    let v = m.vault.clone();
    let (names, tracks) = tauri::async_runtime::spawn_blocking(move || (music::names(&v), music::walk(&v))).await.map_err(|_| ())?;
    Ok(serde_json::json!({ "folders": names, "tracks": tracks }))
}

/// A folder lent to the music page: Windows' own folder picker over this window; false when the person closed it.
#[tauri::command]
async fn music_folder_add(window: tauri::WebviewWindow, m: State<'_, Messenger>) -> Result<bool, ()> {
    let hwnd = window.hwnd().map_err(|_| ())?.0 as isize;
    let picked = tauri::async_runtime::spawn_blocking(move || music::pick_folder(hwnd)).await.ok().flatten();
    Ok(picked.is_some_and(|p| music::add(&m.vault, &p)))
}

/// WHAT A TRACK CARRIES ITSELF (iOS MTTrackMeta.load): its name, artist and length, read once per file off the window's thread; the
/// cover as an address the page draws (a data: address of the picture as the file holds it).
#[tauri::command]
async fn track_meta(m: State<'_, Messenger>, file: String, mid: Option<String>, lent: Option<bool>, id: Option<String>, index: Option<usize>,
                    ext: Option<String>) -> Result<serde_json::Value, ()> {
    let vault_media = m.media.clone();
    let meta = tauri::async_runtime::spawn_blocking(move || {
        trackmeta::kept_or(&file, || {
            if lent == Some(true) {
                return music::path_of(&file).map(|p| trackmeta::from_path(&p)).unwrap_or_default();
            }
            let name = match (id, index) {
                (Some(id), Some(i)) => board::file_name(&id, i, ext.as_deref().unwrap_or("")),
                _ => mid.unwrap_or_default(),
            };
            vault_media.get(&name).map(|b| trackmeta::from_bytes(&b)).unwrap_or_default()
        })
    }).await.map_err(|_| ())?;
    let cover = meta.cover.as_ref().map(|(b, mime)| format!("data:{mime};base64,{}", wire::b64(b)));
    Ok(serde_json::json!({ "title": meta.title, "artist": meta.artist, "length": meta.length, "cover": cover }))
}

/// A lent track's bytes, for the page's player.
#[tauri::command]
async fn music_track(id: String) -> Result<tauri::ipc::Response, ()> {
    tauri::async_runtime::spawn_blocking(move || music::bytes(&id)).await.ok().flatten().map(tauri::ipc::Response::new).ok_or(())
}

/// THE SHARE SHEET OF WINDOWS (iOS UIActivityViewController): words and a link handed to the system's «Поделиться», on the window's
/// own thread; false when the sheet would not open (the window then copies them, as before).
#[tauri::command]
async fn share_text(app: AppHandle, window: tauri::WebviewWindow, title: String, text: String, link: Option<String>) -> Result<bool, ()> {
    let hwnd = window.hwnd().map_err(|_| ())?.0 as isize;
    let (tx, rx) = std::sync::mpsc::channel();
    app.run_on_main_thread(move || {
        let _ = tx.send(music::share(hwnd, &title, &text, link.as_deref()));
    }).map_err(|_| ())?;
    let shown = tauri::async_runtime::spawn_blocking(move || rx.recv_timeout(std::time::Duration::from_secs(10)).unwrap_or(false)).await.unwrap_or(false);
    trace_line(&format!("share sheet shown={shown}"));
    Ok(shown)
}

/// THE TRACK HANDED ON (iOS MontanaPlayerBar.share, the big player's share): a letter's track, a lent folder's or a post's, under the
/// name the page shows, to Windows' own «Поделиться»; false when there is nothing here to hand yet or the sheet would not open.
#[tauri::command]
#[allow(clippy::too_many_arguments)]
async fn share_file(app: AppHandle, window: tauri::WebviewWindow, mid: Option<String>, lent: Option<String>, id: Option<String>, index: Option<usize>,
                    title: String, ext: String) -> Result<bool, ()> {
    let hwnd = window.hwnd().map_err(|_| ())?.0 as isize;
    let a = app.clone();
    let file = tauri::async_runtime::spawn_blocking(move || {
        let m = a.state::<Messenger>();
        let bytes = if let Some(l) = lent {
            music::bytes(&l)
        } else if let (Some(id), Some(i)) = (id, index) {
            m.media.get(&board::file_name(&id, i, &ext))
        } else {
            mid.and_then(|x| m.media.get(&x))
        }?;
        music::shared_file(&bytes, &title, &ext).map(|f| (f, title))
    }).await.map_err(|_| ())?;
    let Some((file, title)) = file else {
        trace_line("share file none -- nothing here to hand yet");
        return Ok(false);
    };
    let (tx, rx) = std::sync::mpsc::channel();
    app.run_on_main_thread(move || {
        let _ = tx.send(music::share_file(hwnd, &title, file));
    }).map_err(|_| ())?;
    let shown = tauri::async_runtime::spawn_blocking(move || rx.recv_timeout(std::time::Duration::from_secs(10)).unwrap_or(false)).await.unwrap_or(false);
    trace_line(&format!("share file shown={shown}"));
    Ok(shown)
}

/// THE P2P WALL (iOS NetworkTabView's P2P tab): the nodes this computer reaches -- every machine of the network with its doors,
/// each asked now and timed.
#[tauri::command]
async fn p2p_wall() -> Result<Vec<doors::MachineSeen>, ()> {
    tauri::async_runtime::spawn_blocking(doors::wall).await.map_err(|_| ())
}

/// THE VPN WALL (iOS NetworkTabView, MontanaVPNStore): the person's plans and servers, each with what the page draws.
#[tauri::command]
async fn vpn_state(m: State<'_, Messenger>) -> Result<serde_json::Value, ()> {
    let s = vpn::load(&m.vault);
    let rows: Vec<serde_json::Value> = s.servers.iter().map(|c| serde_json::json!({
        "id": c.id(), "name": c.name, "proto": c.proto.word(), "host": c.host, "port": c.port, "network": c.network, "security": c.security,
        "plan": c.subscription, "reason": c.reason, "scheme": c.scheme,
    })).collect();
    Ok(serde_json::json!({ "servers": rows, "plans": s.plans, "engine": false }))
}

/// A server's link, a list of them, or a plan's link (iOS addFromLink / the subscription's alert): the plan is fetched from its own
/// panel. "links:N" | "plan:N"; the failure's word.
#[tauri::command]
async fn vpn_add(app: AppHandle, text: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        if let Some(url) = vpn::subscription_url(&text) {
            return vpn::take_plan(&m.vault, &url).map(|n| format!("plan:{n}"));
        }
        // EVERY ROAD IN IS ONE ROAD (iOS MontanaVPNIntake): a pasted text is read by its shape -- links, a plan's body, a profile
        let fresh = vpn::body(text.as_bytes(), "").servers;
        if fresh.is_empty() {
            return Err("none".into());
        }
        let mut s = vpn::load(&m.vault);
        let n = vpn::add(&mut s, fresh);
        vpn::save(&m.vault, &s);
        Ok(format!("links:{n}"))
    }).await.map_err(|_| "stopped".to_string())?
}

/// A row's or a plan's own deed (iOS the server's menu and the plan's): rename, remove, fold, take the plan again; the link or the
/// engine's JSON copied.
#[tauri::command]
async fn vpn_do(app: AppHandle, what: String, id: String, name: Option<String>) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        let mut s = vpn::load(&m.vault);
        let row = s.servers.iter().position(|c| c.id() == id);
        let out = match (what.as_str(), row) {
            ("rename", Some(i)) => { s.servers[i].name = name.unwrap_or_default().trim().chars().take(64).collect(); "ok".into() }
            ("remove", Some(i)) => { s.servers.remove(i); "ok".into() }
            ("link", Some(i)) => { if clipboard::copy_text(&vpn::serialize(&s.servers[i])) { "copied".into() } else { return Err("clipboard".into()) } }
            ("json", Some(i)) => match vpn::share_json(&s.servers[i]) {
                Some(j) if clipboard::copy_text(&j) => "copied".into(),
                _ => return Err("json".into()),
            },
            ("plan-remove", _) => { s.plans.retain(|p| p.url != id); s.servers.retain(|c| c.subscription.as_deref() != Some(id.as_str())); "ok".into() }
            ("plan-fold", _) => { if let Some(p) = s.plans.iter_mut().find(|p| p.url == id) { p.folded = Some(p.folded != Some(true)); } "ok".into() }
            ("plan-reload", _) => return vpn::take_plan(&m.vault, &id).map(|n| format!("plan:{n}")),
            _ => return Err("unknown".into()),
        };
        vpn::save(&m.vault, &s);
        Ok(out)
    }).await.map_err(|_| "stopped".to_string())?
}

/// THE PERSONS OF THIS COMPUTER (iOS MTSeats): who waits on the shelf, for the drawer's faces and the first screen's cross.
#[tauri::command]
async fn seats_state(p: State<'_, Person>) -> Result<seats::Shown, ()> {
    let h = seats::here().ok_or(())?;
    Ok(seats::shown(h, p.seed.has_seed()))
}

/// A CALL HOLDS THE SEAT (iOS refusedForCall, 11.10.2026 No.61): a move starts the program again, and a call or a room standing
/// would lose its road mid-word. The move is refused, and written.
fn seat_busy(road: &str) -> bool {
    let busy = !CALLS.lock().unwrap().is_empty() || rooms::standing();
    if busy {
        trace_line(&format!("seat_move REFUSED a call stands road={road}"));
    }
    busy
}

/// What the person leaving leaves on disk before the program starts again: the coins' windows closed into the book, the book
/// written, the name and the face the drawer of the others shows.
fn leave_seat(app: &AppHandle) {
    let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
    WALLET_OPEN.store(false, std::sync::atomic::Ordering::SeqCst);
    coins::close_windows(&m.vault, true);
    coins::flush(&m.vault, &m.dir, &|r| groups::is_group(r));
    if let Some(h) = seats::here() {
        seats::note_face(h, &p.profile.read().user_name);
    }
}

/// The drawer's face of a person on the shelf (iOS switchTo): that person is seated, the program starts again in their folder.
#[tauri::command]
async fn seat_switch(app: AppHandle, id: String) -> Result<(), String> {
    let h = seats::here().ok_or("seat")?;
    if seat_busy("switch") {
        return Err("call".into());
    }
    leave_seat(&app);
    seats::switch_to(h, &id).map_err(|e| format!("{e:?}"))?;
    trace_line("seat_move switch");
    app.restart();
}

/// THE PLUS AT THE DRAWER'S HEAD (iOS makeRoom): the person seated goes to the shelf, never wiped, and the first screen opens on
/// the Montana road for a new person, my page's ground carried into it (a photo ground with its file).
#[tauri::command]
async fn seat_add(app: AppHandle, carry: Option<String>) -> Result<(), String> {
    let h = seats::here().ok_or("seat")?;
    if seat_busy("make-room") {
        return Err("call".into());
    }
    leave_seat(&app);
    let carry = carry.filter(|c| c.len() <= 80);
    let id = seats::make_room(h, carry.clone()).map_err(|e| format!("{e:?}"))?;
    if let Some(name) = carry.as_deref().and_then(|c| c.strip_prefix("photo:")).filter(|n| n.starts_with("gnd_")) {
        if let Some(bytes) = app.state::<Messenger>().media.get(name) {
            if let Ok(s) = media::Store::at(&seats::folder(&h.base, &seats::book(&h.base), &id).join("media")) {
                s.put(name, &bytes);
            }
        }
    }
    trace_line("seat_move make-room");
    app.restart();
}

/// The first screen's cross (iOS returnToLast): the empty seat goes, the person who waited last is seated again.
#[tauri::command]
async fn seat_return(app: AppHandle) -> Result<(), String> {
    let h = seats::here().ok_or("seat")?;
    seats::return_to_last(h).map_err(|e| format!("{e:?}"))?;
    trace_line("seat_move return");
    app.restart();
}

/// THE TRACE OF A CHECK (iOS MontanaTrace, its diary): a line of the window's machinery into <data>/trace.log -- only with
/// MONTANA_TRACE=1 and a data folder of its own (MONTANA_DATA_DIR), never in a person's run; no words of a letter ride it.
#[tauri::command]
fn trace(line: String) {
    trace_line(&line);
}
pub(crate) fn trace_line(line: &str) {
    if std::env::var_os("MONTANA_TRACE").is_none() || std::env::var_os("MONTANA_DATA_DIR").is_none() {
        return;
    }
    let Some(dir) = seats::here().map(|h| h.folder.clone()) else { return };
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(std::path::Path::new(&dir).join("trace.log")) {
        let _ = writeln!(f, "{} {}", wire::now_ms(), line.chars().take(300).collect::<String>());
    }
}

#[tauri::command]
async fn turn_cred() -> Result<Option<serde_json::Value>, ()> {
    Ok(tauri::async_runtime::spawn_blocking(calls::turn_cred).await.ok().flatten())
}

#[tauri::command]
async fn calls_log(app: AppHandle) -> Result<Vec<serde_json::Value>, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        Ok(m.calls_log())
    }).await.map_err(|_| ())?
}

/// The missed calls not yet seen, for the badge on the calls' icon and the logo (iOS missedCallsUnseen).
#[tauri::command]
async fn calls_missed(app: AppHandle) -> Result<usize, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        Ok(m.calls_missed())
    }).await.map_err(|_| ())?
}

/// The calls page is looked at: its badge clears (iOS clearMissedCallsBadge).
#[tauri::command]
async fn calls_seen(app: AppHandle) -> Result<(), ()> {
    tauri::async_runtime::spawn_blocking(move || {
        app.state::<Messenger>().calls_seen();
        Ok(())
    }).await.map_err(|_| ())?
}

/// A NEW GROUP OR CHANNEL (iOS «New Group», «New Channel»): the title, the words about it, the chosen correspondences and
/// the kind («c» a channel); its chat.
#[tauri::command]
async fn group_create(app: AppHandle, title: String, pipes: Vec<String>, kind: Option<String>, about: Option<String>) -> Result<String, ()> {
    let a = app.clone();
    let r = tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
        m.desk(&p).and_then(|d| d.group_make(kind.as_deref().unwrap_or("g"), &title, about.as_deref().unwrap_or(""), &pipes))
    }).await.map_err(|_| ())?;
    changed(&app);
    r.ok_or(())
}

/// The group's own page: its members by name, who owns it, whether I am out.
#[tauri::command]
async fn group_info(p: State<'_, Person>, m: State<'_, Messenger>, chat: String) -> Result<Option<serde_json::Value>, ()> {
    let Some(id) = chat.strip_prefix("grp:") else { return Ok(None) };
    let Some(g) = groups::held_of(&m.vault).remove(id) else { return Ok(None) };
    let ru = p.lang.starts_with("ru");
    let mut people = vec![serde_json::json!({ "seat": "0", "name": if g.owner.is_empty() { p.profile.read().user_name } else { g.names.get("0").cloned().unwrap_or_default() },
                                              "owner": true, "me": g.me == "0" })];
    let seats: Vec<(String, String)> = if g.owner.is_empty() {
        g.members.iter().map(|x| (x.seat.clone(), m.book.chat(&x.pipe).map(|c| if c.alias.trim().is_empty() { c.name } else { c.alias }).filter(|n| !n.is_empty()).or_else(|| g.names.get(&x.seat).cloned()).unwrap_or_default())).collect()
    } else {
        g.names.iter().filter(|(s, _)| *s != "0").map(|(s, n)| (s.clone(), n.clone())).collect()
    };
    for (seat, name) in seats {
        let name = if seat == g.me { p.profile.read().user_name } else if name.is_empty() { (if ru { "Участник" } else { "Member" }).into() } else { name };
        people.push(serde_json::json!({ "seat": seat, "name": name, "admin": g.admins.contains(&seat), "me": seat == g.me,
                                        "rank": g.ranks.get(&seat).cloned().unwrap_or_default(),
                                        "taken": g.admin_taken.get(&seat).cloned().unwrap_or_default() }));
    }
    if !g.owner.is_empty() && g.me != "0" && !people.iter().any(|x| x["me"] == true) {
        people.push(serde_json::json!({ "seat": g.me, "name": p.profile.read().user_name, "me": true, "admin": g.admins.contains(&g.me),
                                        "rank": g.ranks.get(&g.me).cloned().unwrap_or_default() }));
    }
    let face = if m.faces.has(&chat) { m.book.chat(&chat).map_or(1, |c| c.face_at.max(1)) } else { 0 };
    Ok(Some(serde_json::json!({ "title": g.title, "count": g.count, "owner": g.owner.is_empty(), "left": g.left, "removed": g.removed, "people": people,
                                "face": face, "kind": g.kind, "about": g.about, "signs": g.signs, "reacts": !g.reacts_off, "talks": g.talks,
                                "react_list": g.react_list, "barred": g.barred, "approval": g.approval, "history": g.history,
                                "requests": if g.owner.is_empty() { serde_json::json!(g.requests) } else { serde_json::json!([]) }, "slow": g.slow, "admin": g.admins.contains(&g.me),
                                "rights": groups::ADMIN_RIGHTS.iter().filter(|r| groups::admin_can(&g, &g.me, r)).collect::<Vec<_>>() })))
}

#[tauri::command]
async fn group_add(app: AppHandle, chat: String, pipes: Vec<String>) -> Result<(), ()> {
    deed(app, move |d| { if let Some(id) = chat.strip_prefix("grp:") { d.group_add(id, &pipes) } });
    Ok(())
}

#[tauri::command]
async fn group_remove(app: AppHandle, chat: String, seat: String) -> Result<(), ()> {
    deed(app, move |d| { if let Some(id) = chat.strip_prefix("grp:") { d.group_remove(id, &seat) } });
    Ok(())
}

#[tauri::command]
async fn group_leave(app: AppHandle, chat: String) -> Result<(), ()> {
    deed(app, move |d| {
        if let Some(id) = chat.strip_prefix("grp:") {
            rooms::group_gone(d, id); // a person outside a group is in none of its rooms
            d.group_leave(id)
        }
    });
    Ok(())
}

/// A GROUP'S ROOMS FOR THE WINDOW (iOS MTRoomBook and the room in hand): every living room by its chat, and mine.
#[tauri::command]
async fn room_state(app: AppHandle) -> Result<serde_json::Value, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        m.desk(&p).map(|d| rooms::state_now(&d))
    }).await.ok().flatten().ok_or(())
}

/// A ROOM OPENED IN A GROUP (iOS MTGroupRoom.open): the kind, the camera, the seats invited; a living room is joined instead.
#[tauri::command]
async fn room_open(app: AppHandle, chat: String, kind: String, video: bool, seats: Vec<String>) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let d = m.desk(&p).ok_or("The call could not start")?;
        let r = rooms::open(&d, &chat, &kind, video, &seats);
        changed(&app);
        r.map_err(|e| e.to_string())
    }).await.map_err(|_| "The call could not start".to_string())?
}

/// THIS MACHINE COMES INTO THE GROUP'S ROOM (iOS join: the bar over the chat, an invitation).
#[tauri::command]
async fn room_join(app: AppHandle, chat: String, video: bool) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let d = m.desk(&p).ok_or("The call has ended")?;
        rooms::join(&d, &chat, video).map_err(|e| e.to_string())
    }).await.map_err(|_| "The call has ended".to_string())?
}

/// The ways out of a room and its control (iOS leave, endForEveryone, invite, ownerDrop), and what the window's pairs learned
/// (a pair stood or fell; a seat no pair stood with for three minutes, or whose pair said bye, vanished).
#[tauri::command]
async fn room_do(app: AppHandle, act: String, seat: Option<String>, seats: Option<Vec<String>>, on: Option<bool>, chat: Option<String>) -> Result<(), ()> {
    deed(app, move |d| match act.as_str() {
        "leave" => rooms::leave(d),
        "end" => rooms::end_for_everyone(d),
        "invite" => rooms::invite(d, &seats.unwrap_or_default()),
        "drop" => rooms::owner_drop(d, seat.as_deref().unwrap_or("")),
        "vanish" => rooms::vanish(d, seat.as_deref().unwrap_or(""), true),
        "bye" => rooms::vanish(d, seat.as_deref().unwrap_or(""), false),
        "linked" => rooms::linked(d, seat.as_deref().unwrap_or(""), on.unwrap_or(false)),
        "wait" => rooms::join_when_known(d, chat.as_deref().unwrap_or(""), seat.as_deref().unwrap_or("")),
        _ => {}
    });
    Ok(())
}

/// A CALL OF TWO GROWS INTO A ROOM (iOS MTGroupRoom.grow): a group of the peer and the people chosen, the room minted; the
/// word the call's road carries to the peer comes back.
#[tauri::command]
async fn room_grow(app: AppHandle, peer: String, chats: Vec<String>, video: bool) -> Result<String, String> {
    let r = tauri::async_runtime::spawn_blocking({
        let app = app.clone();
        move || {
            let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
            m.desk(&p).and_then(|d| rooms::grow_prepare(&d, &peer, &chats, video))
        }
    }).await.ok().flatten();
    changed(&app);
    r.ok_or_else(|| "The call could not start".to_string())
}

/// The peer answered the move (its room key and moment), or said nothing: the room of the grown call opens.
#[tauri::command]
async fn room_grown(app: AppHandle, reply: Option<String>) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let d = m.desk(&p).ok_or("The call could not start")?;
        let r = rooms::grow_open(&d, reply.as_deref());
        changed(&app);
        r.map_err(|e| e.to_string())
    }).await.map_err(|_| "The call could not start".to_string())?
}

/// The peer grew our call into a room (iOS takeInline): the group and the room stand here; my room key and moment go back.
#[tauri::command]
async fn room_take_inline(app: AppHandle, chat: String, head: String, payload: String) -> Result<Option<String>, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        let r = m.desk(&p).and_then(|d| rooms::take_inline(&d, &chat, &head, &payload));
        changed(&app);
        r
    }).await.map_err(|_| ())
}

/// Whom a call of two may grow with (iOS MTCallAddSheet): the people this machine writes with by a pipe, the peer left out.
#[tauri::command]
async fn room_grow_people(m: State<'_, Messenger>, chat: String) -> Result<Vec<(String, String)>, ()> {
    let mut out: Vec<(String, String)> = m.book.all().into_iter()
        .filter(|c| c.reference != chat && !groups::is_group(&c.reference) && !c.blocked && !c.hidden && m.book.secret(&c.reference).is_some())
        .map(|c| { let n = if c.alias.trim().is_empty() { c.name.clone() } else { c.alias.clone() }; (c.reference, n) })
        .filter(|(_, n)| !n.trim().is_empty()).collect();
    out.sort_by_key(|(_, n)| n.to_lowercase());
    Ok(out)
}

/// A PAIR WORD TO A SEAT OF THE ROOM (iOS MTGroupRoom.send): false while the seat's room key has not come.
#[tauri::command]
async fn room_send(app: AppHandle, seat: String, c: String, g: i64, sdp: Option<String>, ice: Option<Vec<rooms::Ice>>) -> Result<bool, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        m.desk(&p).is_some_and(|d| rooms::send(&d.twin, &seat, &c, g, sdp, ice))
    }).await.map_err(|_| ())
}

/// The people of a group this machine may invite into its room (iOS invitable): every seat it knows by name, but its own and
/// those already in.
#[tauri::command]
async fn room_invitable(p: State<'_, Person>, m: State<'_, Messenger>, chat: String) -> Result<Vec<(String, String)>, ()> {
    let Some(id) = chat.strip_prefix("grp:") else { return Ok(vec![]) };
    let Some(d) = m.desk(&p) else { return Ok(vec![]) };
    let Some(g) = d.group(id) else { return Ok(vec![]) };
    let inside: Vec<String> = rooms::state_now(&d)["live"]["people"].as_array().into_iter().flatten()
        .filter_map(|x| x["seat"].as_str().map(str::to_string)).collect();
    let mut seats: Vec<String> = if g.owner.is_empty() { g.members.iter().map(|m| m.seat.clone()).collect() } else {
        std::iter::once("0".to_string()).chain(g.names.keys().cloned()).collect()
    };
    seats.sort();
    seats.dedup();
    let ru = p.lang.starts_with("ru");
    let mut out: Vec<(String, String)> = seats.into_iter().filter(|s| *s != g.me && !inside.contains(s)).map(|s| {
        let n = d.seat_name(&g, &s);
        let n = if n.is_empty() { (if ru { "Участник" } else { "Member" }).to_string() } else { n };
        (s, n)
    }).collect();
    out.sort_by_key(|(_, n)| n.to_lowercase());
    Ok(out)
}

/// THE GROUP'S PHOTO (iOS MTGroupPage, the owner's photo): a JPEG of 160 pixels the window made, raw, the group's chat in the
/// «chat» header; kept, and carried to every member with the invitation.
#[tauri::command]
fn group_face(app: AppHandle, request: tauri::ipc::Request) -> Result<(), ()> {
    let tauri::ipc::InvokeBody::Raw(body) = request.body() else { return Err(()) };
    let chat = request.headers().get("chat").and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
    let Some(id) = chat.strip_prefix("grp:").map(str::to_string) else { return Err(()) };
    if body.len() > groups::FACE_LIMIT / 4 * 3 || !body.starts_with(&[0xFF, 0xD8]) {
        return Err(());
    }
    let body = body.clone();
    deed(app, move |d| { d.group_face(&id, &body); });
    Ok(())
}

/// The group's link (iOS «Invite Link»): the owner's card with the group's mark; `reset` -- a new mark first.
#[tauri::command]
async fn group_link(app: AppHandle, chat: String, reset: bool) -> Result<Option<String>, ()> {
    let a = app.clone();
    Ok(tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
        let id = chat.strip_prefix("grp:")?.to_string();
        let d = m.desk(&p)?;
        if reset {
            d.group_link_reset(&id);
        }
        d.group_link(&id)
    }).await.ok().flatten())
}

/// THE FOLDERS OVER THE CHATS (iOS MTChatFolders, «chatFolders»): the person's own setting, kept in the vault as iOS keeps it --
/// the folders in the tabs' order, each its kinds and chats taken and its states and chats left out. Empty -- the first folders.
#[tauri::command]
async fn folders_get(m: State<'_, Messenger>) -> Result<String, ()> {
    Ok(m.vault.get(FOLDERS).and_then(|b| String::from_utf8(b).ok()).unwrap_or_default())
}

#[tauri::command]
async fn folders_set(m: State<'_, Messenger>, folders: String) -> Result<bool, ()> {
    let ok = folders.len() <= 64 * 1024 && serde_json::from_str::<Vec<serde_json::Value>>(&folders).is_ok_and(|f| f.len() <= 50);
    Ok(ok && m.vault.set(FOLDERS, folders.as_bytes()))
}

/// A pair's chess letters, each with its side and its ladder (iOS MTChessRecord.entries): the window replays the games.
#[tauri::command]
async fn chess_letters(m: State<'_, Messenger>, chat: String) -> Result<Vec<serde_json::Value>, ()> {
    Ok(m.book.chat(&chat).map(|c| c.msgs.iter().filter(|x| !x.edited && x.qt.is_empty() && chess::letter(&x.text).is_some())
        .map(|x| serde_json::json!({ "text": x.text, "mine": x.mine, "at": x.at, "state": x.state, "statusAt": x.status_at }))
        .collect()).unwrap_or_default())
}

/// The owner shows or hides the group's past to new members (iOS setHistory).
#[tauri::command]
async fn group_set_history(app: AppHandle, chat: String, visible: bool) -> Result<(), ()> {
    deed(app, move |d| { if let Some(id) = chat.strip_prefix("grp:") { d.group_set_history(id, visible) } });
    Ok(())
}

/// The owner's link asks it first, or lets people in (iOS setApproval).
#[tauri::command]
async fn group_set_approval(app: AppHandle, chat: String, on: bool) -> Result<(), ()> {
    deed(app, move |d| { if let Some(id) = chat.strip_prefix("grp:") { d.group_set_approval(id, on) } });
    Ok(())
}

/// The owner adds one who asked by the link (iOS approve), or dismisses them (iOS dismiss).
#[tauri::command]
async fn group_request(app: AppHandle, chat: String, pipe: String, add: bool) -> Result<(), ()> {
    deed(app, move |d| {
        if let Some(id) = chat.strip_prefix("grp:") {
            if add {
                d.group_approve(id, &pipe);
            } else {
                d.group_dismiss(id, &pipe);
            }
        }
    });
    Ok(())
}

/// The owner names or dismisses an administrator (iOS setAdmin): the rights left out and a title of its own.
#[tauri::command]
async fn group_set_admin(app: AppHandle, chat: String, seat: String, on: bool, taken: Vec<String>, rank: String) -> Result<(), ()> {
    deed(app, move |d| { if let Some(id) = chat.strip_prefix("grp:") { d.group_set_admin(id, &seat, on, &taken, &rank) } });
    Ok(())
}

/// What the members may not do and the slow mode (iOS setRights), by the owner.
#[tauri::command]
async fn group_set_rights(app: AppHandle, chat: String, barred: Vec<String>, slow: u32) -> Result<(), ()> {
    deed(app, move |d| { if let Some(id) = chat.strip_prefix("grp:") { d.group_set_rights(id, &barred, slow) } });
    Ok(())
}

/// A person taken out by the owner, or asked of the owner by an administrator who may (iOS kick).
#[tauri::command]
async fn group_kick(app: AppHandle, chat: String, seat: String) -> Result<(), ()> {
    deed(app, move |d| { if let Some(id) = chat.strip_prefix("grp:") { d.group_kick(id, &seat) } });
    Ok(())
}

/// Why these words may not go into the group now (iOS refusal): a right's word, or «slow:<seconds>»; nothing when they may.
#[tauri::command]
async fn group_refusal(p: State<'_, Person>, m: State<'_, Messenger>, chat: String, words: String) -> Result<Option<String>, ()> {
    Ok(chat.strip_prefix("grp:").and_then(|id| m.desk(&p).and_then(|d| d.group_refusal(id, &words))))
}

/// A channel's own ways, by its owner (iOS «Sign Messages», «Allow Reactions»).
#[tauri::command]
async fn channel_set(app: AppHandle, chat: String, signs: bool, reacts: bool, talks: Option<bool>) -> Result<(), ()> {
    deed(app, move |d| {
        if let Some(id) = chat.strip_prefix("grp:") {
            let talks = talks.unwrap_or_else(|| d.group(id).is_some_and(|g| g.talks));
            d.channel_set(id, signs, reacts, talks)
        }
    });
    Ok(())
}

/// The reactions a channel takes, by its owner (iOS setReactionList): empty -- every one.
#[tauri::command]
async fn channel_reactions(app: AppHandle, chat: String, list: Vec<String>) -> Result<(), ()> {
    deed(app, move |d| { if let Some(id) = chat.strip_prefix("grp:") { d.channel_reactions(id, &list) } });
    Ok(())
}

/// A comment of mine under a channel's post (iOS comment); false when it did not go.
#[tauri::command]
async fn channel_comment(app: AppHandle, chat: String, post: String, text: String) -> Result<bool, ()> {
    let a = app.clone();
    let ok = tauri::async_runtime::spawn_blocking(move || {
        let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
        chat.strip_prefix("grp:").and_then(|id| m.desk(&p).map(|d| d.channel_comment(id, &post, &text))).unwrap_or(false)
    }).await.unwrap_or(false);
    changed(&app);
    Ok(ok)
}

/// The comments under a channel's post, in their order (iOS MTChannelComments).
#[tauri::command]
async fn channel_comments(m: State<'_, Messenger>, chat: String, post: String) -> Result<Vec<groups::Comment>, ()> {
    Ok(groups::comments_of(&m.vault, &chat).remove(&post).unwrap_or_default())
}

#[tauri::command]
async fn group_rename(app: AppHandle, chat: String, title: String) -> Result<(), ()> {
    deed(app, move |d| { if let Some(id) = chat.strip_prefix("grp:") { d.group_rename(id, &title) } });
    Ok(())
}

#[tauri::command]
async fn chat_forward(app: AppHandle, chat: String, mid: String, to: String) -> Result<(), ()> {
    deed(app, move |d| { d.forward(&chat, &mid, &to); });
    Ok(())
}

#[tauri::command]
async fn search(app: AppHandle, q: String) -> Result<Vec<serde_json::Value>, ()> {
    tauri::async_runtime::spawn_blocking(move || {
        let m = app.state::<Messenger>();
        Ok(m.search(&q))
    }).await.map_err(|_| ())?
}

#[tauri::command]
async fn chat_delete(app: AppHandle, chat: String, mids: Vec<String>, everyone: bool) -> Result<(), ()> {
    // a letter of mine deleted on its way: its film's writing and its pieces stop with it (iOS: «its transport dies with the row»)
    mids.iter().for_each(|x| media::stop(x));
    deed(app, move |d| d.delete(&chat, &mids, everyone));
    Ok(())
}

#[tauri::command]
async fn chat_edit(app: AppHandle, chat: String, mid: String, text: String) -> Result<(), ()> {
    let text = text.trim().to_string();
    if text.is_empty() || text.chars().count() > PIECE || marks::is_service(&text) {
        return Err(());
    }
    deed(app, move |d| { d.edit_letter(&chat, &mid, &text); });
    Ok(())
}

#[tauri::command]
async fn chat_react(app: AppHandle, chat: String, mid: String, emoji: String) -> Result<(), ()> {
    deed(app, move |d| d.react(&chat, &mid, &emoji));
    Ok(())
}

#[tauri::command]
async fn chat_erase(app: AppHandle, chat: String, both: bool) -> Result<(), ()> {
    app.state::<Messenger>().keep_draft(&chat, "");   // its unsent words leave with the feed (iOS purgeConversation)
    deed(app, move |d| d.erase(&chat, both));
    Ok(())
}

/// THE COIN'S REFRESH (iOS ChatsListView.pullRefresh: the box asked at once, whatever waits there landed): the list drawn past the
/// coin's trigger asks the node's box now instead of at the walk's next beat -- off the window's thread.
#[tauri::command]
async fn pull_refresh(app: AppHandle) -> Result<(), ()> {
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        if let Some(d) = m.desk(&p) {
            if d.fetch_once() > 0 {
                changed(&app);
                ring(&app, &p, &m, std::mem::take(&mut *d.news.lock().unwrap()));
            }
        }
    });
    Ok(())
}

/// THE DELETION'S TERMS (iOS MontanaDeleteChatSheet): whether «Delete for me and them» stands, and whether a coin letter travels.
#[tauri::command]
async fn chat_erase_terms(m: State<'_, Messenger>, chat: String) -> Result<serde_json::Value, ()> {
    let (both, coins) = m.erase_terms(&chat);
    Ok(serde_json::json!({ "both": both, "coins": coins }))
}

/// BLOCK OR UNBLOCK a correspondent (iOS «Заблокировать» / «Разблокировать»).
#[tauri::command]
async fn chat_block(app: AppHandle, chat: String, on: bool) -> Result<(), ()> {
    deed(app, move |d| if on { d.block(&chat) } else { d.unblock(&chat) });
    Ok(())
}

/// THE BLOCKED (Settings → Privacy → «Заблокированные»): their chats and names.
#[tauri::command]
async fn blocked_list(m: State<'_, Messenger>) -> Result<Vec<(String, String)>, ()> {
    Ok(m.book.all().into_iter().filter(|c| c.blocked).map(|c| (c.reference, c.name)).collect())
}

/// A REPORT (iOS MontanaSafety: no network endpoint -- a letter to contact@montana.quest): the reason, the reporter's and
/// the reported reference, the letter if one; the person's mail program opens it. No mail program: the report and the
/// address go to the clipboard and the window says so (false).
#[tauri::command]
async fn report(p: State<'_, Person>, m: State<'_, Messenger>, chat: String, reason: String, mid: Option<String>,
                text: Option<String>, who: Option<String>) -> Result<bool, ()> {
    let reason = if ["spam", "abuse", "hate", "illegal", "other"].contains(&reason.as_str()) { reason } else { "other".into() };
    let name = who.unwrap_or_else(|| m.book.given_name(&chat).unwrap_or_default());
    let letter = mid.as_deref().and_then(|x| m.book.chat(&chat).and_then(|c| c.msgs.into_iter().find(|l| l.mid == x)));
    let mut body = format!("Report ({reason})\nReporter: {}\nReported: {chat}", p.seed.twin().unwrap_or_default());
    if !name.is_empty() {
        body.push_str(&format!(" ({name})"));
    }
    if let Some(l) = &letter {
        body.push_str(&format!("\nLetter: {}\n\n---\n{}\n---", l.mid, l.text));
    } else if let Some(x) = mid.as_deref().filter(|x| !x.is_empty()) {
        // A POST REPORTED (iOS MontanaReport of a post): its name, and its words as its wall showed them
        body.push_str(&format!("\nLetter: {x}"));
        if let Some(t) = text.as_deref().filter(|t| !t.is_empty()) {
            body.push_str(&format!("\n\n---\n{t}\n---"));
        }
    }
    body.push_str("\n\nBuild: Windows 0.1.0");
    let subject = format!("Montana report ({reason})");
    let enc = |s: &str| s.bytes().map(|b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect::<String>();
    let url = format!("mailto:contact@montana.quest?subject={}&body={}", enc(&subject), enc(&body));
    if open_in_browser(&url) {
        return Ok(true);
    }
    clipboard::copy_text(&format!("contact@montana.quest\n{subject}\n\n{body}"));
    Ok(false)
}

/// The person's own mark on a chat: pin, archive, mute, unread.
#[tauri::command]
async fn chat_flag(app: AppHandle, chat: String, flag: String, on: bool) -> Result<bool, ()> {
    let ok = app.state::<Messenger>().flag(&chat, &flag, on);
    changed(&app);
    Ok(ok)
}

/// Text onto the clipboard (a letter's words: an ordinary copy).
#[tauri::command]
async fn copy_text(text: String) -> Result<bool, ()> {
    Ok(clipboard::copy_text(&text))
}

/// The window says which chat it shows (or none): no banner for it while the window is in front; «in my chat» (WA:) is said
/// to the one it shows and «left» to the one it left, and the lane of the open chat is listened to (iOS chatPresenceMoved).
#[tauri::command]
async fn chat_focus(app: AppHandle, chat: Option<String>) -> Result<(), ()> {
    let m = app.state::<Messenger>();
    let was = std::mem::replace(&mut *m.open.lock().unwrap(), chat.clone());
    trace_line(&format!("focus chat={:?} was={:?}", chat.as_deref().map(|c| &c[..c.len().min(10)]), was.as_deref().map(|c| &c[..c.len().min(10)])));
    if was == chat {
        return Ok(());
    }
    let (a, now) = (app.clone(), chat.clone());
    std::thread::spawn(move || {
        let (p, m) = (a.state::<Person>(), a.state::<Messenger>());
        let chat = now;
        if p.profile.read().presence_sharing == Some(false) {
            return;
        }
        let Some(d) = m.desk(&p) else { return };
        if let Some(w) = was {
            m.presence.post(&m.book, &d.twin, &w, &m.presence.word_watch(&m.book, &m.faces, &w, false));
        }
        if let Some(c) = &chat {
            m.presence.post(&m.book, &d.twin, c, &m.presence.word_watch(&m.book, &m.faces, c, true));
        }
    });
    if let Some(c) = chat {
        lane(app, c);
    }
    Ok(())
}

/// THE MONEY FLOW OF A CHAT (iOS MTMoneyFlow): read, or turned. Turned on, the chat gets its own row «the money flow began»; turned
/// off, my live words end on their screen and theirs leave mine.
#[tauri::command]
async fn money_flow(app: AppHandle, chat: String, on: Option<bool>) -> Result<bool, ()> {
    let Some(on) = on else { return Ok(presence::flow_on(&chat)) };
    if groups::is_group(&chat) {
        return Ok(false);
    }
    let m = app.state::<Messenger>();
    let all = presence::set_flow(&chat, on);
    m.vault.set("moneyFlow", serde_json::to_vec(&all).unwrap_or_default().as_slice());
    if on {
        let mid = book::mint_mid();
        let at = book::birth_ms(&mid).unwrap_or_else(wire::now_ms);
        m.book.edit(&chat, |c| {
            // one row a minute at most (iOS appendMoneyFlow)
            if c.msgs.last().is_some_and(|l| l.text == post::marks::FLOW_ROW && at - l.at < 60_000) {
                return;
            }
            c.msgs.push(book::Msg { mid, text: post::marks::FLOW_ROW.into(), mine: true, at, state: 3, ..Default::default() });
        });
    } else {
        m.presence.drop_live(&chat);
        let ended = DRAFTS_SAID.lock().unwrap().remove(&chat).is_some_and(|t| !t.is_empty());
        if ended {
            let p = app.state::<Person>();
            if let Some(d) = m.desk(&p) {
                m.presence.post(&m.book, &d.twin, &chat, &m.presence.word_draft("", 0, "", false));
            }
        }
    }
    trace_line(&format!("money_flow on={on}"));
    changed(&app);
    Ok(on)
}

/// A chess board stands before the person's eyes (iOS MTChessGameScreen.shownGame): a game, no banners while the window is in front.
static PLAYING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
#[tauri::command]
fn play_quiet(on: bool) {
    PLAYING.store(on, std::sync::atomic::Ordering::SeqCst);
}

/// MY LIVE WORDS (iOS sendDraft): what my field holds, said on the lane of a chat whose Money Flow is on; the words already standing
/// on the wire are not said again, an empty text ends the draft wherever it is said from -- and when what stands is unknown (a
/// first word of this life), the ending speaks. `ck`: the chat closed or the window hid, their bubble freezes (iOS checkpoint).
static DRAFTS_SAID: std::sync::Mutex<std::collections::BTreeMap<String, String>> = std::sync::Mutex::new(std::collections::BTreeMap::new());
#[tauri::command]
async fn chat_draft(app: AppHandle, chat: String, text: String, caret: i64, rm: Option<String>, ck: Option<bool>) -> Result<(), ()> {
    let text: String = text.chars().take(4500).collect();
    if groups::is_group(&chat) || (!text.is_empty() && !presence::flow_on(&chat)) {
        return Ok(());
    }
    {
        let mut said = DRAFTS_SAID.lock().unwrap();
        if said.get(&chat) == Some(&text) {
            return Ok(());
        }
        said.insert(chat.clone(), text.clone());
    }
    let ck = ck.unwrap_or(false);
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        if let Some(d) = m.desk(&p) {
            m.presence.post(&m.book, &d.twin, &chat, &m.presence.word_draft(&text, caret, rm.as_deref().unwrap_or(""), ck));
            let what = if text.is_empty() { "end".to_string() } else { format!("word len={}", text.chars().count()) };
            trace_line(&format!("draft_tx {what}{}", if ck { " ck" } else { "" }));
        }
    });
    Ok(())
}

/// I type in their chat (iOS: TY: when the field holds words, at most every 3 s -- the window keeps the pace); in a group, the
/// group's instant word «ty» to the pipes it rides, while the person shares their presence (iOS MTGroup.typing).
#[tauri::command]
async fn chat_typing(app: AppHandle, chat: String) -> Result<(), ()> {
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        if let Some(d) = m.desk(&p) {
            match chat.strip_prefix("grp:") {
                Some(id) if p.profile.read().presence_sharing != Some(false) => d.group_typing(id),
                Some(_) => {}
                None => {
                    m.presence.post(&m.book, &d.twin, &chat, &m.presence.word_typing());
                }
            }
        }
    });
    Ok(())
}

/// Who types in a group now, the earliest first: the names the group knows them by (empty -- a member without one).
#[tauri::command]
async fn group_typing(p: State<'_, Person>, m: State<'_, Messenger>, chat: String) -> Result<Vec<String>, ()> {
    let seats = m.presence.group_typing(&chat);
    if seats.is_empty() {
        return Ok(vec![]);
    }
    let g = chat.strip_prefix("grp:").and_then(|id| m.desk(&p).and_then(|d| d.group(id)));
    Ok(seats.iter().map(|s| g.as_ref().and_then(|g| g.names.get(s).cloned()).unwrap_or_default()).collect())
}

/// Where a correspondent is now: typing, in my chat, in the app, gone, or when last seen.
#[tauri::command]
async fn presence(m: State<'_, Messenger>, chat: String) -> Result<presence::Seen, ()> {
    Ok(m.presence.seen(&chat))
}

/// THE LANE OF THE OPEN CHAT (iOS startChatPolling): a long poll while the chat stays open; their live words move the ladder,
/// a fresh «in my chat» is answered «in the app», a stale tag heals my face, name or bio, «box» fetches the box, a letter on
/// the lane lands at once.
fn lane(app: AppHandle, chat: String) {
    std::thread::spawn(move || {
        let dev = format!("windows-{}", std::process::id());
        loop {
            let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
            if m.open.lock().unwrap().as_deref() != Some(chat.as_str()) {
                return;
            }
            let Some(d) = m.desk(&p) else { trace_line("lane no desk"); return };
            let Some((words, boxed)) = presence::Presence::listen(&m.book, &d.twin, &chat, &dev) else {
                trace_line(&format!("lane none chat={} secret={} doors={}", &chat[..chat.len().min(10)], m.book.secret(&chat).is_some(), crate::doors::all().len()));
                std::thread::sleep(std::time::Duration::from_secs(3));
                continue;
            };
            let mut moved = false;
            let blocked = m.book.chat(&chat).is_some_and(|c| c.blocked);
            for (epoch, body) in words.into_iter().filter(|_| !blocked) {
                match epoch.as_str() {
                    "chat" => {
                        let text = String::from_utf8_lossy(&body).into_owned();
                        let (mv, echo) = m.presence.hear(&chat, &text, false);
                        trace_line(&format!("lane_heard chat={} word={} moved={mv} seen={}", &chat[..chat.len().min(10)], text.chars().take(24).collect::<String>().escape_debug(), m.presence.seen(&chat).state));
                        moved |= mv;
                        if echo && p.profile.read().presence_sharing != Some(false) {
                            m.presence.post(&m.book, &d.twin, &chat, &m.presence.word_app(&m.book, &m.faces, &chat, true));
                        }
                        heal(&m, &d, &chat, &text);
                    }
                    "letter" => moved |= d.lane_letter(&chat, &body),
                    // a call's word on the open chat's lane: the window's call hears it
                    ep if ep.len() == 16 => call_packet(&app, &chat, ep, &String::from_utf8_lossy(&body)),
                    _ => {}
                }
            }
            if boxed {
                moved |= d.fetch_once() > 0;
            }
            if moved {
                changed(&app);
                let _ = app.emit(PRESENCE, &chat);
            }
        }
    });
}

/// Their word says my face, name or bio they hold is stale: the receipted mark is forgotten and the next walk says it again.
fn heal(m: &Messenger, d: &post::Desk, chat: &str, text: &str) {
    let face = presence::wire_tag(&d.self_face);
    let name = presence::wire_tag(d.my_name.trim().as_bytes());
    let about = presence::about_tag(&d.about.0, &d.about.1);
    if let Some((f, n, a)) = m.presence.stale(chat, text, &face, &name, &about) {
        m.book.edit(chat, |c| {
            if f { c.face_said.clear(); c.face_flight.clear(); }
            if n { c.announced.clear(); c.name_flight.clear(); }
            if a { c.about_said.clear(); c.about_flight.clear(); }
        });
    }
}

/// «In the app» (AP:) to the freshest correspondents (iOS presencePeers: 128): when the window comes to the front, and «not»
/// 8 s after it left it -- only if it was said this run.
fn greet(m: &Messenger, d: &post::Desk, open: bool) {
    let rows = m.rows();
    for r in rows.iter().filter(|r| !r.archived && !r.blocked).take(128) {
        m.presence.post(&m.book, &d.twin, &r.reference, &m.presence.word_app(&m.book, &m.faces, &r.reference, open));
    }
}

/// THE BANNER OF A LETTER (iOS MontanaNotify.presentLetter): the sender's name over the words, unless the person turned the
/// preview or the sender off, or the letter's chat is the one before their eyes.
fn ring(app: &AppHandle, p: &Person, m: &Messenger, news: Vec<post::News>) {
    let s = p.profile.read();
    if news.is_empty() || s.notif_enabled == Some(false) {
        return;
    }
    let front = app.get_webview_window("main").and_then(|w| w.is_focused().ok()).unwrap_or(false);
    let open = m.open.lock().unwrap().clone();
    // NO BANNER WHILE A PERSON PLAYS (iOS MTPlayQuiet): the open chat's own Money Flow or a chess board before their eyes
    if front && (open.as_deref().is_some_and(presence::flow_on) || PLAYING.load(std::sync::atomic::Ordering::SeqCst)) {
        return;
    }
    let ru = p.lang.starts_with("ru");
    for n in news {
        // a group's letter that names me rings through the mute (iOS MTGroup.mentionsMe)
        let named = groups::is_group(&n.chat) && groups::mentions_me(&n.text, &profile::strip_crown(s.user_name.trim()));
        if (front && open.as_deref() == Some(n.chat.as_str())) || (m.quiet(&n.chat) && !named) {
            continue;
        }
        let name = m.book.chat(&n.chat).map(|c| c.name).filter(|n| !n.trim().is_empty())
            .unwrap_or_else(|| (if ru { "Собеседник" } else { "Correspondent" }).to_string());
        let title = if s.notif_sender == Some(false) { "Montana".to_string() } else { name };
        // A LETTER TO A PERSON ON THE SHELF (iOS MTNodeWire.ShelfEar): the banner says whose it is
        let title = match seats::here().filter(|h| h.shelf) {
            Some(_) => format!("{title} — {} {}", if ru { "для" } else { "for" }, profile::strip_crown(s.user_name.trim())),
            None => title,
        };
        let body = if n.text == post::marks::KEPT {
                // THE WORD SAYS WHAT A LEVEL IS (iOS presentKept): the fact, then the rule that made it
                (if ru { "Сообщение, которое вы удалили у всех, осталось у собеседника. В Монтане уровни открывают функции: с уровня 7 человек может запретить удаление у себя." }
                 else { "Their device keeps the message you deleted for everyone. In Montana levels open functions: from level 7 a person can forbid deletion on their device." }).to_string()
            }
            else if s.notif_preview == Some(false) { (if ru { "Новое сообщение" } else { "New message" }).to_string() }
            else if filter::folds(false, &n.text) { (if ru { "Скрыто фильтром" } else { "Hidden by the filter" }).to_string() } // the banner reads the filter too
            else if passwords::is_letter(&n.text) { (if ru { "🔑 Пароль от собеседника" } else { "🔑 Shared password" }).to_string() } // nor any secret
            // SHOW SENDER HAS ONE OWNER (iOS 2304 MontanaNotify.showsSender): off, no banner names who wrote -- a group's words
            // without «who:», a room's call from «Correspondent»
            else if s.notif_sender == Some(false) { n.anon.unwrap_or(n.text) }
            else { n.text };
        let mut banner = app.notification().builder().title(title).body(body);
        if s.notif_sound != Some(false) {
            banner = banner.sound("Default"); // the platform's sound, as iOS .default
        }
        let _ = banner.show();
    }
}

/// The chat is before the person's eyes: their letters are read (iOS sendReadMark on the open chat, the app active).
#[tauri::command]
async fn chat_read(app: AppHandle, chat: String) -> Result<(), ()> {
    let unread = app.state::<Messenger>().book.chat(&chat).is_some_and(|c| c.unread > 0);
    if !unread {
        return Ok(());
    }
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        if let Some(d) = m.desk(&p) {
            d.mark_read(&chat);
        }
        changed(&app);
    });
    Ok(())
}

/// The person's link of the chosen kind and its QR; the kind is kept (iOS @AppStorage cardKind).
#[tauri::command]
async fn card(p: State<'_, Person>, m: State<'_, Messenger>, kind: Option<String>) -> Result<Option<qr::Card>, ()> {
    if let Some(k) = kind.filter(|k| k == "permanent" || k == "temporary") {
        p.profile.update(|s| s.card_kind = k);
    }
    let kind = if p.profile.read().card_kind == "temporary" { "temporary" } else { "permanent" };
    let link = m.card_link(&p, kind);
    if let Some(l) = &link {
        m.lay_card_face(l);
    }
    Ok(link.and_then(|link| qr::Card::of(link, kind, if kind == "temporary" { m.renews() } else { 0 })))
}

#[tauri::command]
async fn card_copy(p: State<'_, Person>, m: State<'_, Messenger>) -> Result<bool, ()> {
    let kind = p.profile.read().card_kind;
    Ok(m.card_link(&p, &kind).is_some_and(|l| clipboard::copy_text(&l)))
}

/// A link the person pasted: met off the window's thread (the card is fetched from the node).
#[tauri::command]
async fn meet(app: AppHandle, link: String) -> Result<meeting::Outcome, ()> {
    let a = app.clone();
    let out = tauri::async_runtime::spawn_blocking(move || {
        let m = a.state::<Messenger>();
        let out = m.meet(&link);
        // a group's link: the join is asked of the owner just met (iOS askJoin)
        if let (meeting::Outcome::Opened(r), Some((g, mark))) = (&out, groups::join_mark(&link)) {
            if let Some(d) = m.desk(&a.state::<Person>()) {
                d.group_join(r, &g, &mark);
            }
        }
        out
    }).await.map_err(|_| ())?;
    changed(&app);
    Ok(out)
}

/// A page of Montana's site in the person's browser (iOS openURL .systemAction): only the site's own pages, by name --
/// the window never hands an address of its choosing to the system.
#[tauri::command]
async fn open_site(page: String) -> Result<bool, ()> {
    let url = match page.as_str() {
        "privacy" => "https://montana.quest/privacy/",   // MontanaSafety.privacy
        "site" => "https://montana.quest",                // MontanaSafety.site
        "guide" => "https://montana.xxx/faq/",            // MontanaSafety.guide
        "source" => "https://github.com/efir369999/montana_messenger",   // MontanaSafety.source: the specification and the code
        "mail" => "mailto:contact@montana.quest",          // MontanaSafety.contactMail
        "notifications" => "ms-settings:notifications",   // Windows' own page of banners (iOS: the app's system settings)
        _ => return Ok(false),
    };
    Ok(open_in_browser(url))
}

#[cfg(windows)]
fn open_in_browser(url: &str) -> bool {
    use windows_sys::Win32::UI::Shell::ShellExecuteW;
    use windows_sys::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
    let wide = |s: &str| s.encode_utf16().chain(std::iter::once(0)).collect::<Vec<u16>>();
    let (verb, target) = (wide("open"), wide(url));
    // SAFETY: NUL-terminated strings for the call; the result above 32 means the shell took it
    let r = unsafe { ShellExecuteW(std::ptr::null_mut(), verb.as_ptr(), target.as_ptr(), std::ptr::null(), std::ptr::null(), SW_SHOWNORMAL) };
    r as isize > 32
}

#[cfg(not(windows))]
fn open_in_browser(_: &str) -> bool {
    false
}

/// The language of the person's Windows ("ru-RU" -> "ru-ru"), for the call sign.
fn system_lang() -> String {
    #[cfg(windows)]
    {
        use windows_sys::Win32::Globalization::GetUserDefaultLocaleName;
        let mut buf = [0u16; 85];
        // SAFETY: a buffer of LOCALE_NAME_MAX_LENGTH
        let n = unsafe { GetUserDefaultLocaleName(buf.as_mut_ptr(), buf.len() as i32) };
        if n > 1 {
            return String::from_utf16_lossy(&buf[..(n - 1) as usize]).to_lowercase();
        }
    }
    "en".into()
}

/// THE TRAY (the Windows form of iOS's push: the app goes on hearing letters while its window is closed): a left click
/// opens the window, the menu opens it or quits; closing the window only hides it.
fn tray(app: &tauri::App) -> tauri::Result<()> {
    use tauri::menu::{Menu, MenuItem};
    use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
    let lang = app.state::<Person>().profile.read().language;
    let ru = if lang.is_empty() { system_lang().starts_with("ru") } else { lang == "ru" };
    let open = MenuItem::with_id(app, "open", if ru { "Открыть Montana" } else { "Open Montana" }, true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", if ru { "Выйти из Montana" } else { "Quit Montana" }, true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open, &quit])?;
    let mut b = TrayIconBuilder::with_id("montana").tooltip("Montana").menu(&menu).show_menu_on_left_click(false)
        .on_menu_event(|app, e| match e.id.as_ref() {
            "open" => show(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, e| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
                show(tray.app_handle());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        b = b.icon(icon.clone());
    }
    b.build(app)?;
    Ok(())
}

fn show(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.unminimize();
        let _ = w.set_focus();
    }
}

/// THE MICROPHONE AND THE CAMERA FOR THE APP'S OWN PAGE (iOS: the system asks once for the app): a desktop program is governed
/// by Windows' own privacy switches, not by a browser's question. WebView2 would ask «the site wants your microphone» -- the
/// app answers for its own page (http://tauri.localhost) and only for those two; every other request keeps WebView2's way.
#[cfg(windows)]
fn own_permissions(app: &tauri::App) {
    let Some(w) = app.get_webview_window("main") else { return };
    let _ = w.with_webview(|pw| {
        use webview2_com::Microsoft::Web::WebView2::Win32::*;
        // SAFETY: the web view's own controller on its own thread; the handler only reads the request and sets its state
        unsafe {
            let Ok(core) = pw.controller().CoreWebView2() else { return };
            let mut token = 0i64;
            let handler = webview2_com::PermissionRequestedEventHandler::create(Box::new(|_, args| {
                let Some(args) = args else { return Ok(()) };
                let mut kind = COREWEBVIEW2_PERMISSION_KIND::default();
                args.PermissionKind(&mut kind)?;
                let mut uri = windows::core::PWSTR::null();
                args.Uri(&mut uri)?;
                let uri = webview2_com::take_pwstr(uri);
                let own = uri.starts_with("http://tauri.localhost/") || uri.starts_with("https://tauri.localhost/") || uri.starts_with("tauri://localhost");
                if own && (kind == COREWEBVIEW2_PERMISSION_KIND_MICROPHONE || kind == COREWEBVIEW2_PERMISSION_KIND_CAMERA) {
                    args.SetState(COREWEBVIEW2_PERMISSION_STATE_ALLOW)?;
                }
                Ok(())
            }));
            let _ = core.add_PermissionRequested(&handler, &mut token);
        }
    });
}

/// The taskbar's mark of letters waiting (a red dot over the icon; Windows' overlay), drawn once.
fn waiting_dot() -> tauri::image::Image<'static> {
    let n = 32u32;
    let mut px = vec![0u8; (n * n * 4) as usize];
    for y in 0..n {
        for x in 0..n {
            let (dx, dy) = (x as f32 - 15.5, y as f32 - 15.5);
            let d = (dx * dx + dy * dy).sqrt();
            if d <= 15.5 {
                let i = ((y * n + x) * 4) as usize;
                let edge = (15.5 - d).min(1.0);   // a soft rim
                px[i..i + 4].copy_from_slice(&[255, 59, 48, (255.0 * edge) as u8]);
            }
        }
    }
    tauri::image::Image::new_owned(px, n, n)
}

/// THE WALK (iOS MontanaDeliveryEngine's pickup; Android's foreground long-poll): every few seconds the letters of mine no node
/// took go again and the boxes are read; the card is laid on the node again when due. The window hears a change.
/// THE TWIN'S OWN ROAD: laying the words and blocks for the person's other devices goes to the nodes and back, seconds at a
/// time; it runs on a thread of its own, one at a time, so the walk's pickup of letters never waits behind it.
fn twin_walk(app: &AppHandle) {
    static BUSY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
    if BUSY.swap(true, std::sync::atomic::Ordering::AcqRel) {
        return;
    }
    let app = app.clone();
    std::thread::spawn(move || {
        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
        if m.desk(&p).is_some_and(|d| d.twin_walk()) {
            changed(&app);
        }
        BUSY.store(false, std::sync::atomic::Ordering::Release);
    });
}

fn walk(app: AppHandle) {
    std::thread::spawn(move || {
        let mut tick: u64 = 0;
        let mut dotted = false;
        loop {
            // presence: the greeting by the window's front, the beat of the open chat every 20 s, the sweep every minute
            {
                let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
                let sharing = p.profile.read().presence_sharing != Some(false);
                if let Some(d) = m.desk(&p) {
                    let (focused, since, said) = *m.front.lock().unwrap();
                    if sharing && focused && said != Some(true) {
                        m.front.lock().unwrap().2 = Some(true);
                        greet(&m, &d, true);
                    }
                    if sharing && !focused && said == Some(true) && wire::now_ms() - since >= 8_000 {
                        m.front.lock().unwrap().2 = Some(false);
                        greet(&m, &d, false);
                    }
                    if sharing && focused && tick % 5 == 4 {
                        if let Some(c) = m.open.lock().unwrap().clone() {
                            m.presence.post(&m.book, &d.twin, &c, &m.presence.word_watch(&m.book, &m.faces, &c, true));
                        }
                    }
                    if tick.is_multiple_of(15) && m.presence.sweep(&m.book, &d.twin) {
                        changed(&app);
                    }
                }
            }
            {
                let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
                if tick == 0 {
                    m.fill_archive(&p);
                    if let Some(d) = m.desk(&p) {
                        d.twin_soon("hist", 30_000); // the blocks this machine sealed before the other devices heard of them
                    }
                }
                // the light copy, once a day while the person keeps their copy with their contacts (iOS MTKeeping.tick: mine, told,
                // agrees -- no switch of its own); a copy begun is one tried, the next waits the day
                let keeps = tick % 900 == 30 && keeping::agrees() && m.desk(&p).is_some_and(|d| keeping::mine(&d) && keeping::told(&d));
                if keeps {
                    let at = |k: &str| m.vault.get(k).and_then(|b| String::from_utf8(b).ok()).and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);
                    if wire::now_ms() / 1000 - at("lightAt").max(at("lightTried")) >= 86_400 {
                        m.vault.set("lightTried", (wire::now_ms() / 1000).to_string().as_bytes());
                        if let (Some(words), Some(a)) = (p.seed.mnemonic(), m.archive(&p)) {
                            let g = m.vault.get("lightGen").and_then(|b| String::from_utf8(b).ok()).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0) + 1;
                            if history::lay_light(&words, &a, g, my_card(&p)) {
                                m.vault.set("lightGen", g.to_string().as_bytes());
                                m.vault.set("lightAt", (wire::now_ms() / 1000).to_string().as_bytes());
                            }
                        }
                    }
                }
                if let Some(d) = m.desk(&p) {
                    rooms::beat(&d);
                    d.group_retry();
                    let moved = d.flush();
                    let landed = d.fetch_once();
                    for c in m.presence.groups_moved() {
                        let _ = app.emit(PRESENCE, &c); // who types in a group moved: its chat's head asks again
                    }
                    twin_walk(&app); // the person's other devices: the mirror and the blocks laid when due, beside the walk
                    if moved || landed > 0 {
                        changed(&app);
                    }
                    ring(&app, &p, &m, std::mem::take(&mut *d.news.lock().unwrap()));
                    for r in std::mem::take(&mut *calls::RINGS.lock().unwrap()) {
                        let _ = app.emit(CALL_RING, &r);
                        show(&app); // a call brings the window forward, as a phone's ringing screen
                    }
                    // the files of their letters: up to three a walk, a big one only when the person asked for it
                    let by_themselves = auto_download(&p);
                    for _ in 0..3 {
                        let want = m.want.lock().unwrap().take();
                        let auto = if by_themselves { AUTO_FETCH } else { 0 };
                        if !d.fetch_media(want.as_deref(), auto) {
                            break;
                        }
                        changed(&app);
                    }
                    if tick.is_multiple_of(60) && !(card::Card { vault: &m.vault }).outstanding_invites().is_empty() {
                        let kind = p.profile.read().card_kind;
                        m.card_link(&p, &kind);
                    }
                }
            }
            // the taskbar says letters wait, as the iOS badge does (muted and archived chats count nothing)
            {
                let m = app.state::<Messenger>();
                let waiting = m.rows().iter().any(|r| r.unread > 0 && !r.muted && !r.archived);
                if waiting != dotted {
                    if let Some(w) = app.get_webview_window("main") {
                        let _ = w.set_overlay_icon(waiting.then(waiting_dot));
                    }
                    dotted = waiting;
                }
            }
            tick += 1;
            std::thread::sleep(std::time::Duration::from_secs(4));
        }
    });
}

pub fn run() {
    let context = tauri::generate_context!();
    // THE SEAT FIRST (iOS MTSeats.launch): which person this process stands for, before any owner reads a folder
    let here = seats::settle(&context.config().identifier);
    // A FOLDER OF ITS OWN IS WHOLE: a test run's folder (MONTANA_DATA_DIR) and every seat but the first keep the window's web
    // view data there too (WebView2 reads WEBVIEW2_USER_DATA_FOLDER over the app's folder) -- a second person shares no browser
    // with the first. A move starts the program again with this process's variables: what this process set, it sets again.
    let own = std::env::var_os("MONTANA_WEBVIEW_OWN").is_some();
    if own || std::env::var_os("WEBVIEW2_USER_DATA_FOLDER").is_none() {
        if here.folder != here.base || std::env::var_os("MONTANA_DATA_DIR").is_some() {
            std::env::set_var("WEBVIEW2_USER_DATA_FOLDER", here.folder.join("EBWebView"));
            std::env::set_var("MONTANA_WEBVIEW_OWN", "1");
        } else if own {
            std::env::remove_var("WEBVIEW2_USER_DATA_FOLDER");
            std::env::remove_var("MONTANA_WEBVIEW_OWN");
        }
    }
    if !seats::hold(here) {
        // another process stands for this person: Montana opened twice asks the window standing to come forward
        if !here.shelf {
            let _ = std::fs::write(here.base.join(seats::SHOW), b"1");
        }
        return;
    }
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .register_asynchronous_uri_scheme_protocol("mtfile", |ctx, request, responder| {
            let app = ctx.app_handle().clone();
            std::thread::spawn(move || responder.respond(file_range(&app, &request)));
        })
        .setup(|app| {
            // the seat's folder: the app's local data (or a test run's MONTANA_DATA_DIR) for the first person, Seats\<id> beside it
            // for every other one
            let dir = here.folder.clone();
            let vault = vault::Vault::at(&dir.join("vault"))?;
            app.manage(Person::new(seed::Seed::new(vault.clone()), profile::Profile::at(&dir), system_lang()));
            person::start(&vault, &dir);   // the seconds of the person seated (iOS MTPersonChain)
            fabric::start(&vault, &dir);   // and the fabric of time of their correspondences (iOS MTFabric)
            presence::flows_load(vault.get("moneyFlow").and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default());
            app.manage(Messenger::new(vault, media::Store::at(&dir.join("media"))?, media::Store::at(&dir.join("faces"))?, dir.clone()));
            let lang = app.state::<Person>().profile.read().language;
            rooms::set_ru(if lang.is_empty() { system_lang().starts_with("ru") } else { lang == "ru" });
            filter::set_on(app.state::<Person>().profile.read().objectionable_filter != Some(false));
            let ear = app.handle().clone();
            rooms::on_change(Box::new(move |name, v| { let _ = ear.emit(name, v); }));
            // a file of mine on its way: its ring and its word on the bubble (iOS MTTransferBoard)
            let ring = app.handle().clone();
            media::on_transfer(Box::new(move |mid, now| {
                let _ = ring.emit("montana://transfer", serde_json::json!({ "mid": mid, "share": now.as_ref().map(|x| x.0), "word": now.map(|x| x.1) }));
            }));
            walk(app.handle().clone());
            keeping_walk(app.handle().clone());
            board_walk(app.handle().clone());
            coin_walk(app.handle().clone());
            channels_walk(app.handle().clone());
            if !here.shelf {
                home_walk(app.handle().clone());   // the daily copy to one's own node rides the seated person's window
            }
            if here.shelf {
                shelf_walk(app.handle().clone());
            } else {
                // the window is made here, not by the config: a person on the shelf has none
                tauri::WebviewWindowBuilder::from_config(app.handle(), &app.config().app.windows[0])?.build()?;
                tray(app)?;
                #[cfg(windows)]
                own_permissions(app);
                seats_walk(app.handle().clone());
            }
            Ok(())
        })
        .on_window_event(|w, e| {
            // the window in front or not: the walk greets «in the app» or says «not» after 8 s (iOS appPresence)
            if let tauri::WindowEvent::Focused(f) = e {
                person::set_front(*f);   // a node's answer is a second of the person only while the window stands in front
                let m = w.app_handle().state::<Messenger>();
                let mut front = m.front.lock().unwrap();
                // THE RETURN TO THE APP (iOS scenePhase .active): the window back in front after a second or more away -- a focus
                // that only moves inside the window (a field, the web view) is no return
                let back = *f && !front.0 && wire::now_ms() - front.1 >= 1000;
                if front.0 != *f {
                    *front = (*f, wire::now_ms(), front.2);
                }
                drop(front);
                if back {
                    // THE OPEN CHAT IS READ WHEN IT COMES BEFORE THE EYES (iOS markRead on the conversation's appearance): a letter
                    // that landed while the window stood behind is read once the window has stood in front for 0.8 s -- the web
                    // view's own «focus» is not told on every return (a window raised by the system or by Alt+Tab)
                    let app = w.app_handle().clone();
                    std::thread::spawn(move || {
                        std::thread::sleep(std::time::Duration::from_millis(800));
                        let (p, m) = (app.state::<Person>(), app.state::<Messenger>());
                        let Some(chat) = m.open.lock().unwrap().clone() else { return };
                        if !m.front.lock().unwrap().0 || m.book.chat(&chat).is_none_or(|c| c.unread == 0) {
                            return;
                        }
                        if let Some(d) = m.desk(&p) {
                            d.mark_read(&chat);
                            changed(&app);
                        }
                    });
                    auto_fire("active", false);   // iOS MTWalletScreen: scenePhase active -- if !pantheon.lit { autoMint.fire() }
                    tip::ask("active");   // their tips first, in one round trip (iOS ContentView, scenePhase)
                    coinvault::soon("active", 1.0);   // the seed's other devices, gathered at the return
                }
            }
            // closing the window hides it: the walk goes on, letters land and ring; the tray brings it back or quits
            if let tauri::WindowEvent::CloseRequested { api, .. } = e {
                if w.label() == "main" {
                    api.prevent_close();
                    let _ = w.hide();
                    person_left(w.app_handle());
                }
            }
            // folded into the taskbar: the window left the person as a hidden one does (iOS: the app in the background)
            if let tauri::WindowEvent::Resized(_) = e {
                if w.label() == "main" && w.is_minimized().unwrap_or(false) {
                    person_left(w.app_handle());
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            core_info,
            identity_state,
            identity_create,
            identity_restore,
            identity_copy_words,
            identity_set_name,
            identity_accept_terms,
            chats,
            chat_open,
            chat_send,
            chat_read,
            chat_focus,
            chat_delete,
            chat_forward,
            group_create,
            call_begin,
            call_post,
            call_heard,
            call_end,
            call_buried,
            call_hold,
            call_held,
            call_unhold,
            keep_state,
            node_lamp,
            share_chains,
            coin_key,
            system_currency,
            chain_files,
            bar_first,
            keep_do,
            gif_search,
            gif_get,
            card_get,
            card_set,
            ground_keep,
            ground_forget,
            ground_page_set,
            peer_ground,
            vpn_state,
            p2p_wall,
            app_icon,
            timechains,
            music_state,
            music_folder_add,
            music_track,
            track_meta,
            share_text,
            share_file,
            vpn_add,
            vpn_do,
            seats_state,
            seat_switch,
            seat_add,
            seat_return,
            wallet_state,
            wallet_tap,
            wallet_touch,
            wallet_pull,
            coin_send,
            coin_send_own,
            home_node_state,
            home_node_setup,
            home_node_host,
            home_node_switch,
            home_node_send,
            home_node_take_back,
            home_files_state,
            home_files_keep,
            cache_clear,
            cache_term,
            media_look,
            media_board,
            disk_use,
            disk_clear,
            copy_inventory,
            copy_pages,
            copy_plan_set,
            copy_remove,
            wall_state,
            wall_feed,
            wall_file_put,
            wall_post,
            wall_draft,
            wall_draft_set,
            wall_open,
            wall_find,
            wall_file,
            wall_do,
            wall_rules,
            wall_rule_set,
            recording_keep,
            callsigns,
            passwords_open,
            passwords_save,
            passwords_remove,
            passwords_lock,
            password_code,
            password_fresh,
            password_copy,
            secret_send,
            secret_take,
            stickers_state,
            sticker_add,
            sticker_adopt,
            sticker_forget,
            sticker_send,
            sticker_ask,
            sticker_passport,
            turn_cred,
            route_key,
            trace,
            room_state,
            room_open,
            room_join,
            room_do,
            room_send,
            room_invitable,
            room_grow,
            room_grown,
            room_take_inline,
            room_grow_people,
            calls_log,
            calls_missed,
            calls_seen,
            group_info,
            group_add,
            group_remove,
            group_leave,
            group_rename,
            group_face,
            link_card,
            link_picture,
            chat_card,
            open_link,
            channel_set,
            channel_comment,
            channel_comments,
            channel_reactions,
            group_set_admin,
            group_set_approval,
            group_set_history,
            chess_letters,
            peer_rename,
            folders_get,
            folders_set,
            group_request,
            group_set_rights,
            group_kick,
            group_refusal,
            group_link,
            chat_pin,
            search,
            chat_edit,
            chat_react,
            chat_erase,
            chat_erase_terms,
            pull_refresh,
            copy_text,
            chat_flag,
            chat_kept_draft,
            chat_keep_draft,
            chat_block,
            blocked_list,
            report,
            chat_typing,
            group_typing,
            presence,
            chat_send_media,
            chat_big_begin,
            levels_state,
            coin_badges,
            chat_coin,
            money_flow,
            chat_draft,
            play_quiet,
            protocol_core,
            coin_rate_set,
            coin_moves_all,
            auto_react,
            coins_shown,
            levels_set,
            picture_png,
            chat_big_piece,
            chat_big_end,
            media_get,
            media_want,
            media_open,
            chat_send_voice,
            face_get,
            face_set,
            settings_get,
            setting_set,
            seed_reveal,
            account_delete,
            peer_about,
            media_list,
            history_copy,
            history_restore,
            card,
            card_copy,
            meet,
            open_site
        ])
        .run(context)
        .expect("Montana could not start its window");
}
