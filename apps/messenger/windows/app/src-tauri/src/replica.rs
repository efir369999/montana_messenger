//! THIS COMPUTER'S COPY OF THE NETWORK'S CHAINS (iOS MTCoinReplica, Audit/COIN-TX-V3.md section 6): once in ten minutes, with the
//! consent to keep for others, what each chain node took since the last round is pulled and kept; every chain is folded from its
//! first record by the chain's own rules (cointx::step, the nodes' _tx_step), a RECV after the SEND it settles; the root of the
//! nodes' newest checkpoint is computed here and signed with the seed's coin key at both nodes. The person's own chain as this copy
//! folded it reaches the wallet before the node's word (wallet::heard_copy).

use crate::cointx::{self, Hands, Kind, Rec, SendInfo, St, CHAIN_NODES, ZERO};
use crate::vault::Vault;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

#[derive(Clone, Serialize, Deserialize)]
pub struct Row {
    pub id: String,
    pub rec: String,
    pub at: i64,
    pub node: String,
}
/// at: the moment of the last round, kept with the rows -- a process born anew has nothing in memory. known: the names of the rows
/// whose signature verified here once.
#[derive(Default, Serialize, Deserialize)]
struct Held {
    #[serde(default)]
    seq: BTreeMap<String, i64>,
    #[serde(default)]
    rows: Vec<Row>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    at: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    known: Option<Vec<String>>,
}

fn place(vault: &Vault) -> Option<std::path::PathBuf> {
    Some(vault.dir().parent()?.join("TimeChain").join("coin-replica.json"))
}
fn load(vault: &Vault) -> Held {
    place(vault).and_then(|p| std::fs::read(p).ok()).and_then(|d| serde_json::from_slice(&d).ok()).unwrap_or_default()
}
fn save(vault: &Vault, h: &Held) {
    let (Some(p), Ok(d)) = (place(vault), serde_json::to_vec(h)) else { return };
    if let Some(dir) = p.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let tmp = p.with_extension("json.tmp");
    if std::fs::write(&tmp, d).is_ok() {
        let _ = std::fs::rename(&tmp, &p);
    }
}

#[derive(Default)]
pub struct Folded {
    pub keys: usize,
    pub records: usize,
    pub root: String,
    pub bad: usize,
    pub waiting: usize,
    pub mine: Option<St>,
    pub verified: HashSet<String>,
}

/// Every chain folded from its first record in its own order (prev), a RECV after the SEND it settles; then the root of the
/// checkpoint T exactly as the node computes it (section 6): for every key in ascending from, its last record and its count at T.
pub fn fold(rows: &[Row], t: i64, me: Option<&str>, known: &HashSet<String>) -> Folded {
    let mut out = Folded::default();
    let mut by_prev: HashMap<String, HashMap<String, Rec>> = HashMap::new();
    let mut at_of: HashMap<String, i64> = HashMap::new();
    let mut seen = HashSet::new();
    for row in rows {
        if !seen.insert(row.id.as_str()) {
            continue;
        }
        let read = crate::wire::unb64(&row.rec).and_then(|d| cointx::read_known(&d, known.contains(&row.id)));
        let Some(r) = read.filter(|r| r.id == row.id) else {
            out.bad += 1;
            continue;
        };
        out.verified.insert(r.id.clone());
        if r.version == 1 {
            continue; // a version 1 row stands on no chain
        }
        if cointx::chain_node(&r.from) != Some(row.node.as_str()) {
            out.bad += 1; // a node serves only its own chains
            continue;
        }
        at_of.insert(r.id.clone(), row.at);
        by_prev.entry(r.from.clone()).or_default().insert(r.prev.clone(), r);
    }
    let mut st: HashMap<String, St> = HashMap::new();
    let (mut sends, mut settled, mut broken) = (HashMap::<String, SendInfo>::new(), HashSet::<String>::new(), HashSet::<String>::new());
    let mut order: HashMap<String, Vec<String>> = HashMap::new();
    let mut moved = true;
    while moved {
        moved = false;
        for (from, chain) in &by_prev {
            if broken.contains(from) {
                continue;
            }
            let mut s = st.get(from).cloned().unwrap_or_else(St::new);
            while let Some(r) = chain.get(&s.head) {
                let at = at_of.get(&r.id).copied().unwrap_or(0);
                let (next, wait) = cointx::step(&s, r, at, &sends, &settled);
                if wait {
                    break;
                }
                let Some(n) = next else {
                    broken.insert(from.clone());
                    out.bad += 1;
                    break;
                };
                if r.version == 3 && r.kind == Kind::Send as u8 {
                    sends.insert(r.id.clone(), SendInfo { from: from.clone(), amount: r.amount as i64, at, to: r.to.clone(), dec: r.a as i64 });
                }
                if r.version == 2 {
                    if let Some(d) = cointx::v2_spent(&s, r.amount as i64) {
                        sends.insert(r.id.clone(), SendInfo { from: from.clone(), amount: r.amount as i64, at, to: vec![0; 32], dec: d });
                    }
                }
                if r.version == 3 && (r.kind == Kind::Recv as u8 || r.kind == Kind::Refund as u8) {
                    settled.insert(r.refr.clone());
                }
                order.entry(from.clone()).or_default().push(r.id.clone());
                s = n;
                moved = true;
            }
            st.insert(from.clone(), s);
        }
    }
    for (from, chain) in &by_prev {
        if !broken.contains(from) && chain.contains_key(st.get(from).map(|s| s.head.as_str()).unwrap_or(ZERO)) {
            out.waiting += 1;
        }
    }
    if let Some(me) = me.filter(|m| !broken.contains(*m)) {
        out.mine = st.get(me).cloned();
    }
    let mut froms: Vec<&String> = order.keys().collect();
    froms.sort();
    let mut keys = vec![];
    for from in froms {
        let ids: Vec<&String> = order[from].iter().filter(|id| at_of.get(*id).copied().unwrap_or(i64::MAX) <= t).collect();
        let (Some(last), Some(f)) = (ids.last(), cointx::unhex32(from)) else { continue };
        let Some(l) = cointx::unhex32(last) else { continue };
        keys.push((f, l, ids.len() as u64));
        out.keys += 1;
        out.records += ids.len();
    }
    out.root = cointx::root(&mut keys);
    out
}

