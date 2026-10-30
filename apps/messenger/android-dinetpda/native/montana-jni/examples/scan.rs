//! THE SCANNER'S SIDE, AS AN iPHONE DOES IT — a proof tool for the Mac, never shipped: every step goes through the iOS
//! doors of mt-bindings (MontanaCard.expand, MontanaFirstContact.begin, MontanaWakePush.wakeRdv). It prints the /wake body
//! that lays the first letter in the node's box, and the pipe secret for the letters after it.
//!   scan card <invite_b64url> <sealed_card_b64>   → the card opened: pk (hex) and the name
//!   scan first <invite_b64url> <sealed_card_b64> <mid> <text> <name>   → {wake json}\n<secret hex>
//!   scan letter <secret_hex> <mid> <text> <name>   → {wake json} for a letter under the pipe
//!   scan open <secret_hex> <env_b64> <at_seconds>   → the letter's fields
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

fn sha(parts: &[&[u8]]) -> [u8; 32] { let mut h = Sha256::new(); for p in parts { h.update(p); } h.finalize().into() }
fn hex(b: &[u8]) -> String { b.iter().map(|x| format!("{:02x}", x)).collect() }
fn unhex(s: &str) -> Vec<u8> { (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect() }
fn b64(b: &[u8]) -> String { base64_std(b) }
fn now() -> u64 { SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() }

const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
fn base64_std(b: &[u8]) -> String {
    let mut o = String::new();
    for c in b.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        o.push(T[(n >> 18) as usize & 63] as char); o.push(T[(n >> 12) as usize & 63] as char);
        o.push(if c.len() > 1 { T[(n >> 6) as usize & 63] as char } else { '=' });
        o.push(if c.len() > 2 { T[n as usize & 63] as char } else { '=' });
    }
    o
}
fn unb64(s: &str) -> Vec<u8> {
    let s: String = s.chars().map(|c| match c { '-' => '+', '_' => '/', c => c }).filter(|c| *c != '=').collect();
    let mut out = Vec::new(); let mut buf = 0u32; let mut bits = 0;
    for ch in s.bytes() { let v = T.iter().position(|&t| t == ch).unwrap() as u32; buf = buf << 6 | v; bits += 6; if bits >= 8 { bits -= 8; out.push((buf >> bits) as u8); } }
    out
}
fn b64url(b: &[u8]) -> String { b64(b).replace('+', "-").replace('/', "_").trim_end_matches('=').to_string() }

fn seal(key: &[u8; 32], plain: &[u8]) -> Vec<u8> {
    let mut nonce = [0u8; 12];
    unsafe { mt_bindings::ffi_c::mt_random_fast(nonce.as_mut_ptr(), 12) };
    let (mut p, mut n): (*mut u8, usize) = (std::ptr::null_mut(), 0);
    assert_eq!(unsafe { mt_bindings::ffi_e2e::mt_e2e_seal_blob(key.as_ptr(), nonce.as_ptr(), plain.as_ptr(), plain.len(), &mut p, &mut n) }, 0);
    let v = unsafe { std::slice::from_raw_parts(p, n) }.to_vec(); unsafe { mt_bindings::ffi_e2e::mt_e2e_free(p, n) }; v
}
fn open(key: &[u8; 32], sealed: &[u8]) -> Option<Vec<u8>> {
    let (mut p, mut n): (*mut u8, usize) = (std::ptr::null_mut(), 0);
    if unsafe { mt_bindings::ffi_e2e::mt_e2e_open_blob(key.as_ptr(), sealed.as_ptr(), sealed.len(), &mut p, &mut n) } != 0 { return None; }
    let v = unsafe { std::slice::from_raw_parts(p, n) }.to_vec(); unsafe { mt_bindings::ffi_e2e::mt_e2e_free(p, n) }; Some(v)
}
fn body_key(secret: &[u8], w: u64) -> [u8; 32] { sha(&[b"mt-pipe-key\0", secret, &w.to_le_bytes()]) }
fn sub_id(conv: &str, r: &str) -> String { hex(&sha(&[b"mt-wake-sub\0", conv.as_bytes(), b"\0", r.as_bytes()])) }

