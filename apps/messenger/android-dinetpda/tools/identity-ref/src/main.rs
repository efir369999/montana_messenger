//! The person's own reference from 24 words, computed by the core alone — the value iOS and Android both call the twin
//! (iOS MontanaSeed.twin, Android MontanaSeed.twin, Identity.kt): hex(SHA-256(mt_mldsa_seed_for_role(master, "mt-owner-key"))[..16]).
//! Two devices that print the same reference hold one identity; the apps show its first ten characters in their logs
//! (Android: `wall_rx … from=`).
//!
//!     tools/wsl-build.sh identity-ref <file holding the 24 words>
use sha2::{Digest, Sha256};

fn main() {
    let path = std::env::args().nth(1).expect("usage: identity-ref <file holding the 24 words>");
    let text = std::fs::read_to_string(&path).expect("the words file");
    let master = mt_mnemonic::mnemonic_to_master_seed(text.trim()).expect("these are not 24 words of a Montana phrase");
    let owner = mt_mnemonic::mldsa_seed_for_role(&master, b"mt-owner-key");
    let digest = Sha256::digest(&owner[..]);
    let reference: String = digest[..16].iter().map(|b| format!("{b:02x}")).collect();
    println!("{reference}");
}
