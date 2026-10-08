// What every vector of this crate needs and none of them owns: a directory that is wiped whether the
// vector passes or panics, the two public values of a person a payer needs, and the byte pattern the
// vectors draw their keys from.
//
// **One place, because seven were seven.** Each of these stood copied into every file that used it,
// and copies of one thing diverge at the first edit while both read correctly on their own. A
// helper of a vector is a thing of the tree exactly as a constant of the protocol is.
//
// Each vector binary compiles this module for itself and uses the part of it that it needs, so the
// compiler judges the rest unused in that binary and would be right to. That is a property of how
// integration vectors are built and not a dead item of this tree.
#![allow(dead_code)]

use montana_wallet::pay::Payee;
use std::path::PathBuf;

// A directory of its own for a vector, gone when the vector is. The name is the vector's to choose
// and must be distinct, since two of them under one name would share a wallet.
pub struct Scratch(pub PathBuf);

impl Scratch {
    pub fn named(what: &str) -> Self {
        let at = std::env::temp_dir().join(format!("montana-{what}"));
        let _ = std::fs::remove_dir_all(&at);
        std::fs::create_dir_all(&at).expect("a scratch directory is writable");
        Self(at)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

// A pattern of bytes a vector draws a key from: one seed, one index, and nothing of chance in it, so
// a vector that fails fails the same way twice.
pub fn of(seed: u8, at: u8) -> [u8; 32] {
    let mut out = [seed; 32];
    out[31] = at;
    out
}

// The two public values a payer is handed: the naming half of the payee and the key its notes are
// paid to. Nothing else about a payee is arranged with them.
pub fn payee_of(seed: u8) -> (Payee, [u8; 32]) {
    let nf_key = of(seed, 0);
    (
        Payee {
            half: mt_derive::note::nf_pk(&nf_key),
            note_pk: of(seed, 1),
        },
        nf_key,
    )
}