fn card(inv: &[u8], sealed: &[u8]) -> Vec<u8> {
    let k = sha(&[b"mt-rdv-k\0", inv]);
    open(&k, sealed).expect("the card opens under the invitation")
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    match a[1].as_str() {
        "card" => { let p = card(&unb64(&a[2]), &unb64(&a[3])); println!("pk={}… name={}", &hex(&p[..8]), String::from_utf8_lossy(&p[1184..])); }
        "first" => {
            let inv = unb64(&a[2]);
            let payload = card(&inv, &unb64(&a[3]));
            let root = &payload[..1184];
            let (mut ct, mut ss) = (vec![0u8; 1088], [0u8; 32]);
            assert_eq!(unsafe { mt_bindings::ffi_c::mt_mlkem_encaps(root.as_ptr(), ct.as_mut_ptr(), ss.as_mut_ptr()) }, 0);
            let mut secret = [0u8; 32];
            assert_eq!(unsafe { mt_bindings::ffi_names::mt_name_first_secret(ss.as_ptr(), 32, root.as_ptr(), 1184, ct.as_ptr(), 1088, secret.as_mut_ptr()) }, 0);
            let conf = b64url(&sha(&[b"mt-first-conf\0", &secret, &ct])[..16]);
            let mut body = ct.clone();
            for f in [&a[4], &a[5], &a[6], &String::new(), &conf] { body.extend_from_slice(f.as_bytes()); body.push(0); }
            body.resize(1536, 0);
            let letter_key = sha(&[b"mt-rdv-letter\0", &inv]);
            let env = seal(&body_key(&letter_key, now() / 60), &body);
            let cw = hex(&sha(&[b"mt-rdv-wake\0", &inv, &(now() / 86400).to_le_bytes()]));
            println!("{{\"conv\":\"{}\",\"from_id\":\"{}\",\"mid\":\"{}\",\"env\":\"{}\"}}", cw, sub_id(&cw, "mac-scanner"), a[4], b64(&env));
            println!("{}", hex(&secret));
        }
        "letter" => {
            let secret = unhex(&a[2]);
            let mut body = Vec::new();
            for f in [&a[3], &a[4], &a[5], &String::new()] { body.extend_from_slice(f.as_bytes()); body.push(0); }
            body.resize(2048, 0);
            let env = seal(&body_key(&secret, now() / 60), &body);
            let cw = hex(&sha(&[b"mt-wake-conv\0", &secret, &(now() / 86400).to_le_bytes()]));
            println!("{{\"conv\":\"{}\",\"from_id\":\"{}\",\"mid\":\"{}\",\"env\":\"{}\"}}", cw, sub_id(&cw, "mac-scanner"), a[3], b64(&env));
        }
        "media" => {
            // media <secret_hex> <mid> <file> <kind> <ext>: every piece as a /blob-put body, then the /wake body with MD:{manifest}
            let secret = unhex(&a[2]); let data = std::fs::read(&a[4]).unwrap();
            let mut bk = [0u8; 32]; unsafe { mt_bindings::ffi_c::mt_random_fast(bk.as_mut_ptr(), 32) };
            let mut chunks = Vec::new();
            for (i, piece) in data.chunks(512 * 1024).enumerate() {
                let mut padded = piece.to_vec(); padded.resize(mt_messenger_e2e::media::pad_len(piece.len()), 0);
                let nb = sha(&[&bk, &(i as u64).to_le_bytes(), &padded]);
                let mut nonce = [0u8; 12]; nonce.copy_from_slice(&nb[..12]);
                let sealed = mt_messenger_e2e::media::seal_blob(&bk, &nonce, &padded);
                let bid = hex(&sha(&[&sealed]));
                println!("{{\"bid\":\"{}\",\"data\":\"{}\"}}", bid, b64(&sealed));
                chunks.push(format!("{{\"bid\":\"{}\",\"cs\":{}}}", bid, piece.len()));
            }
            let man = format!("{{\"k\":\"{}\",\"e\":\"{}\",\"bk\":\"{}\",\"sz\":{},\"chunks\":[{}],\"cap\":\"from the Mac\"}}", a[5], a[6], b64(&bk), data.len(), chunks.join(","));
            let text = format!("\u{200b}\u{200b}MD:{}", man);
            let mut body = Vec::new();
            for f in [&a[3], &text, &"Mac".to_string(), &String::new()] { body.extend_from_slice(f.as_bytes()); body.push(0); }
            body.resize(2048, 0);
            let env = seal(&body_key(&secret, now() / 60), &body);
            let cw = hex(&sha(&[b"mt-wake-conv\0", &secret, &(now() / 86400).to_le_bytes()]));
            println!("WAKE {{\"conv\":\"{}\",\"from_id\":\"{}\",\"mid\":\"{}\",\"env\":\"{}\"}}", cw, sub_id(&cw, "mac-scanner"), a[3], b64(&env));
        }
        "blobopen" => {
            // blobopen <key_b64> <sealed_file> <out_file> [cs]: a node blob opened under its key, cut to cs when given
            let k = unb64(&a[2]); let mut key = [0u8; 32]; key.copy_from_slice(&k);
            let sealed = std::fs::read(&a[3]).unwrap();
            let mut p = open(&key, &sealed).expect("the blob opens");
            if let Some(cs) = a.get(5) { p.truncate(cs.parse().unwrap()); }
            println!("sha_ok={}", hex(&sha(&[&sealed])));
            std::fs::write(&a[4], p).unwrap();
        }
        "offer" => {
            // offer <name>: a card as an iPhone mints it — the blob-put body, the link, and the secret half (hex) on the last line
            let mut seed = [0u8; 64]; unsafe { mt_bindings::ffi_c::mt_random_fast(seed.as_mut_ptr(), 64) };
            let (mut pk, mut sk) = (vec![0u8; 1184], vec![0u8; 2400]);
            assert_eq!(unsafe { mt_bindings::ffi_c::mt_mlkem_keypair_from_seed(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) }, 0);
            let mut inv = [0u8; 32]; unsafe { mt_bindings::ffi_c::mt_random_fast(inv.as_mut_ptr(), 32) };
            let mut payload = pk.clone(); payload.extend_from_slice(a[2].as_bytes());
            let sealed = seal(&sha(&[b"mt-rdv-k\0", &inv]), &payload);
            println!("{{\"bid\":\"{}\",\"data\":\"{}\",\"over\":true}}", hex(&sha(&[b"mt-rdv-a\0", &inv])), b64(&sealed));
            println!("https://montana.quest/temp/{}", b64url(&inv));
            println!("{}", hex(&sk));
            println!("{}", hex(&pk));
        }
        "accept" => {
            // accept <inv_b64url> <sk_hex> <pk_hex> <env_b64> <at>: the owner's side — open the first letter, prove it, print the secret
            let inv = unb64(&a[2]); let sk = unhex(&a[3]); let pk = unhex(&a[4]); let sealed = unb64(&a[5]); let at: u64 = a[6].parse().unwrap();
            let lk = sha(&[b"mt-rdv-letter\0", &inv]);
            let mut plain = None;
            for back in 0..1440u64 { for w in [at / 60 - back, at / 60 + 1] { if plain.is_none() { plain = open(&body_key(&lk, w), &sealed); } } }
            let plain = plain.expect("the first letter opens under the invitation");
            let ct = &plain[..1088];
            let mut ss = [0u8; 32];
            assert_eq!(unsafe { mt_bindings::ffi_c::mt_mlkem_decaps(sk.as_ptr(), ct.as_ptr(), ss.as_mut_ptr()) }, 0);
            let mut secret = [0u8; 32];
            assert_eq!(unsafe { mt_bindings::ffi_names::mt_name_first_secret(ss.as_ptr(), 32, pk.as_ptr(), 1184, ct.as_ptr(), 1088, secret.as_mut_ptr()) }, 0);
            let f: Vec<String> = plain[1088..].split(|b| *b == 0).take(5).map(|x| String::from_utf8_lossy(x).to_string()).collect();
            let conf = b64url(&sha(&[b"mt-first-conf\0", &secret, ct])[..16]);
            println!("fields={:?} conf_ok={}", &f[..4], f[4] == conf);
            println!("{}", hex(&secret));
        }
        "labels" => {
            let secret = unhex(&a[2]);
            let cw = hex(&sha(&[b"mt-wake-conv\0", &secret, &(now() / 86400).to_le_bytes()]));
            println!("{{\"subs\":[\"{}\"],\"sids\":[\"{}\"]}}", cw, sub_id(&cw, "mac-scanner"));
        }
        "rdvlabels" => {
            let inv = unb64(&a[2]);
            let cw = hex(&sha(&[b"mt-rdv-wake\0", &inv, &(now() / 86400).to_le_bytes()]));
            println!("{{\"subs\":[\"{}\"],\"sids\":[\"{}\"]}}", cw, sub_id(&cw, "mac-owner"));
        }
        "open" => {
            let secret = unhex(&a[2]); let sealed = unb64(&a[3]); let at: u64 = a[4].parse().unwrap();
            for back in 0..1440u64 { for w in [at / 60 - back, at / 60 + 1] {
                if let Some(p) = open(&body_key(&secret, w), &sealed) {
                    let f: Vec<String> = p.split(|b| *b == 0).take(6).map(|x| String::from_utf8_lossy(x).to_string()).collect();
                    println!("{:?}", f); return;
                } } }
            println!("sealed");
        }
        _ => {}
    }
}