static RUNNING: AtomicBool = AtomicBool::new(false);
static RAN_AT: Mutex<f64> = Mutex::new(0.0);
fn now_s() -> f64 {
    crate::wire::now_ms() as f64 / 1000.0
}
/// Whether a round may start: none runs, and ten minutes passed since this process's last.
pub fn due() -> bool {
    !RUNNING.load(Ordering::SeqCst) && 600.0 <= now_s() - *RAN_AT.lock().unwrap()
}

/// One round: what each chain node took since the last round, the whole fold, the root of the nodes' newest checkpoint computed
/// here and signed with the seed's coin key at both nodes. Once in ten minutes at most, only with the consent to keep for others.
pub fn run(vault: &Vault, h: &Hands, why: &str) {
    if !crate::keeping::others_in(vault) || !due() || RUNNING.swap(true, Ordering::SeqCst) {
        return;
    }
    *RAN_AT.lock().unwrap() = now_s();
    round(vault, h, why);
    RUNNING.store(false, Ordering::SeqCst);
}

fn round(vault: &Vault, h: &Hands, why: &str) {
    let mut held = load(vault);
    // ONCE IN TEN MINUTES ACROSS PROCESSES (iOS 23.10.2026): the round's moment stands in the file it folds, so a process born anew
    // does not pull and fold the whole network again
    if now_s() - held.at.unwrap_or(0.0) < 600.0 {
        return;
    }
    held.at = Some(now_s());
    let mut pulled = 0;
    // each node through any door of its machine, as the chain's own asks go (iOS chainDoor): a machine whose api name this network
    // does not reach is read through its other doors
    for (name, host) in CHAIN_NODES {
        let door = format!("https://{host}/pushwake");
        let mut since = held.seq.get(name).copied().unwrap_or(0);
        for _ in 0..64 {
            let (code, o) = crate::doors::post_machine(&door, "/tx-since", &json!({ "since": since }), 60_000);
            let Some(txs) = o.as_ref().filter(|_| code == 200).and_then(|o| o["txs"].as_array()) else { break };
            for x in txs {
                let (Some(id), Some(rec), Some(seq)) = (x["id"].as_str(), x["rec"].as_str(), x["seq"].as_i64()) else { continue };
                held.rows.push(Row { id: id.into(), rec: rec.into(), at: x["at"].as_i64().unwrap_or(0), node: name.into() });
                since = since.max(seq);
                pulled += 1;
            }
            held.seq.insert(name.into(), since);
            if txs.len() < 512 {
                break;
            }
        }
    }
    save(vault, &held);
    let me = h.from();
    let Some(door) = cointx::chain_door(&me) else { return };
    let (code, r) = crate::wallet::ask(&door, "/tx-root", &json!({}));
    let (Some(t), Some(node_root)) = (r.as_ref().filter(|_| code == 200).and_then(|o| o["at"].as_i64()),
                                      r.as_ref().and_then(|o| o["root"].as_str().map(String::from))) else {
        mark(&format!("why={why} pulled={pulled} rows={} no checkpoint code={code}", held.rows.len()));
        return;
    };
    let known: HashSet<String> = held.known.clone().unwrap_or_default().into_iter().collect();
    let f = fold(&held.rows, t, Some(&me), &known);
    if f.verified != known {
        let mut v: Vec<String> = f.verified.iter().cloned().collect();
        v.sort();
        held.known = Some(v);
        save(vault, &held);
    }
    // the person's own chain as this copy folded it: the wallet's split hears it before the node's word (iOS MTCoinSplit)
    if f.bad == 0 {
        if let Some(mine) = &f.mine {
            crate::wallet::heard_copy(mine, t);
        }
    }
    let mut signed = 0;
    if let (0, true, Some(root)) = (f.bad, 0 < f.keys, cointx::unhex32(&f.root)) {
        let msg = [b"mt-coin-root-sig-v1".as_slice(), &(t as u64).to_le_bytes(), &root].concat();
        if let Some(sig) = h.sign(&msg) {
            for (_, host) in CHAIN_NODES {
                let body = json!({ "pk": crate::wire::b64(&h.pk), "at": t, "root": f.root, "sig": crate::wire::b64(&sig) });
                if crate::doors::post_machine(&format!("https://{host}/pushwake"), "/tx-root-sign", &body, 15_000).0 == 200 {
                    signed += 1;
                }
            }
        }
    }
    mark(&format!("why={why} keys={} records={} pulled={pulled} bad={} waiting={} T={t} root={} same={} signed={signed}", f.keys, f.records, f.bad,
                  f.waiting, f.root.get(..12).unwrap_or(""), (f.root == node_root) as u8));
}

