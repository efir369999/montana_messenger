//! THE CARD (iOS MontanaCard, MontanaFirstContact.swift; Android MontanaCard.kt): what the QR code and the shared link carry.
//! The link holds only an INVITATION -- 32 random bytes -- and the card lies on the node under it, sealed: the contact key
//! (ML-KEM-768, 1184 bytes) and the name of the one showing it. Whoever holds the link fetches the card, encapsulates to
//! the key once, and a correspondence exists; the key's secret half never leaves this machine. Byte for byte as iOS lays it.
//! Two kinds: the PERMANENT link, born once and kept; the TEMPORARY one of the day, turned 24 hours after its birth.

use crate::wire::{b64, b64url, domained, hex, now_ms, unb64, unb64url};
use crate::{crypto, doors, vault::Vault};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;
use std::sync::Mutex;

pub const PERM_PREFIX: &str = "https://montana.quest/perp/";
pub const TEMP_PREFIX: &str = "https://montana.quest/temp/";
const NAME_LIMIT: usize = 64;
const LIFETIME: f64 = 24.0 * 3600.0;
const PERM_MAGIC: &[u8] = b"mt-rdv-perm";
pub const SPENT_MAGIC: &[u8] = b"mt-rdv-spent";
// the records, sealed in the device vault under iOS's own names (MontanaLocalVault)
const KEYS: &str = "cardKeys";
const PERM: &str = "rdvPermanent";
const DAILY: &str = "rdvCards";
const CURRENT: &str = "rdvCurrent";
const BORN: &str = "rdvCurrentBorn";
const PERM_UP: &str = "rdvPermUpAt";
const DAILY_UP: &str = "rdvUpAt";
const TWIN: &str = "rdvTwin"; // the live cards the person's other devices gave birth to: inv -> {p, at} (iOS rdvTwin)
/// A sibling's card lives its own day and the receiving generation after it (iOS twinCardLife).
const TWIN_LIFE: f64 = 2.0 * LIFETIME + 3600.0;

pub fn rdv_key(inv: &[u8]) -> [u8; 32] {
    domained("mt-rdv-k", &[inv])
}
pub fn rdv_bid(inv: &[u8]) -> String {
    hex(&domained("mt-rdv-a", &[inv]))
}
pub fn perm_bid(inv: &[u8]) -> String {
    hex(&domained("mt-rdv-p", &[inv]))
}

fn now_s() -> f64 {
    now_ms() as f64 / 1000.0
}

pub struct Card<'a> {
    pub vault: &'a Vault,
}

static LOCK: Mutex<()> = Mutex::new(());

impl<'a> Card<'a> {
    fn map(&self, name: &str) -> BTreeMap<String, Vec<u8>> {
        let Some(raw) = self.vault.get(name) else { return BTreeMap::new() };
        let Ok(Value::Object(o)) = serde_json::from_slice::<Value>(&raw) else { return BTreeMap::new() };
        o.into_iter().filter_map(|(k, v)| v.as_str().and_then(unb64).map(|b| (k, b))).collect()
    }

    fn save(&self, name: &str, m: &BTreeMap<String, Vec<u8>>) -> bool {
        let o: Map<String, Value> = m.iter().map(|(k, v)| (k.clone(), Value::String(b64(v)))).collect();
        self.vault.set(name, Value::Object(o).to_string().as_bytes())
    }

    fn text(&self, name: &str) -> Option<String> {
        self.vault.get(name).and_then(|b| String::from_utf8(b).ok())
    }

    fn key_held(&self, payload: &[u8]) -> bool {
        payload.len() >= 1184 && self.map(KEYS).contains_key(&b64url(&payload[..1184]))
    }

    /// The card's body wears the profile's name of this moment (iOS reminted): the key, and the name after it.
    fn with_name(payload: &[u8], name: &str) -> Vec<u8> {
        let mut out = payload[..1184].to_vec();
        let n = name.trim().as_bytes();
        if !n.is_empty() && n.len() <= NAME_LIMIT {
            out.extend_from_slice(n);
        }
        out
    }

    /// A card minted from a fresh seed, its secret half kept (iOS offer(seed:)): the invitation and the payload.
    fn born(&self, name: &str) -> Option<(Vec<u8>, Vec<u8>)> {
        let seed = crypto::random(64)?;
        let inv = crypto::random(32)?;
        let (pk, sk) = crypto::mlkem_keypair(&seed)?;
        let mut keys = self.map(KEYS);
        keys.insert(b64url(&pk), sk);
        if !self.save(KEYS, &keys) {
            return None;
        }
        Some((inv, Self::with_name(&pk, name)))
    }

