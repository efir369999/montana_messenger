//! THE DOORS OF THE NETWORK (iOS nodes.txt, MontanaNodes and MontanaWakePush; Android Doors.kt, MontanaCard.doors): the nodes'
//! /pushwake doors. The network names its machines and each one's doors (/pushwake/doors): every door of a machine opens the
//! same boxes and blobs, so a read asks one living door of each machine -- a letter lies on the one machine its writer
//! elected -- and a write goes to the first door that takes it, the one that answered last first (iOS writeOrder). A wss door's
//! host answers /pushwake too, its HTTP face (Android accel_paths): a machine whose own door is out of reach is read through it.

use crate::http;
use crate::wire::{b64, unb64};
use serde_json::{json, Value};
use std::sync::Mutex;

/// The shipped list (iOS nodes.txt; Android MontanaCard.doors): the two machines, each with its door and its door's HTTP face,
/// as the network names them -- the list a read goes by until the network's own answer comes (a door out of reach leaves the
/// machine its other door).
pub const SHIPPED: [(&str, [&str; 2]); 2] = [
    ("mow", ["https://api.montana.quest/pushwake", "https://door.montana.quest/pushwake"]),
    ("ams", ["https://montana.xxx/pushwake", "https://door.montana.xxx/pushwake"]),
];

/// The channels' doors as shipped (iOS nodes.txt, line for line): the first doors dialled before the network named any other.
const SHIPPED_CHANNEL: &str = "api.montana.quest:443\nmontana.xxx:443\nwss://door.montana.quest/ws";
/// The channels' doors as the network named them (iOS MontanaNodes.learn: the answer's «doors», «host:port» and «wss://host/path»).
static LEARNED: Mutex<Vec<String>> = Mutex::new(Vec::new());

static LAST_GOOD: Mutex<Option<String>> = Mutex::new(None);
type Machine = (String, Vec<String>);
/// The machines as the network named them, each with its HTTP doors, and when it was asked (s); empty -- the shipped list.
static MACHINES: Mutex<(Vec<Machine>, i64)> = Mutex::new((Vec::new(), 0));
/// THE BARRED (iOS MontanaSafety.setBarred, Guideline 1.2): the addresses the network's operators barred after a report ride
/// the same answer; every install refuses their letters and calls on every road, as a blocked one's.
static BARRED: Mutex<Vec<String>> = Mutex::new(Vec::new());
const RELEARN_S: i64 = 3600;
const ASK_AGAIN_S: i64 = 300;
/// door -> (failures in a row, resting until (s), the rest it was given (s))
static HEALTH: Mutex<Vec<(String, u32, i64, i64)>> = Mutex::new(Vec::new());

/// A CHECK'S OWN NODE (MONTANA_TEST_DOOR, read only in a check's run -- MONTANA_DATA_DIR set, as the clock's shift in wire.rs): a node
/// put up on this computer for a check (tools/clocknode.py: the original's montana-home-node.py on a clock of the check's own),
/// the only door the client knows -- the network is never asked. Loopback only; never in the person's program.
pub fn test_door() -> Option<&'static str> {
    static DOOR: std::sync::OnceLock<Option<String>> = std::sync::OnceLock::new();
    DOOR.get_or_init(|| {
        std::env::var_os("MONTANA_DATA_DIR")?;
        std::env::var("MONTANA_TEST_DOOR").ok().map(|d| d.trim().trim_end_matches('/').to_string())
            .filter(|d| d.starts_with("http://127.0.0.1:") || d.starts_with("https://127.0.0.1:"))
    }).as_deref()
}

fn now_s() -> i64 {
    crate::wire::now_ms() / 1000
}

fn resting(d: &str) -> bool {
    HEALTH.lock().unwrap().iter().any(|(x, _, until, _)| x == d && *until > now_s())
}

/// Doors in the order they are tried: the one that answered last, then the living ones by their failures in a row (a door
/// never tried stands before one that failed), the resting ones last; else the network's order.
fn ordered(doors: &[String]) -> Vec<String> {
    let good = LAST_GOOD.lock().unwrap().clone();
    let h = HEALTH.lock().unwrap().clone();
    let now = now_s();
    let mut v = doors.to_vec();
    v.sort_by_key(|d| {
        let e = h.iter().find(|(x, ..)| x == d);
        (good.as_ref() != Some(d), e.is_some_and(|e| e.2 > now), e.map_or(0, |e| e.1))
    });
    v
}