fn mark(line: &str) {
    crate::trace_line(&format!("coin_replica {line}"));
}

#[cfg(test)]
mod tests {
    use super::*;

    /// THE NETWORK'S CHAINS FOLDED HERE (read only, no signature laid): every row both nodes hold pulled, folded by the chain's
    /// rules; no row is bad, and the root of the nodes' newest checkpoint computed here is the node's own when both nodes answer;
    /// each key the fold holds stands on the head its node tells.
    #[test]
    #[ignore]
    fn the_copy_of_the_chains_folds_to_the_nodes_root() {
        if std::env::var("MONTANA_LIVE").is_err() {
            return;
        }
        let mut rows = vec![];
        let mut answered = vec![];
        for (name, host) in CHAIN_NODES {
            let door = format!("https://{host}/pushwake");
            let mut since = 0;
            let mut got = false;
            for _ in 0..64 {
                let (code, o) = crate::doors::post_machine(&door, "/tx-since", &json!({ "since": since }), 60_000);
                let Some(txs) = o.as_ref().filter(|_| code == 200).and_then(|o| o["txs"].as_array()) else { break };
                got = true;
                for x in txs {
                    rows.push(Row { id: x["id"].as_str().unwrap().into(), rec: x["rec"].as_str().unwrap().into(), at: x["at"].as_i64().unwrap_or(0), node: name.into() });
                    since = since.max(x["seq"].as_i64().unwrap());
                }
                if txs.len() < 512 {
                    break;
                }
            }
            eprintln!("{name}: {}", if got { "answered" } else { "silent" });
            if got {
                answered.push((name, door));
            }
        }
        assert!(!answered.is_empty(), "no chain node answers");
        let (_, door) = &answered[0];
        let (code, r) = crate::doors::post_machine(door, "/tx-root", &json!({}), 30_000);
        assert_eq!(code, 200);
        let r = r.unwrap();
        let t = r["at"].as_i64().unwrap();
        let started = std::time::Instant::now();
        let f = fold(&rows, t, None, &HashSet::new());
        eprintln!("rows={} keys={} records={} bad={} waiting={} verified in {:?}", rows.len(), f.keys, f.records, f.bad, f.waiting, started.elapsed());
        assert_eq!(f.bad, 0, "every row reads, verifies and folds");
        assert_eq!(f.verified.len(), rows.iter().map(|r| &r.id).collect::<HashSet<_>>().len());
        // the names verified once are not verified again, and the fold is the same
        let again = fold(&rows, t, None, &f.verified);
        assert_eq!((again.root.as_str(), again.bad), (f.root.as_str(), 0));
        if answered.len() == CHAIN_NODES.len() {
            assert_eq!(f.root, r["root"].as_str().unwrap(), "the root computed here is the node's");
            assert_eq!((f.keys as i64, f.records as i64), (r["keys"].as_i64().unwrap(), r["records"].as_i64().unwrap()));
        } else {
            eprintln!("one node silent: the root is not compared ({} here, {} the node's)", f.root, r["root"]);
        }
        // the heads the fold reached are the heads the nodes tell, key by key, for the keys of the nodes that answered
        let mut heads = std::collections::BTreeSet::new();
        for row in &rows {
            heads.insert(cointx::read_known(&crate::wire::unb64(&row.rec).unwrap(), true).unwrap().from);
        }
        let mut st_of: HashMap<String, St> = HashMap::new();
        for from in &heads {
            if let Some(s) = fold(&rows, t, Some(from), &f.verified).mine {
                st_of.insert(from.clone(), s);
            }
            if st_of.len() >= 12 {
                break;
            }
        }
        for (from, s) in &st_of {
            let door = cointx::chain_door(from).unwrap();
            let (code, o) = crate::wallet::ask(&door, "/tx-head", &json!({ "from": from }));
            if code != 200 {
                continue;
            }
            let o = o.unwrap();
            let height = o["height"].as_str().and_then(|s| s.parse().ok()).or_else(|| o["height"].as_i64()).unwrap_or(-1);
            // a key that laid a record after the pull stands higher at its node
            if height == s.height {
                assert_eq!(s.head, o["head"].as_str().unwrap(), "key {from}");
            } else {
                assert!(s.height < height, "key {from}: {} here, {height} at the node", s.height);
            }
        }
        eprintln!("heads compared: {}", st_of.len());
    }
}