    fn due(&self, stamp: &str) -> bool {
        self.text(stamp).and_then(|s| s.parse::<f64>().ok()).is_none_or(|at| now_s() - at > 7200.0)
    }

    /// The card onto the node (and its stamp only on the node's ok), off the caller's thread.
    fn upload(&self, inv: Vec<u8>, payload: Vec<u8>, stamp: &'static str, perm: bool) {
        let Some(sealed) = crypto::seal(&rdv_key(&inv), &payload) else { return };
        let mark = if perm { crypto::seal(&rdv_key(&inv), PERM_MAGIC) } else { None };
        if cfg!(test) && std::env::var_os("MONTANA_LIVE").is_none() {
            return; // the unit tests stay off the network; the live tests (--ignored, MONTANA_LIVE=1) go up
        }
        let vault = self.vault.clone();
        std::thread::spawn(move || {
            let mut ok = doors::put_blob(&rdv_bid(&inv), &sealed);
            if !ok {
                std::thread::sleep(std::time::Duration::from_secs(20));
                ok = doors::put_blob(&rdv_bid(&inv), &sealed);
            }
            if let Some(m) = mark {
                doors::put_blob(&perm_bid(&inv), &m);
            }
            if ok {
                vault.set(stamp, format!("{}", now_s()).as_bytes());
            }
        });
    }

    /// THE PERMANENT LINK: born once, shown as long as the person keeps it, laid on the node again every two hours or at a rename.
    pub fn offer_permanent(&self, name: &str) -> Option<String> {
        let _g = LOCK.lock().unwrap();
        let perm = self.map(PERM);
        if let Some((inv64, payload)) = perm.iter().next() {
            if let (Some(inv), true) = (unb64url(inv64), self.key_held(payload)) {
                let np = Self::with_name(payload, name);
                let renamed = np != *payload;
                if renamed {
                    self.save(PERM, &BTreeMap::from([(inv64.clone(), np.clone())]));
                }
                if renamed || self.due(PERM_UP) {
                    self.upload(inv, np, PERM_UP, true);
                }
                return Some(format!("{PERM_PREFIX}{inv64}"));
            }
        }
        let (inv, payload) = self.born(name)?;
        let inv64 = b64url(&inv);
        self.save(PERM, &BTreeMap::from([(inv64.clone(), payload.clone())]));
        self.upload(inv, payload, PERM_UP, true);
        Some(format!("{PERM_PREFIX}{inv64}"))
    }

    /// THE LINK OF THE DAY: born exactly a day after the one before; the one before keeps receiving, older ones answer «spent».
    pub fn offer_short(&self, name: &str) -> Option<String> {
        let _g = LOCK.lock().unwrap();
        let mut daily = self.map(DAILY);
        let cur = self.text(CURRENT);
        let born_at = self.text(BORN).and_then(|s| s.parse::<f64>().ok());
        if let (Some(c), Some(b)) = (&cur, born_at) {
            if now_s() - b < LIFETIME {
                if let (Some(payload), Some(inv)) = (daily.get(c).cloned(), unb64url(c)) {
                    if self.key_held(&payload) {
                        if self.due(DAILY_UP) {
                            self.upload(inv, payload, DAILY_UP, false);
                        }
                        return Some(format!("{TEMP_PREFIX}{c}"));
                    }
                }
            }
        }
        let (inv, payload) = self.born(name)?;
        let inv64 = b64url(&inv);
        let mut keep = BTreeMap::new();
        if let Some(c) = &cur {
            if let Some(p) = daily.get(c) {
                keep.insert(c.clone(), p.clone()); // the receiving generation: its secret stays
            }
        }
        keep.insert(inv64.clone(), payload.clone());
        if !self.save(DAILY, &keep) || !self.vault.set(CURRENT, inv64.as_bytes()) || !self.vault.set(BORN, format!("{}", now_s()).as_bytes()) {
            // a card that did not settle is no card: the orphaned secret is taken back
            let mut keys = self.map(KEYS);
            keys.remove(&b64url(&payload[..1184]));
            self.save(KEYS, &keys);
            return None;
        }
        // yesterday's links answer «spent» at once; the generations older than the one before are buried whole
        let mut keys = self.map(KEYS);
        for (old64, pl) in std::mem::take(&mut daily) {
            if let Some(old) = unb64url(&old64) {
                if let Some(tomb) = crypto::seal(&rdv_key(&old), SPENT_MAGIC) {
                    std::thread::spawn(move || { doors::put_blob(&rdv_bid(&old), &tomb); });
                }
            }
            if Some(&old64) != cur.as_ref() {
                keys.remove(&b64url(&pl[..1184.min(pl.len())]));
            }
        }
        self.save(KEYS, &keys);
        self.upload(inv, payload, DAILY_UP, false);
        Some(format!("{TEMP_PREFIX}{inv64}"))
    }