/// A door of the network's list as the HTTP door it opens: «host:443» and «wss://host/ws» both -- https://host/pushwake.
fn http_of(door: &str) -> Option<String> {
    let host = door.strip_prefix("wss://").map(|r| r.split('/').next().unwrap_or("")).unwrap_or_else(|| door.split(':').next().unwrap_or(""));
    let ok = !host.is_empty() && host.len() <= 253 && host.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-');
    ok.then(|| format!("https://{}/pushwake", host.to_ascii_lowercase()))
}

/// The machines of the network's answer (iOS MontanaNodes.machines): each id with its HTTP doors, in the network's order.
fn machines_of(v: &Value) -> Vec<(String, Vec<String>)> {
    let mut out = vec![];
    for n in v["nodes"].as_array().into_iter().flatten().take(32) {
        let id = n["id"].as_str().unwrap_or("").chars().take(32).collect::<String>();
        let mut doors: Vec<String> = n["doors"].as_array().into_iter().flatten().filter_map(|d| d.as_str()).filter_map(http_of).collect();
        doors.dedup();
        if !id.is_empty() && !doors.is_empty() {
            out.push((id, doors));
        }
    }
    out
}

/// The doors of the network's answer as written (its «doors»): the channels dial these, not their HTTP faces.
fn learned_of(v: &Value) -> Vec<String> {
    v["doors"].as_array().into_iter().flatten().filter_map(|d| d.as_str()).take(64).map(str::to_string).collect()
}

/// iOS MontanaNodes.parse 180-223: a comment goes by the line, a line may carry several doors (a comma or a space between), and a
/// door is named once.
fn parse_doors(raw: &str) -> Vec<crate::channel::Door> {
    let mut out: Vec<crate::channel::Door> = vec![];
    for line in raw.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with('#')) {
        for d in line.split([',', ' ']).filter_map(crate::channel::Door::parse) {
            if !out.contains(&d) {
                out.push(d);
            }
        }
    }
    out
}

/// THE CHANNELS' DOORS (iOS MontanaNodes.list 225-235): the network's list once learned, else the shipped one.
pub fn channel_doors() -> Vec<crate::channel::Door> {
    if test_door().is_some() {
        return vec![]; // a check's own node carries the boxes, the blobs and the signals; no channel of the network
    }
    learn();
    let net = parse_doors(&LEARNED.lock().unwrap().join("\n"));
    if net.is_empty() { parse_doors(SHIPPED_CHANNEL) } else { net }
}

/// The barred addresses of the network's answer: trimmed, none empty.
fn barred_of(v: &Value) -> Vec<String> {
    v["barred"].as_array().into_iter().flatten().take(100_000).filter_map(|b| b.as_str()).map(|b| b.trim().to_string())
        .filter(|b| !b.is_empty() && b.len() <= 256).collect()
}

/// A correspondence the network barred: refused like a blocked one.
pub fn barred(reference: &str) -> bool {
    BARRED.lock().unwrap().iter().any(|b| b == reference)
}

/// THE NETWORK ASKED FOR ITS MACHINES (iOS MontanaNodes.refresh): /pushwake/doors of the first door that answers; asked again
/// within the hour, and five minutes after a failure. The shipped list stands until an answer comes.
fn learn() {
    let now = now_s();
    {
        let mut m = MACHINES.lock().unwrap();
        let due = if m.0.is_empty() { ASK_AGAIN_S } else { RELEARN_S };
        if now - m.1 < due {
            return;
        }
        m.1 = now; // one asker at a time: the others go on with what stands
    }
    if cfg!(test) && std::env::var_os("MONTANA_LIVE").is_none() {
        return; // the unit tests stay off the network
    }
    let known: Vec<String> = MACHINES.lock().unwrap().0.iter().flat_map(|(_, d)| d.clone()).collect();
    let shipped: Vec<String> = ordered(&SHIPPED.iter().flat_map(|(_, d)| d.iter().map(|s| s.to_string())).collect::<Vec<_>>());
    for door in shipped.into_iter().chain(known) {
        let Some((200, body)) = http::get(&format!("{door}/doors"), 8_000, 64 * 1024, false) else {
            failed(&door); // a door that did not answer is not the first asked next
            continue;
        };
        let Ok(v) = serde_json::from_slice::<Value>(&body) else { continue };
        let found = machines_of(&v);
        if v["barred"].is_array() {
            *BARRED.lock().unwrap() = barred_of(&v);
        }
        if !learned_of(&v).is_empty() {
            *LEARNED.lock().unwrap() = learned_of(&v);
        }
        if !found.is_empty() {
            *MACHINES.lock().unwrap() = (found, now);
            return;
        }
    }
}

