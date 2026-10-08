// Machine checks for the username-lease mechanism (checklist "Username: creation, ownership,
// recovery", items 14-18). Crypto only: prints the material an HTTP driver needs.
//   pubkey <mnemonic>          -> account_id_hex pubkey_b64
//   sign   <mnemonic> <nonce>  -> signature_b64 over "mt-auth" || 0x00 || nonce
use mt_crypto::{keypair_from_seed, sign};
use mt_mnemonic::{mldsa_seed_for_role, mnemonic_to_master_seed};

fn b64(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for c in data.chunks(3) {
        let b = [c[0], *c.get(1).unwrap_or(&0), *c.get(2).unwrap_or(&0)];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        for i in 0..4 {
            if i <= c.len() {
                out.push(T[((n >> (18 - 6 * i)) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

fn b64url_decode(s: &str) -> Vec<u8> {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut acc: u32 = 0;
    let mut bits = 0;
    let mut out = Vec::new();
    for ch in s.bytes().filter(|b| *b != b'=') {
        let v = T.iter().position(|c| *c == ch).expect("base64url alphabet") as u32;
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
        }
    }
    out
}

fn keys(mnemonic: &str) -> (Vec<u8>, Vec<u8>, [u8; 32]) {
    let master = mnemonic_to_master_seed(mnemonic).expect("mnemonic");
    let seed = mldsa_seed_for_role(&master, mt_codec::domain::ACCOUNT_KEY);
    let (pk, sk) = keypair_from_seed(&seed).expect("keypair");
    let mut buf = Vec::new();
    buf.extend_from_slice(mt_codec::domain::ACCOUNT);
    buf.push(0x00);
    buf.extend_from_slice(&1u16.to_le_bytes());
    buf.extend_from_slice(pk.as_bytes());
    let id = mt_crypto::sha256_raw(&buf);
    (pk.as_bytes().to_vec(), sk.as_bytes().to_vec(), id)
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(String::as_str) {
        Some("pubkey") => {
            let (pk, _sk, id) = keys(&a[2]);
            println!("{} {}", hex(&id), b64(&pk));
        },
        Some("sign") => {
            let (_pk, sk, _id) = keys(&a[2]);
            let mut msg = Vec::new();
            msg.extend_from_slice(mt_codec::domain::MSG_AUTH);
            msg.push(0x00);
            msg.extend_from_slice(&b64url_decode(&a[3]));
            let sk = mt_crypto::SecretKey::from_slice(&sk).expect("sk");
            println!("{}", b64(sign(&sk, &msg).expect("sign").as_bytes()));
        },
        Some("mnemonic") => {
            // Deterministic throwaway identity: entropy = SHA-256(label). Test accounts must be
            // reproducible across runs, so the checks can re-enter the same account.
            let e = mt_crypto::sha256_raw(a[2].as_bytes());
            println!("{}", mt_mnemonic::entropy_to_mnemonic(&e));
        },
        _ => eprintln!("usage: username_lease_probe pubkey|sign|mnemonic <arg> [nonce_b64url]"),
    }
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}