    /// When the link of the day renews (ms): its birth and a day (iOS cardLifetimeSeconds).
    pub fn short_renews(&self) -> Option<i64> {
        self.text(BORN).and_then(|s| s.parse::<f64>().ok()).map(|b| ((b + LIFETIME) * 1000.0) as i64)
    }

    /// THE LIVE CARDS OF THIS MACHINE FOR THE PERSON'S OTHER DEVICES (iOS twinLiveCards): the day's and the permanent one,
    /// each with its secret -- {i, p, k} -- to ride the pipe only these words derive.
    pub fn live_cards(&self) -> Vec<(String, String)> {
        let _g = LOCK.lock().unwrap();
        let keys = self.map(KEYS);
        let daily = self.map(DAILY);
        let mut out = vec![];
        let cur = self.text(CURRENT).and_then(|c| daily.get(&c).map(|p| (c, p.clone())));
        for (inv, p) in cur.into_iter().chain(self.map(PERM)) {
            let Some(sk) = p.get(..1184).and_then(|root| keys.get(&b64url(root))) else { continue };
            out.push((inv.clone(), json!({ "i": inv, "p": b64(&p), "k": b64(sk) }).to_string()));
        }
        out
    }

    /// A SIBLING'S CARD TAKEN (iOS takeTwin): its secret beside this machine's own, its invitation in the sibling's record --
    /// never laid on the node again here, never buried by this machine's rotation; a card past its two days leaves both.
    pub fn take_twin(&self, body: &str) -> bool {
        let Ok(o) = serde_json::from_str::<Value>(body) else { return false };
        let (Some(inv), Some(p), Some(k)) = (o["i"].as_str(), o["p"].as_str().and_then(unb64), o["k"].as_str().and_then(unb64)) else { return false };
        if unb64url(inv).is_none_or(|i| i.len() != 32) || p.len() < 1184 || p.len() > 1184 + NAME_LIMIT || k.is_empty() {
            return false;
        }
        let _g = LOCK.lock().unwrap();
        let now = now_s();
        let mut twins: Map<String, Value> = self.vault.get(TWIN).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        let mut keys = self.map(KEYS);
        let fresh = !twins.contains_key(inv);
        if fresh {
            twins.insert(inv.to_string(), json!({ "p": b64(&p), "at": now }));
        }
        keys.insert(b64url(&p[..1184]), k);
        twins.retain(|_, c| {
            let old = now - c["at"].as_f64().unwrap_or(0.0) > TWIN_LIFE;
            if old {
                if let Some(pl) = c["p"].as_str().and_then(unb64).filter(|pl| pl.len() >= 1184) {
                    keys.remove(&b64url(&pl[..1184]));
                }
            }
            !old
        });
        self.save(KEYS, &keys) && self.vault.set(TWIN, Value::Object(twins).to_string().as_bytes()) && fresh
    }

    fn twins(&self) -> BTreeMap<String, Vec<u8>> {
        let now = now_s();
        let twins: Map<String, Value> = self.vault.get(TWIN).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        twins.into_iter().filter(|(_, c)| now - c["at"].as_f64().unwrap_or(0.0) <= TWIN_LIFE)
            .filter_map(|(k, c)| c["p"].as_str().and_then(unb64).map(|p| (k, p))).collect()
    }

    /// Every live invitation: the daily generations, the permanent one, and the cards of the person's other devices (iOS
    /// outstandingInvites over rdvAll).
    pub fn outstanding_invites(&self) -> Vec<Vec<u8>> {
        let mut out: Vec<Vec<u8>> = Vec::new();
        for k in self.map(DAILY).keys().chain(self.map(PERM).keys()).chain(self.twins().keys()) {
            if let Some(i) = unb64url(k).filter(|i| i.len() == 32) {
                if !out.contains(&i) {
                    out.push(i);
                }
            }
        }
        out
    }