/// The machines and their doors: the network's, or the shipped list, one door a machine.
fn machines() -> Vec<(String, Vec<String>)> {
    if let Some(d) = test_door() {
        return vec![("test".into(), vec![d.to_string()])];
    }
    learn();
    let m = MACHINES.lock().unwrap().0.clone();
    if m.is_empty() {
        SHIPPED.iter().map(|(id, d)| (id.to_string(), d.iter().map(|s| s.to_string()).collect())).collect()
    } else {
        m
    }
}

/// A door as the P2P wall shows it (iOS MontanaNodes.state): open -- it answered first of its machine; spare -- it answered, its
/// machine held already by a faster door; lost -- it answered before and rests now after its failures; silent -- no answer.
#[derive(serde::Serialize, Debug, Clone)]
pub struct DoorSeen {
    pub label: String,
    pub ms: Option<u64>,
    pub state: &'static str,
}
#[derive(serde::Serialize, Debug, Clone)]
pub struct MachineSeen {
    pub id: String,
    pub held: bool,
    pub doors: Vec<DoorSeen>,
}

/// THE NODES THIS COMPUTER REACHES (iOS NetworkTabView's P2P tab, MontanaNodes.live): every door of every machine asked at once
/// for the network's list of doors, each answer timed; a machine is held when one of its doors answered.
pub fn wall() -> Vec<MachineSeen> {
    let ms = machines();
    let probes: Vec<(usize, String, std::thread::JoinHandle<Option<u64>>)> = ms.iter().enumerate().flat_map(|(i, (_, doors))| {
        doors.iter().map(move |d| {
            let door = d.clone();
            (i, d.clone(), std::thread::spawn(move || {
                let t0 = std::time::Instant::now();
                match http::get(&format!("{door}/doors"), 8_000, 64 * 1024, false) {
                    Some((200, _)) => Some(t0.elapsed().as_millis() as u64),
                    _ => None,
                }
            }))
        }).collect::<Vec<_>>()
    }).collect();
    let mut out: Vec<MachineSeen> = ms.iter().map(|(id, _)| MachineSeen { id: id.clone(), held: false, doors: vec![] }).collect();
    let health = HEALTH.lock().unwrap().clone();
    for (i, door, h) in probes {
        let ms = h.join().ok().flatten();
        let label = door.trim_start_matches("https://").trim_end_matches("/pushwake").to_string();
        let failed_before = health.iter().any(|(x, n, ..)| *x == door && *n > 0);
        let state = match ms {
            Some(_) => "open",
            None if failed_before => "lost",
            None => "silent",
        };
        out[i].doors.push(DoorSeen { label, ms, state });
    }
    for m in &mut out {
        // the fastest door of a machine is its open one; another that answered is its spare
        m.doors.sort_by_key(|d| d.ms.unwrap_or(u64::MAX));
        let mut first = true;
        for d in &mut m.doors {
            if d.state == "open" {
                if !first {
                    d.state = "spare";
                }
                first = false;
            }
        }
        m.held = !first;
    }
    out
}

/// The doors in the order a write tries them: the last that answered, the living ones; a resting door only when every door
/// rests (iOS writeOrder).
pub fn write_order() -> Vec<String> {
    let all = ordered(&machines().into_iter().flat_map(|(_, d)| d).collect::<Vec<_>>());
    let (live, rest): (Vec<String>, Vec<String>) = all.into_iter().partition(|d| !resting(d));
    if live.is_empty() { rest } else { live }
}

/// THE MACHINE BEHIND A DOOR, AT ANY OF ITS DOORS (iOS MTCoinTx.chainDoor's own word: «its node through the api door when the phone
/// knows it, else through any door of that node the phone holds»): the doors of the machine that names `door` among its own, in
/// the order they are tried; the named door alone when no machine names it.
pub fn of_machine(door: &str) -> Vec<String> {
    machines().into_iter().find(|(_, d)| d.iter().any(|x| x == door)).map(|(_, d)| ordered(&d)).unwrap_or_else(|| vec![door.to_string()])
}

/// One ask of the machine behind `door`, at its doors in the order they are tried until one answers.
pub fn post_machine(door: &str, path: &str, body: &Value, timeout_ms: u32) -> (i32, Option<Value>) {
    let mut last = (-1, None);
    for d in of_machine(door) {
        last = post_at(&d, path, body, timeout_ms);
        if last.0 != -1 {
            break;
        }
    }
    last
}

/// One door of each machine, for a read: the first in the order they are tried (a resting one only when the machine has no
/// other).
pub fn all() -> Vec<String> {
    machines().into_iter().filter_map(|(_, doors)| ordered(&doors).into_iter().next()).collect()
}

/// A READ OF EVERY MACHINE (a letter lies on the one machine its writer elected): each machine asked at its doors in the order
/// they are tried until one answers -- a door out of reach gives the read to the next door of the same machine at once, so a
/// read made once (the light copy after the words) still reaches every machine. `take` hears each machine's answer and says
/// whether the read is done (a blob found on one machine is not asked of the next).
pub fn read_machines(path: &str, body: &Value, timeout_ms: u32, mut take: impl FnMut(i32, Option<Value>) -> bool) {
    for (_, doors) in machines() {
        let mut last = (-1, None);
        for d in ordered(&doors) {
            last = post_at(&d, path, body, timeout_ms);
            if last.0 > 0 && last.0 < 500 {
                break;
            }
        }
        if take(last.0, last.1) {
            return;
        }
    }
}

/// Every machine's answer to a read, one a machine.
pub fn read_each(path: &str, body: &Value, timeout_ms: u32) -> Vec<(i32, Option<Value>)> {
    let mut out = vec![];
    read_machines(path, body, timeout_ms, |code, v| {
        out.push((code, v));
        false
    });
    out
}

/// Any answer below 500 -- a 404, a 429 too -- says the door lives (iOS: revived).
fn answered(door: &str, code: i32) {
    if code == 200 {
        *LAST_GOOD.lock().unwrap() = Some(door.to_string());
    }
    HEALTH.lock().unwrap().retain(|(d, ..)| d != door);
}

/// DOOR DEATH (iOS MontanaWakePush 318-347): two failures in a row -- no answer, or a 5xx -- put the door at rest for a
/// minute, doubling each time up to eight; the walks go round it meanwhile.
fn failed(door: &str) {
    let mut h = HEALTH.lock().unwrap();
    let now = now_s();
    match h.iter_mut().find(|(d, ..)| d == door) {
        Some(e) => {
            e.1 += 1;
            if e.1 >= 2 && e.2 <= now {
                e.3 = if e.3 == 0 { 60 } else { (e.3 * 2).min(480) };
                e.2 = now + e.3;
            }
        }
        None => h.push((door.to_string(), 1, 0, 0)),
    }
}

/// One POST to one door: the code and the JSON answer.
pub fn post_at(door: &str, path: &str, body: &Value, timeout_ms: u32) -> (i32, Option<Value>) {
    let (code, text) = http::post(&format!("{door}{path}"), &body.to_string(), timeout_ms);
    if code > 0 && code < 500 { answered(door, code) } else { failed(door) }
    (code, text.and_then(|t| serde_json::from_str(&t).ok()))
}

/// A write: the first door that answers 200 ends the walk.
pub fn write(path: &str, body: &Value, timeout_ms: u32) -> bool {
    write_order().iter().any(|d| post_at(d, path, body, timeout_ms).0 == 200)
}

/// A LETTER'S CARGO LIES ON EVERY MACHINE (iOS 2304 MontanaWakePush 1960-1969, MontanaBlobUpload.mirror; 20.10, T1 16:53Z): the first
/// door that answers 200 ends the write, and the same piece is laid on every other machine by one door of each, aside -- a node's
/// copy to its sibling rides the same broken road a reader may have, only the sender who just reached a machine can lay it on the
/// others. A failed copy costs the redundancy alone: the first machine holds the piece.
pub fn write_mirrored(path: &'static str, body: &Value, timeout_ms: u32) -> bool {
    let Some(took) = write_order().into_iter().find(|d| post_at(d, path, body, timeout_ms).0 == 200) else { return false };
    let others: Vec<String> = machines().into_iter().filter(|(_, ds)| !ds.contains(&took)).filter_map(|(_, ds)| ordered(&ds).into_iter().next()).collect();
    if !others.is_empty() {
        let body = body.clone();
        std::thread::spawn(move || {
            for d in others {
                let _ = post_at(&d, path, &body, timeout_ms);
            }
        });
    }
    true
}

/// A blob onto the node (iOS putBlob): POST /blob-put {bid, data, over}.
pub fn put_blob(bid: &str, data: &[u8]) -> bool {
    write("/blob-put", &json!({ "bid": bid, "data": b64(data), "over": true }), http::cargo_timeout_ms(data.len()))
}