    /// This person's own live cards with their secret halves -- the permanent one first, then the day's (iOS invites + cardKeys):
    /// what another person of the same computer meets them by (seats::pair_with_shelf).
    pub fn own_keys(&self) -> Vec<(Vec<u8>, Vec<u8>)> {
        let _g = LOCK.lock().unwrap();
        let keys = self.map(KEYS);
        let mut out = vec![];
        for p in self.map(PERM).into_values().chain(self.map(DAILY).into_values()) {
            let Some(root) = p.get(..1184) else { continue };
            if let Some(sk) = keys.get(&b64url(root)) {
                out.push((root.to_vec(), sk.clone()));
            }
        }
        out
    }

    /// Whether the root is the permanent card's (iOS isPermanentRoot).
    pub fn is_permanent_root(&self, root: &[u8]) -> bool {
        self.map(PERM).values().any(|p| p.len() >= 1184 && &p[..1184] == root)
    }

    /// THE OFFERING SIDE, FROM THE BOX (iOS accept(firstLetter:invite:conf:)): the invitation whose seal opened the letter names
    /// the one card; decapsulation never refuses, so the key confirmation is the proof --
    /// SHA-256("mt-first-conf"‖0‖secret‖ct)[0..16] in base64url, compared in constant time. The secret and the root.
    pub fn accept_first(&self, ct: &[u8], inv64: &str, conf: &str) -> Option<(Vec<u8>, Vec<u8>)> {
        let (root, sk) = {
            let _g = LOCK.lock().unwrap();
            let mut all = self.map(DAILY);
            all.extend(self.map(PERM));
            all.extend(self.twins());
            let payload = all.get(inv64)?.clone();
            let root = payload.get(..1184)?.to_vec();
            let sk = self.map(KEYS).get(&b64url(&root))?.clone();
            (root, sk)
        };
        let ss = crypto::mlkem_decaps(&sk, ct)?;
        let secret = crypto::first_secret(&ss, &root, ct)?;
        let want = b64url(&domained("mt-first-conf", &[&secret, ct])[..16]);
        let same = want.len() == conf.len() && want.bytes().zip(conf.bytes()).fold(0u8, |d, (a, b)| d | (a ^ b)) == 0;
        same.then_some((secret, root))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vault(name: &str) -> (Vault, std::path::PathBuf) {
        let d = std::env::temp_dir().join(format!("montana-card-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        (Vault::at(&d).unwrap(), d)
    }

    #[test]
    fn the_permanent_link_is_born_once_and_the_scanners_first_letter_opens_with_its_key() {
        let (v, d) = vault("perm");
        let c = Card { vault: &v };
        let link = c.offer_permanent("Alice").unwrap();
        assert!(link.starts_with(PERM_PREFIX));
        assert_eq!(c.offer_permanent("Alice").unwrap(), link, "the permanent link is born once");
        let inv64 = link.trim_start_matches(PERM_PREFIX);
        // the scanner's side, by hand: the card's root and name, one encapsulation, the key confirmation
        let payload = c.map(PERM)[inv64].clone();
        assert_eq!(&payload[1184..], b"Alice");
        let root = payload[..1184].to_vec();
        let (ct, ss) = crypto::mlkem_encaps(&root).unwrap();
        let secret = crypto::first_secret(&ss, &root, &ct).unwrap();
        let conf = b64url(&domained("mt-first-conf", &[&secret, &ct])[..16]);
        let (got, got_root) = c.accept_first(&ct, inv64, &conf).unwrap();
        assert_eq!((got, got_root), (secret, root));
        assert!(c.accept_first(&ct, inv64, "AAAAAAAAAAAAAAAAAAAAAA").is_none(), "a wrong confirmation opens nothing");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn the_link_of_the_day_stays_for_a_day() {
        let (v, d) = vault("daily");
        let c = Card { vault: &v };
        let l1 = c.offer_short("").unwrap();
        assert!(l1.starts_with(TEMP_PREFIX));
        assert_eq!(c.offer_short("").unwrap(), l1);
        assert_eq!(c.outstanding_invites().len(), 1);
        let _ = std::fs::remove_dir_all(&d);
    }
}