/// A new blob onto the node, never laid over another (a long letter, a chunk): POST /blob-put {bid, data}.
pub fn put_new_blob(bid: &str, data: &[u8]) -> bool {
    write("/blob-put", &json!({ "bid": bid, "data": b64(data) }), http::cargo_timeout_ms(data.len()))
}

/// A blob of the node (iOS getBlob): POST /blob-get {bid} → {data}, from the first door that has it.
pub fn get_blob(bid: &str) -> Option<Vec<u8>> {
    for door in all() {
        let (code, v) = post_at(&door, "/blob-get", &json!({ "bid": bid }), http::POST_DEADLINE_MS);
        if code == 200 {
            if let Some(d) = v.as_ref().and_then(|v| v["data"].as_str()).filter(|s| !s.is_empty()).and_then(unb64) {
                return Some(d);
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{crypto, wire};

    #[test]
    fn the_networks_machines_and_their_http_doors() {
        let v: Value = serde_json::from_str(r#"{"doors": [], "nodes": [
            {"id": "mow", "doors": ["api.montana.quest:443", "wss://door.montana.quest/ws"]},
            {"id": "ams", "doors": ["api.montana.xxx:443", "wss://door.montana.xxx/ws"]},
            {"id": "bad", "doors": ["wss://evil host/ws"]}], "barred": []}"#).unwrap();
        let m = machines_of(&v);
        assert_eq!(m.len(), 2, "a machine with no door it can open is left out");
        assert_eq!(m[0], ("mow".to_string(), vec!["https://api.montana.quest/pushwake".to_string(), "https://door.montana.quest/pushwake".to_string()]));
        assert_eq!(m[1].1[1], "https://door.montana.xxx/pushwake", "a wss door's host is the machine's HTTP face too");
        assert!(barred_of(&v).is_empty());
        let b: Value = serde_json::from_str(r#"{"barred": [" mtA1 ", "", 7, "mtB2"]}"#).unwrap();
        assert_eq!(barred_of(&b), ["mtA1", "mtB2"], "the network's barred addresses, trimmed");
    }

    #[test]
    fn the_channels_doors_are_ios_nodes_txt_until_the_network_names_its_own() {
        let shipped: Vec<String> = parse_doors(SHIPPED_CHANNEL).iter().map(|d| d.label()).collect();
        assert_eq!(shipped, ["api.montana.quest:443", "montana.xxx:443", "wss/door.montana.quest:443"]);
        let ios = "# The doors: the first nodes a phone dials.\n# One per line: host:port (port 443) or a wss:// address\n\
                   api.montana.quest:443\nmontana.xxx:443\n\nwss://door.montana.quest/ws\n";
        assert_eq!(parse_doors(ios), parse_doors(SHIPPED_CHANNEL), "a comment goes by the line, not word by word");
        assert_eq!(parse_doors("a.test:9000, b.test a.test:9000").len(), 2, "several on a line, each named once");
        let v: Value = serde_json::from_str(r#"{"doors": ["api.montana.quest:443", "wss://door.montana.xxx/ws"]}"#).unwrap();
        assert_eq!(learned_of(&v), ["api.montana.quest:443", "wss://door.montana.xxx/ws"]);
    }

    #[test]
    fn a_door_that_failed_is_tried_after_one_never_tried() {
        let (a, b) = ("https://a.test/pushwake".to_string(), "https://b.test/pushwake".to_string());
        assert_eq!(ordered(&[a.clone(), b.clone()]), [a.clone(), b.clone()], "the network's order when nothing is known");
        failed(&a);
        assert_eq!(ordered(&[a.clone(), b.clone()]), [b.clone(), a.clone()]);
        answered(&a, 200);
        assert_eq!(ordered(&[b.clone(), a.clone()]), [a.clone(), b.clone()], "the one that answered last comes first");
        HEALTH.lock().unwrap().clear();
        *LAST_GOOD.lock().unwrap() = None;
    }

    /// The live network: a sealed blob laid on a node and fetched back. Run with --ignored (it speaks to Montana's nodes).
    #[test]
    #[ignore]
    fn a_blob_goes_onto_a_node_and_comes_back() {
        let key = crypto::random(32).unwrap();
        let sealed = crypto::seal(&key, b"montana-windows probe").unwrap();
        let bid = wire::hex(&wire::sha(&[&sealed]));
        assert!(put_blob(&bid, &sealed), "no door took the blob: {:?}", write_order());
        let back = get_blob(&bid).expect("no door gave the blob back");
        assert_eq!(crypto::open(&key, &back).as_deref(), Some(&b"montana-windows probe"[..]));
    }
}
